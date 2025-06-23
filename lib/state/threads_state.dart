import 'package:flutter/foundation.dart';
import 'dart:collection';

// Thread message data model - represents a complete sequencer state snapshot
class ThreadMessage {
  final String id;
  final String threadId;
  final String userId;
  final String userName;
  final SequencerSnapshot sequencerState;
  final DateTime timestamp;
  final String? comment; // Optional comment from user about changes made

  const ThreadMessage({
    required this.id,
    required this.threadId,
    required this.userId,
    required this.userName,
    required this.sequencerState,
    required this.timestamp,
    this.comment,
  });

  ThreadMessage copyWith({
    String? id,
    String? threadId,
    String? userId,
    String? userName,
    SequencerSnapshot? sequencerState,
    DateTime? timestamp,
    String? comment,
  }) {
    return ThreadMessage(
      id: id ?? this.id,
      threadId: threadId ?? this.threadId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      sequencerState: sequencerState ?? this.sequencerState,
      timestamp: timestamp ?? this.timestamp,
      comment: comment ?? this.comment,
    );
  }
}

// Complete sequencer state snapshot - matches project.audio.sources structure
class SequencerSnapshot {
  final String id; // unique snapshot ID
  final String name; // descriptive name for this version
  final DateTime createdAt;
  final String version; // version string like "1.0", "2.1", etc.
  final ProjectAudio audio; // Full audio structure matching database

  const SequencerSnapshot({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.audio,
    this.version = '1.0',
  });

  factory SequencerSnapshot.fromJson(Map<String, dynamic> json) {
    return SequencerSnapshot(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      version: json['version'] ?? '1.0',
      audio: ProjectAudio.fromJson(json['audio'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'version': version,
    'audio': audio.toJson(),
  };

  SequencerSnapshot copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    String? version,
    ProjectAudio? audio,
  }) {
    return SequencerSnapshot(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      version: version ?? this.version,
      audio: audio ?? this.audio,
    );
  }
}

// Matches project.audio structure from database
class ProjectAudio {
  final String format; // mp3, wav, etc.
  final double duration; // seconds
  final int sampleRate; // 44100, 48000, etc.
  final int channels; // 1 (mono), 2 (stereo)
  final String? url; // Main audio file URL (optional for unsaved)
  final List<AudioRender> renders; // Rendered versions
  final List<AudioSource> sources; // The actual sequencer data

  const ProjectAudio({
    required this.format,
    required this.duration,
    required this.sampleRate,
    required this.channels,
    this.url,
    this.renders = const [],
    required this.sources,
  });

  factory ProjectAudio.fromJson(Map<String, dynamic> json) {
    return ProjectAudio(
      format: json['format'] ?? 'mp3',
      duration: (json['duration'] ?? 0.0).toDouble(),
      sampleRate: json['sample_rate'] ?? 44100,
      channels: json['channels'] ?? 2,
      url: json['url'],
      renders: (json['renders'] as List? ?? [])
          .map((r) => AudioRender.fromJson(r))
          .toList(),
      sources: (json['sources'] as List? ?? [])
          .map((s) => AudioSource.fromJson(s))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'format': format,
    'duration': duration,
    'sample_rate': sampleRate,
    'channels': channels,
    'url': url,
    'renders': renders.map((r) => r.toJson()).toList(),
    'sources': sources.map((s) => s.toJson()).toList(),
  };
}

class AudioRender {
  final String id;
  final String url;
  final DateTime createdAt;
  final String version;
  final String quality; // low, medium, high, ultra

  const AudioRender({
    required this.id,
    required this.url,
    required this.createdAt,
    required this.version,
    required this.quality,
  });

  factory AudioRender.fromJson(Map<String, dynamic> json) {
    return AudioRender(
      id: json['id'] ?? '',
      url: json['url'] ?? '',
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      version: json['version'] ?? '1.0',
      quality: json['quality'] ?? 'medium',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'created_at': createdAt.toIso8601String(),
    'version': version,
    'quality': quality,
  };
}

class AudioSource {
  final List<SequencerScene> scenes;
  final List<SampleInfo> samples;

  const AudioSource({
    required this.scenes,
    required this.samples,
  });

  factory AudioSource.fromJson(Map<String, dynamic> json) {
    return AudioSource(
      scenes: (json['scenes'] as List? ?? [])
          .map((s) => SequencerScene.fromJson(s))
          .toList(),
      samples: (json['samples'] as List? ?? [])
          .map((s) => SampleInfo.fromJson(s))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'scenes': scenes.map((s) => s.toJson()).toList(),
    'samples': samples.map((s) => s.toJson()).toList(),
  };
}

class SequencerScene {
  final List<SequencerLayer> layers;
  final SceneMetadata metadata;

  const SequencerScene({
    required this.layers,
    required this.metadata,
  });

  factory SequencerScene.fromJson(Map<String, dynamic> json) {
    return SequencerScene(
      layers: (json['layers'] as List? ?? [])
          .map((l) => SequencerLayer.fromJson(l))
          .toList(),
      metadata: SceneMetadata.fromJson(json['metadata'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'layers': layers.map((l) => l.toJson()).toList(),
    'metadata': metadata.toJson(),
  };
}

class SequencerLayer {
  final String id; // layer_001, layer_002, etc.
  final int index; // 0, 1, 2, 3, etc. (layer position)
  final List<SequencerRow> rows;

  const SequencerLayer({
    required this.id,
    required this.index,
    required this.rows,
  });

  factory SequencerLayer.fromJson(Map<String, dynamic> json) {
    return SequencerLayer(
      id: json['id'] ?? '',
      index: json['index'] ?? 0,
      rows: (json['rows'] as List? ?? [])
          .map((r) => SequencerRow.fromJson(r))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'index': index,
    'rows': rows.map((r) => r.toJson()).toList(),
  };
}

class SequencerRow {
  final List<SequencerCell> cells;

  const SequencerRow({
    required this.cells,
  });

  factory SequencerRow.fromJson(Map<String, dynamic> json) {
    return SequencerRow(
      cells: (json['cells'] as List? ?? [])
          .map((c) => SequencerCell.fromJson(c))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'cells': cells.map((c) => c.toJson()).toList(),
  };
}

class SequencerCell {
  final CellSample sample;

  const SequencerCell({
    required this.sample,
  });

  factory SequencerCell.fromJson(Map<String, dynamic> json) {
    return SequencerCell(
      sample: CellSample.fromJson(json['sample'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'sample': sample.toJson(),
  };
}

class CellSample {
  final String? sampleId;
  final String? sampleName;

  const CellSample({
    this.sampleId,
    this.sampleName,
  });

  factory CellSample.fromJson(Map<String, dynamic> json) {
    return CellSample(
      sampleId: json['sample_id'],
      sampleName: json['sample_name'],
    );
  }

  Map<String, dynamic> toJson() => {
    'sample_id': sampleId,
    'sample_name': sampleName,
  };

  bool get isEmpty => sampleId == null;
  bool get hasSample => sampleId != null;
}

class SceneMetadata {
  final String user; // UUID of who created this grid
  final DateTime createdAt;
  final int bpm;
  final String key; // C Major, D Minor, etc.
  final String timeSignature; // 4/4, 3/4, etc.

  const SceneMetadata({
    required this.user,
    required this.createdAt,
    required this.bpm,
    required this.key,
    required this.timeSignature,
  });

  factory SceneMetadata.fromJson(Map<String, dynamic> json) {
    return SceneMetadata(
      user: json['user'] ?? '',
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      bpm: json['bpm'] ?? 120,
      key: json['key'] ?? 'C Major',
      timeSignature: json['time_signature'] ?? '4/4',
    );
  }

  Map<String, dynamic> toJson() => {
    'user': user,
    'created_at': createdAt.toIso8601String(),
    'bpm': bpm,
    'key': key,
    'time_signature': timeSignature,
  };
}

class SampleInfo {
  final String id; // kick_01, snare_02, etc.
  final String name; // Human readable name
  final String url; // Sample audio file URL
  final bool isPublic; // Can others use this sample

  const SampleInfo({
    required this.id,
    required this.name,
    required this.url,
    required this.isPublic,
  });

  factory SampleInfo.fromJson(Map<String, dynamic> json) {
    return SampleInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      isPublic: json['is_public'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'is_public': isPublic,
  };
}

// Thread data model - represents a collaborative session
class CollaborativeThread {
  final String id;
  final String originalProjectId;
  final String originalUserId;
  final String originalUserName;
  final String collaboratorUserId;
  final String collaboratorUserName;
  final String projectTitle;
  final List<ThreadMessage> messages;
  final ThreadStatus status;
  final DateTime createdAt;
  final DateTime lastActivity;
  final SequencerSnapshot? currentState; // Latest sequencer state
  final bool isActiveForUser; // Is this thread active for current user

  const CollaborativeThread({
    required this.id,
    required this.originalProjectId,
    required this.originalUserId,
    required this.originalUserName,
    required this.collaboratorUserId,
    required this.collaboratorUserName,
    required this.projectTitle,
    this.messages = const [],
    required this.status,
    required this.createdAt,
    required this.lastActivity,
    this.currentState,
    this.isActiveForUser = false,
  });

  CollaborativeThread copyWith({
    String? id,
    String? originalProjectId,
    String? originalUserId,
    String? originalUserName,
    String? collaboratorUserId,
    String? collaboratorUserName,
    String? projectTitle,
    List<ThreadMessage>? messages,
    ThreadStatus? status,
    DateTime? createdAt,
    DateTime? lastActivity,
    SequencerSnapshot? currentState,
    bool? isActiveForUser,
  }) {
    return CollaborativeThread(
      id: id ?? this.id,
      originalProjectId: originalProjectId ?? this.originalProjectId,
      originalUserId: originalUserId ?? this.originalUserId,
      originalUserName: originalUserName ?? this.originalUserName,
      collaboratorUserId: collaboratorUserId ?? this.collaboratorUserId,
      collaboratorUserName: collaboratorUserName ?? this.collaboratorUserName,
      projectTitle: projectTitle ?? this.projectTitle,
      messages: messages ?? this.messages,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastActivity: lastActivity ?? this.lastActivity,
      currentState: currentState ?? this.currentState,
      isActiveForUser: isActiveForUser ?? this.isActiveForUser,
    );
  }

  String get otherUserName => originalUserName == collaboratorUserName ? collaboratorUserName : originalUserName;
  String get otherUserId => originalUserId == collaboratorUserId ? collaboratorUserId : originalUserId;
}

// Thread status enum
enum ThreadStatus {
  active,      // Thread is active and both users can edit
  paused,      // Thread is paused
  completed,   // Thread is completed
  abandoned,   // Thread was abandoned by one user
}

// Threads state management - handles all collaborative threads
class ThreadsState extends ChangeNotifier {
  final Map<String, CollaborativeThread> _threads = {};
  String? _activeThreadId;
  String? _currentUserId;
  bool _isConnected = false;

  // Getters
  UnmodifiableMapView<String, CollaborativeThread> get threads => 
      UnmodifiableMapView(_threads);
  String? get activeThreadId => _activeThreadId;
  String? get currentUserId => _currentUserId;
  bool get isConnected => _isConnected;
  
  CollaborativeThread? get activeThread => 
      _activeThreadId != null ? _threads[_activeThreadId] : null;
  
  List<CollaborativeThread> get threadsList => 
      _threads.values.toList()..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));

  List<CollaborativeThread> get activeThreadsList => 
      _threads.values.where((thread) => thread.status == ThreadStatus.active).toList()
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));

  // Initialize current user
  void setCurrentUser(String userId) {
    _currentUserId = userId;
    notifyListeners();
  }

  // Connection management
  void setConnectionStatus(bool isConnected) {
    _isConnected = isConnected;
    notifyListeners();
  }

  // Start a new collaborative thread
  Future<String> startThread({
    required String originalProjectId,
    required String originalUserId,
    required String originalUserName,
    required String collaboratorUserId,
    required String collaboratorUserName,
    required String projectTitle,
    required SequencerSnapshot initialState,
  }) async {
    final threadId = 'thread_${DateTime.now().millisecondsSinceEpoch}_${originalUserId.substring(0, 8)}';
    
    // Create initial message with the starting state
    final initialMessage = ThreadMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}_${originalUserId.substring(0, 8)}',
      threadId: threadId,
      userId: originalUserId,
      userName: originalUserName,
      sequencerState: initialState,
      timestamp: DateTime.now(),
      comment: 'Started collaborative work on "${projectTitle}"',
    );
    
    final thread = CollaborativeThread(
      id: threadId,
      originalProjectId: originalProjectId,
      originalUserId: originalUserId,
      originalUserName: originalUserName,
      collaboratorUserId: collaboratorUserId,
      collaboratorUserName: collaboratorUserName,
      projectTitle: projectTitle,
      messages: [initialMessage],
      status: ThreadStatus.active,
      createdAt: DateTime.now(),
      lastActivity: DateTime.now(),
      currentState: initialState,
      isActiveForUser: true,
    );

    _threads[threadId] = thread;
    _activeThreadId = threadId;

    notifyListeners();
    return threadId;
  }

  // Join an existing thread
  void joinThread(String threadId) {
    if (_threads.containsKey(threadId)) {
      _activeThreadId = threadId;
      
      // Mark thread as active for current user
      final thread = _threads[threadId]!;
      _threads[threadId] = thread.copyWith(
        isActiveForUser: true,
        lastActivity: DateTime.now(),
      );
      
      notifyListeners();
    }
  }

  // Leave current thread
  void leaveThread() {
    if (_activeThreadId != null && _threads.containsKey(_activeThreadId!)) {
      final thread = _threads[_activeThreadId!]!;
      _threads[_activeThreadId!] = thread.copyWith(
        isActiveForUser: false,
        lastActivity: DateTime.now(),
      );
    }
    
    _activeThreadId = null;
    notifyListeners();
  }

  // Send a new message (sequencer state) to a thread
  void sendMessage({
    required String threadId,
    required SequencerSnapshot sequencerState,
    String? comment,
  }) {
    if (!_threads.containsKey(threadId) || _currentUserId == null) return;

    final thread = _threads[threadId]!;
    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_${_currentUserId!.substring(0, 8)}';
    
    final message = ThreadMessage(
      id: messageId,
      threadId: threadId,
      userId: _currentUserId!,
      userName: _getUserName(_currentUserId!),
      sequencerState: sequencerState,
      timestamp: DateTime.now(),
      comment: comment,
    );

    final updatedMessages = List<ThreadMessage>.from(thread.messages)
      ..add(message);

    _threads[threadId] = thread.copyWith(
      messages: updatedMessages,
      lastActivity: DateTime.now(),
      currentState: sequencerState,
    );

    notifyListeners();
  }

  // Get the latest message in a thread
  ThreadMessage? getLatestMessage(String threadId) {
    if (!_threads.containsKey(threadId)) return null;
    
    final thread = _threads[threadId]!;
    if (thread.messages.isEmpty) return null;
    
    return thread.messages.last;
  }

  // Get all messages in a thread
  List<ThreadMessage> getThreadMessages(String threadId) {
    if (!_threads.containsKey(threadId)) return [];
    
    return _threads[threadId]!.messages;
  }

  // Get user name by ID (simplified - in real app this would come from user service)
  String _getUserName(String userId) {
    // This is a simplified implementation
    // In a real app, you'd fetch this from a user service
    return 'User ${userId.substring(0, 8)}';
  }

  // Update thread status
  void updateThreadStatus(String threadId, ThreadStatus status) {
    if (_threads.containsKey(threadId)) {
      final thread = _threads[threadId]!;
      _threads[threadId] = thread.copyWith(
        status: status,
        lastActivity: DateTime.now(),
      );
      notifyListeners();
    }
  }

  // Get thread history as a readable list
  List<String> getThreadHistory(String threadId) {
    if (!_threads.containsKey(threadId)) return [];
    
    final thread = _threads[threadId]!;
    return thread.messages.map((message) {
      final timeStr = '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';
      final comment = message.comment ?? 'Updated sequencer';
      return '$timeStr ${message.userName}: $comment';
    }).toList();
  }

  // Clear all threads (for logout/reset)
  void clearThreads() {
    _threads.clear();
    _activeThreadId = null;
    notifyListeners();
  }

  // Remove a specific thread
  void removeThread(String threadId) {
    _threads.remove(threadId);
    if (_activeThreadId == threadId) {
      _activeThreadId = null;
    }
    notifyListeners();
  }
} 