class ThreadInvite {
  final String userId;
  final String userName;
  final String status; // pending | accepted | declined | cancelled
  final String invitedBy;
  final DateTime invitedAt;

  const ThreadInvite({
    required this.userId,
    required this.userName,
    required this.status,
    required this.invitedBy,
    required this.invitedAt,
  });

  factory ThreadInvite.fromJson(Map<String, dynamic> json) {
    return ThreadInvite(
      userId: json['user_id'] ?? '',
      userName: json['user_name'] ?? '',
      status: json['status'] ?? 'pending',
      invitedBy: json['invited_by'] ?? '',
      invitedAt: DateTime.parse(json['invited_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'user_name': userName,
        'status': status,
        'invited_by': invitedBy,
        'invited_at': invitedAt.toIso8601String(),
      };
}


