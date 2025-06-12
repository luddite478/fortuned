import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../state/app_state.dart';

class ChatClient {
  WebSocket? _socket;
  String? _clientId;
  bool _isConnected = false;
  
  // Stream controllers for reactive updates
  final _messageController = StreamController<ChatMessage>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _onlineUsersController = StreamController<List<String>>.broadcast();
  final _chatHistoryController = StreamController<ChatHistoryResponse>.broadcast();
  final _deliveryController = StreamController<DeliveryConfirmation>.broadcast();
  
  // Simple server configuration from environment
  static String get serverUrl {
    final host = dotenv.env['WEBSOCKET_HOST'] ?? 'localhost';
    final port = dotenv.env['WEBSOCKET_PORT'] ?? '8765';
    return 'ws://$host:$port';
  }
  
  static String get authToken => dotenv.env['WEBSOCKET_TOKEN'] ?? 'secure_chat_token_9999';
  static String get clientIdPrefix => dotenv.env['CLIENT_ID_PREFIX'] ?? 'flutter_user';
  
  // Getters for streams (for listening in UI)
  Stream<ChatMessage> get messageStream => _messageController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<List<String>> get onlineUsersStream => _onlineUsersController.stream;
  Stream<ChatHistoryResponse> get chatHistoryStream => _chatHistoryController.stream;
  Stream<DeliveryConfirmation> get deliveryStream => _deliveryController.stream;
  bool get isConnected => _isConnected;
  String? get clientId => _clientId;
  
  Future<bool> connect(String clientId) async {
    try {
      _clientId = clientId;
      print('🔗 Connecting to $serverUrl as $clientId...');
      
      // Connect to WebSocket
      _socket = await WebSocket.connect(serverUrl);
      
      // Send authentication message
      final authMessage = jsonEncode({
        'token': authToken,
        'client_id': clientId,
      });
      
      _socket!.add(authMessage);
      print('🔐 Sent authentication...');
      
      // Listen for messages
      _socket!.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );
      
      return true;
      
    } catch (e) {
      _errorController.add('Connection failed: $e');
      return false;
    }
  }
  
  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data as String);
      final type = message['type'];
      
      switch (type) {
        case 'connected':
          _isConnected = true;
          if (!_connectionController.isClosed) {
            _connectionController.add(true);
          }
          print('✅ ${message['message']}');
          break;
          
        case 'message':
          if (!_messageController.isClosed) {
            final chatMessage = ChatMessage(
              from: message['from'],
              message: message['message'],
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                message['timestamp'] * 1000,
              ),
            );
            _messageController.add(chatMessage);
          }
          break;
          
        case 'delivered':
          if (!_deliveryController.isClosed) {
            final delivery = DeliveryConfirmation(
              to: message['to'],
              message: message['message'],
            );
            _deliveryController.add(delivery);
          }
          print('✅ Message delivered to ${message['to']}');
          break;
          
        case 'error':
          if (!_errorController.isClosed) {
            _errorController.add(message['message']);
          }
          break;
          
        case 'online_users':
          if (!_onlineUsersController.isClosed) {
            final users = List<String>.from(message['users'] ?? []);
            _onlineUsersController.add(users);
          }
          break;
          
        case 'chat_history':
          if (!_chatHistoryController.isClosed) {
            final withUser = message['with'];
            final messagesData = List<Map<String, dynamic>>.from(message['messages'] ?? []);
            final messages = messagesData.map((msgData) {
              return ChatMessage(
                from: msgData['from'],
                to: msgData['to'],
                message: msgData['message'],
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                  msgData['timestamp'] * 1000,
                ),
              );
            }).toList();
            
            final response = ChatHistoryResponse(
              withUser: withUser,
              messages: messages,
            );
            _chatHistoryController.add(response);
          }
          break;
          
        default:
          print('📩 Unknown message: $data');
      }
    } catch (e) {
      print('📩 Raw message: $data');
    }
  }
  
  void _handleError(error) {
    _isConnected = false;
    if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
    if (!_errorController.isClosed) {
      _errorController.add('WebSocket error: $error');
    }
  }
  
  void _handleDisconnect() {
    _isConnected = false;
    if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
    print('🔌 Disconnected from server');
  }
  
  Future<bool> sendMessage(String targetId, String message) async {
    if (!_isConnected || _socket == null) {
      if (!_errorController.isClosed) {
        _errorController.add('Not connected to server');
      }
      return false;
    }
    
    try {
      final formattedMessage = '$targetId::$message';
      _socket!.add(formattedMessage);
      return true;
    } catch (e) {
      if (!_errorController.isClosed) {
        _errorController.add('Failed to send message: $e');
      }
      return false;
    }
  }

  Future<bool> requestOnlineUsers() async {
    if (!_isConnected || _socket == null) {
      if (!_errorController.isClosed) {
        _errorController.add('Not connected to server');
      }
      return false;
    }

    try {
      final request = jsonEncode({
        'type': 'list_users',
      });
      _socket!.add(request);
      return true;
    } catch (e) {
      if (!_errorController.isClosed) {
        _errorController.add('Failed to request online users: $e');
      }
      return false;
    }
  }

  Future<bool> requestChatHistory(String withUser) async {
    if (!_isConnected || _socket == null) {
      if (!_errorController.isClosed) {
        _errorController.add('Not connected to server');
      }
      return false;
    }

    try {
      final request = jsonEncode({
        'type': 'chat_history',
        'with': withUser,
      });
      _socket!.add(request);
      return true;
    } catch (e) {
      if (!_errorController.isClosed) {
        _errorController.add('Failed to request chat history: $e');
      }
      return false;
    }
  }
  
  void disconnect() {
    _socket?.close();
    _isConnected = false;
    if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
  }
  
  // Clean up streams when disposing
  void dispose() {
    disconnect();
    if (!_messageController.isClosed) {
      _messageController.close();
    }
    if (!_connectionController.isClosed) {
      _connectionController.close();
    }
    if (!_errorController.isClosed) {
      _errorController.close();
    }
    if (!_onlineUsersController.isClosed) {
      _onlineUsersController.close();
    }
    if (!_chatHistoryController.isClosed) {
      _chatHistoryController.close();
    }
    if (!_deliveryController.isClosed) {
      _deliveryController.close();
    }
  }
}

// Data model for chat history response
class ChatHistoryResponse {
  final String withUser;
  final List<ChatMessage> messages;
  
  ChatHistoryResponse({
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