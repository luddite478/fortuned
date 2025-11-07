import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../http_client.dart';
import '../../models/thread/thread.dart';
import 'local_cache_service.dart';
import 'sync_state_service.dart';

/// Manages thread metadata caching with background sync
/// 
/// Strategy:
/// - Load from cache first (instant UI)
/// - Sync from server in background (throttled to 60s)
/// - Server always wins on conflicts
class ThreadsCacheService {
  static const String _threadsFile = 'threads.json';
  static const String _syncKey = 'threads';
  static const Duration _syncThrottle = Duration(seconds: 60);

  /// Load threads for a user
  /// Returns cached data immediately, syncs from server in background
  static Future<List<Thread>> loadThreads({
    required String userId,
    bool forceSync = false,
  }) async {
    // Step 1: Load from cache first
    final cachedThreads = await _loadFromCache();

    // Step 2: Check if we should sync
    final shouldSync = forceSync || 
        await SyncStateService.shouldSync(_syncKey, _syncThrottle);

    if (shouldSync) {
      // Sync in background (don't await)
      _syncFromServer(userId).then((freshThreads) {
        if (freshThreads != null) {
          debugPrint('✅ [THREADS] Background sync completed: ${freshThreads.length} threads');
        }
      });
    } else {
      final lastSync = await SyncStateService.getLastSyncTime(_syncKey);
      if (lastSync != null) {
        final secondsAgo = DateTime.now().difference(lastSync).inSeconds;
        debugPrint('⏭️ [THREADS] Skipping sync (last synced ${secondsAgo}s ago)');
      }
    }

    return cachedThreads;
  }

  /// Load threads from cache
  static Future<List<Thread>> _loadFromCache() async {
    try {
      final data = await LocalCacheService.readJson(_threadsFile);
      if (data == null) {
        debugPrint('📂 [THREADS] No cached threads found');
        return [];
      }

      final threadsData = data['threads'] as List? ?? [];
      final threads = threadsData
          .map((t) => Thread.fromJson(t as Map<String, dynamic>))
          .toList();

      debugPrint('✅ [THREADS] Loaded ${threads.length} threads from cache');
      return threads;
    } catch (e) {
      debugPrint('❌ [THREADS] Error loading from cache: $e');
      return [];
    }
  }

  /// Sync threads from server
  static Future<List<Thread>?> _syncFromServer(String userId) async {
    try {
      final response = await ApiHttpClient.get(
        '/threads',
        queryParams: {
          'user_id': userId,
          'limit': '100',
        },
      );

      if (response.statusCode != 200) {
        debugPrint('❌ [THREADS] Server returned ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final threadsData = json['threads'] as List? ?? [];
      final threads = threadsData
          .map((t) => Thread.fromJson(t as Map<String, dynamic>))
          .toList();

      // Save to cache
      await _saveToCache(threads);
      await SyncStateService.updateSyncTime(_syncKey, DateTime.now());

      debugPrint('✅ [THREADS] Synced ${threads.length} threads from server');
      return threads;
    } catch (e) {
      debugPrint('❌ [THREADS] Sync failed: $e (continuing with cached data)');
      return null;
    }
  }

  /// Save threads to cache
  static Future<bool> _saveToCache(List<Thread> threads) async {
    final data = {
      'version': 1,
      'cached_at': DateTime.now().toIso8601String(),
      'threads': threads.map((t) => t.toJson()).toList(),
    };

    return await LocalCacheService.writeJson(_threadsFile, data);
  }

  /// Force sync from server (bypasses throttle)
  static Future<List<Thread>?> forceSync({required String userId}) async {
    return await _syncFromServer(userId);
  }

  /// Clear thread cache
  static Future<void> clearCache() async {
    await LocalCacheService.deleteFile(_threadsFile);
    await SyncStateService.clearSyncTime(_syncKey);
    debugPrint('✅ [THREADS] Cache cleared');
  }

  /// Get a single thread from cache by ID
  static Future<Thread?> getThreadById(String threadId) async {
    final threads = await _loadFromCache();
    try {
      return threads.firstWhere((t) => t.id == threadId);
    } catch (_) {
      return null;
    }
  }

  /// Update a thread in cache (after server update)
  static Future<bool> updateThreadInCache(Thread thread) async {
    final threads = await _loadFromCache();
    final index = threads.indexWhere((t) => t.id == thread.id);
    
    if (index != -1) {
      threads[index] = thread;
    } else {
      threads.add(thread);
    }

    return await _saveToCache(threads);
  }

  /// Remove a thread from cache
  static Future<bool> removeThreadFromCache(String threadId) async {
    final threads = await _loadFromCache();
    threads.removeWhere((t) => t.id == threadId);
    return await _saveToCache(threads);
  }
}

