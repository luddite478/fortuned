import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../state/threads_state.dart';

// Thread request/response models
class CreateThreadRequest {
  final String originalProjectId;
  final String collaboratorUserId;
  final SequencerSnapshot initialState;

  CreateThreadRequest({
    required this.originalProjectId,
    required this.collaboratorUserId,
    required this.initialState,
  });

  Map<String, dynamic> toJson() => {
    'original_project_id': originalProjectId,
    'collaborator_user_id': collaboratorUserId,
    'initial_state': initialState.toJson(),
  };
}

class SendMessageRequest {
  final String threadId;
  final SequencerSnapshot sequencerState;
  final String? comment;

  SendMessageRequest({
    required this.threadId,
    required this.sequencerState,
    this.comment,
  });

  Map<String, dynamic> toJson() => {
    'thread_id': threadId,
    'sequencer_state': sequencerState.toJson(),
    'comment': comment,
  };
}

class ThreadResponse {
  final String threadId;
  final CollaborativeThread thread;

  ThreadResponse({
    required this.threadId,
    required this.thread,
  });

  factory ThreadResponse.fromJson(Map<String, dynamic> json) {
    return ThreadResponse(
      threadId: json['thread_id'] ?? '',
      thread: CollaborativeThread(
        id: json['id'] ?? '',
        originalProjectId: json['original_project_id'] ?? '',
        originalUserId: json['original_user_id'] ?? '',
        originalUserName: json['original_user_name'] ?? '',
        collaboratorUserId: json['collaborator_user_id'] ?? '',
        collaboratorUserName: json['collaborator_user_name'] ?? '',
        projectTitle: json['project_title'] ?? '',
        messages: (json['messages'] as List<dynamic>? ?? [])
            .map((msg) => ThreadMessage(
                  id: msg['id'] ?? '',
                  threadId: msg['thread_id'] ?? '',
                  userId: msg['user_id'] ?? '',
                  userName: msg['user_name'] ?? '',
                  sequencerState: SequencerSnapshot.fromJson(msg['sequencer_state'] ?? {}),
                  timestamp: DateTime.parse(msg['timestamp'] ?? DateTime.now().toIso8601String()),
                  comment: msg['comment'],
                ))
            .toList(),
        status: ThreadStatus.values.firstWhere(
          (status) => status.toString().split('.').last == json['status'],
          orElse: () => ThreadStatus.active,
        ),
        createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
        lastActivity: DateTime.parse(json['last_activity'] ?? DateTime.now().toIso8601String()),
        currentState: json['current_state'] != null 
          ? SequencerSnapshot.fromJson(json['current_state'])
          : null,
      ),
    );
  }
}

// Threads service for API communication
class ThreadsService {
  static String get _baseUrl {
    final serverIp = dotenv.env['SERVER_IP'] ?? 'localhost';
    return 'http://$serverIp:8888/api/v1';
  }
  
  static String get _apiToken {
    final token = dotenv.env['API_TOKEN'] ?? '';
    if (token.isEmpty) {
      return 'asdfasdasduiu546'; // Fallback for development
    }
    return token;
  }

  // Create a new collaborative thread
  static Future<ThreadResponse> createThread({
    required String originalProjectId,
    required String collaboratorUserId,
    required SequencerSnapshot initialState,
  }) async {
    try {
      final request = CreateThreadRequest(
        originalProjectId: originalProjectId,
        collaboratorUserId: collaboratorUserId,
        initialState: initialState,
      );

      final url = Uri.parse('$_baseUrl/threads/create')
          .replace(queryParameters: {'token': _apiToken});

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(request.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = json.decode(response.body);
        return ThreadResponse.fromJson(jsonData);
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid API token');
      } else {
        throw Exception('Failed to create thread: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Send a new message (sequencer state) to a thread
  static Future<void> sendMessage({
    required String threadId,
    required SequencerSnapshot sequencerState,
    String? comment,
  }) async {
    try {
      final request = SendMessageRequest(
        threadId: threadId,
        sequencerState: sequencerState,
        comment: comment,
      );

      final url = Uri.parse('$_baseUrl/threads/message')
          .replace(queryParameters: {'token': _apiToken});

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(request.toJson()),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to send message: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Get user's threads
  static Future<List<CollaborativeThread>> getUserThreads({
    required String userId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/threads/user')
          .replace(queryParameters: {
        'user_id': userId,
        'token': _apiToken,
        'limit': limit.toString(),
        'offset': offset.toString(),
      });

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final threadsList = jsonData['threads'] as List<dynamic>? ?? [];
        
        return threadsList.map((threadData) => 
            ThreadResponse.fromJson(threadData).thread).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid API token');
      } else {
        throw Exception('Failed to load threads: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Get specific thread details
  static Future<CollaborativeThread> getThread(String threadId) async {
    try {
      final url = Uri.parse('$_baseUrl/threads/details')
          .replace(queryParameters: {
        'thread_id': threadId,
        'token': _apiToken,
      });

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return ThreadResponse.fromJson(jsonData).thread;
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid API token');
      } else if (response.statusCode == 404) {
        throw Exception('Thread not found');
      } else {
        throw Exception('Failed to load thread: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Get thread messages
  static Future<List<ThreadMessage>> getThreadMessages({
    required String threadId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/threads/messages')
          .replace(queryParameters: {
        'thread_id': threadId,
        'token': _apiToken,
        'limit': limit.toString(),
        'offset': offset.toString(),
      });

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final messagesList = jsonData['messages'] as List<dynamic>? ?? [];
        
        return messagesList.map((msgData) => ThreadMessage(
          id: msgData['id'] ?? '',
          threadId: msgData['thread_id'] ?? '',
          userId: msgData['user_id'] ?? '',
          userName: msgData['user_name'] ?? '',
          sequencerState: SequencerSnapshot.fromJson(msgData['sequencer_state'] ?? {}),
          timestamp: DateTime.parse(msgData['timestamp'] ?? DateTime.now().toIso8601String()),
          comment: msgData['comment'],
        )).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid API token');
      } else {
        throw Exception('Failed to load messages: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Update thread status
  static Future<void> updateThreadStatus({
    required String threadId,
    required ThreadStatus status,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/threads/status')
          .replace(queryParameters: {
        'thread_id': threadId,
        'status': status.toString().split('.').last,
        'token': _apiToken,
      });

      final response = await http.put(url);

      if (response.statusCode != 200) {
        throw Exception('Failed to update thread status: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Join thread
  static Future<CollaborativeThread> joinThread(String threadId) async {
    try {
      final url = Uri.parse('$_baseUrl/threads/join')
          .replace(queryParameters: {
        'thread_id': threadId,
        'token': _apiToken,
      });

      final response = await http.post(url);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return ThreadResponse.fromJson(jsonData).thread;
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid API token');
      } else if (response.statusCode == 404) {
        throw Exception('Thread not found');
      } else {
        throw Exception('Failed to join thread: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Leave thread
  static Future<void> leaveThread(String threadId) async {
    try {
      final url = Uri.parse('$_baseUrl/threads/leave')
          .replace(queryParameters: {
        'thread_id': threadId,
        'token': _apiToken,
      });

      final response = await http.post(url);

      if (response.statusCode != 200) {
        throw Exception('Failed to leave thread: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
} 