import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../state/threads_state.dart';

class ThreadsService {
  static String get _baseUrl {
    final serverIp = dotenv.env['SERVER_HOST'] ?? 'localhost';
    // Use HTTPS for production, HTTP for localhost development
    final protocol = serverIp == 'localhost' ? 'http' : 'https';
    final port = serverIp == 'localhost' ? ':8888' : '';
    return '$protocol://$serverIp$port/api/v1';
  }
  
  static String get _apiToken {
    final token = dotenv.env['API_TOKEN'] ?? '';
    return token;
  }

  // Create a new thread
  static Future<String> createThread({
    required String title,
    required List<ThreadUser> users,
    ThreadCheckpoint? initialCheckpoint,
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/threads');
      
      final body = <String, dynamic>{
        'title': title,
        'users': users.map((u) => u.toJson()).toList(),
        'metadata': metadata,
        'token': _apiToken,
      };
      
      if (initialCheckpoint != null) {
        body['initial_checkpoint'] = initialCheckpoint.toJson();
      }

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = json.decode(response.body);
        return jsonData['thread_id'] ?? jsonData['id'];
      } else {
        throw Exception('Failed to create thread: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error creating thread: $e');
    }
  }

  // Add a checkpoint to an existing thread
  static Future<void> addCheckpoint(String threadId, ThreadCheckpoint checkpoint) async {
    try {
      final url = Uri.parse('$_baseUrl/threads/$threadId/checkpoints');
      
      final body = jsonEncode({
        'checkpoint': checkpoint.toJson(),
        'token': _apiToken,
      });

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to add checkpoint: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error adding checkpoint: $e');
    }
  }

  // Join an existing thread
  static Future<void> joinThread(String threadId, String userId, String userName) async {
    try {
      final url = Uri.parse('$_baseUrl/threads/$threadId/users');
      
      final body = jsonEncode({
        'user_id': userId,
        'user_name': userName,
        'token': _apiToken,
      });

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to join thread: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error joining thread: $e');
    }
  }

  // Get all threads
  static Future<List<Thread>> getThreads({
    int limit = 50,
    int offset = 0,
    String? userId,
  }) async {
    try {
      final queryParams = {
        'limit': limit.toString(),
        'offset': offset.toString(),
        'token': _apiToken,
      };
      
      if (userId != null) {
        queryParams['user_id'] = userId;
      }

      final url = Uri.parse('$_baseUrl/threads/list').replace(queryParameters: queryParams);
      
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final threadsList = jsonData['threads'] as List<dynamic>? ?? [];
        
        return threadsList.map((threadJson) => Thread.fromJson(threadJson)).toList();
      } else {
        throw Exception('Failed to get threads: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error getting threads: $e');
    }
  }

  // Get a specific thread
  static Future<Thread?> getThread(String threadId) async {
    try {
      final url = Uri.parse('$_baseUrl/threads/thread').replace(queryParameters: {
        'id': threadId,
        'token': _apiToken,
      });
      
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return Thread.fromJson(jsonData);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to get thread: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error getting thread: $e');
    }
  }

  // Get threads for a specific user
  static Future<List<Thread>> getUserThreads(String userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    return getThreads(limit: limit, offset: offset, userId: userId);
  }

  // Update thread metadata
  static Future<void> updateThread(String threadId, {
    String? title,
    ThreadStatus? status,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/threads/$threadId');
      
      final updateData = <String, dynamic>{
        'token': _apiToken,
      };
      
      if (title != null) updateData['title'] = title;
      if (status != null) updateData['status'] = status.name;
      if (metadata != null) updateData['metadata'] = metadata;

      final body = jsonEncode(updateData);

      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update thread: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error updating thread: $e');
    }
  }

  // Delete a thread (archive it)
  static Future<void> deleteThread(String threadId) async {
    try {
      final url = Uri.parse('$_baseUrl/threads/$threadId').replace(queryParameters: {
        'token': _apiToken,
      });
      
      final response = await http.delete(url);

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to delete thread: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error deleting thread: $e');
    }
  }

  // Get thread statistics
  static Future<Map<String, dynamic>> getThreadStats() async {
    try {
      final url = Uri.parse('$_baseUrl/threads/stats').replace(queryParameters: {
        'token': _apiToken,
      });
      
      final response = await http.get(url);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to get thread stats: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error getting thread stats: $e');
    }
  }

  // Search threads
  static Future<List<Thread>> searchThreads({
    required String query,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/threads/search').replace(queryParameters: {
        'q': query,
        'limit': limit.toString(),
        'offset': offset.toString(),
        'token': _apiToken,
      });
      
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final threadsList = jsonData['threads'] as List<dynamic>? ?? [];
        
        return threadsList.map((threadJson) => Thread.fromJson(threadJson)).toList();
      } else {
        throw Exception('Failed to search threads: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error searching threads: $e');
    }
  }
} 