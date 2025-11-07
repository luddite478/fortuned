import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../http_client.dart';
import 'local_cache_service.dart';

/// Manages snapshot caching with LRU eviction
/// 
/// Strategy:
/// - On-demand loading (cache-first, fallback to server)
/// - LRU eviction (keep most recent 30 snapshots)
/// - Track access times for eviction decisions
class SnapshotsCacheService {
  static const String _snapshotsDir = 'snapshots';
  static const int _maxSnapshots = 30;

  /// Get the file path for a snapshot
  static String _getFilePath(String snapshotId) => '$_snapshotsDir/$snapshotId.json';

  /// Load a snapshot by message ID
  /// Checks cache first, downloads from server if not found
  static Future<Map<String, dynamic>?> loadSnapshot(String messageId) async {
    // Step 1: Check cache
    final cached = await _loadFromCache(messageId);
    if (cached != null) {
      debugPrint('✅ [SNAPSHOTS] Loaded from cache: $messageId');
      await _updateAccessTime(messageId); // Update LRU
      return cached;
    }

    // Step 2: Download from server
    debugPrint('⬇️ [SNAPSHOTS] Downloading from server: $messageId');
    final snapshot = await _fetchFromServer(messageId);

    if (snapshot != null) {
      // Step 3: Save to cache
      await _saveToCache(messageId, snapshot);
      
      // Step 4: Evict old snapshots if needed
      await _evictOldSnapshotsIfNeeded();
      
      return snapshot;
    }

    return null;
  }

  /// Load snapshot from cache
  static Future<Map<String, dynamic>?> _loadFromCache(String messageId) async {
    try {
      final data = await LocalCacheService.readJson(_getFilePath(messageId));
      if (data == null) {
        return null;
      }

      return data['snapshot'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('❌ [SNAPSHOTS] Error loading from cache: $e');
      return null;
    }
  }

  /// Fetch snapshot from server
  static Future<Map<String, dynamic>?> _fetchFromServer(String messageId) async {
    try {
      final response = await ApiHttpClient.get(
        '/messages/$messageId',
        queryParams: {
          'include_snapshot': 'true',
        },
      );

      if (response.statusCode != 200) {
        debugPrint('❌ [SNAPSHOTS] Server returned ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['snapshot'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('❌ [SNAPSHOTS] Fetch failed: $e');
      return null;
    }
  }

  /// Save snapshot to cache
  static Future<bool> _saveToCache(
    String messageId,
    Map<String, dynamic> snapshot,
  ) async {
    final data = {
      'version': 1,
      'snapshot_id': messageId,
      'cached_at': DateTime.now().toIso8601String(),
      'last_accessed_at': DateTime.now().toIso8601String(),
      'snapshot': snapshot,
    };

    return await LocalCacheService.writeJson(_getFilePath(messageId), data);
  }

  /// Update last accessed time for LRU
  static Future<void> _updateAccessTime(String messageId) async {
    try {
      final data = await LocalCacheService.readJson(_getFilePath(messageId));
      if (data == null) return;

      data['last_accessed_at'] = DateTime.now().toIso8601String();
      await LocalCacheService.writeJson(_getFilePath(messageId), data);
    } catch (e) {
      debugPrint('❌ [SNAPSHOTS] Error updating access time: $e');
    }
  }

  /// Evict old snapshots if over the limit (LRU)
  static Future<void> _evictOldSnapshotsIfNeeded() async {
    try {
      final files = await LocalCacheService.listFiles(_snapshotsDir);
      
      if (files.length <= _maxSnapshots) {
        return; // Under limit, no eviction needed
      }

      // Load metadata for all snapshots
      final List<_SnapshotMeta> metas = [];
      for (var file in files) {
        if (file.path.endsWith('.json')) {
          try {
            final content = await file.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final lastAccessed = json['last_accessed_at'] as String?;
            
            if (lastAccessed != null) {
              metas.add(_SnapshotMeta(
                file: file,
                lastAccessed: DateTime.parse(lastAccessed),
              ));
            }
          } catch (e) {
            debugPrint('❌ [SNAPSHOTS] Error reading metadata: $e');
          }
        }
      }

      // Sort by last accessed (oldest first)
      metas.sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));

      // Delete oldest until we're under the limit
      final toDelete = metas.length - _maxSnapshots;
      for (var i = 0; i < toDelete; i++) {
        await metas[i].file.delete();
        debugPrint('🗑️ [SNAPSHOTS] Evicted old snapshot (LRU)');
      }

      debugPrint('✅ [SNAPSHOTS] Eviction complete, keeping ${_maxSnapshots} snapshots');
    } catch (e) {
      debugPrint('❌ [SNAPSHOTS] Error during eviction: $e');
    }
  }

  /// Check if a snapshot is cached
  static Future<bool> isCached(String messageId) async {
    return await LocalCacheService.fileExists(_getFilePath(messageId));
  }

  /// Manually cache a snapshot (e.g., after creating a message)
  static Future<bool> cacheSnapshot(
    String messageId,
    Map<String, dynamic> snapshot,
  ) async {
    final success = await _saveToCache(messageId, snapshot);
    if (success) {
      await _evictOldSnapshotsIfNeeded();
      debugPrint('✅ [SNAPSHOTS] Manually cached snapshot: $messageId');
    }
    return success;
  }

  /// Clear a specific snapshot from cache
  static Future<void> clearSnapshot(String messageId) async {
    await LocalCacheService.deleteFile(_getFilePath(messageId));
    debugPrint('✅ [SNAPSHOTS] Cleared snapshot: $messageId');
  }

  /// Clear all snapshots
  static Future<void> clearAllSnapshots() async {
    try {
      final dir = await LocalCacheService.getCacheDirectory(_snapshotsDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      debugPrint('✅ [SNAPSHOTS] All snapshots cleared');
    } catch (e) {
      debugPrint('❌ [SNAPSHOTS] Error clearing all snapshots: $e');
    }
  }

  /// Get cache statistics
  static Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final files = await LocalCacheService.listFiles(_snapshotsDir);
      final size = await LocalCacheService.getDirectorySize(_snapshotsDir);

      return {
        'count': files.length,
        'size_bytes': size,
        'size_formatted': LocalCacheService.formatBytes(size),
        'limit': _maxSnapshots,
      };
    } catch (e) {
      return {
        'count': 0,
        'size_bytes': 0,
        'size_formatted': '0 B',
        'limit': _maxSnapshots,
      };
    }
  }
}

/// Internal class to hold snapshot metadata for LRU eviction
class _SnapshotMeta {
  final dynamic file;
  final DateTime lastAccessed;

  _SnapshotMeta({
    required this.file,
    required this.lastAccessed,
  });
}

