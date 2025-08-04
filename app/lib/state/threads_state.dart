import 'package:flutter/foundation.dart';
import '../services/threads_service.dart';
import 'sequencer_state.dart';

enum ThreadStatus { active, paused, completed, archived }

enum InviteStatus { pending, accepted, declined, cancelled }

class ThreadInvite {
  final String userId;
  final String userName;
  final InviteStatus status;
  final String invitedBy;
  final DateTime invitedAt;
  
  const ThreadInvite({
    required this.userId,
    required this.userName,
    required this.status,
    required this.invitedBy,
    required this.invitedAt,
  });
  
  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'user_name': userName,
    'status': status.name,
    'invited_by': invitedBy,
    'invited_at': invitedAt.toIso8601String(),
  };
  
  factory ThreadInvite.fromJson(Map<String, dynamic> json) {
    return ThreadInvite(
      userId: json['user_id'] ?? '',
      userName: json['user_name'] ?? '',
      status: InviteStatus.values.firstWhere(
        (s) => s.name == (json['status'] ?? 'pending'),
        orElse: () => InviteStatus.pending,
      ),
      invitedBy: json['invited_by'] ?? '',
      invitedAt: DateTime.parse(json['invited_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class ThreadUser {
  final String id;
  final String name;
  final DateTime joinedAt;
  
  const ThreadUser({
    required this.id,
    required this.name,
    required this.joinedAt,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'joined_at': joinedAt.toIso8601String(),
  };
  
  factory ThreadUser.fromJson(Map<String, dynamic> json) {
    return ThreadUser(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      joinedAt: DateTime.parse(json['joined_at'] ?? DateTime.now().toIso8601String()),
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
    required this.version,
    required this.audio,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'version': version,
    'audio': audio.toJson(),
  };

  factory SequencerSnapshot.fromJson(Map<String, dynamic> json) {
    return SequencerSnapshot(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      version: json['version'] ?? '1.0',
      audio: ProjectAudio.fromJson(json['audio'] ?? {}),
    );
  }

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
  final int sampleRate;
  final int channels;
  final String url;
  final List<AudioRender> renders;
  final List<AudioSource> sources; // The actual sequencer data

  const ProjectAudio({
    required this.format,
    required this.duration,
    required this.sampleRate,
    required this.channels,
    required this.url,
    required this.renders,
    required this.sources,
  });

  factory ProjectAudio.fromJson(Map<String, dynamic> json) {
    return ProjectAudio(
      format: json['format'] ?? 'mp3',
      duration: (json['duration'] ?? 0.0).toDouble(),
      sampleRate: json['sample_rate'] ?? 44100,
      channels: json['channels'] ?? 2,
      url: json['url'] ?? '',
      renders: (json['renders'] as List<dynamic>? ?? [])
          .map((render) => AudioRender.fromJson(render))
          .toList(),
      sources: (json['sources'] as List<dynamic>? ?? [])
          .map((source) => AudioSource.fromJson(source))
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
  final String createdAt;
  final String version;
  final String quality;

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
      createdAt: json['created_at'] ?? '',
      version: json['version'] ?? '',
      quality: json['quality'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'created_at': createdAt,
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
      scenes: (json['scenes'] as List<dynamic>? ?? [])
          .map((scene) => SequencerScene.fromJson(scene))
          .toList(),
      samples: (json['samples'] as List<dynamic>? ?? [])
          .map((sample) => SampleInfo.fromJson(sample))
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
      layers: (json['layers'] as List<dynamic>? ?? [])
          .map((layer) => SequencerLayer.fromJson(layer))
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
  final String id;
  final int index;
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
      rows: (json['rows'] as List<dynamic>? ?? [])
          .map((row) => SequencerRow.fromJson(row))
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
      cells: (json['cells'] as List<dynamic>? ?? [])
          .map((cell) => SequencerCell.fromJson(cell))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'cells': cells.map((c) => c.toJson()).toList(),
  };
}

class SequencerCell {
  final CellSample? sample;

  const SequencerCell({
    this.sample,
  });

  factory SequencerCell.fromJson(Map<String, dynamic> json) {
    return SequencerCell(
      sample: json['sample'] != null 
          ? CellSample.fromJson(json['sample'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'sample': sample?.toJson(),
  };
}

class CellSample {
  final String? sampleId;
  final String? sampleName;

  const CellSample({
    this.sampleId,
    this.sampleName,
  });

  bool get hasSample => sampleId != null && sampleId!.isNotEmpty;

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
}

class SceneMetadata {
  final String user;
  final int bpm;
  final String key;
  final String timeSignature;
  final DateTime createdAt;

  const SceneMetadata({
    required this.user,
    required this.bpm,
    required this.key,
    required this.timeSignature,
    required this.createdAt,
  });

  factory SceneMetadata.fromJson(Map<String, dynamic> json) {
    return SceneMetadata(
      user: json['user'] ?? '',
      bpm: json['bpm'] ?? 120,
      key: json['key'] ?? 'C Major',
      timeSignature: json['time_signature'] ?? '4/4',
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() => {
    'user': user,
    'bpm': bpm,
    'key': key,
    'time_signature': timeSignature,
    'created_at': createdAt.toIso8601String(),
  };
}

class SampleInfo {
  final String id;
  final String name;
  final String url;
  final bool isPublic;

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
      isPublic: json['is_public'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'is_public': isPublic,
  };
}

// A checkpoint represents a project state at a specific point in time
class ProjectCheckpoint {
  final String id;
  final String userId; // User who created this checkpoint
  final String userName;
  final DateTime timestamp;
  final String comment; // Optional description of changes
  final SequencerSnapshot snapshot; // Complete project state

  const ProjectCheckpoint({
    required this.id,
    required this.userId,
    required this.userName,
    required this.timestamp,
    required this.comment,
    required this.snapshot,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'user_name': userName,
    'timestamp': timestamp.toIso8601String(),
    'comment': comment,
    'snapshot': snapshot.toJson(),
  };

  factory ProjectCheckpoint.fromJson(Map<String, dynamic> json) {
    return ProjectCheckpoint(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      userName: json['user_name'] ?? '',
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      comment: json['comment'] ?? '',
      snapshot: SequencerSnapshot.fromJson(json['snapshot'] ?? {}),
    );
  }
}

// A thread represents the complete history of a project
class Thread {
  final String id;
  final String title;
  final List<ThreadUser> users; // First user is always the initial author
  final List<ThreadInvite> invites; // Pending/historical invitations
  final List<ProjectCheckpoint> checkpoints;
  final ThreadStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> metadata; // Additional project metadata

  const Thread({
    required this.id,
    required this.title,
    required this.users,
    this.invites = const [],
    required this.checkpoints,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.metadata = const {},
  });

  // Get the initial author (first user)
  ThreadUser get author => users.first;
  
  // Get the latest checkpoint
  ProjectCheckpoint? get latestCheckpoint =>
      checkpoints.isNotEmpty ? checkpoints.last : null;
  
  // Check if user is part of this thread
  bool hasUser(String userId) => users.any((user) => user.id == userId);
  
  // Get user by ID
  ThreadUser? getUser(String userId) => 
      users.where((user) => user.id == userId).firstOrNull;

  // Check if user has been invited to this thread
  bool isUserInvited(String userId) => invites.any((invite) => invite.userId == userId);
  
  // Check if user has a pending invitation
  bool hasPendingInvite(String userId) => 
      invites.any((invite) => invite.userId == userId && invite.status == InviteStatus.pending);
  
  // Get invite by user ID
  ThreadInvite? getInvite(String userId) => 
      invites.where((invite) => invite.userId == userId).firstOrNull;
  
  // Get all pending invites
  List<ThreadInvite> get pendingInvites => 
      invites.where((invite) => invite.status == InviteStatus.pending).toList();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'users': users.map((u) => u.toJson()).toList(),
    'invites': invites.map((i) => i.toJson()).toList(),
    'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
    'status': status.name,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'metadata': metadata,
  };

  factory Thread.fromJson(Map<String, dynamic> json) {
    return Thread(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      users: (json['users'] as List<dynamic>? ?? [])
          .map((user) => ThreadUser.fromJson(user))
          .toList(),
      invites: (json['invites'] as List<dynamic>? ?? [])
          .map((invite) => ThreadInvite.fromJson(invite))
          .toList(),
      checkpoints: (json['checkpoints'] as List<dynamic>? ?? [])
          .map((checkpoint) => ProjectCheckpoint.fromJson(checkpoint))
          .toList(),
      status: ThreadStatus.values.firstWhere(
        (s) => s.name == (json['status'] ?? 'active'),
        orElse: () => ThreadStatus.active,
      ),
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updated_at'] ?? DateTime.now().toIso8601String()),
      metadata: json['metadata'] ?? {},
    );
  }

  Thread copyWith({
    String? id,
    String? title,
    List<ThreadUser>? users,
    List<ThreadInvite>? invites,
    List<ProjectCheckpoint>? checkpoints,
    ThreadStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) {
    return Thread(
      id: id ?? this.id,
      title: title ?? this.title,
      users: users ?? this.users,
      invites: invites ?? this.invites,
      checkpoints: checkpoints ?? this.checkpoints,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }
}

class ThreadsState extends ChangeNotifier {
  List<Thread> _threads = [];
  String? _currentUserId;
  String? _currentUserName;
  Thread? _activeThread;
  bool _isLoading = false;
  String? _error;
  String? _expandedCheckpointId; // Track which checkpoint is magnified

  // Getters
  List<Thread> get threads => _threads;
  String? get currentUserId => _currentUserId;
  String? get currentUserName => _currentUserName;
  Thread? get activeThread => _activeThread;
  Thread? get currentThread => _activeThread; // Alias for convenience
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get expandedCheckpointId => _expandedCheckpointId;

  // Get threads where user is a participant
  List<Thread> getUserThreads(String userId) {
    return _threads.where((thread) => thread.hasUser(userId)).toList();
  }

  // Get threads created by a specific user
  List<Thread> getUserCreatedThreads(String userId) {
    return _threads.where((thread) => thread.author.id == userId).toList();
  }

  void setCurrentUser(String userId, [String? userName]) {
    _currentUserId = userId;
    _currentUserName = userName;
    notifyListeners();
  }

  void setActiveThread(Thread? thread) {
    _activeThread = thread;
    notifyListeners();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void setExpandedCheckpoint(String? checkpointId) {
    _expandedCheckpointId = checkpointId;
    notifyListeners();
  }

  // Create a new thread (can be solo or with collaborators)
  Future<String> createThread({
    required String title,
    required String authorId,
    required String authorName,
    List<String> collaboratorIds = const [],
    List<String> collaboratorNames = const [],
    SequencerSnapshot? initialSnapshot,
    Map<String, dynamic> metadata = const {},
    bool createInitialCheckpoint = true, // New parameter to control initial checkpoint
  }) async {
    try {
      setLoading(true);
      setError(null);

      // Create thread users list (author first, then collaborators)
      final users = <ThreadUser>[
        ThreadUser(
          id: authorId,
          name: authorName,
          joinedAt: DateTime.now(),
        ),
      ];

      // Add collaborators
      for (int i = 0; i < collaboratorIds.length; i++) {
        users.add(ThreadUser(
          id: collaboratorIds[i],
          name: i < collaboratorNames.length ? collaboratorNames[i] : 'User ${collaboratorIds[i]}',
          joinedAt: DateTime.now(),
        ));
      }

      // Create initial checkpoint only if requested
      ProjectCheckpoint? initialCheckpoint;
      if (createInitialCheckpoint && initialSnapshot != null) {
        initialCheckpoint = ProjectCheckpoint(
          id: 'checkpoint_${DateTime.now().millisecondsSinceEpoch}',
          userId: authorId,
          userName: authorName,
          timestamp: DateTime.now(),
          comment: collaboratorIds.isEmpty 
              ? 'Created project "${title}"'
              : 'Started collaboration on "${title}"',
          snapshot: initialSnapshot,
        );
      }

      // Create thread using service
      final threadId = await ThreadsService.createThread(
        title: title,
        users: users,
        initialCheckpoint: initialCheckpoint, // Can be null now
        metadata: metadata,
      );

      // Create local thread object
      final thread = Thread(
        id: threadId,
        title: title,
        users: users,
        checkpoints: initialCheckpoint != null ? [initialCheckpoint] : [], // Empty list if no initial checkpoint
        status: ThreadStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        metadata: metadata,
      );

      // Add to local state
      _threads.add(thread);
      setActiveThread(thread);

      return threadId;
    } catch (e) {
      setError('Failed to create thread: $e');
      rethrow;
    } finally {
      setLoading(false);
    }
  }

  // Add a checkpoint to an existing thread
  Future<void> addCheckpoint({
    required String threadId,
    required String userId,
    required String userName,
    required String comment,
    required SequencerSnapshot snapshot,
  }) async {
    try {
      setLoading(true);
      setError(null);

      final checkpoint = ProjectCheckpoint(
        id: 'checkpoint_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        userName: userName,
        timestamp: DateTime.now(),
        comment: comment,
        snapshot: snapshot,
      );

      await ThreadsService.addCheckpoint(threadId, checkpoint);

      // Update local state
      final threadIndex = _threads.indexWhere((t) => t.id == threadId);
      if (threadIndex != -1) {
        final thread = _threads[threadIndex];
        final updatedCheckpoints = [...thread.checkpoints, checkpoint];
        _threads[threadIndex] = thread.copyWith(
          checkpoints: updatedCheckpoints,
          updatedAt: DateTime.now(),
        );

        if (_activeThread?.id == threadId) {
          setActiveThread(_threads[threadIndex]);
        }
      }
    } catch (e) {
      setError('Failed to add checkpoint: $e');
      rethrow;
    } finally {
      setLoading(false);
    }
  }

  // Convenience method to add checkpoint from current sequencer state
  Future<void> addCheckpointFromSequencer(String threadId, String comment, SequencerState sequencerState) async {
    final snapshot = sequencerState.createSnapshot(comment: comment);
    await addCheckpoint(
      threadId: threadId,
      userId: _currentUserId ?? 'unknown',
      userName: _currentUserName ?? 'Unknown User',
      comment: comment,
      snapshot: snapshot,
    );
  }

  // Note: Removed createSoloThread and ensureActiveSoloThread methods
  // ThreadsState should only manage server data, not create local threads
  // Use the sequencer's publishToDatabase method to create threads on server

  // Join an existing thread
  Future<void> joinThread({
    required String threadId,
    required String userId,
    required String userName,
  }) async {
    try {
      setLoading(true);
      setError(null);

      await ThreadsService.joinThread(threadId, userId, userName);

      // Update local state
      final threadIndex = _threads.indexWhere((t) => t.id == threadId);
      if (threadIndex != -1) {
        final thread = _threads[threadIndex];
        final newUser = ThreadUser(
          id: userId,
          name: userName,
          joinedAt: DateTime.now(),
        );
        final updatedUsers = [...thread.users, newUser];
        _threads[threadIndex] = thread.copyWith(
          users: updatedUsers,
          updatedAt: DateTime.now(),
        );
      }
    } catch (e) {
      setError('Failed to join thread: $e');
      rethrow;
    } finally {
      setLoading(false);
    }
  }

  // Load threads from service
  Future<void> loadThreads() async {
    try {
      setLoading(true);
      setError(null);

      // Only load threads for the current user
      if (_currentUserId == null) {
        setError('User not authenticated');
        return;
      }
      
      final threads = await ThreadsService.getThreads(userId: _currentUserId);
      _threads = threads;
    } catch (e) {
      setError('Failed to load threads: $e');
    } finally {
      setLoading(false);
    }
  }

  // Load a specific thread
  Future<Thread?> loadThread(String threadId) async {
    try {
      setLoading(true);
      setError(null);

      final thread = await ThreadsService.getThread(threadId);
      if (thread != null) {
        final existingIndex = _threads.indexWhere((t) => t.id == threadId);
        if (existingIndex != -1) {
          _threads[existingIndex] = thread;
        } else {
          _threads.add(thread);
        }
      }
      return thread;
    } catch (e) {
      setError('Failed to load thread: $e');
      return null;
    } finally {
      setLoading(false);
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Send invitation to user for a thread
  Future<void> sendInvitation({
    required String threadId,
    required String userId,
    required String userName,
    required String invitedBy,
  }) async {
    try {
      setLoading(true);
      setError(null);

      // Check if user is already part of thread or already invited
      final thread = _threads.firstWhere((t) => t.id == threadId);
      
      if (thread.hasUser(userId)) {
        throw Exception('User is already a member of this thread');
      }
      
      if (thread.hasPendingInvite(userId)) {
        throw Exception('User already has a pending invitation');
      }

      await ThreadsService.sendInvitation(threadId, userId, userName, invitedBy);

      // Update local state - add the invite to the thread
      final invite = ThreadInvite(
        userId: userId,
        userName: userName,
        status: InviteStatus.pending,
        invitedBy: invitedBy,
        invitedAt: DateTime.now(),
      );

      final threadIndex = _threads.indexWhere((t) => t.id == threadId);
      if (threadIndex != -1) {
        final updatedInvites = [..._threads[threadIndex].invites, invite];
        _threads[threadIndex] = _threads[threadIndex].copyWith(
          invites: updatedInvites,
          updatedAt: DateTime.now(),
        );

        if (_activeThread?.id == threadId) {
          setActiveThread(_threads[threadIndex]);
        }
      }
    } catch (e) {
      setError('Failed to send invitation: $e');
      rethrow;
    } finally {
      setLoading(false);
    }
  }

  // Accept an invitation
  Future<void> acceptInvitation({
    required String threadId,
    required String userId,
    required String userName,
  }) async {
    try {
      setLoading(true);
      setError(null);

      await ThreadsService.acceptInvitation(threadId, userId);

      // Update local state - add user to thread and remove invite
      final threadIndex = _threads.indexWhere((t) => t.id == threadId);
      if (threadIndex != -1) {
        final thread = _threads[threadIndex];
        
        // Add user to users list
        final newUser = ThreadUser(
          id: userId,
          name: userName,
          joinedAt: DateTime.now(),
        );
        final updatedUsers = [...thread.users, newUser];
        
        // Remove invite from invites list
        final updatedInvites = thread.invites
            .where((invite) => invite.userId != userId)
            .toList();

        _threads[threadIndex] = thread.copyWith(
          users: updatedUsers,
          invites: updatedInvites,
          updatedAt: DateTime.now(),
        );

        if (_activeThread?.id == threadId) {
          setActiveThread(_threads[threadIndex]);
        }
      }
    } catch (e) {
      setError('Failed to accept invitation: $e');
      rethrow;
    } finally {
      setLoading(false);
    }
  }

  // Decline an invitation
  Future<void> declineInvitation({
    required String threadId,
    required String userId,
  }) async {
    try {
      setLoading(true);
      setError(null);

      await ThreadsService.declineInvitation(threadId, userId);

      // Update local state - remove invite
      final threadIndex = _threads.indexWhere((t) => t.id == threadId);
      if (threadIndex != -1) {
        final thread = _threads[threadIndex];
        
        // Remove invite from invites list
        final updatedInvites = thread.invites
            .where((invite) => invite.userId != userId)
            .toList();

        _threads[threadIndex] = thread.copyWith(
          invites: updatedInvites,
          updatedAt: DateTime.now(),
        );

        if (_activeThread?.id == threadId) {
          setActiveThread(_threads[threadIndex]);
        }
      }
    } catch (e) {
      setError('Failed to decline invitation: $e');
      rethrow;
    } finally {
      setLoading(false);
    }
  }

  // Get all threads where user has pending invitations
  List<Thread> getThreadsWithPendingInvites(String userId) {
    return _threads.where((thread) => thread.hasPendingInvite(userId)).toList();
  }

  // Get count of pending invitations for a user
  int getPendingInvitesCount(String userId) {
    int count = 0;
    for (final thread in _threads) {
      if (thread.hasPendingInvite(userId)) {
        count++;
      }
    }
    return count;
  }
} 