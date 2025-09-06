enum SendStatus { sending, failed, sent }

class Message {
  final String id; // empty for not-yet-sent
  final DateTime createdAt;
  final DateTime timestamp;
  final String userId;
  final String? parentThread;
  final Map<String, dynamic> snapshot;
  final Map<String, dynamic>? snapshotMetadata;

  // Client-only
  final String? localTempId;
  final SendStatus? sendStatus;

  const Message({
    required this.id,
    required this.createdAt,
    required this.timestamp,
    required this.userId,
    required this.parentThread,
    required this.snapshot,
    this.snapshotMetadata,
    this.localTempId,
    this.sendStatus,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      userId: json['user_id'] ?? '',
      parentThread: json['parent_thread'],
      snapshot: Map<String, dynamic>.from(json['snapshot'] ?? {}),
      snapshotMetadata: json['snapshot_metadata'] == null ? null : Map<String, dynamic>.from(json['snapshot_metadata'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'timestamp': timestamp.toIso8601String(),
        'user_id': userId,
        'parent_thread': parentThread,
        'snapshot': snapshot,
        if (snapshotMetadata != null) 'snapshot_metadata': snapshotMetadata,
      };

  Message copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? timestamp,
    String? userId,
    String? parentThread,
    Map<String, dynamic>? snapshot,
    Map<String, dynamic>? snapshotMetadata,
    String? localTempId,
    SendStatus? sendStatus,
  }) {
    return Message(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      timestamp: timestamp ?? this.timestamp,
      userId: userId ?? this.userId,
      parentThread: parentThread ?? this.parentThread,
      snapshot: snapshot ?? this.snapshot,
      snapshotMetadata: snapshotMetadata ?? this.snapshotMetadata,
      localTempId: localTempId ?? this.localTempId,
      sendStatus: sendStatus ?? this.sendStatus,
    );
  }
}


