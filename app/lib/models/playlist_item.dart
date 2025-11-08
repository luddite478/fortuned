// Import for RenderUploadStatus
import 'package:fortuned/models/thread/message.dart' show RenderUploadStatus;

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
  final String? localPath; // Local file path for instant playback
  final RenderUploadStatus? uploadStatus; // Upload status if still uploading

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
    this.localPath,
    this.uploadStatus,
  });

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    RenderUploadStatus? status;
    if (json['upload_status'] != null) {
      final statusStr = json['upload_status'] as String;
      status = RenderUploadStatus.values.firstWhere(
        (e) => e.toString().split('.').last == statusStr,
        orElse: () => RenderUploadStatus.completed,
      );
    }
    
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
      localPath: json['local_path'],
      uploadStatus: status,
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
        if (localPath != null) 'local_path': localPath,
        if (uploadStatus != null) 'upload_status': uploadStatus.toString().split('.').last,
      };
  
  /// Create a copy with updated fields
  PlaylistItem copyWith({
    String? name,
    String? url,
    String? id,
    String? format,
    int? bitrate,
    double? duration,
    int? sizeBytes,
    DateTime? createdAt,
    String? type,
    String? localPath,
    RenderUploadStatus? uploadStatus,
  }) {
    return PlaylistItem(
      name: name ?? this.name,
      url: url ?? this.url,
      id: id ?? this.id,
      format: format ?? this.format,
      bitrate: bitrate ?? this.bitrate,
      duration: duration ?? this.duration,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdAt: createdAt ?? this.createdAt,
      type: type ?? this.type,
      localPath: localPath ?? this.localPath,
      uploadStatus: uploadStatus ?? this.uploadStatus,
    );
  }
}

