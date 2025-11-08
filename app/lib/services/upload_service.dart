import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/thread/message.dart';
import 'http_client.dart';

class UploadService {
  /// Upload audio file to server with content-based addressing
  /// 
  /// Flow:
  /// 1. Read file and calculate SHA-256 hash
  /// 2. Upload with hash (server uses it as S3 key)
  /// 3. Server deduplicates automatically by hash
  static Future<Render?> uploadAudio({
    required String filePath,
    String format = 'mp3',
    int? bitrate,
    double? duration,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ [UPLOAD] File does not exist: $filePath');
        return null;
      }

      // Calculate SHA-256 hash for content-based addressing
      debugPrint('🔐 [UPLOAD] Calculating content hash...');
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes);
      final contentHash = hash.toString(); // Hex string
      
      debugPrint('📊 [UPLOAD] File hash: $contentHash');
      debugPrint('📦 [UPLOAD] File size: ${bytes.length} bytes');

      // Prepare fields (include hash for server-side deduplication)
      final fields = <String, String>{
        'format': format,
        'content_hash': contentHash,
      };
      if (bitrate != null) {
        fields['bitrate'] = bitrate.toString();
      }
      if (duration != null) {
        fields['duration'] = duration.toString();
      }

      debugPrint('🔄 [UPLOAD] Uploading audio file: $filePath');
      
      // Use ApiHttpClient for upload
      final response = await ApiHttpClient.uploadFile(
        '/upload/audio',
        filePath,
        fields: fields,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        
        // Log upload result
        final status = json['status'] ?? 'unknown';
        final s3Key = json['s3_key'] ?? 'unknown';
        final audioFileId = json['audio_file_id'] ?? 'MISSING';
        
        if (status == 'existing') {
          debugPrint('♻️  [UPLOAD] File already exists on server (deduplicated)');
          debugPrint('📍 [UPLOAD] S3 key: $s3Key');
        } else {
          debugPrint('✅ [UPLOAD] Upload successful (new file)');
          debugPrint('📍 [UPLOAD] S3 key: $s3Key');
        }
        
        debugPrint('🆔 [UPLOAD] Audio file ID: $audioFileId');
        
        final render = Render.fromJson(json);
        debugPrint('🎵 [UPLOAD] Render URL: ${render.url}');
        debugPrint('🎵 [UPLOAD] Render ID: ${render.id}');
        return render;
      } else {
        debugPrint('❌ [UPLOAD] Upload failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ [UPLOAD] Upload error: $e');
      return null;
    }
  }
}
