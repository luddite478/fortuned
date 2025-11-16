import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../utils/log.dart';

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

  static String get publicBaseUrl {
    final serverHost = dotenv.env['SERVER_HOST'] ?? '';
    final apiPort = dotenv.env['HTTPS_API_PORT'] ?? '443';
    final protocol = 'https';
    final port = apiPort == '443' ? '' : ':$apiPort';
    return '$protocol://$serverHost$port';
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
    
    Log.d('GET: $finalUrl', 'HTTP');
    if (queryParams != null && queryParams.isNotEmpty) {
      Log.d('Query params: $queryParams', 'HTTP');
    }
    
    try {
      final response = await http.get(finalUrl, headers: _defaultHeaders);
      
      Log.d('Response status: ${response.statusCode}', 'HTTP');
      Log.d('Response body: ${response.body}', 'HTTP');
      
      if (response.statusCode >= 400) {
        Log.e('HTTP Error ${response.statusCode} for GET $path', 'HTTP');
      } else {
        Log.d('GET $path completed successfully', 'HTTP');
      }
      
      return response;
    } catch (e) {
      Log.e('Network error for GET $path', 'HTTP', e);
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
    
    Log.d('POST: $finalUrl', 'HTTP');
    if (queryParams != null && queryParams.isNotEmpty) {
      Log.d('Query params: $queryParams', 'HTTP');
    }
    Log.d('Request body: $jsonBody', 'HTTP');
    
    try {
      final response = await http.post(
        finalUrl,
        headers: _defaultHeaders,
        body: jsonBody,
      );
      
      Log.d('Response status: ${response.statusCode}', 'HTTP');
      Log.d('Response body: ${response.body}', 'HTTP');
      
      if (response.statusCode >= 400) {
        Log.e('HTTP Error ${response.statusCode} for POST $path', 'HTTP');
      } else {
        Log.d('POST $path completed successfully', 'HTTP');
      }
      
      return response;
    } catch (e) {
      Log.e('Network error for POST $path', 'HTTP', e);
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
    
    Log.d('PUT: $finalUrl', 'HTTP');
    if (queryParams != null && queryParams.isNotEmpty) {
      Log.d('Query params: $queryParams', 'HTTP');
    }
    Log.d('Request body: $jsonBody', 'HTTP');
    
    try {
      final response = await http.put(
        finalUrl,
        headers: _defaultHeaders,
        body: jsonBody,
      );
      
      Log.d('Response status: ${response.statusCode}', 'HTTP');
      Log.d('Response body: ${response.body}', 'HTTP');
      
      if (response.statusCode >= 400) {
        Log.e('HTTP Error ${response.statusCode} for PUT $path', 'HTTP');
      } else {
        Log.d('PUT $path completed successfully', 'HTTP');
      }
      
      return response;
    } catch (e) {
      Log.e('Network error for PUT $path', 'HTTP', e);
      rethrow;
    }
  }

  /// DELETE request with authentication token in query params
  static Future<http.Response> delete(String path, {Map<String, String>? queryParams}) async {
    final url = Uri.parse('$_baseUrl$path');
    final finalQueryParams = queryParams ?? <String, String>{};
    finalQueryParams['token'] = _apiToken;
    final finalUrl = url.replace(queryParameters: finalQueryParams);
    
    Log.d('DELETE: $finalUrl', 'HTTP');
    if (queryParams != null && queryParams.isNotEmpty) {
      Log.d('Query params: $queryParams', 'HTTP');
    }
    
    try {
      final response = await http.delete(finalUrl, headers: _defaultHeaders);
      
      Log.d('Response status: ${response.statusCode}', 'HTTP');
      Log.d('Response body: ${response.body}', 'HTTP');
      
      if (response.statusCode >= 400) {
        Log.e('HTTP Error ${response.statusCode} for DELETE $path', 'HTTP');
      } else {
        Log.d('DELETE $path completed successfully', 'HTTP');
      }
      
      return response;
    } catch (e) {
      Log.e('Network error for DELETE $path', 'HTTP', e);
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
    
    Log.d('UPLOAD: $url', 'HTTP');
    Log.d('File: $filePath', 'HTTP');
    
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
      
      Log.d('Uploading file...', 'HTTP');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      Log.d('Response status: ${response.statusCode}', 'HTTP');
      Log.d('Response body: ${response.body}', 'HTTP');
      
      if (response.statusCode >= 400) {
        Log.e('HTTP Error ${response.statusCode} for UPLOAD $path', 'HTTP');
      } else {
        Log.i('UPLOAD $path completed successfully', 'HTTP');
      }
      
      return response;
    } catch (e) {
      Log.e('Network error for UPLOAD $path', 'HTTP', e);
      rethrow;
    }
  }
} 