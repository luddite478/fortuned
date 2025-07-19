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

  /// GET request
  static Future<http.Response> get(String path, {Map<String, String>? queryParams}) async {
    final url = Uri.parse('$_baseUrl$path');
    final finalUrl = queryParams != null ? url.replace(queryParameters: queryParams) : url;
    
    return await http.get(finalUrl, headers: _defaultHeaders);
  }

  /// POST request
  static Future<http.Response> post(String path, {Map<String, dynamic>? body, Map<String, String>? queryParams}) async {
    final url = Uri.parse('$_baseUrl$path');
    final finalUrl = queryParams != null ? url.replace(queryParameters: queryParams) : url;
    
    return await http.post(
      finalUrl,
      headers: _defaultHeaders,
      body: body != null ? json.encode(body) : null,
    );
  }

  /// PUT request
  static Future<http.Response> put(String path, {Map<String, dynamic>? body, Map<String, String>? queryParams}) async {
    final url = Uri.parse('$_baseUrl$path');
    final finalUrl = queryParams != null ? url.replace(queryParameters: queryParams) : url;
    
    return await http.put(
      finalUrl,
      headers: _defaultHeaders,
      body: body != null ? json.encode(body) : null,
    );
  }

  /// DELETE request
  static Future<http.Response> delete(String path, {Map<String, String>? queryParams}) async {
    final url = Uri.parse('$_baseUrl$path');
    final finalUrl = queryParams != null ? url.replace(queryParameters: queryParams) : url;
    
    return await http.delete(finalUrl, headers: _defaultHeaders);
  }

  /// POST request with authentication token
  static Future<http.Response> postWithAuth(String path, {Map<String, dynamic>? body, Map<String, String>? queryParams}) async {
    final bodyWithAuth = body ?? <String, dynamic>{};
    bodyWithAuth['token'] = _apiToken;
    
    return await post(path, body: bodyWithAuth, queryParams: queryParams);
  }

  /// PUT request with authentication token
  static Future<http.Response> putWithAuth(String path, {Map<String, dynamic>? body, Map<String, String>? queryParams}) async {
    final bodyWithAuth = body ?? <String, dynamic>{};
    bodyWithAuth['token'] = _apiToken;
    
    return await put(path, body: bodyWithAuth, queryParams: queryParams);
  }

  /// GET request with authentication token in query params
  static Future<http.Response> getWithAuth(String path, {Map<String, String>? queryParams}) async {
    final finalQueryParams = queryParams ?? <String, String>{};
    finalQueryParams['token'] = _apiToken;
    
    return await get(path, queryParams: finalQueryParams);
  }

  /// DELETE request with authentication token in query params
  static Future<http.Response> deleteWithAuth(String path, {Map<String, String>? queryParams}) async {
    final finalQueryParams = queryParams ?? <String, String>{};
    finalQueryParams['token'] = _apiToken;
    
    return await delete(path, queryParams: finalQueryParams);
  }
} 