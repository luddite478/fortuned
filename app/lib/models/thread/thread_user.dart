class ThreadUser {
  final String id;
  final String username;
  final String name;
  final DateTime joinedAt;

  const ThreadUser({
    required this.id,
    required this.username,
    required this.name,
    required this.joinedAt,
  });

  factory ThreadUser.fromJson(Map<String, dynamic> json) {
    return ThreadUser(
      id: json['id'] ?? '',
      username: json['username'] ?? json['name'] ?? '',  // Fallback to name if username not present
      name: json['name'] ?? '',
      joinedAt: DateTime.parse(json['joined_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'name': name,
        'joined_at': joinedAt.toIso8601String(),
      };
}


