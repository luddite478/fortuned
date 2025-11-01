import 'thread_user.dart';
import 'thread_invite.dart';

class Thread {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ThreadUser> users;
  final List<String> messageIds;
  final List<ThreadInvite> invites;
  final bool isLocal;
  final Map<String, dynamic>? metadata;

  const Thread({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.users,
    required this.messageIds,
    required this.invites,
    this.isLocal = false,
    this.metadata,
  });

  factory Thread.fromJson(Map<String, dynamic> json) {
    return Thread(
      id: json['id'] ?? '',
      name: json['name'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updated_at'] ?? DateTime.now().toIso8601String()),
      users: (json['users'] as List<dynamic>? ?? [])
          .map((u) => ThreadUser.fromJson(u))
          .toList(),
      messageIds: (json['messages'] as List<dynamic>? ?? [])
          .map((m) => m.toString())
          .toList(),
      invites: (json['invites'] as List<dynamic>? ?? [])
          .map((i) => ThreadInvite.fromJson(i))
          .toList(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'users': users.map((u) => u.toJson()).toList(),
        'messages': messageIds,
        'invites': invites.map((i) => i.toJson()).toList(),
        if (metadata != null) 'metadata': metadata,
      };

  Thread copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ThreadUser>? users,
    List<String>? messageIds,
    List<ThreadInvite>? invites,
    bool? isLocal,
    Map<String, dynamic>? metadata,
  }) {
    return Thread(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      users: users ?? this.users,
      messageIds: messageIds ?? this.messageIds,
      invites: invites ?? this.invites,
      isLocal: isLocal ?? this.isLocal,
      metadata: metadata ?? this.metadata,
    );
  }
}


