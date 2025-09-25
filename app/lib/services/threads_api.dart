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
  static Future<List<Message>> getMessages(
    String threadId, {
    int? limit,
    String? order, // 'asc' | 'desc'
    bool includeSnapshot = true,
  }) async {
    final query = <String, String>{
      'thread_id': threadId,
      'include_snapshot': includeSnapshot ? 'true' : 'false',
    };
    if (limit != null) query['limit'] = limit.toString();
    if (order != null) query['order'] = order;
    final http.Response res = await ApiHttpClient.get('/messages', queryParams: query);
    if (res.statusCode != 200) {
      throw Exception('Failed to get messages: ${res.statusCode} ${res.body}');
    }
    final data = json.decode(res.body);
    final list = (data is List) ? data : (data['messages'] as List<dynamic>? ?? []);
    return list.map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Message> getMessageById(String messageId, {bool includeSnapshot = true}) async {
    final http.Response res = await ApiHttpClient.get('/messages/$messageId', queryParams: {
      'include_snapshot': includeSnapshot ? 'true' : 'false',
    });
    if (res.statusCode != 200) {
      throw Exception('Failed to get message: ${res.statusCode} ${res.body}');
    }
    final data = json.decode(res.body) as Map<String, dynamic>;
    return Message.fromJson(data);
  }

  static Future<Message?> getLatestMessage(String threadId, {bool includeSnapshot = true}) async {
    final list = await getMessages(
      threadId,
      limit: 1,
      order: 'desc',
      includeSnapshot: includeSnapshot,
    );
    if (list.isEmpty) return null;
    return list.first;
  }

  static Future<Message> createMessage({
    required String threadId,
    required String userId,
    required Map<String, dynamic> snapshot,
    Map<String, dynamic>? snapshotMetadata,
    DateTime? timestamp,
  }) async {
    final body = <String, dynamic>{
      'parent_thread': threadId,
      'user_id': userId,
      'snapshot': snapshot,
      if (snapshotMetadata != null) 'snapshot_metadata': snapshotMetadata,
      if (timestamp != null) 'timestamp': timestamp.toIso8601String(),
    };
    final http.Response res = await ApiHttpClient.post('/messages', body: body);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Failed to create message: ${res.statusCode} ${res.body}');
    }
    final data = json.decode(res.body) as Map<String, dynamic>;
    return Message.fromJson(data);
  }

  static Future<void> deleteMessage(String messageId) async {
    final http.Response res = await ApiHttpClient.delete('/messages/$messageId');
    if (res.statusCode != 200) {
      throw Exception('Failed to delete message: ${res.statusCode} ${res.body}');
    }
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

  // Thread deletion
  static Future<void> deleteThread(String threadId) async {
    final res = await ApiHttpClient.delete('/threads/$threadId');
    if (res.statusCode != 200) {
      throw Exception('Failed to delete thread: ${res.statusCode} ${res.body}');
    }
  }
}


