import 'package:flutter/foundation.dart';
import 'local_cache_service.dart';

/// Tracks last sync timestamps for each resource to enable incremental syncing
/// 
/// Example sync_state.json:
/// {
///   "threads": "2025-11-07T10:30:00.000Z",
///   "messages:thread_123": "2025-11-07T10:31:00.000Z",
///   "snapshots": "2025-11-07T10:32:00.000Z"
/// }
class SyncStateService {
  static const String _syncStateFile = 'sync_state.json';

  /// Get the last sync time for a specific resource
  /// Returns null if never synced
  static Future<DateTime?> getLastSyncTime(String resourceKey) async {
    try {
      final data = await LocalCacheService.readJson(_syncStateFile);
      if (data == null) return null;

      final timestamp = data[resourceKey] as String?;
      if (timestamp == null) return null;

      return DateTime.parse(timestamp);
    } catch (e) {
      debugPrint('❌ [SYNC_STATE] Error reading sync time for $resourceKey: $e');
      return null;
    }
  }

  /// Update the last sync time for a specific resource
  static Future<void> updateSyncTime(String resourceKey, DateTime time) async {
    try {
      final data = await LocalCacheService.readJson(_syncStateFile) ?? {};
      data[resourceKey] = time.toIso8601String();
      
      final success = await LocalCacheService.writeJson(_syncStateFile, data);
      if (success) {
        debugPrint('✅ [SYNC_STATE] Updated $resourceKey: ${time.toIso8601String()}');
      }
    } catch (e) {
      debugPrint('❌ [SYNC_STATE] Error updating sync time for $resourceKey: $e');
    }
  }

  /// Get sync times for multiple resources
  static Future<Map<String, DateTime>> getSyncTimes(List<String> resourceKeys) async {
    final result = <String, DateTime>{};
    
    try {
      final data = await LocalCacheService.readJson(_syncStateFile);
      if (data == null) return result;

      for (final key in resourceKeys) {
        final timestamp = data[key] as String?;
        if (timestamp != null) {
          try {
            result[key] = DateTime.parse(timestamp);
          } catch (_) {
            // Skip invalid timestamps
          }
        }
      }
    } catch (e) {
      debugPrint('❌ [SYNC_STATE] Error reading sync times: $e');
    }

    return result;
  }

  /// Clear sync state for a specific resource
  static Future<void> clearSyncTime(String resourceKey) async {
    try {
      final data = await LocalCacheService.readJson(_syncStateFile) ?? {};
      data.remove(resourceKey);
      await LocalCacheService.writeJson(_syncStateFile, data);
      debugPrint('✅ [SYNC_STATE] Cleared sync time for $resourceKey');
    } catch (e) {
      debugPrint('❌ [SYNC_STATE] Error clearing sync time for $resourceKey: $e');
    }
  }

  /// Clear all sync state
  static Future<void> clearAll() async {
    try {
      await LocalCacheService.deleteFile(_syncStateFile);
      debugPrint('✅ [SYNC_STATE] Cleared all sync times');
    } catch (e) {
      debugPrint('❌ [SYNC_STATE] Error clearing all sync times: $e');
    }
  }

  /// Check if a resource should be synced based on throttle duration
  /// Returns true if last sync was more than [throttleDuration] ago, or never synced
  static Future<bool> shouldSync(
    String resourceKey,
    Duration throttleDuration,
  ) async {
    final lastSync = await getLastSyncTime(resourceKey);
    if (lastSync == null) return true;

    final timeSinceSync = DateTime.now().difference(lastSync);
    return timeSinceSync >= throttleDuration;
  }
}

