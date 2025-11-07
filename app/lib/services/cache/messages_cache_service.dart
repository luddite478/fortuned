import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../http_client.dart';
import '../../models/thread/message.dart';
import 'local_cache_service.dart';
import 'sync_state_service.dart';
import 'offline_sync_service.dart';

/// Manages message caching with incremental sync and optimistic updates
/// 
/// Strategy:
/// - Load from cache first (instant UI)
/// - Fetch only new messages since last sync (incremental)
/// - Optimistic updates for creates (update UI immediately)
/// - Queue offline operations for later sync
class MessagesCacheService {
  static const String _messagesDir = 'messages';

  /// Get the sync key for a specific thread
  static String _getSyncKey(String threadId) => 'messages:$threadId';

  /// Get the file path for a thread's messages
  static String _getFilePath(String threadId) => '$_messagesDir/$threadId.json';

  /// Load messages for a thread
  /// Returns cached messages + syncs new messages since last sync
  static Future<List<Message>> loadMessages({
    required String threadId,
    bool forceFullSync = false,
  }) async {
    // Step 1: Load from cache
    final cachedMessages = await _loadFromCache(threadId);

    // Step 2: Sync new messages since last sync
    final lastSync = await SyncStateService.getLastSyncTime(_getSyncKey(threadId));
    final newMessages = await _syncNewMessages(
      threadId,
      since: forceFullSync ? null : lastSync,
    );

    // Step 3: Merge and save if we got new messages
    if (newMessages.isNotEmpty) {
      final merged = _mergeMessages(cachedMessages, newMessages);
      await _saveToCache(threadId, merged);
      debugPrint('✅ [MESSAGES] Synced ${newMessages.length} new messages for thread $threadId');
      return merged;
    }

    if (cachedMessages.isNotEmpty) {
      debugPrint('✅ [MESSAGES] Loaded ${cachedMessages.length} messages from cache');
    }

    return cachedMessages;
  }

  /// Load messages from cache
  static Future<List<Message>> _loadFromCache(String threadId) async {
    try {
      final data = await LocalCacheService.readJson(_getFilePath(threadId));
      if (data == null) {
        return [];
      }

      final messagesData = data['messages'] as List? ?? [];
      final messages = messagesData
          .map((m) => Message.fromJson(m as Map<String, dynamic>))
          .toList();

      return messages;
    } catch (e) {
      debugPrint('❌ [MESSAGES] Error loading from cache: $e');
      return [];
    }
  }

  /// Sync new messages from server (incremental)
  static Future<List<Message>> _syncNewMessages(
    String threadId, {
    DateTime? since,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': '1000',
        'include_snapshot': 'false', // Fetch metadata only, snapshots on-demand
      };

      // Add 'since' filter for incremental sync
      if (since != null) {
        queryParams['since'] = since.toIso8601String();
      }

      final response = await ApiHttpClient.get(
        '/threads/$threadId/messages',
        queryParams: queryParams,
      );

      if (response.statusCode != 200) {
        debugPrint('❌ [MESSAGES] Server returned ${response.statusCode}');
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final messagesData = json['messages'] as List? ?? [];
      final messages = messagesData
          .map((m) => Message.fromJson(m as Map<String, dynamic>))
          .toList();

      // Update sync time
      await SyncStateService.updateSyncTime(
        _getSyncKey(threadId),
        DateTime.now(),
      );

      return messages;
    } catch (e) {
      debugPrint('❌ [MESSAGES] Sync failed: $e');
      return [];
    }
  }

  /// Merge cached and fresh messages (server wins on conflicts)
  static List<Message> _mergeMessages(
    List<Message> cached,
    List<Message> fresh,
  ) {
    final Map<String, Message> merged = {
      for (var msg in cached) msg.id: msg,
    };

    // Add/update with fresh messages (server wins)
    for (var msg in fresh) {
      merged[msg.id] = msg;
    }

    // Sort by timestamp
    final result = merged.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return result;
  }

  /// Save messages to cache
  static Future<bool> _saveToCache(String threadId, List<Message> messages) async {
    final data = {
      'version': 1,
      'thread_id': threadId,
      'cached_at': DateTime.now().toIso8601String(),
      'last_synced_at': DateTime.now().toIso8601String(),
      'messages': messages.map((m) => m.toJson()).toList(),
    };

    return await LocalCacheService.writeJson(_getFilePath(threadId), data);
  }

  /// Create a new message (optimistic update)
  /// Updates cache immediately, syncs to server, queues if offline
  static Future<bool> createMessage({
    required String threadId,
    required Message message,
  }) async {
    // Step 1: Add to cache immediately (optimistic)
    final cachedMessages = await _loadFromCache(threadId);
    cachedMessages.add(message);
    await _saveToCache(threadId, cachedMessages);

    debugPrint('✅ [MESSAGES] Message added to cache (optimistic)');

    // Step 2: Send to server
    try {
      final response = await ApiHttpClient.post(
        '/messages',
        body: message.toJson(),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ [MESSAGES] Message synced to server');
        return true;
      } else {
        // Server rejected - remove from cache (rollback)
        debugPrint('❌ [MESSAGES] Server rejected message, rolling back');
        cachedMessages.removeWhere((m) => m.id == message.id);
        await _saveToCache(threadId, cachedMessages);
        return false;
      }
    } catch (e) {
      // Offline or network error - queue for later sync
      debugPrint('⏳ [MESSAGES] Offline: queuing message for later sync');
      await OfflineSyncService.queueOperation({
        'type': 'create_message',
        'thread_id': threadId,
        'message': message.toJson(),
      });
      return true; // Keep in cache, will sync when online
    }
  }

  /// Delete a message
  /// Updates cache optimistically, syncs to server, queues if offline
  static Future<bool> deleteMessage({
    required String threadId,
    required String messageId,
  }) async {
    // Step 1: Remove from cache optimistically
    final cachedMessages = await _loadFromCache(threadId);
    final originalIndex = cachedMessages.indexWhere((m) => m.id == messageId);
    
    if (originalIndex == -1) {
      debugPrint('❌ [MESSAGES] Message not found in cache: $messageId');
      return false;
    }

    final removedMessage = cachedMessages.removeAt(originalIndex);
    await _saveToCache(threadId, cachedMessages);

    debugPrint('✅ [MESSAGES] Message removed from cache (optimistic)');

    // Step 2: Delete on server
    try {
      final response = await ApiHttpClient.delete('/messages/$messageId');

      if (response.statusCode == 200) {
        debugPrint('✅ [MESSAGES] Message deleted on server');
        return true;
      } else {
        // Server rejected - restore to cache (rollback)
        debugPrint('❌ [MESSAGES] Server rejected delete, rolling back');
        cachedMessages.insert(originalIndex, removedMessage);
        await _saveToCache(threadId, cachedMessages);
        return false;
      }
    } catch (e) {
      // Offline - queue for later sync
      debugPrint('⏳ [MESSAGES] Offline: queuing delete for later sync');
      await OfflineSyncService.queueOperation({
        'type': 'delete_message',
        'thread_id': threadId,
        'message_id': messageId,
      });
      return true; // Keep removed from cache, will sync when online
    }
  }

  /// Clear message cache for a specific thread
  static Future<void> clearCache(String threadId) async {
    await LocalCacheService.deleteFile(_getFilePath(threadId));
    await SyncStateService.clearSyncTime(_getSyncKey(threadId));
    debugPrint('✅ [MESSAGES] Cache cleared for thread $threadId');
  }

  /// Clear all message caches
  static Future<void> clearAllCaches() async {
    try {
      final dir = await LocalCacheService.getCacheDirectory(_messagesDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      debugPrint('✅ [MESSAGES] All message caches cleared');
    } catch (e) {
      debugPrint('❌ [MESSAGES] Error clearing all caches: $e');
    }
  }

  /// Get a single message from cache by ID
  static Future<Message?> getMessageById({
    required String threadId,
    required String messageId,
  }) async {
    final messages = await _loadFromCache(threadId);
    try {
      return messages.firstWhere((m) => m.id == messageId);
    } catch (_) {
      return null;
    }
  }
}

