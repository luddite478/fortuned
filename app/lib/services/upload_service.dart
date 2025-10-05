import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/thread/message.dart';

class UploadService {
  static String get _baseUrl {
    final serverHost = dotenv.env['SERVER_HOST'] ?? '';
    return '$serverHost/api/v1';
  }

  static String get _token {
    return dotenv.env['API_TOKEN'] ?? '';
  }

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

      final uri = Uri.parse('$_baseUrl/upload/audio');
      final request = http.MultipartRequest('POST', uri);
      
      // Add fields
      request.fields['token'] = _token;
      request.fields['format'] = format;
      if (bitrate != null) {
        request.fields['bitrate'] = bitrate.toString();
      }
      if (duration != null) {
        request.fields['duration'] = duration.toString();
      }

      // Add file
      request.files.add(
        await http.MultipartFile.fromPath('file', filePath),
      );

      debugPrint('🔄 [UPLOAD] Uploading audio file: $filePath');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

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

