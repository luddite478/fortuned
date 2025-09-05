class ThreadUser {
  final String id;
  final String name;
  final DateTime joinedAt;

  const ThreadUser({
    required this.id,
    required this.name,
    required this.joinedAt,
  });

  factory ThreadUser.fromJson(Map<String, dynamic> json) {
    return ThreadUser(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      joinedAt: DateTime.parse(json['joined_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'joined_at': joinedAt.toIso8601String(),
      };
}


