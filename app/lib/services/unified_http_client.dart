import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// DevHttpOverrides class to trust self-signed certificates
class DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

/// Unified HTTP client service for all network requests
class UnifiedHttpClient {
  static const String _contentTypeJson = 'application/json';
  
  /// Get base URL for API requests
  static String get _baseUrl {
    final serverHost = dotenv.env['SERVER_HOST'] ?? '';
    final apiPort = dotenv.env['HTTPS_API_PORT'] ?? '443';
    final protocol = 'https';
    final port = apiPort == '443' ? '' : ':$apiPort';
    return '$protocol://$serverHost$port/api/v1';
  }
  
  /// Get API token from environment
  static String get _apiToken {
    return dotenv.env['API_TOKEN'] ?? '';
  }
  
  /// Get default headers for API requests
  static Map<String, String> get _defaultHeaders {
    return {
      'Content-Type': _contentTypeJson,
    };
  }
  
  /// Initialize HTTP overrides for stage environment
  static void initializeHttpOverrides() {
    final env = dotenv.env['ENV'] ?? '';
    if (env == 'stage') {
      HttpOverrides.global = DevHttpOverrides();
      print('🔒 DevHttpOverrides enabled for stage environment');
    }
  }
  
  /// Make a GET request
  static Future<http.Response> get(
    String endpoint, {
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool includeToken = true,
  }) async {
    final url = Uri.parse('$_baseUrl/$endpoint');
    
    // Add token to query parameters if needed
    final params = Map<String, String>.from(queryParameters ?? {});
    if (includeToken && _apiToken.isNotEmpty) {
      params['token'] = _apiToken;
    }
    
    final finalUrl = url.replace(queryParameters: params.isNotEmpty ? params : null);
    final finalHeaders = {..._defaultHeaders, ...?headers};
    
    print('🌐 GET: $finalUrl');
    return await http.get(finalUrl, headers: finalHeaders);
  }
  
  /// Make a POST request
  static Future<http.Response> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool includeToken = true,
  }) async {
    final url = Uri.parse('$_baseUrl/$endpoint');
    final finalHeaders = {..._defaultHeaders, ...?headers};
    
    // Add token to body if needed
    final requestBody = Map<String, dynamic>.from(body ?? {});
    if (includeToken && _apiToken.isNotEmpty) {
      requestBody['token'] = _apiToken;
    }
    
    final jsonBody = jsonEncode(requestBody);
    
    print('🌐 POST: $url');
    print('📝 Body: $jsonBody');
    
    return await http.post(url, headers: finalHeaders, body: jsonBody);
  }
  
  /// Make a PUT request
  static Future<http.Response> put(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool includeToken = true,
  }) async {
    final url = Uri.parse('$_baseUrl/$endpoint');
    final finalHeaders = {..._defaultHeaders, ...?headers};
    
    // Add token to body if needed
    final requestBody = Map<String, dynamic>.from(body ?? {});
    if (includeToken && _apiToken.isNotEmpty) {
      requestBody['token'] = _apiToken;
    }
    
    final jsonBody = jsonEncode(requestBody);
    
    print('🌐 PUT: $url');
    print('📝 Body: $jsonBody');
    
    return await http.put(url, headers: finalHeaders, body: jsonBody);
  }
  
  /// Make a DELETE request
  static Future<http.Response> delete(
    String endpoint, {
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool includeToken = true,
  }) async {
    final url = Uri.parse('$_baseUrl/$endpoint');
    
    // Add token to query parameters if needed
    final params = Map<String, String>.from(queryParameters ?? {});
    if (includeToken && _apiToken.isNotEmpty) {
      params['token'] = _apiToken;
    }
    
    final finalUrl = url.replace(queryParameters: params.isNotEmpty ? params : null);
    final finalHeaders = {..._defaultHeaders, ...?headers};
    
    print('🌐 DELETE: $finalUrl');
    return await http.delete(finalUrl, headers: finalHeaders);
  }
  
  /// Make a request to a custom URL (for non-API endpoints)
  static Future<http.Response> getCustomUrl(
    String fullUrl, {
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse(fullUrl);
    final finalHeaders = {..._defaultHeaders, ...?headers};
    
    print('🌐 GET Custom: $url');
    return await http.get(url, headers: finalHeaders);
  }
  
  /// Make a POST request to a custom URL (for non-API endpoints)
  static Future<http.Response> postCustomUrl(
    String fullUrl, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse(fullUrl);
    final finalHeaders = {..._defaultHeaders, ...?headers};
    final jsonBody = body != null ? jsonEncode(body) : null;
    
    print('🌐 POST Custom: $url');
    if (jsonBody != null) {
      print('📝 Body: $jsonBody');
    }
    
    return await http.post(url, headers: finalHeaders, body: jsonBody);
  }
} 