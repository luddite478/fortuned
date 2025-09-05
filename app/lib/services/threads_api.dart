import 'dart:convert';
import 'package:http/http.dart' as http;
import 'http_client.dart';
import '../models/thread/thread.dart';
import '../models/thread/message.dart';
import '../models/thread/thread_user.dart';

class ThreadsApi {
  // Threads
  static Future<List<Thread>> getThreads({String? userId}) async {
    final query = <String, String>{};
    if (userId != null && userId.isNotEmpty) {
      query['user_id'] = userId;
    }
    final http.Response res = await ApiHttpClient.get('/threads', queryParams: query);
    if (res.statusCode != 200) {
      throw Exception('Failed to get threads: ${res.statusCode} ${res.body}');
    }
    final data = json.decode(res.body);
    final list = (data is List) ? data : (data['threads'] as List<dynamic>? ?? []);
    return list.map((e) => Thread.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Thread> getThread(String threadId) async {
    final http.Response res = await ApiHttpClient.get('/threads/$threadId');
    if (res.statusCode != 200) {
      throw Exception('Failed to get thread: ${res.statusCode} ${res.body}');
    }
    final data = json.decode(res.body) as Map<String, dynamic>;
    return Thread.fromJson(data);
  }

  static Future<String> createThread({
    required List<ThreadUser> users,
    Map<String, dynamic>? metadata,
  }) async {
    final body = <String, dynamic>{
      'users': users.map((u) => u.toJson()).toList(),
      if (metadata != null) 'metadata': metadata,
    };
    final http.Response res = await ApiHttpClient.post('/threads', body: body);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Failed to create thread: ${res.statusCode} ${res.body}');
    }
    final data = json.decode(res.body);
    return data['id'] ?? data['thread_id'];
  }

  // Messages
  static Future<List<Message>> getMessages(String threadId) async {
    final http.Response res = await ApiHttpClient.get('/messages', queryParams: {
      'thread_id': threadId,
    });
    if (res.statusCode != 200) {
      throw Exception('Failed to get messages: ${res.statusCode} ${res.body}');
    }
    final data = json.decode(res.body);
    final list = (data is List) ? data : (data['messages'] as List<dynamic>? ?? []);
    return list.map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Message> createMessage({
    required String threadId,
    required String userId,
    required Map<String, dynamic> snapshot,
    Map<String, dynamic>? metadata,
    DateTime? timestamp,
  }) async {
    final body = <String, dynamic>{
      'parent_thread': threadId,
      'user_id': userId,
      'snapshot': snapshot,
      if (metadata != null) 'metadata': metadata,
      if (timestamp != null) 'timestamp': timestamp.toIso8601String(),
    };
    final http.Response res = await ApiHttpClient.post('/messages', body: body);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Failed to create message: ${res.statusCode} ${res.body}');
    }
    final data = json.decode(res.body) as Map<String, dynamic>;
    return Message.fromJson(data);
  }

  // Invites
  static Future<void> sendInvite({
    required String threadId,
    required String userId,
    required String userName,
    required String invitedBy,
  }) async {
    final body = {
      'user_id': userId,
      'user_name': userName,
      'invited_by': invitedBy,
    };
    final res = await ApiHttpClient.post('/threads/$threadId/invites', body: body);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Failed to send invite: ${res.statusCode} ${res.body}');
    }
  }

  static Future<void> acceptInvite({
    required String threadId,
    required String userId,
  }) async {
    final res = await ApiHttpClient.put('/threads/$threadId/invites/$userId', body: {
      'action': 'accept',
    });
    if (res.statusCode != 200) {
      throw Exception('Failed to accept invite: ${res.statusCode} ${res.body}');
    }
  }

  static Future<void> declineInvite({
    required String threadId,
    required String userId,
  }) async {
    final res = await ApiHttpClient.put('/threads/$threadId/invites/$userId', body: {
      'action': 'decline',
    });
    if (res.statusCode != 200) {
      throw Exception('Failed to decline invite: ${res.statusCode} ${res.body}');
    }
  }
}


