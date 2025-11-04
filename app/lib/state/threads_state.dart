import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/thread/thread.dart';
import '../models/thread/message.dart';
import '../models/thread/thread_user.dart';
import '../models/thread/thread_invite.dart';
import '../services/threads_api.dart';
import '../services/ws_client.dart';
import '../services/snapshot/snapshot_service.dart';
import '../services/upload_service.dart';
import 'sequencer/table.dart';
import 'sequencer/playback.dart';
import 'sequencer/sample_bank.dart';
import 'sequencer/recording.dart';

class ThreadsState extends ChangeNotifier {
  final WebSocketClient _wsClient;

  // Identity
  String? _currentUserId;
  String? _currentUserName;

  // Data
  final List<Thread> _threads = [];
  final List<Thread> _unsyncedThreads = [];
  Thread? _activeThread;
  final Map<String, List<Message>> _messagesByThread = {};
  final Map<String, bool> _messagesLoadingByThread = {};
  bool _isThreadViewActive = false;
  
  // Track deleted thread IDs to prevent restoration during refresh
  final Set<String> _deletedThreadIds = {};

  // UI state
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _error;
  
  // Track if initial load is complete
  bool _hasLoaded = false;

  // Snapshot service factory deps
  final TableState _tableState;
  final PlaybackState _playbackState;
  final SampleBankState _sampleBankState;
  RecordingState? _recordingState;

  ThreadsState({
    required WebSocketClient wsClient,
    required TableState tableState,
    required PlaybackState playbackState,
    required SampleBankState sampleBankState,
  })  : _wsClient = wsClient,
        _tableState = tableState,
        _playbackState = playbackState,
        _sampleBankState = sampleBankState {
    _registerWsHandlers();
  }

  void attachRecordingState(RecordingState recordingState) {
    _recordingState = recordingState;
  }

  // Getters
  List<Thread> get threads {
    final all = [..._threads, ..._unsyncedThreads];
    all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(all);
  }
  Thread? get activeThread => _activeThread;
  // Backward-compat alias for older call sites
  Thread? get currentThread => _activeThread;
  List<Message> get activeThreadMessages =>
      _activeThread == null ? const [] : List.unmodifiable(_messagesByThread[_activeThread!.id] ?? const []);
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;
  String? get currentUserId => _currentUserId;
  String? get currentUserName => _currentUserName;
  bool get isThreadViewActive => _isThreadViewActive;
  
  bool isLoadingMessages(String threadId) => _messagesLoadingByThread[threadId] ?? false;
  bool hasMessagesLoaded(String threadId) => _messagesByThread.containsKey(threadId);

  void setCurrentUser(String userId, [String? userName]) {
    _currentUserId = userId;
    _currentUserName = userName;
    notifyListeners();
  }

  void setActiveThread(Thread? thread) {
    _activeThread = thread;
    notifyListeners();
  }

  void enterThreadView(String threadId) {
    _isThreadViewActive = true;
    notifyListeners();
  }

  void exitThreadView() {
    _isThreadViewActive = false;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String? value) {
    _error = value;
    notifyListeners();
  }

  Future<void> loadThreads({bool silent = false}) async {
    // If already loaded and not forcing refresh, return immediately
    if (_hasLoaded && !silent) {
      debugPrint('🧵 [THREADS] Using cached threads (${_threads.length} items)');
      return;
    }
    
    try {
      if (!silent) {
        _isLoading = true;
        notifyListeners();
      } else {
        _isRefreshing = true;
      }
      
      _error = null;
      
      final result = await ThreadsApi.getThreads(userId: _currentUserId);
      // Filter out threads that were deleted locally to prevent restoration
      final filtered = result.where((t) => !_deletedThreadIds.contains(t.id)).toList();
      _threads
        ..clear()
        ..addAll(filtered);
      _hasLoaded = true;

      await syncOfflineThreads();
      
      debugPrint('🧵 [THREADS] Loaded threads: ${_threads.length} items');
    } catch (e) {
      _setError('Failed to load threads: $e');
      debugPrint('❌ [THREADS] Error loading threads: $e');
      rethrow;
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
    }
  }
  
  /// Refresh threads in background (silent update)
  Future<void> refreshThreadsInBackground() async {
    if (!_hasLoaded) {
      // If not loaded yet, do a normal load
      await loadThreads();
      return;
    }
    
    debugPrint('🔄 [THREADS] Refreshing threads in background...');
    await loadThreads(silent: true);
  }

  Future<void> ensureThreadSummary(String threadId) async {
    // Don't restore deleted threads
    if (_deletedThreadIds.contains(threadId)) {
      return;
    }
    
    try {
      _setError(null);
      final thread = await ThreadsApi.getThread(threadId);
      // Double-check thread wasn't deleted while fetching
      if (_deletedThreadIds.contains(threadId)) {
        return;
      }
      final existingIndex = _threads.indexWhere((t) => t.id == threadId);
      if (existingIndex >= 0) {
        _threads[existingIndex] = thread;
      } else {
        _threads.add(thread);
      }
      notifyListeners();
    } catch (e) {
      _setError('Failed to load thread summary: $e');
      rethrow;
    }
  }

  Future<void> loadMessages(
    String threadId, {
    bool force = false,
    int? limit,
    String? order,
    bool includeSnapshot = false,
  }) async {
    // Skip if already loaded and not forcing refresh
    if (!force && _messagesByThread.containsKey(threadId)) {
      debugPrint('📬 [THREADS] Using cached messages for thread $threadId (${_messagesByThread[threadId]?.length} messages)');
      return;
    }
    
    try {
      _messagesLoadingByThread[threadId] = true;
      _setLoading(true);
      _setError(null);
      notifyListeners();
      
      final messages = await ThreadsApi.getMessages(
        threadId,
        limit: limit,
        order: order,
        includeSnapshot: includeSnapshot,
      );
      // Store in ascending (oldest -> newest) for UI
      final List<Message> stored = (order == 'desc') ? messages.reversed.toList() : messages;
      
      // Merge with any existing optimistic uploads
      final existingMessages = _messagesByThread[threadId] ?? [];
      _messagesByThread[threadId] = _mergeMessagesPreservingUploads(existingMessages, stored);
      
      debugPrint('📬 [THREADS] Loaded ${stored.length} messages for thread $threadId (stored ascending)');
    } catch (e) {
      _setError('Failed to load messages: $e');
      debugPrint('❌ [THREADS] Error loading messages: $e');
      rethrow;
    } finally {
      _messagesLoadingByThread[threadId] = false;
      _setLoading(false);
      notifyListeners();
    }
  }

  /// Preload recent messages in background (silent, without snapshots for speed)
  /// This is called when opening sequencer to make thread screen navigation instant
  /// Always reloads with the specified limit to ensure fresh data
  Future<void> preloadRecentMessages(String threadId, {int limit = 30}) async {
    // Skip if currently loading
    if (_messagesLoadingByThread[threadId] == true) {
      debugPrint('📬 [THREADS] Messages currently loading for thread $threadId, skipping preload');
      return;
    }
    
    try {
      _messagesLoadingByThread[threadId] = true;
      notifyListeners();
      
      debugPrint('📬 [THREADS] Preloading recent $limit messages in background for thread $threadId...');
      final messages = await ThreadsApi.getMessages(
        threadId,
        limit: limit,
        order: 'desc',
        includeSnapshot: false, // Don't load snapshots for speed
      );
      // Store ascending for UI
      final stored = messages.reversed.toList();
      
      // Merge with any existing optimistic uploads
      final existingMessages = _messagesByThread[threadId] ?? [];
      _messagesByThread[threadId] = _mergeMessagesPreservingUploads(existingMessages, stored);
      
      debugPrint('✅ [THREADS] Preloaded ${messages.length} recent messages for thread $threadId');
    } catch (e) {
      debugPrint('⚠️ [THREADS] Failed to preload messages (non-critical): $e');
      // Don't rethrow - this is a background operation
    } finally {
      _messagesLoadingByThread[threadId] = false;
      notifyListeners();
    }
  }

  Future<String> createThread({
    required List<ThreadUser> users,
    required String name,
    Map<String, dynamic>? metadata,
  }) async {
    final connectivityResult = await (Connectivity().checkConnectivity());
    final isOnline = connectivityResult != ConnectivityResult.none;

    if (!isOnline) {
      return _createThreadOffline(users: users, name: name, metadata: metadata);
    }

    try {
      _setLoading(true);
      _setError(null);
      final threadId = await ThreadsApi.createThread(
        users: users, 
        name: name,
        metadata: metadata,
      );
      await ensureThreadSummary(threadId);
      // Set active thread to the newly created one
      final idx = _threads.indexWhere((t) => t.id == threadId);
      if (idx >= 0) {
        _activeThread = _threads[idx];
      } else {
        _activeThread = Thread(
          id: threadId,
          name: name,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          users: const [],
          messageIds: const [],
          invites: const [],
        );
      }
      return threadId;
    } catch (e) {
      _setError('Failed to create thread: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  String _createThreadOffline({
    required List<ThreadUser> users,
    required String name,
    Map<String, dynamic>? metadata,
  }) {
    final tempId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final newThread = Thread(
      id: tempId,
      name: name,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      users: users,
      messageIds: const [],
      invites: const [],
      isLocal: true,
    );
    _unsyncedThreads.add(newThread);
    _activeThread = newThread;
    notifyListeners();
    return tempId;
  }

  Future<void> syncOfflineThreads() async {
    if (_unsyncedThreads.isEmpty) return;

    final connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) return;

    // Filter out deleted threads before syncing
    final threadsToSync = _unsyncedThreads.where((t) => !_deletedThreadIds.contains(t.id)).toList();
    if (threadsToSync.isEmpty) return;

    debugPrint('🔄 [THREADS] Syncing ${threadsToSync.length} offline threads...');
    
    final syncedThreads = <Thread>[];
    for (final localThread in threadsToSync) {
      try {
        final threadId = await ThreadsApi.createThread(
          users: localThread.users,
          name: localThread.name,
          metadata: localThread.metadata,
        );
        final syncedThread = await ThreadsApi.getThread(threadId);
        syncedThreads.add(syncedThread);
        
        // If the synced thread was active, update it
        if (_activeThread?.id == localThread.id) {
          _activeThread = syncedThread;
        }
      } catch (e) {
        debugPrint('❌ [THREADS] Failed to sync thread ${localThread.id}: $e');
        // Keep it in unsynced list to retry later
        syncedThreads.add(localThread);
      }
    }

    _unsyncedThreads.clear();
    for (final thread in syncedThreads) {
      if (thread.isLocal) {
        _unsyncedThreads.add(thread);
      } else {
        final existingIndex = _threads.indexWhere((t) => t.id == thread.id);
        if (existingIndex >= 0) {
          _threads[existingIndex] = thread;
        } else {
          _threads.add(thread);
        }
      }
    }
    notifyListeners();
  }

  Future<void> sendMessageFromSequencer({
    required String threadId,
  }) async {
    final snapshotService = SnapshotService(
      tableState: _tableState,
      playbackState: _playbackState,
      sampleBankState: _sampleBankState,
    );
    final jsonString = snapshotService.exportToJson(name: 'Snapshot');
    final Map<String, dynamic> snapshotMap = json.decode(jsonString) as Map<String, dynamic>;
    final snapshotMetadata = <String, dynamic>{
      'sections_count': _tableState.sectionsCount,
      'sections_steps': List<int>.generate(_tableState.sectionsCount, (i) => _tableState.getSectionStepCount(i)),
      'sections_loops_num': _playbackState.getSectionsLoopsNum(),
      'layers': _tableState.getLayersLengthPerSection(),
      'renders': <dynamic>[],
    };

    final tempId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    
    // Create optimistic render if there's audio to upload
    final List<Render> optimisticRenders = [];
    if (_recordingState != null && _recordingState!.convertedMp3Path != null) {
      final optimisticRender = Render(
        id: 'temp_${DateTime.now().microsecondsSinceEpoch}',
        url: '', // Empty until uploaded
        format: 'mp3',
        bitrate: 320,
        duration: _recordingState!.recordingDuration.inSeconds.toDouble(),
        createdAt: DateTime.now(),
        uploadStatus: RenderUploadStatus.uploading,
      );
      optimisticRenders.add(optimisticRender);
      debugPrint('🎵 [THREADS] Created optimistic render for message');
    }
    
    final pending = Message(
      id: '',
      createdAt: DateTime.now(),
      timestamp: DateTime.now(),
      userId: _currentUserId ?? 'unknown',
      parentThread: threadId,
      snapshot: snapshotMap,
      snapshotMetadata: snapshotMetadata,
      renders: optimisticRenders,
      localTempId: tempId,
      sendStatus: SendStatus.sending,
    );
    _messagesByThread.putIfAbsent(threadId, () => []);
    _messagesByThread[threadId] = [..._messagesByThread[threadId]!, pending];
    notifyListeners();

    try {
      final saved = await ThreadsApi.createMessage(
        threadId: threadId,
        userId: _currentUserId ?? 'unknown',
        snapshot: snapshotMap,
        snapshotMetadata: snapshotMetadata,
        renders: [],
        timestamp: pending.timestamp,
      );

      // Replace pending with saved (keep optimistic renders with uploading status)
      final list = _messagesByThread[threadId] ?? [];
      final idx = list.indexWhere((m) => m.localTempId == tempId);
      if (idx >= 0) {
        // Preserve optimistic renders from pending message
        final optimisticRenders = list[idx].renders.where((r) => r.uploadStatus == RenderUploadStatus.uploading).toList();
        final updated = saved.copyWith(
          sendStatus: SendStatus.sent, 
          localTempId: null,
          renders: optimisticRenders, // Keep optimistic renders
        );
        list[idx] = updated;
        _messagesByThread[threadId] = List<Message>.from(list);
        notifyListeners();
      } else {
        // If not found (e.g., reconciled by websocket), append if missing by id
        final exists = list.any((m) => m.id == saved.id);
        if (!exists) {
          _messagesByThread[threadId] = [...list, saved.copyWith(sendStatus: SendStatus.sent)];
          notifyListeners();
        }
      }
      
      // Check if there's a recording to upload - do this AFTER we have the message ID
      if (_recordingState != null && _recordingState!.convertedMp3Path != null) {
        debugPrint('🎵 [THREADS] Found recording to upload for message: ${saved.id}');
        _recordingState!.setUploading(true);
        _recordingState!.clearUploadStatus();
        
        // Start upload in background with the specific message ID
        unawaited(_uploadRecordingInBackground(saved.id, _recordingState!.convertedMp3Path!));
      }
    } catch (e) {
      // Mark as failed
      final list = _messagesByThread[threadId] ?? [];
      final idx = list.indexWhere((m) => m.localTempId == tempId);
      if (idx >= 0) {
        list[idx] = list[idx].copyWith(sendStatus: SendStatus.failed);
        _messagesByThread[threadId] = List<Message>.from(list);
        notifyListeners();
      }
    }
  }

  Future<void> _uploadRecordingInBackground(String messageId, String mp3Path) async {
    try {
      debugPrint('🔄 [THREADS] Starting upload for message $messageId: $mp3Path');
      
      final render = await UploadService.uploadAudio(
        filePath: mp3Path,
        format: 'mp3',
        bitrate: 320,
      );

      if (render != null) {
        debugPrint('✅ [THREADS] Upload completed: ${render.url}');
        _recordingState?.setUploadedRenderUrl(render.url);
        _recordingState?.setUploading(false);
        
        // Update the specific message with the uploaded render
        await _attachRenderToMessage(messageId, render);
      } else {
        debugPrint('❌ [THREADS] Upload failed');
        _recordingState?.setUploadError('Upload failed');
        _recordingState?.setUploading(false);
        
        // Mark render as failed in the message
        _markRenderAsFailed(messageId);
      }
    } catch (e) {
      debugPrint('❌ [THREADS] Upload error: $e');
      _recordingState?.setUploadError('Upload error: $e');
      _recordingState?.setUploading(false);
      
      // Mark render as failed in the message
      _markRenderAsFailed(messageId);
    }
  }
  
  void _markRenderAsFailed(String messageId) {
    // Find the message and mark its optimistic renders as failed
    for (final entry in _messagesByThread.entries) {
      final list = entry.value;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx >= 0) {
        final message = list[idx];
        final updatedRenders = message.renders.map((r) {
          if (r.uploadStatus == RenderUploadStatus.uploading) {
            return r.copyWith(uploadStatus: RenderUploadStatus.failed);
          }
          return r;
        }).toList();
        
        list[idx] = message.copyWith(renders: updatedRenders);
        _messagesByThread[entry.key] = List<Message>.from(list);
        notifyListeners();
        break;
      }
    }
  }

  Future<void> _attachRenderToMessage(String messageId, Render render) async {
    // Update on server first
    try {
      await ThreadsApi.attachRenderToMessage(messageId, render);
      debugPrint('✅ [THREADS] Render attached to message $messageId on server');
    } catch (e) {
      debugPrint('❌ [THREADS] Failed to attach render on server: $e');
      return;
    }
    
    // Update local state - find the message by ID across all threads
    for (final entry in _messagesByThread.entries) {
      final list = entry.value;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx >= 0) {
        final message = list[idx];
        
        // Replace optimistic renders with actual uploaded render
        final nonOptimisticRenders = message.renders.where((r) => r.uploadStatus != RenderUploadStatus.uploading).toList();
        final updatedRenders = [...nonOptimisticRenders, render.copyWith(uploadStatus: RenderUploadStatus.completed)];
        final updatedMessage = message.copyWith(renders: updatedRenders);
        
        list[idx] = updatedMessage;
        _messagesByThread[entry.key] = List<Message>.from(list);
        notifyListeners();
        
        debugPrint('✅ [THREADS] Replaced optimistic render with uploaded render for message $messageId');
        break;
      }
    }
  }

  /// Optimistically remove a thread from the local state
  /// Returns the removed thread if found, null otherwise
  Thread? removeThreadOptimistically(String threadId) {
    // Track as deleted to prevent restoration during refresh
    _deletedThreadIds.add(threadId);
    
    // Clean up cached messages
    _messagesByThread.remove(threadId);
    
    final threadIndex = _threads.indexWhere((t) => t.id == threadId);
    if (threadIndex >= 0) {
      final removed = _threads.removeAt(threadIndex);
      // Also clear active thread if it was the deleted one
      if (_activeThread?.id == threadId) {
        _activeThread = null;
      }
      notifyListeners();
      return removed;
    }
    
    final unsyncedIndex = _unsyncedThreads.indexWhere((t) => t.id == threadId);
    if (unsyncedIndex >= 0) {
      final removed = _unsyncedThreads.removeAt(unsyncedIndex);
      // Also clear active thread if it was the deleted one
      if (_activeThread?.id == threadId) {
        _activeThread = null;
      }
      notifyListeners();
      return removed;
    }
    
    return null;
  }

  Future<bool> deleteMessage(String threadId, String messageId) async {
    try {
      await ThreadsApi.deleteMessage(messageId);
      final list = _messagesByThread[threadId] ?? [];
      _messagesByThread[threadId] = list.where((m) => m.id != messageId).toList();
      notifyListeners();
      return true;
    } catch (e) {
      _setError('Failed to delete message: $e');
      return false;
    }
  }

  Future<void> retrySendMessage(String threadId, String localTempId) async {
    final list = _messagesByThread[threadId] ?? [];
    final idx = list.indexWhere((m) => m.localTempId == localTempId);
    if (idx < 0) return;
    final pending = list[idx];
    if (pending.sendStatus != SendStatus.failed) return;

    _messagesByThread[threadId] = [
      ...list..removeAt(idx),
      pending.copyWith(sendStatus: SendStatus.sending),
    ];
    notifyListeners();

    try {
      final saved = await ThreadsApi.createMessage(
        threadId: threadId,
        userId: _currentUserId ?? 'unknown',
        snapshot: pending.snapshot,
        snapshotMetadata: pending.snapshotMetadata,
        timestamp: pending.timestamp,
      );
      final refreshed = _messagesByThread[threadId] ?? [];
      final idx2 = refreshed.indexWhere((m) => m.localTempId == localTempId);
      if (idx2 >= 0) {
        refreshed[idx2] = saved.copyWith(sendStatus: SendStatus.sent, localTempId: null);
        _messagesByThread[threadId] = List<Message>.from(refreshed);
        notifyListeners();
      }
    } catch (e) {
      final refreshed = _messagesByThread[threadId] ?? [];
      final idx2 = refreshed.indexWhere((m) => m.localTempId == localTempId);
      if (idx2 >= 0) {
        refreshed[idx2] = refreshed[idx2].copyWith(sendStatus: SendStatus.failed);
        _messagesByThread[threadId] = List<Message>.from(refreshed);
        notifyListeners();
      }
    }
  }

  Future<bool> applyMessage(Message message) async {
    final service = SnapshotService(
      tableState: _tableState,
      playbackState: _playbackState,
      sampleBankState: _sampleBankState,
    );
    try {
      Map<String, dynamic> snapshotToApply = message.snapshot;
      if (snapshotToApply.isEmpty) {
        final full = await ThreadsApi.getMessageById(message.id, includeSnapshot: true);
        snapshotToApply = full.snapshot;
      }
      final jsonString = json.encode(snapshotToApply);
      final ok = await service.importFromJson(jsonString);
      return ok;
    } catch (_) {
      return false;
    }
  }

  // === UNIFIED PROJECT LOADING ===
  
  /// Load project snapshot from cache or API (cache-aware)
  /// Returns snapshot map or null if not available
  Future<Map<String, dynamic>?> loadProjectSnapshot(
    String threadId, {
    bool forceRefresh = false,
  }) async {
    debugPrint('📂 [PROJECT_LOAD] Loading snapshot for thread $threadId (forceRefresh: $forceRefresh)');
    
    // 1. Check cache first (if not forcing refresh)
    if (!forceRefresh) {
      final cachedMessages = _messagesByThread[threadId];
      if (cachedMessages != null && cachedMessages.isNotEmpty) {
        final latestCached = cachedMessages.last;
        if (latestCached.snapshot.isNotEmpty) {
          debugPrint('📦 [PROJECT_LOAD] Using cached snapshot from message ${latestCached.id}');
          return latestCached.snapshot;
        }
      }
    }
    
    // 2. Fetch from API with snapshot
    debugPrint('📥 [PROJECT_LOAD] Fetching latest message with snapshot from API');
    try {
      final latest = await ThreadsApi.getLatestMessage(threadId, includeSnapshot: true);
      
      if (latest == null) {
        debugPrint('⚠️ [PROJECT_LOAD] No messages found for thread $threadId');
        return null;
      }
      
      // 3. Update cache
      _updateMessageCache(threadId, latest);
      
      return latest.snapshot;
    } catch (e) {
      debugPrint('❌ [PROJECT_LOAD] Failed to fetch snapshot: $e');
      return null;
    }
  }
  
  /// Update message cache with a message (preserves existing snapshot if new one is empty)
  void _updateMessageCache(String threadId, Message message) {
    final messages = _messagesByThread[threadId] ?? [];
    final existingIndex = messages.indexWhere((m) => m.id == message.id);
    
    if (existingIndex >= 0) {
      // Update existing message (preserve snapshot if new message lacks it)
      final existing = messages[existingIndex];
      messages[existingIndex] = message.snapshot.isNotEmpty 
        ? message 
        : message.copyWith(snapshot: existing.snapshot);
      debugPrint('🔄 [PROJECT_LOAD] Updated cached message ${message.id}');
    } else {
      // Add new message
      messages.add(message);
      debugPrint('➕ [PROJECT_LOAD] Added message ${message.id} to cache');
    }
    
    _messagesByThread[threadId] = messages;
    notifyListeners();
  }
  
  /// Unified project loader - handles initialization, caching, and import
  /// This is the single entry point for loading projects from both:
  /// - Projects screen (initial load)
  /// - Thread view (checkpoint loading)
  Future<bool> loadProjectIntoSequencer(
    String threadId, {
    Map<String, dynamic>? snapshotOverride,
    bool forceRefresh = false,
  }) async {
    try {
      debugPrint('📂 [PROJECT_LOAD] === LOADING PROJECT $threadId ===');
      
      // 1. Get snapshot (from override, cache, or API)
      Map<String, dynamic>? snapshot = snapshotOverride;
      if (snapshot == null || snapshot.isEmpty) {
        snapshot = await loadProjectSnapshot(threadId, forceRefresh: forceRefresh);
      }
      
      if (snapshot == null || snapshot.isEmpty) {
        debugPrint('⚠️ [PROJECT_LOAD] No snapshot available for thread $threadId');
        return false;
      }
      
      // 2. Import snapshot (this handles ALL necessary resets internally)
      //    Note: The import process in import.dart handles:
      //    - Stops playback
      //    - Resets SunVox patterns (surgical, not full reinit)
      //    - Clears sample bank, table, sections
      //    - Imports fresh data
      //    - Recreates SunVox patterns and syncs
      //    - Clears undo/redo history
      //
      //    The native systems (table, playback, sample_bank) are already
      //    initialized by their state constructors, so no manual init needed.
      final service = SnapshotService(
        tableState: _tableState,
        playbackState: _playbackState,
        sampleBankState: _sampleBankState,
      );
      
      final jsonString = json.encode(snapshot);
      final ok = await service.importFromJson(jsonString);
      
      if (ok) {
        debugPrint('✅ [PROJECT_LOAD] Successfully loaded project $threadId');
      } else {
        debugPrint('❌ [PROJECT_LOAD] Failed to import project $threadId');
      }
      
      return ok;
    } catch (e, stackTrace) {
      debugPrint('❌ [PROJECT_LOAD] Failed to load project: $e');
      debugPrint('📋 [PROJECT_LOAD] Stack trace: $stackTrace');
      return false;
    }
  }

  // Invites
  Future<void> sendInvite({
    required String threadId,
    required String userId,
    required String userName,
  }) async {
    if (_currentUserId == null) throw Exception('User not authenticated');
    await ThreadsApi.sendInvite(
      threadId: threadId,
      userId: userId,
      userName: userName,
      invitedBy: _currentUserId!,
    );
    // Update local thread invites list
    final index = _threads.indexWhere((t) => t.id == threadId);
    if (index >= 0) {
      final invites = [..._threads[index].invites];
      invites.add(ThreadInvite(
        userId: userId,
        userName: userName,
        status: 'pending',
        invitedBy: _currentUserId!,
        invitedAt: DateTime.now(),
      ));
      _threads[index] = _threads[index].copyWith(invites: invites);
        if (_activeThread?.id == threadId) {
        _activeThread = _threads[index];
      }
      notifyListeners();
    }
  }

  Future<void> acceptInvite({required String threadId, required String userId, required String userName}) async {
    await ThreadsApi.acceptInvite(threadId: threadId, userId: userId);
    final index = _threads.indexWhere((t) => t.id == threadId);
    if (index >= 0) {
      final thread = _threads[index];
      final users = [...thread.users, ThreadUser(id: userId, name: userName, joinedAt: DateTime.now())];
      final invites = thread.invites.where((i) => i.userId != userId).toList();
      _threads[index] = thread.copyWith(users: users, invites: invites);
        if (_activeThread?.id == threadId) {
        _activeThread = _threads[index];
      }
      notifyListeners();
    }
  }

  Future<void> declineInvite({required String threadId, required String userId}) async {
    await ThreadsApi.declineInvite(threadId: threadId, userId: userId);
    final index = _threads.indexWhere((t) => t.id == threadId);
    if (index >= 0) {
      final thread = _threads[index];
      final invites = thread.invites.where((i) => i.userId != userId).toList();
      _threads[index] = thread.copyWith(invites: invites);
        if (_activeThread?.id == threadId) {
        _activeThread = _threads[index];
      }
      notifyListeners();
    }
  }

  Future<bool> joinThread({required String threadId}) async {
    if (_currentUserId == null || _currentUserName == null) {
      throw Exception('User not authenticated');
    }
    try {
      await ThreadsApi.joinThread(
        threadId: threadId,
        userId: _currentUserId!,
        userName: _currentUserName!,
      );
      // Refresh thread list to include the newly joined thread
      await loadThreads(silent: true);
      return true;
    } catch (e) {
      debugPrint('❌ [THREADS] Failed to join thread: $e');
      return false;
    }
  }

  // WebSocket integration
  void _registerWsHandlers() {
    _wsClient.registerMessageHandler('message_created', _onMessageCreated);
  }

  void disposeWs() {
    _wsClient.unregisterAllHandlers('message_created');
  }

  void _onMessageCreated(Map<String, dynamic> payload) {
    try {
      final threadId = payload['parent_thread'] as String? ?? payload['thread_id'] as String?;
      if (threadId == null) return;
      final shouldApply = (_activeThread?.id == threadId) || _messagesByThread.containsKey(threadId);
      if (!shouldApply) return;
      final message = Message.fromJson(payload);
      final list = _messagesByThread[threadId] ?? [];
      final pendingIdx = list.indexWhere((m) => m.sendStatus != null && m.sendStatus != SendStatus.sent && _isSameMessageContent(m, message));
      if (pendingIdx >= 0) {
        // Preserve local upload status and snapshot when reconciling with server message
        final localMessage = list[pendingIdx];
        final mergedRenders = _mergeRenders(localMessage.renders, message.renders);
        final mergedSnapshot = message.snapshot.isEmpty && localMessage.snapshot.isNotEmpty
          ? localMessage.snapshot
          : message.snapshot;
        
        list[pendingIdx] = message.copyWith(
          sendStatus: SendStatus.sent, 
          localTempId: null,
          renders: mergedRenders,
          snapshot: mergedSnapshot,
        );
      } else if (!list.any((m) => m.id == message.id)) {
        // Check if we have a cached version with snapshot
        final existing = list.firstWhere((m) => m.id == message.id, orElse: () => message);
        final preservedSnapshot = message.snapshot.isEmpty && existing.snapshot.isNotEmpty
          ? existing.snapshot
          : message.snapshot;
        
        list.add(message.copyWith(
          sendStatus: SendStatus.sent,
          snapshot: preservedSnapshot,
        ));
      }
      _messagesByThread[threadId] = List<Message>.from(list);
      notifyListeners();
    } catch (_) {}
  }

  /// Merge local renders (with uploadStatus) with server renders
  /// Preserves local uploadStatus for ongoing uploads
  List<Render> _mergeRenders(List<Render> localRenders, List<Render> serverRenders) {
    if (localRenders.isEmpty) return serverRenders;
    if (serverRenders.isEmpty) return localRenders;
    
    final result = <Render>[];
    
    // Add server renders first (they are the source of truth)
    for (final serverRender in serverRenders) {
      // Check if this render exists locally with upload status
      final localRender = localRenders.firstWhere(
        (r) => r.id == serverRender.id || (r.id.startsWith('temp_') && r.url.isEmpty && serverRender.url.isNotEmpty),
        orElse: () => serverRender,
      );
      
      // If local render is uploading and server render doesn't have uploadStatus, preserve local status
      if (localRender.uploadStatus == RenderUploadStatus.uploading && serverRender.uploadStatus == null) {
        result.add(serverRender.copyWith(uploadStatus: RenderUploadStatus.uploading));
      } else {
        result.add(serverRender);
      }
    }
    
    // Add any local optimistic renders that aren't in server renders yet
    for (final localRender in localRenders) {
      if (localRender.uploadStatus == RenderUploadStatus.uploading && 
          !result.any((r) => r.id == localRender.id)) {
        result.add(localRender);
      }
    }
    
    return result;
  }

  /// Merge existing local messages with server messages, preserving upload status
  List<Message> _mergeMessagesPreservingUploads(List<Message> existingMessages, List<Message> serverMessages) {
    if (existingMessages.isEmpty) return serverMessages;
    
    final result = <Message>[];
    
    // Process server messages and merge with local upload status if needed
    for (final serverMsg in serverMessages) {
      // Find corresponding local message
      final localMsg = existingMessages.firstWhere(
        (m) => m.id == serverMsg.id || (m.localTempId != null && _isSameMessageContent(m, serverMsg)),
        orElse: () => serverMsg,
      );
      
      // If local message has optimistic renders being uploaded, preserve them
      if (localMsg.renders.any((r) => r.uploadStatus == RenderUploadStatus.uploading)) {
        final mergedRenders = _mergeRenders(localMsg.renders, serverMsg.renders);
        result.add(serverMsg.copyWith(renders: mergedRenders));
      } else {
        result.add(serverMsg);
      }
    }
    
    return result;
  }

  bool _isSameMessageContent(Message a, Message b) {
    return a.userId == b.userId && (a.timestamp.difference(b.timestamp).inSeconds.abs() <= 2);
  }
}


