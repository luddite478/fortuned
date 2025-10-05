import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../models/thread/message.dart';
import 'http_client.dart';

class UploadService {
  /// Upload audio file to server and return Render object
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

      // Prepare fields
      final fields = <String, String>{
        'format': format,
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
        final render = Render.fromJson(json);
        debugPrint('✅ [UPLOAD] Upload successful: ${render.url}');
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
