import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../http_client.dart';
import '../upload_service.dart';
import 'local_cache_service.dart';

/// Manages offline operation queue and syncing
/// 
/// Strategy:
/// - Queue operations when offline or network errors occur
/// - Process queue when connectivity returns
/// - Retry with exponential backoff (max 3 attempts)
/// - Remove operations after successful sync
class OfflineSyncService {
  static const String _queueFile = 'pending_sync/operations.json';
  static const _uuid = Uuid();

  /// Queue an operation for later sync
  /// 
  /// Example operation:
  /// {
  ///   'type': 'create_message',
  ///   'thread_id': '123',
  ///   'message': {...}
  /// }
  static Future<void> queueOperation(Map<String, dynamic> operation) async {
    try {
      final queue = await _loadQueue();
      
      queue.add({
        ...operation,
        'id': _uuid.v4(),
        'queued_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
      });

      await _saveQueue(queue);
      debugPrint('⏳ [OFFLINE_SYNC] Queued operation: ${operation['type']}');
    } catch (e) {
      debugPrint('❌ [OFFLINE_SYNC] Error queuing operation: $e');
    }
  }

  /// Process all pending operations in the queue
  /// Call this when connectivity returns or on app resume
  static Future<void> processQueue() async {
    final queue = await _loadQueue();
    
    if (queue.isEmpty) {
      debugPrint('✅ [OFFLINE_SYNC] Queue is empty');
      return;
    }

    debugPrint('🔄 [OFFLINE_SYNC] Processing ${queue.length} pending operations');

    final List<Map<String, dynamic>> failed = [];
    int successCount = 0;

    for (var operation in queue) {
      try {
        final success = await _executeOperation(operation);

        if (success) {
          successCount++;
          debugPrint('✅ [OFFLINE_SYNC] Synced: ${operation['type']}');
        } else {
          // Increment retry count
          operation['retry_count'] = (operation['retry_count'] ?? 0) + 1;

          if (operation['retry_count'] < 3) {
            failed.add(operation);
            debugPrint('⚠️ [OFFLINE_SYNC] Failed, will retry: ${operation['type']}');
          } else {
            debugPrint('❌ [OFFLINE_SYNC] Failed after 3 retries: ${operation['type']}');
          }
        }
      } catch (e) {
        debugPrint('❌ [OFFLINE_SYNC] Error executing operation: $e');
        operation['retry_count'] = (operation['retry_count'] ?? 0) + 1;
        if (operation['retry_count'] < 3) {
          failed.add(operation);
        }
      }
    }

    // Save failed operations back to queue
    await _saveQueue(failed);

    if (successCount > 0) {
      debugPrint('✅ [OFFLINE_SYNC] Processed $successCount operations successfully');
    }
    if (failed.isNotEmpty) {
      debugPrint('⚠️ [OFFLINE_SYNC] ${failed.length} operations remain in queue');
    }
  }

  /// Execute a single operation
  static Future<bool> _executeOperation(Map<String, dynamic> operation) async {
    final type = operation['type'] as String;

    switch (type) {
      case 'create_message':
        return await _syncCreateMessage(operation);

      case 'delete_message':
        return await _syncDeleteMessage(operation);

      case 'add_playlist':
        return await _syncAddPlaylist(operation);

      case 'remove_playlist':
        return await _syncRemovePlaylist(operation);
      
      case 'upload_audio':
        return await _syncUploadAudio(operation);

      default:
        debugPrint('⚠️ [OFFLINE_SYNC] Unknown operation type: $type');
        return false;
    }
  }

  /// Sync create message operation
  static Future<bool> _syncCreateMessage(Map<String, dynamic> op) async {
    try {
      final response = await ApiHttpClient.post(
        '/messages',
        body: op['message'],
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ [OFFLINE_SYNC] Create message failed: $e');
      return false;
    }
  }

  /// Sync delete message operation
  static Future<bool> _syncDeleteMessage(Map<String, dynamic> op) async {
    try {
      final messageId = op['message_id'] as String;
      final response = await ApiHttpClient.delete('/messages/$messageId');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ [OFFLINE_SYNC] Delete message failed: $e');
      return false;
    }
  }

  /// Sync add playlist operation
  static Future<bool> _syncAddPlaylist(Map<String, dynamic> op) async {
    try {
      final response = await ApiHttpClient.post(
        '/users/playlist/add',
        body: {
          'user_id': op['user_id'],
          'render': op['render'],
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ [OFFLINE_SYNC] Add playlist failed: $e');
      return false;
    }
  }

  /// Sync remove playlist operation
  static Future<bool> _syncRemovePlaylist(Map<String, dynamic> op) async {
    try {
      final response = await ApiHttpClient.post(
        '/users/playlist/remove',
        body: {
          'user_id': op['user_id'],
          'render_id': op['render_id'],
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ [OFFLINE_SYNC] Remove playlist failed: $e');
      return false;
    }
  }
  
  /// Sync audio upload operation
  static Future<bool> _syncUploadAudio(Map<String, dynamic> op) async {
    try {
      final messageId = op['message_id'] as String;
      final filePath = op['file_path'] as String;
      final format = op['format'] as String? ?? 'mp3';
      final bitrate = op['bitrate'] as int? ?? 320;
      
      // Check if file still exists
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ [OFFLINE_SYNC] Audio file no longer exists: $filePath');
        return true; // File gone, remove from queue (success = remove)
      }
      
      debugPrint('🔄 [OFFLINE_SYNC] Retrying audio upload for message $messageId');
      
      // Upload audio
      final render = await UploadService.uploadAudio(
        filePath: filePath,
        format: format,
        bitrate: bitrate,
      );
      
      if (render == null) {
        debugPrint('❌ [OFFLINE_SYNC] Audio upload failed, will retry');
        return false; // Failed, keep in queue for retry
      }
      
      debugPrint('✅ [OFFLINE_SYNC] Audio uploaded successfully: ${render.url}');
      
      // Attach render to message
      final attachResponse = await ApiHttpClient.post(
        '/messages/$messageId/renders',
        body: {
          'render': render.toJson(),
        },
      );
      
      if (attachResponse.statusCode == 200) {
        debugPrint('✅ [OFFLINE_SYNC] Render attached to message $messageId');
        return true; // Success, remove from queue
      } else {
        debugPrint('❌ [OFFLINE_SYNC] Failed to attach render: ${attachResponse.statusCode}');
        return false; // Keep in queue for retry
      }
    } catch (e) {
      debugPrint('❌ [OFFLINE_SYNC] Upload audio failed: $e');
      return false; // Keep in queue for retry
    }
  }

  /// Load queue from cache
  static Future<List<Map<String, dynamic>>> _loadQueue() async {
    try {
      final data = await LocalCacheService.readJson(_queueFile);
      if (data == null) {
        return [];
      }

      final operations = data['operations'] as List? ?? [];
      return operations.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ [OFFLINE_SYNC] Error loading queue: $e');
      return [];
    }
  }

  /// Save queue to cache
  static Future<bool> _saveQueue(List<Map<String, dynamic>> queue) async {
    final data = {
      'version': 1,
      'updated_at': DateTime.now().toIso8601String(),
      'operations': queue,
    };

    return await LocalCacheService.writeJson(_queueFile, data);
  }

  /// Get queue status
  static Future<Map<String, dynamic>> getQueueStatus() async {
    final queue = await _loadQueue();
    
    final byType = <String, int>{};
    for (var op in queue) {
      final type = op['type'] as String;
      byType[type] = (byType[type] ?? 0) + 1;
    }

    return {
      'total': queue.length,
      'by_type': byType,
      'has_pending': queue.isNotEmpty,
    };
  }

  /// Clear the queue (use with caution)
  static Future<void> clearQueue() async {
    await LocalCacheService.deleteFile(_queueFile);
    debugPrint('✅ [OFFLINE_SYNC] Queue cleared');
  }

  /// Remove a specific operation from queue by ID
  static Future<void> removeOperation(String operationId) async {
    final queue = await _loadQueue();
    queue.removeWhere((op) => op['id'] == operationId);
    await _saveQueue(queue);
    debugPrint('✅ [OFFLINE_SYNC] Removed operation: $operationId');
  }
}

