import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../state/threads_state.dart';
import 'http_client.dart';
import 'ws_client.dart';

// Thread message data model (moved from chat_state.dart)
class ThreadMessage {
  final String from;
  final String? to;
  final String message;
  final DateTime timestamp;
  final bool isDelivered;
  final bool isRead;

  const ThreadMessage({
    required this.from,
    this.to,
    required this.message,
    required this.timestamp,
    this.isDelivered = false,
    this.isRead = false,
  });

  ThreadMessage copyWith({
    String? from,
    String? to,
    String? message,
    DateTime? timestamp,
    bool? isDelivered,
    bool? isRead,
  }) {
    return ThreadMessage(
      from: from ?? this.from,
      to: to ?? this.to,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isDelivered: isDelivered ?? this.isDelivered,
      isRead: isRead ?? this.isRead,
    );
  }
}

// Data model for thread history response
class ThreadHistoryResponse {
  final String withUser;
  final List<ThreadMessage> messages;
  
  ThreadHistoryResponse({
    required this.withUser,
    required this.messages,
  });
}

// Data model for delivery confirmation
class DeliveryConfirmation {
  final String to;
  final String message;
  
  DeliveryConfirmation({
    required this.to,
    required this.message,
  });
}

// Data model for thread notification (when someone shares a thread)
class ThreadNotification {
  final String from;
  final String threadId;
  final String threadTitle;
  final DateTime timestamp;
  
  ThreadNotification({
    required this.from,
    required this.threadId,
    required this.threadTitle,
    required this.timestamp,
  });
}

// Data model for thread invitation notification
class ThreadInvitationNotification {
  final String fromUserId;
  final String fromUserName;
  final String threadId;
  final String threadTitle;
  final DateTime timestamp;
  
  ThreadInvitationNotification({
    required this.fromUserId,
    required this.fromUserName,
    required this.threadId,
    required this.threadTitle,
    required this.timestamp,
  });
}

class ThreadsService {
  static String get _baseUrl {
    final serverIp = dotenv.env['SERVER_HOST'] ?? '';
    final apiPort = dotenv.env['HTTPS_API_PORT'] ?? '443';
    final protocol = 'https';
    final port = apiPort == '443' ? '' : ':$apiPort';
    return '$protocol://$serverIp$port/api/v1';
  }
  
  static String get _apiToken {
    final token = dotenv.env['API_TOKEN'] ?? '';
    return token;
  }

  // WebSocket client for real-time communication (injected)
  final WebSocketClient _wsClient;
  
  // Stream controllers for real-time thread events
  final _messageController = StreamController<ThreadMessage>.broadcast();
  final _threadHistoryController = StreamController<ThreadHistoryResponse>.broadcast();
  final _deliveryController = StreamController<DeliveryConfirmation>.broadcast();
  final _threadNotificationController = StreamController<ThreadNotification>.broadcast();
  final _threadInvitationController = StreamController<ThreadInvitationNotification>.broadcast();
  
  // Getters for streams (for listening in UI)
  Stream<ThreadMessage> get messageStream => _messageController.stream;
  Stream<ThreadHistoryResponse> get threadHistoryStream => _threadHistoryController.stream;
  Stream<DeliveryConfirmation> get deliveryStream => _deliveryController.stream;
  Stream<ThreadNotification> get threadNotificationStream => _threadNotificationController.stream;
  Stream<ThreadInvitationNotification> get threadInvitationStream => _threadInvitationController.stream;
  Stream<bool> get connectionStream => _wsClient.connectionStream;
  Stream<String> get errorStream => _wsClient.errorStream;
  bool get isConnected => _wsClient.isConnected;
  String? get clientId => _wsClient.clientId;

  ThreadsService({required WebSocketClient wsClient}) : _wsClient = wsClient {
    // Register handlers for specific message types
    _registerMessageHandlers();
  }

  void _registerMessageHandlers() {
    // Register handlers for each message type we care about
    _wsClient.registerMessageHandler('message', _handleDirectMessage);
    _wsClient.registerMessageHandler('delivered', _handleDeliveryConfirmation);
    _wsClient.registerMessageHandler('thread_history', _handleThreadHistory);
    _wsClient.registerMessageHandler('thread_message', _handleThreadNotification);
    _wsClient.registerMessageHandler('thread_invitation', _handleThreadInvitation);
  }

  void _handleDirectMessage(Map<String, dynamic> message) {
    if (!_messageController.isClosed) {
      final threadMessage = ThreadMessage(
        from: message['from'],
        message: message['message'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          message['timestamp'] * 1000,
        ),
      );
      _messageController.add(threadMessage);
    }
  }

  void _handleDeliveryConfirmation(Map<String, dynamic> message) {
    if (!_deliveryController.isClosed) {
      final delivery = DeliveryConfirmation(
        to: message['to'],
        message: message['message'],
      );
      _deliveryController.add(delivery);
    }
    print('✅ Message delivered to ${message['to']}');
  }



  void _handleThreadHistory(Map<String, dynamic> message) {
    if (!_threadHistoryController.isClosed) {
      final withUser = message['with'];
      final messagesData = List<Map<String, dynamic>>.from(message['messages'] ?? []);
      final messages = messagesData.map((msgData) {
        return ThreadMessage(
          from: msgData['from'],
          to: msgData['to'],
          message: msgData['message'],
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            msgData['timestamp'] * 1000,
          ),
        );
      }).toList();
      
      final response = ThreadHistoryResponse(
        withUser: withUser,
        messages: messages,
      );
      _threadHistoryController.add(response);
    }
  }

  void _handleThreadNotification(Map<String, dynamic> message) {
    if (!_threadNotificationController.isClosed) {
      final threadNotification = ThreadNotification(
        from: message['from'],
        threadId: message['thread_id'],
        threadTitle: message['thread_title'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          message['timestamp'] * 1000,
        ),
      );
      _threadNotificationController.add(threadNotification);
    }
  }

  void _handleThreadInvitation(Map<String, dynamic> message) {
    if (!_threadInvitationController.isClosed) {
      final threadInvitation = ThreadInvitationNotification(
        fromUserId: message['from_user_id'],
        fromUserName: message['from_user_name'],
        threadId: message['thread_id'],
        threadTitle: message['thread_title'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          message['timestamp'] * 1000,
        ),
      );
      _threadInvitationController.add(threadInvitation);
    }
  }

  // Connect to WebSocket for real-time communication
  Future<bool> connectRealtime(String clientId) async {
    return await _wsClient.connect(clientId);
  }

  // Disconnect WebSocket
  void disconnectRealtime() {
    _wsClient.disconnect();
  }

  // Send a direct message to another user
  Future<bool> sendDirectMessage(String targetId, String message) async {
    final formattedMessage = '$targetId::$message';
    return await _wsClient.sendMessage(formattedMessage);
  }



  // Request thread history with another user
  Future<bool> requestThreadHistory(String withUser) async {
    final request = {
      'type': 'thread_history',
      'with': withUser,
    };
    return await _wsClient.sendMessage(request);
  }

  // Send thread message notification to another user
  Future<bool> sendThreadMessage(String targetUser, String threadId, String threadTitle) async {
    print('📡 Attempting to send thread message to $targetUser');
    print('📡 Connection status: isConnected=${_wsClient.isConnected}');
    
    if (!_wsClient.isConnected) {
      final errorMsg = 'Not connected to server';
      print('📡 ❌ $errorMsg');
      return false;
    }

    try {
      final request = {
        'type': 'thread_message',
        'target_user': targetUser,
        'thread_id': threadId,
        'thread_title': threadTitle,
      };
      
      print('📡 Sending WebSocket message: $request');
      final success = await _wsClient.sendMessage(request);
      if (success) {
        print('📡 ✅ WebSocket message sent successfully to $targetUser');
      } else {
        print('📡 ❌ Failed to send WebSocket message');
      }
      return success;
    } catch (e) {
      final errorMsg = 'Failed to send thread message: $e';
      print('📡 ❌ $errorMsg');
      return false;
    }
  }

  // Dispose method to clean up resources
  void dispose() {
    // Unregister all message handlers
    _wsClient.unregisterAllHandlers('message');
    _wsClient.unregisterAllHandlers('delivered');
    _wsClient.unregisterAllHandlers('thread_history');
    _wsClient.unregisterAllHandlers('thread_message');
    _wsClient.unregisterAllHandlers('thread_invitation');
    
    _wsClient.dispose();
    if (!_messageController.isClosed) {
      _messageController.close();
    }
    if (!_threadHistoryController.isClosed) {
      _threadHistoryController.close();
    }
    if (!_deliveryController.isClosed) {
      _deliveryController.close();
    }
    if (!_threadNotificationController.isClosed) {
      _threadNotificationController.close();
    }
    if (!_threadInvitationController.isClosed) {
      _threadInvitationController.close();
    }
  }

  // Create a new thread
  static Future<String> createThread({
    required String title,
    required List<ThreadUser> users,
    ProjectCheckpoint? initialCheckpoint,
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      final body = <String, dynamic>{
        'title': title,
        'users': users.map((u) => u.toJson()).toList(),
        'metadata': metadata,
      };
      
      if (initialCheckpoint != null) {
        body['initial_checkpoint'] = initialCheckpoint.toJson();
      }

      final response = await ApiHttpClient.post('/threads', body: body);

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
  static Future<void> addCheckpoint(String threadId, ProjectCheckpoint checkpoint) async {
    try {
      final body = <String, dynamic>{
        'checkpoint': checkpoint.toJson(),
      };

      final response = await ApiHttpClient.post('/threads/$threadId/checkpoints', body: body);

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
      final body = {
        'user_id': userId,
        'user_name': userName,
      };

      final response = await ApiHttpClient.post('/threads/$threadId/users', body: body);

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
      };
      
      if (userId != null) {
        queryParams['user_id'] = userId;
      }

      final response = await ApiHttpClient.get('/threads/list', queryParams: queryParams);

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
      final queryParams = {
        'id': threadId,
      };
      
      final response = await ApiHttpClient.get('/threads/thread', queryParams: queryParams);

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
      final updateData = <String, dynamic>{};
      
      if (title != null) updateData['title'] = title;
      if (status != null) updateData['status'] = status.name;
      if (metadata != null) updateData['metadata'] = metadata;

      final response = await ApiHttpClient.put('/threads/$threadId', body: updateData);

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
      final response = await ApiHttpClient.delete('/threads/$threadId');

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
      final response = await ApiHttpClient.get('/threads/stats');

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
      final queryParams = {
        'q': query,
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      
      final response = await ApiHttpClient.get('/threads/search', queryParams: queryParams);

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

  // Send invitation to user for a thread
  static Future<void> sendInvitation(String threadId, String userId, String userName, String invitedBy) async {
    try {
      final body = {
        'user_id': userId,
        'user_name': userName,
        'invited_by': invitedBy,
      };

      final response = await ApiHttpClient.post('/threads/$threadId/invites', body: body);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to send invitation: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error sending invitation: $e');
    }
  }

  // Accept an invitation
  static Future<void> acceptInvitation(String threadId, String userId) async {
    try {
      final body = {
        'action': 'accept',
      };

      final response = await ApiHttpClient.put('/threads/$threadId/invites/$userId', body: body);

      if (response.statusCode != 200) {
        throw Exception('Failed to accept invitation: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error accepting invitation: $e');
    }
  }

  // Decline an invitation
  static Future<void> declineInvitation(String threadId, String userId) async {
    try {
      final body = {
        'action': 'decline',
      };

      final response = await ApiHttpClient.put('/threads/$threadId/invites/$userId', body: body);

      if (response.statusCode != 200) {
        throw Exception('Failed to decline invitation: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error declining invitation: $e');
    }
  }
} 