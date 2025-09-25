import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../models/thread/thread.dart';
import '../models/thread/message.dart';
import '../models/thread/thread_user.dart';
import '../models/thread/thread_invite.dart';
import '../services/threads_api.dart';
import '../services/ws_client.dart';
import '../services/snapshot/snapshot_service.dart';
import 'sequencer/table.dart';
import 'sequencer/playback.dart';
import 'sequencer/sample_bank.dart';

class ThreadsState extends ChangeNotifier {
  final WebSocketClient _wsClient;

  // Identity
  String? _currentUserId;
  String? _currentUserName;

  // Data
  final List<Thread> _threads = [];
  Thread? _activeThread;
  final Map<String, List<Message>> _messagesByThread = {};
  bool _isThreadViewActive = false;

  // UI state
  bool _isLoading = false;
  String? _error;

  // Snapshot service factory deps
  final TableState _tableState;
  final PlaybackState _playbackState;
  final SampleBankState _sampleBankState;

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

  // Getters
  List<Thread> get threads => List.unmodifiable(_threads);
  Thread? get activeThread => _activeThread;
  // Backward-compat alias for older call sites
  Thread? get currentThread => _activeThread;
  List<Message> get activeThreadMessages =>
      _activeThread == null ? const [] : List.unmodifiable(_messagesByThread[_activeThread!.id] ?? const []);
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get currentUserId => _currentUserId;
  String? get currentUserName => _currentUserName;
  bool get isThreadViewActive => _isThreadViewActive;

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

  Future<void> loadThreads() async {
    try {
      _setLoading(true);
      _setError(null);
      final result = await ThreadsApi.getThreads(userId: _currentUserId);
      _threads
        ..clear()
        ..addAll(result);
    } catch (e) {
      _setError('Failed to load threads: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> ensureThreadSummary(String threadId) async {
    try {
      _setError(null);
      final thread = await ThreadsApi.getThread(threadId);
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
    bool force = true,
    int? limit,
    String? order,
    bool includeSnapshot = false,
  }) async {
    try {
      _setLoading(true);
      _setError(null);
      final messages = await ThreadsApi.getMessages(
        threadId,
        limit: limit,
        order: order,
        includeSnapshot: includeSnapshot,
      );
      _messagesByThread[threadId] = messages;
    } catch (e) {
      _setError('Failed to load messages: $e');
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<String> createThread({
    required List<ThreadUser> users,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      _setLoading(true);
      _setError(null);
      final threadId = await ThreadsApi.createThread(users: users, metadata: metadata);
      await ensureThreadSummary(threadId);
      // Set active thread to the newly created one
      final idx = _threads.indexWhere((t) => t.id == threadId);
      if (idx >= 0) {
        _activeThread = _threads[idx];
      } else {
        _activeThread = Thread(
          id: threadId,
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
    final pending = Message(
      id: '',
      createdAt: DateTime.now(),
      timestamp: DateTime.now(),
      userId: _currentUserId ?? 'unknown',
      parentThread: threadId,
      snapshot: snapshotMap,
      snapshotMetadata: snapshotMetadata,
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
        timestamp: pending.timestamp,
      );

      // Replace pending with saved
      final list = _messagesByThread[threadId] ?? [];
      final idx = list.indexWhere((m) => m.localTempId == tempId);
      if (idx >= 0) {
        final updated = saved.copyWith(sendStatus: SendStatus.sent, localTempId: null);
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
        list[pendingIdx] = message.copyWith(sendStatus: SendStatus.sent, localTempId: null);
      } else if (!list.any((m) => m.id == message.id)) {
        list.add(message.copyWith(sendStatus: SendStatus.sent));
      }
      _messagesByThread[threadId] = List<Message>.from(list);
      notifyListeners();
    } catch (_) {}
  }

  bool _isSameMessageContent(Message a, Message b) {
    return a.userId == b.userId && (a.timestamp.difference(b.timestamp).inSeconds.abs() <= 2);
  }
}


