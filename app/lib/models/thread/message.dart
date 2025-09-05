enum SendStatus { sending, failed, sent }

class Message {
  final String id; // empty for not-yet-sent
  final DateTime createdAt;
  final DateTime timestamp;
  final String userId;
  final String? parentThread;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic> snapshot;

  // Client-only
  final String? localTempId;
  final SendStatus? sendStatus;

  const Message({
    required this.id,
    required this.createdAt,
    required this.timestamp,
    required this.userId,
    required this.parentThread,
    required this.metadata,
    required this.snapshot,
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
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      snapshot: Map<String, dynamic>.from(json['snapshot'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'timestamp': timestamp.toIso8601String(),
        'user_id': userId,
        'parent_thread': parentThread,
        'metadata': metadata,
        'snapshot': snapshot,
      };

  Message copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? timestamp,
    String? userId,
    String? parentThread,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? snapshot,
    String? localTempId,
    SendStatus? sendStatus,
  }) {
    return Message(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      timestamp: timestamp ?? this.timestamp,
      userId: userId ?? this.userId,
      parentThread: parentThread ?? this.parentThread,
      metadata: metadata ?? this.metadata,
      snapshot: snapshot ?? this.snapshot,
      localTempId: localTempId ?? this.localTempId,
      sendStatus: sendStatus ?? this.sendStatus,
    );
  }
}


