class ThreadUser {
  final String id;
  final String username;
  final String name;
  final DateTime joinedAt;
  final bool isOnline;

  const ThreadUser({
    required this.id,
    required this.username,
    required this.name,
    required this.joinedAt,
    this.isOnline = false,
  });

  factory ThreadUser.fromJson(Map<String, dynamic> json) {
    return ThreadUser(
      id: json['id'] ?? '',
      username: json['username'] ?? json['name'] ?? '',  // Fallback to name if username not present
      name: json['name'] ?? '',
      joinedAt: DateTime.parse(json['joined_at'] ?? DateTime.now().toIso8601String()),
      isOnline: json['is_online'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'name': name,
        'joined_at': joinedAt.toIso8601String(),
        'is_online': isOnline,
      };
  
  ThreadUser copyWith({
    String? id,
    String? username,
    String? name,
    DateTime? joinedAt,
    bool? isOnline,
  }) {
    return ThreadUser(
      id: id ?? this.id,
      username: username ?? this.username,
      name: name ?? this.name,
      joinedAt: joinedAt ?? this.joinedAt,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}


