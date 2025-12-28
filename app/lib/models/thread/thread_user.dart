class ThreadUser {
  final String id;
  final String username;
  final String name;
  final DateTime joinedAt;
  final DateTime lastOnline;

  const ThreadUser({
    required this.id,
    required this.username,
    required this.name,
    required this.joinedAt,
    required this.lastOnline,
  });

  factory ThreadUser.fromJson(Map<String, dynamic> json) {
    return ThreadUser(
      id: json['id'] ?? '',
      username: json['username'] ?? json['name'] ?? '',  // Fallback to name if username not present
      name: json['name'] ?? '',
      joinedAt: DateTime.parse(json['joined_at'] ?? DateTime.now().toIso8601String()),
      lastOnline: DateTime.parse(json['last_online'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'name': name,
        'joined_at': joinedAt.toIso8601String(),
        'last_online': lastOnline.toIso8601String(),
      };
  
  bool get isOnline {
    final now = DateTime.now();
    final diff = now.difference(lastOnline);
    return diff.inMinutes < 15; // Consider online if active within 15 minutes
  }
  
  ThreadUser copyWith({
    String? id,
    String? username,
    String? name,
    DateTime? joinedAt,
    DateTime? lastOnline,
  }) {
    return ThreadUser(
      id: id ?? this.id,
      username: username ?? this.username,
      name: name ?? this.name,
      joinedAt: joinedAt ?? this.joinedAt,
      lastOnline: lastOnline ?? this.lastOnline,
    );
  }
}


