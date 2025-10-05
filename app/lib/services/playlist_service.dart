import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'http_client.dart';
import '../models/playlist_item.dart';
import '../models/thread/message.dart';

class PlaylistService {
  /// Format date as "Oct 5, 2025"
  static String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
  
  /// Add a render to user's playlist
  static Future<bool> addToPlaylist({
    required String userId,
    required Render render,
  }) async {
    try {
      // Format name as "Oct 5, 2025"
      final now = DateTime.now();
      final name = _formatDate(now);
      
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
        debugPrint('✅ [PLAYLIST] Added to playlist: ${render.id}');
        return true;
      } else {
        debugPrint('❌ [PLAYLIST] Failed to add: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ [PLAYLIST] Error adding to playlist: $e');
      return false;
    }
  }
  
  /// Remove an item from user's playlist
  static Future<bool> removeFromPlaylist({
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
        debugPrint('✅ [PLAYLIST] Removed from playlist: $renderId');
        return true;
      } else {
        debugPrint('❌ [PLAYLIST] Failed to remove: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ [PLAYLIST] Error removing from playlist: $e');
      return false;
    }
  }
  
  /// Get user's playlist
  static Future<List<PlaylistItem>> getPlaylist({
    required String userId,
  }) async {
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
        
        debugPrint('✅ [PLAYLIST] Loaded playlist: ${playlist.length} items');
        return playlist;
      } else {
        debugPrint('❌ [PLAYLIST] Failed to load playlist: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('❌ [PLAYLIST] Error loading playlist: $e');
      return [];
    }
  }
}

