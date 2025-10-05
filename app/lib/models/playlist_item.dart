class PlaylistItem {
  final String name;
  final String url;
  final String id;
  final String format;
  final int? bitrate;
  final double? duration;
  final int? sizeBytes;
  final DateTime createdAt;
  final String type; // 'render'

  const PlaylistItem({
    required this.name,
    required this.url,
    required this.id,
    required this.format,
    this.bitrate,
    this.duration,
    this.sizeBytes,
    required this.createdAt,
    required this.type,
  });

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    return PlaylistItem(
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      id: json['id'] ?? '',
      format: json['format'] ?? 'mp3',
      bitrate: json['bitrate'],
      duration: json['duration']?.toDouble(),
      sizeBytes: json['size_bytes'],
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      type: json['type'] ?? 'render',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'id': id,
        'format': format,
        if (bitrate != null) 'bitrate': bitrate,
        if (duration != null) 'duration': duration,
        if (sizeBytes != null) 'size_bytes': sizeBytes,
        'created_at': createdAt.toIso8601String(),
        'type': type,
      };
}

