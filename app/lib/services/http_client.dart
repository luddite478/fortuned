import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Custom HttpOverrides to trust self-signed certificates for stage environment
class DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

/// API HTTP client for all API calls
class ApiHttpClient {
  static String get _baseUrl {
    final serverHost = dotenv.env['SERVER_HOST'] ?? '';
    final apiPort = dotenv.env['HTTPS_API_PORT'] ?? '443';
    final protocol = 'https';
    final port = apiPort == '443' ? '' : ':$apiPort';
    return '$protocol://$serverHost$port/api/v1';
  }

  static String get _apiToken {
    return dotenv.env['API_TOKEN'] ?? '';
  }

  static Map<String, String> get _defaultHeaders {
    return {
      'Content-Type': 'application/json',
    };
  }

  /// GET request with authentication token in query params
  static Future<http.Response> get(String path, {Map<String, String>? queryParams}) async {
    final url = Uri.parse('$_baseUrl$path');
    final finalQueryParams = queryParams ?? <String, String>{};
    finalQueryParams['token'] = _apiToken;
    final finalUrl = url.replace(queryParameters: finalQueryParams);
    
    print('🌐 GET: $finalUrl');
    if (queryParams != null && queryParams.isNotEmpty) {
      print('📝 Query params: $queryParams');
    }
    
    try {
      final response = await http.get(finalUrl, headers: _defaultHeaders);
      
      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');
      
      if (response.statusCode >= 400) {
        print('❌ HTTP Error ${response.statusCode} for GET $path');
      } else {
        print('✅ GET $path completed successfully');
      }
      
      return response;
    } catch (e) {
      print('❌ Network error for GET $path: $e');
      rethrow;
    }
  }

  /// POST request with authentication token in body
  static Future<http.Response> post(String path, {Map<String, dynamic>? body, Map<String, String>? queryParams}) async {
    final url = Uri.parse('$_baseUrl$path');
    final finalUrl = queryParams != null ? url.replace(queryParameters: queryParams) : url;
    final bodyWithAuth = body ?? <String, dynamic>{};
    bodyWithAuth['token'] = _apiToken;
    final jsonBody = json.encode(bodyWithAuth);
    
    print('🌐 POST: $finalUrl');
    if (queryParams != null && queryParams.isNotEmpty) {
      print('📝 Query params: $queryParams');
    }
    print('📝 Request body: $jsonBody');
    
    try {
      final response = await http.post(
        finalUrl,
        headers: _defaultHeaders,
        body: jsonBody,
      );
      
      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');
      
      if (response.statusCode >= 400) {
        print('❌ HTTP Error ${response.statusCode} for POST $path');
      } else {
        print('✅ POST $path completed successfully');
      }
      
      return response;
    } catch (e) {
      print('❌ Network error for POST $path: $e');
      rethrow;
    }
  }

  /// PUT request with authentication token in body
  static Future<http.Response> put(String path, {Map<String, dynamic>? body, Map<String, String>? queryParams}) async {
    final url = Uri.parse('$_baseUrl$path');
    final finalUrl = queryParams != null ? url.replace(queryParameters: queryParams) : url;
    final bodyWithAuth = body ?? <String, dynamic>{};
    bodyWithAuth['token'] = _apiToken;
    final jsonBody = json.encode(bodyWithAuth);
    
    print('🌐 PUT: $finalUrl');
    if (queryParams != null && queryParams.isNotEmpty) {
      print('📝 Query params: $queryParams');
    }
    print('📝 Request body: $jsonBody');
    
    try {
      final response = await http.put(
        finalUrl,
        headers: _defaultHeaders,
        body: jsonBody,
      );
      
      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');
      
      if (response.statusCode >= 400) {
        print('❌ HTTP Error ${response.statusCode} for PUT $path');
      } else {
        print('✅ PUT $path completed successfully');
      }
      
      return response;
    } catch (e) {
      print('❌ Network error for PUT $path: $e');
      rethrow;
    }
  }

  /// DELETE request with authentication token in query params
  static Future<http.Response> delete(String path, {Map<String, String>? queryParams}) async {
    final url = Uri.parse('$_baseUrl$path');
    final finalQueryParams = queryParams ?? <String, String>{};
    finalQueryParams['token'] = _apiToken;
    final finalUrl = url.replace(queryParameters: finalQueryParams);
    
    print('🌐 DELETE: $finalUrl');
    if (queryParams != null && queryParams.isNotEmpty) {
      print('📝 Query params: $queryParams');
    }
    
    try {
      final response = await http.delete(finalUrl, headers: _defaultHeaders);
      
      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');
      
      if (response.statusCode >= 400) {
        print('❌ HTTP Error ${response.statusCode} for DELETE $path');
      } else {
        print('✅ DELETE $path completed successfully');
      }
      
      return response;
    } catch (e) {
      print('❌ Network error for DELETE $path: $e');
      rethrow;
    }
  }

  /// Multipart upload request for file uploads with authentication token
  static Future<http.Response> uploadFile(
    String path, 
    String filePath, {
    String fileFieldName = 'file',
    Map<String, String>? fields,
  }) async {
    final url = Uri.parse('$_baseUrl$path');
    
    print('🌐 UPLOAD: $url');
    print('📁 File: $filePath');
    
    try {
      final request = http.MultipartRequest('POST', url);
      
      // Add authentication token
      request.fields['token'] = _apiToken;
      
      // Add additional fields
      if (fields != null) {
        request.fields.addAll(fields);
      }
      
      // Add file
      request.files.add(
        await http.MultipartFile.fromPath(fileFieldName, filePath),
      );
      
      print('📤 Uploading file...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');
      
      if (response.statusCode >= 400) {
        print('❌ HTTP Error ${response.statusCode} for UPLOAD $path');
      } else {
        print('✅ UPLOAD $path completed successfully');
      }
      
      return response;
    } catch (e) {
      print('❌ Network error for UPLOAD $path: $e');
      rethrow;
    }
  }
} 