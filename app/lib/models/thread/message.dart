enum SendStatus { sending, failed, sent }
enum RenderUploadStatus { pending, uploading, completed, failed }

class Render {
  final String id;
  final String url;
  final String format;
  final int? bitrate;
  final double? duration;
  final int? sizeBytes;
  final DateTime createdAt;
  final RenderUploadStatus? uploadStatus; // Client-only
  final String? localPath; // Client-only: local file path for immediate playback

  const Render({
    required this.id,
    required this.url,
    required this.format,
    this.bitrate,
    this.duration,
    this.sizeBytes,
    required this.createdAt,
    this.uploadStatus,
    this.localPath,
  });

  factory Render.fromJson(Map<String, dynamic> json) {
    return Render(
      id: json['id'] ?? '',
      url: json['url'] ?? '',
      format: json['format'] ?? 'mp3',
      bitrate: json['bitrate'],
      duration: json['duration']?.toDouble(),
      sizeBytes: json['size_bytes'],
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'format': format,
        if (bitrate != null) 'bitrate': bitrate,
        if (duration != null) 'duration': duration,
        if (sizeBytes != null) 'size_bytes': sizeBytes,
        'created_at': createdAt.toIso8601String(),
      };

  Render copyWith({
    String? id,
    String? url,
    String? format,
    int? bitrate,
    double? duration,
    int? sizeBytes,
    DateTime? createdAt,
    RenderUploadStatus? uploadStatus,
    String? localPath,
  }) {
    return Render(
      id: id ?? this.id,
      url: url ?? this.url,
      format: format ?? this.format,
      bitrate: bitrate ?? this.bitrate,
      duration: duration ?? this.duration,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdAt: createdAt ?? this.createdAt,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      localPath: localPath ?? this.localPath,
    );
  }
}

class Message {
  final String id; // empty for not-yet-sent
  final DateTime createdAt;
  final DateTime timestamp;
  final String userId;
  final String? parentThread;
  final Map<String, dynamic> snapshot; // can be empty when include_snapshot=false
  final Map<String, dynamic>? snapshotMetadata;
  final List<Render> renders;

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
    this.renders = const [],
    this.localTempId,
    this.sendStatus,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final rendersList = json['renders'] as List<dynamic>? ?? [];
    return Message(
      id: json['id'] ?? '',
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      userId: json['user_id'] ?? '',
      parentThread: json['parent_thread'],
      snapshot: Map<String, dynamic>.from(json['snapshot'] ?? {}),
      snapshotMetadata: json['snapshot_metadata'] == null ? null : Map<String, dynamic>.from(json['snapshot_metadata'] as Map<String, dynamic>),
      renders: rendersList.map((r) => Render.fromJson(r as Map<String, dynamic>)).toList(),
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
        'renders': renders.map((r) => r.toJson()).toList(),
      };

  Message copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? timestamp,
    String? userId,
    String? parentThread,
    Map<String, dynamic>? snapshot,
    Map<String, dynamic>? snapshotMetadata,
    List<Render>? renders,
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
      renders: renders ?? this.renders,
      localTempId: localTempId ?? this.localTempId,
      sendStatus: sendStatus ?? this.sendStatus,
    );
  }
}


