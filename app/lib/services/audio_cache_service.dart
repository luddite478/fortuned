import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../models/thread/message.dart';

/// Service for caching and managing audio files with LRU eviction
/// 
/// Features:
/// - Downloads from S3 and caches locally
/// - Size-based eviction (default 1GB limit)
/// - LRU eviction (least recently used files deleted first)
/// - Tracks access times for intelligent eviction
class AudioCacheService {
  static final Map<String, String> _urlToLocalPathCache = {};
  static final Map<String, bool> _downloadingUrls = {};
  
  // Cache size limit (1GB default)
  static const int maxCacheSizeBytes = 1 * 1024 * 1024 * 1024;
  static const String _metadataFileName = 'audio_metadata.json';

  /// Get cache directory for audio files
  static Future<String> _getCacheDirectory() async {
    final appName = dotenv.env['APP_NAME'] ?? 'app';
    String baseDir;
    
    if (Platform.isAndroid) {
      baseDir = '/storage/emulated/0/Download/${appName}_data';
    } else if (Platform.isIOS) {
      baseDir = path.join(Directory.systemTemp.path, appName);
    } else if (Platform.isMacOS) {
      baseDir = '${Platform.environment['HOME']}/Documents/$appName';
    } else if (Platform.isWindows) {
      baseDir = '${Platform.environment['USERPROFILE']}\\Documents\\$appName';
    } else {
      baseDir = path.join(Directory.systemTemp.path, appName);
    }
    
    final cacheDir = path.join(baseDir, 'audio_cache');
    final dir = Directory(cacheDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Generate local file path for a render URL
  static Future<String> _getLocalPathForUrl(String url) async {
    final cacheDir = await _getCacheDirectory();
    
    // Extract filename from URL or generate one from hash
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    String filename = pathSegments.isNotEmpty ? pathSegments.last : 'audio_${url.hashCode}.mp3';
    
    // Ensure .mp3 extension
    if (!filename.endsWith('.mp3')) {
      filename = '$filename.mp3';
    }
    
    return path.join(cacheDir, filename);
  }

  /// Check if audio is cached locally
  static Future<bool> isCached(String url) async {
    try {
      final localPath = await _getLocalPathForUrl(url);
      final file = File(localPath);
      final exists = await file.exists();
      
      if (exists) {
        _urlToLocalPathCache[url] = localPath;
      }
      
      return exists;
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error checking cache: $e');
      return false;
    }
  }

  /// Get local path if cached, null otherwise
  static Future<String?> getCachedPath(String url) async {
    // Check memory cache first
    if (_urlToLocalPathCache.containsKey(url)) {
      final cachedPath = _urlToLocalPathCache[url]!;
      if (await File(cachedPath).exists()) {
        return cachedPath;
      } else {
        _urlToLocalPathCache.remove(url);
      }
    }

    // Check filesystem
    final localPath = await _getLocalPathForUrl(url);
    final file = File(localPath);
    if (await file.exists()) {
      _urlToLocalPathCache[url] = localPath;
      return localPath;
    }

    return null;
  }

  /// Download and cache audio from S3 URL
  static Future<String?> downloadAndCache(String url, {Function(double)? onProgress}) async {
    try {
      // Check if already downloading
      if (_downloadingUrls[url] == true) {
        debugPrint('⏳ [AUDIO_CACHE] Already downloading: $url');
        return null;
      }

      // Check if already cached
      final cachedPath = await getCachedPath(url);
      if (cachedPath != null) {
        debugPrint('✅ [AUDIO_CACHE] Already cached: $cachedPath');
        return cachedPath;
      }

      _downloadingUrls[url] = true;
      debugPrint('🔄 [AUDIO_CACHE] Downloading: $url');

      final localPath = await _getLocalPathForUrl(url);
      final file = File(localPath);

      // Download file
      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        debugPrint('❌ [AUDIO_CACHE] Download failed: ${response.statusCode}');
        _downloadingUrls.remove(url);
        return null;
      }

      final contentLength = response.contentLength ?? 0;
      int downloadedBytes = 0;

      final sink = file.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        
        if (contentLength > 0 && onProgress != null) {
          final progress = downloadedBytes / contentLength;
          onProgress(progress);
        }
      }
      await sink.close();

      _urlToLocalPathCache[url] = localPath;
      _downloadingUrls.remove(url);
      
      debugPrint('✅ [AUDIO_CACHE] Downloaded and cached: $localPath');
      return localPath;
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Download error: $e');
      _downloadingUrls.remove(url);
      return null;
    }
  }

  /// Get playable path for a render - returns local path if available, otherwise downloads
  /// If localPathIfRecorded is provided (for current user's recordings), use it directly
  static Future<String?> getPlayablePath(
    Render render, {
    String? localPathIfRecorded,
    Function(double)? onProgress,
  }) async {
    // If this is the user's own recording, use local file directly
    if (localPathIfRecorded != null) {
      final file = File(localPathIfRecorded);
      if (await file.exists()) {
        debugPrint('🎵 [AUDIO_CACHE] Using local recording: $localPathIfRecorded');
        return localPathIfRecorded;
      }
    }

    // Check cache
    final cachedPath = await getCachedPath(render.url);
    if (cachedPath != null) {
      // Update access time for LRU
      await _updateAudioAccessTime(render.url);
      return cachedPath;
    }

    // Check cache size before downloading
    final cacheSize = await getCacheSize();
    if (cacheSize >= maxCacheSizeBytes) {
      debugPrint('⚠️ [AUDIO_CACHE] Cache full, evicting old files');
      await _evictLeastRecentlyUsedAudio();
    }

    // Download and cache
    final downloadedPath = await downloadAndCache(render.url, onProgress: onProgress);
    
    // Track in metadata if successful
    if (downloadedPath != null) {
      await _updateAudioAccessTime(render.url);
    }
    
    return downloadedPath;
  }

  /// Clear entire cache
  static Future<void> clearCache() async {
    try {
      final cacheDir = await _getCacheDirectory();
      final dir = Directory(cacheDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _urlToLocalPathCache.clear();
      debugPrint('🗑️ [AUDIO_CACHE] Cache cleared');
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error clearing cache: $e');
    }
  }

  /// Get cache size in bytes
  static Future<int> getCacheSize() async {
    try {
      final cacheDir = await _getCacheDirectory();
      final dir = Directory(cacheDir);
      if (!await dir.exists()) return 0;

      int totalSize = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error getting cache size: $e');
      return 0;
    }
  }

  /// Format cache size for display
  static String formatCacheSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ============================================================================
  // LRU Eviction Methods
  // ============================================================================

  /// Get path to metadata file
  static Future<File> _getMetadataFile() async {
    final cacheDir = await _getCacheDirectory();
    return File(path.join(cacheDir, _metadataFileName));
  }

  /// Load audio metadata (access times, etc.)
  static Future<Map<String, dynamic>> _loadAudioMetadata() async {
    try {
      final file = await _getMetadataFile();
      if (!await file.exists()) {
        return {};
      }

      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error loading metadata: $e');
      return {};
    }
  }

  /// Save audio metadata
  static Future<void> _saveAudioMetadata(Map<String, dynamic> metadata) async {
    try {
      final file = await _getMetadataFile();
      await file.writeAsString(jsonEncode(metadata));
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error saving metadata: $e');
    }
  }

  /// Update access time for a URL (for LRU tracking)
  static Future<void> _updateAudioAccessTime(String url) async {
    try {
      final metadata = await _loadAudioMetadata();
      
      metadata[url] = {
        'last_accessed_at': DateTime.now().toIso8601String(),
        'access_count': (metadata[url]?['access_count'] ?? 0) + 1,
      };

      await _saveAudioMetadata(metadata);
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error updating access time: $e');
    }
  }

  /// Extract URL from file path
  static String _urlFromPath(String filePath) {
    // Simple heuristic: check if filename is in our URL cache
    for (var entry in _urlToLocalPathCache.entries) {
      if (entry.value == filePath) {
        return entry.key;
      }
    }
    // Fallback: use the filename
    return path.basename(filePath);
  }

  /// Evict least recently used audio files to free up space
  static Future<void> _evictLeastRecentlyUsedAudio() async {
    try {
      final metadata = await _loadAudioMetadata();
      final cacheDir = await _getCacheDirectory();
      final dir = Directory(cacheDir);

      // Get all audio files with access times
      final List<_AudioFileMeta> files = [];
      await for (final entity in dir.list()) {
        if (entity is File && 
            entity.path.endsWith('.mp3') && 
            !entity.path.endsWith(_metadataFileName)) {
          final url = _urlFromPath(entity.path);
          final lastAccessed = metadata[url]?['last_accessed_at'] != null
              ? DateTime.parse(metadata[url]!['last_accessed_at'] as String)
              : DateTime.fromMillisecondsSinceEpoch(0);

          final size = await entity.length();
          files.add(_AudioFileMeta(
            file: entity,
            url: url,
            lastAccessed: lastAccessed,
            size: size,
          ));
        }
      }

      // Sort by last accessed (oldest first)
      files.sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));

      // Delete oldest files until under limit (target 80% of limit)
      final targetSize = (maxCacheSizeBytes * 0.8).toInt();
      int currentSize = await getCacheSize();
      int deletedCount = 0;

      for (var fileMeta in files) {
        if (currentSize <= targetSize) break;

        await fileMeta.file.delete();
        metadata.remove(fileMeta.url);
        _urlToLocalPathCache.remove(fileMeta.url);
        currentSize -= fileMeta.size;
        deletedCount++;

        debugPrint('🗑️ [AUDIO_CACHE] Evicted: ${path.basename(fileMeta.file.path)}');
      }

      // Save updated metadata
      await _saveAudioMetadata(metadata);

      debugPrint('✅ [AUDIO_CACHE] Evicted $deletedCount files, cache now ${formatCacheSize(currentSize)}');
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error during eviction: $e');
    }
  }

  /// Get cache statistics
  static Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final size = await getCacheSize();
      final metadata = await _loadAudioMetadata();
      final fileCount = metadata.length;

      return {
        'file_count': fileCount,
        'size_bytes': size,
        'size_formatted': formatCacheSize(size),
        'limit_bytes': maxCacheSizeBytes,
        'limit_formatted': formatCacheSize(maxCacheSizeBytes),
        'usage_percent': ((size / maxCacheSizeBytes) * 100).toStringAsFixed(1),
      };
    } catch (e) {
      return {
        'file_count': 0,
        'size_bytes': 0,
        'size_formatted': '0 B',
        'limit_bytes': maxCacheSizeBytes,
        'limit_formatted': formatCacheSize(maxCacheSizeBytes),
        'usage_percent': '0.0',
      };
    }
  }
}

/// Internal class to hold audio file metadata for LRU eviction
class _AudioFileMeta {
  final File file;
  final String url;
  final DateTime lastAccessed;
  final int size;

  _AudioFileMeta({
    required this.file,
    required this.url,
    required this.lastAccessed,
    required this.size,
  });
}

