import 'dart:io';
import 'dart:convert';
import 'dart:async';

class ChatClient {
  WebSocket? _socket;
  String? _clientId;
  bool _isConnected = false;
  
  // Stream controllers for reactive updates
  final _messageController = StreamController<ChatMessage>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  
  // Server configuration
  static const String serverUrl = 'ws://localhost:8765'; // Change for production
  static const String authToken = 'secure_chat_token_9999';
  
  // Getters for streams (for listening in UI)
  Stream<ChatMessage> get messageStream => _messageController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get errorStream => _errorController.stream;
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
          _connectionController.add(true);
          print('✅ ${message['message']}');
          break;
          
        case 'message':
          final chatMessage = ChatMessage(
            from: message['from'],
            message: message['message'],
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              message['timestamp'] * 1000,
            ),
          );
          _messageController.add(chatMessage);
          break;
          
        case 'delivered':
          // You could emit a delivery confirmation event here if needed
          print('✅ Message delivered to ${message['to']}');
          break;
          
        case 'error':
          _errorController.add(message['message']);
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
    _connectionController.add(false);
    _errorController.add('WebSocket error: $error');
  }
  
  void _handleDisconnect() {
    _isConnected = false;
    _connectionController.add(false);
    print('🔌 Disconnected from server');
  }
  
  Future<bool> sendMessage(String targetId, String message) async {
    if (!_isConnected || _socket == null) {
      _errorController.add('Not connected to server');
      return false;
    }
    
    try {
      final formattedMessage = '$targetId::$message';
      _socket!.add(formattedMessage);
      return true;
    } catch (e) {
      _errorController.add('Failed to send message: $e');
      return false;
    }
  }
  
  void disconnect() {
    _socket?.close();
    _isConnected = false;
    _connectionController.add(false);
  }
  
  // Clean up streams when disposing
  void dispose() {
    disconnect();
    _messageController.close();
    _connectionController.close();
    _errorController.close();
  }
}

// Data model for chat messages
class ChatMessage {
  final String from;
  final String message;
  final DateTime timestamp;
  
  ChatMessage({
    required this.from,
    required this.message,
    required this.timestamp,
  });
  
  @override
  String toString() => '$from: $message (${timestamp.toLocal()})';
} 