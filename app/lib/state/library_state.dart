import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/playlist_item.dart';
import '../models/thread/message.dart';
import '../services/http_client.dart';

class LibraryState extends ChangeNotifier {
  // Data
  List<PlaylistItem> _playlist = [];
  
  // UI state
  bool _isLoading = false;
  String? _error;
  
  // Track if initial load is complete
  bool _hasLoaded = false;
  
  // Getters
  List<PlaylistItem> get playlist => List.unmodifiable(_playlist);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasLoaded => _hasLoaded;
  
  // ============================================================================
  // Private API methods
  // ============================================================================
  
  /// Fetch playlist from server
  Future<List<PlaylistItem>> _fetchPlaylistFromServer(String userId) async {
    try {
      final response = await ApiHttpClient.get(
        '/users/playlist',
        queryParams: {
          'user_id': userId,
        },
      );
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final playlistData = json['playlist'] as List<dynamic>? ?? [];
        final playlist = playlistData
            .map((item) => PlaylistItem.fromJson(item as Map<String, dynamic>))
            .toList();
        
        debugPrint('✅ [LIBRARY] Fetched playlist from server: ${playlist.length} items');
        return playlist;
      } else {
        debugPrint('❌ [LIBRARY] Failed to fetch playlist: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('❌ [LIBRARY] Error fetching playlist: $e');
      rethrow;
    }
  }
  
  /// Add item to server
  Future<bool> _addToPlaylistOnServer({
    required String userId,
    required Render render,
  }) async {
    try {
      // Format name as "Oct 5, 2025"
      final now = DateTime.now();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final name = '${months[now.month - 1]} ${now.day}, ${now.year}';
      
      // Convert render to playlist item format
      final playlistItem = {
        'name': name,
        'url': render.url,
        'id': render.id,
        'format': render.format,
        if (render.bitrate != null) 'bitrate': render.bitrate,
        if (render.duration != null) 'duration': render.duration,
        if (render.sizeBytes != null) 'size_bytes': render.sizeBytes,
        'created_at': render.createdAt.toIso8601String(),
        'type': 'render',
      };
      
      final response = await ApiHttpClient.post(
        '/users/playlist/add',
        body: {
          'user_id': userId,
          'render': playlistItem,
        },
      );
      
      if (response.statusCode == 200) {
        debugPrint('✅ [LIBRARY] Added to server playlist: ${render.id}');
        return true;
      } else {
        debugPrint('❌ [LIBRARY] Failed to add on server: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ [LIBRARY] Error adding to server playlist: $e');
      return false;
    }
  }
  
  /// Remove item from server
  Future<bool> _removeFromPlaylistOnServer({
    required String userId,
    required String renderId,
  }) async {
    try {
      final response = await ApiHttpClient.post(
        '/users/playlist/remove',
        body: {
          'user_id': userId,
          'render_id': renderId,
        },
      );
      
      if (response.statusCode == 200) {
        debugPrint('✅ [LIBRARY] Removed from server playlist: $renderId');
        return true;
      } else {
        debugPrint('❌ [LIBRARY] Failed to remove on server: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ [LIBRARY] Error removing from server playlist: $e');
      return false;
    }
  }
  
  // ============================================================================
  // Public API methods
  // ============================================================================
  
  /// Load playlist once on app startup
  Future<void> loadPlaylist({required String userId}) async {
    // If already loaded, don't reload
    if (_hasLoaded) {
      debugPrint('📚 [LIBRARY] Playlist already loaded (${_playlist.length} items)');
      return;
    }
    
    try {
      _isLoading = true;
      notifyListeners();
      
      _error = null;
      
      final playlist = await _fetchPlaylistFromServer(userId);
      
      _playlist = playlist;
      _hasLoaded = true;
      
      debugPrint('📚 [LIBRARY] Loaded playlist: ${_playlist.length} items');
    } catch (e) {
      _error = 'Failed to load playlist: $e';
      debugPrint('❌ [LIBRARY] Error loading playlist: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Add item to playlist (optimistic update with background sync)
  Future<bool> addToPlaylist({
    required String userId,
    required Render render,
  }) async {
    // Format name as "Oct 5, 2025"
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final name = '${months[now.month - 1]} ${now.day}, ${now.year}';
    
    // Create playlist item
    final item = PlaylistItem(
      name: name,
      url: render.url,
      id: render.id,
      format: render.format,
      bitrate: render.bitrate,
      duration: render.duration,
      sizeBytes: render.sizeBytes,
      createdAt: render.createdAt,
      type: 'render',
    );
    
    // Optimistically add to local list
    _playlist = [item, ..._playlist];
    notifyListeners();
    
    // Sync to server in background
    try {
      final success = await _addToPlaylistOnServer(
        userId: userId,
        render: render,
      );
      
      if (!success) {
        // Rollback on failure
        _playlist = _playlist.where((i) => i.id != item.id).toList();
        notifyListeners();
        return false;
      }
      
      return true;
    } catch (e) {
      // Rollback on error
      _playlist = _playlist.where((i) => i.id != item.id).toList();
      notifyListeners();
      debugPrint('❌ [LIBRARY] Failed to add to playlist: $e');
      return false;
    }
  }
  
  /// Remove item from playlist (optimistic update with background sync)
  Future<bool> removeFromPlaylist({
    required String userId,
    required String renderId,
  }) async {
    // Find and save the item in case we need to rollback
    final removedIndex = _playlist.indexWhere((i) => i.id == renderId);
    if (removedIndex == -1) {
      debugPrint('❌ [LIBRARY] Item not found: $renderId');
      return false;
    }
    
    final removedItem = _playlist[removedIndex];
    
    // Optimistically remove from local list
    _playlist = List.from(_playlist)..removeAt(removedIndex);
    notifyListeners();
    
    // Sync to server in background
    try {
      final success = await _removeFromPlaylistOnServer(
        userId: userId,
        renderId: renderId,
      );
      
      if (!success) {
        // Rollback on failure - restore at original position
        _playlist = List.from(_playlist)..insert(removedIndex, removedItem);
        notifyListeners();
        return false;
      }
      
      return true;
    } catch (e) {
      // Rollback on error - restore at original position
      _playlist = List.from(_playlist)..insert(removedIndex, removedItem);
      notifyListeners();
      debugPrint('❌ [LIBRARY] Failed to remove from playlist: $e');
      return false;
    }
  }
  
  /// Clear all data (e.g., on logout)
  void clear() {
    _playlist = [];
    _hasLoaded = false;
    _error = null;
    _isLoading = false;
    notifyListeners();
    debugPrint('📚 [LIBRARY] Cleared playlist data');
  }
}

