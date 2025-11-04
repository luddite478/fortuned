import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'reliable_storage.dart';
import '../state/sequencer/table.dart';
import '../state/sequencer/playback.dart';
import '../state/sequencer/sample_bank.dart';
import 'snapshot/snapshot_service.dart';

/// Service for managing thread-specific draft states
/// 
/// Each thread can have a local draft that persists across app sessions.
/// Drafts are saved when navigating away from the sequencer screen and loaded
/// when opening a thread (if no server snapshot exists).
class ThreadDraftService {
  static const String _draftPrefix = 'thread_draft_';
  
  final TableState _tableState;
  final PlaybackState _playbackState;
  final SampleBankState _sampleBankState;
  
  String? _currentThreadId;
  
  ThreadDraftService({
    required TableState tableState,
    required PlaybackState playbackState,
    required SampleBankState sampleBankState,
  })  : _tableState = tableState,
        _playbackState = playbackState,
        _sampleBankState = sampleBankState;
  
  /// Start tracking a specific thread
  /// Call this when opening a thread in the sequencer
  void startTracking(String threadId) {
    _currentThreadId = threadId;
    debugPrint('📝 [DRAFT] Started tracking draft for thread: $threadId');
  }
  
  /// Stop tracking (when leaving sequencer or switching threads)
  void stopTracking() {
    _currentThreadId = null;
    debugPrint('📝 [DRAFT] Stopped tracking draft');
  }
  
  /// Save draft for the currently tracked thread
  /// Call this when navigating away from the sequencer screen
  Future<void> saveDraft() async {
    if (_currentThreadId == null) return;
    await _saveDraft(_currentThreadId!);
  }
  
  /// Save draft for a specific thread
  Future<void> _saveDraft(String threadId) async {
    try {
      final service = SnapshotService(
        tableState: _tableState,
        playbackState: _playbackState,
        sampleBankState: _sampleBankState,
      );
      
      final jsonString = service.exportToJson(
        name: 'Draft',
        id: null,
        description: 'Local draft for thread $threadId',
      );
      
      final key = _getDraftKey(threadId);
      await ReliableStorage.setString(key, jsonString);
      
      debugPrint('💾 [DRAFT] Saved draft for thread: $threadId');
    } catch (e) {
      debugPrint('❌ [DRAFT] Failed to save draft for thread $threadId: $e');
    }
  }
  
  /// Load draft for a specific thread
  /// Returns the snapshot JSON string, or null if no draft exists
  Future<Map<String, dynamic>?> loadDraft(String threadId) async {
    try {
      final key = _getDraftKey(threadId);
      final jsonString = await ReliableStorage.getString(key);
      
      if (jsonString == null || jsonString.isEmpty) {
        debugPrint('📝 [DRAFT] No draft found for thread: $threadId');
        return null;
      }
      
      final snapshot = json.decode(jsonString) as Map<String, dynamic>;
      debugPrint('📥 [DRAFT] Loaded draft for thread: $threadId');
      return snapshot;
    } catch (e) {
      debugPrint('❌ [DRAFT] Failed to load draft for thread $threadId: $e');
      return null;
    }
  }
  
  /// Clear draft for a specific thread
  /// Call this when a message is saved (draft becomes committed)
  Future<void> clearDraft(String threadId) async {
    try {
      final key = _getDraftKey(threadId);
      await ReliableStorage.remove(key);
      debugPrint('🗑️ [DRAFT] Cleared draft for thread: $threadId');
    } catch (e) {
      debugPrint('❌ [DRAFT] Failed to clear draft for thread $threadId: $e');
    }
  }
  
  /// Clear all drafts (useful for cleanup or testing)
  /// Note: This requires knowing thread IDs, so it's mainly for testing
  Future<void> clearAllDrafts(List<String> threadIds) async {
    try {
      int cleared = 0;
      for (final threadId in threadIds) {
        await clearDraft(threadId);
        cleared++;
      }
      debugPrint('🗑️ [DRAFT] Cleared $cleared drafts');
    } catch (e) {
      debugPrint('❌ [DRAFT] Failed to clear all drafts: $e');
    }
  }
  
  String _getDraftKey(String threadId) {
    return '$_draftPrefix$threadId';
  }
}

