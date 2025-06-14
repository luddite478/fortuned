import 'dart:io';
import 'dart:convert';

class ChatClient {
  WebSocket? _socket;
  String? _clientId;
  bool _isConnected = false;
  
  // Server configuration
  static const String serverUrl = 'ws://localhost:8765';
  static const String authToken = 'secure_chat_token_9999';
  
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
      print('❌ Connection failed: $e');
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
          print('✅ ${message['message']}');
          print('👥 Active clients: ${message['active_clients']}');
          break;
          
        case 'message':
          final from = message['from'];
          final msg = message['message'];
          final timestamp = message['timestamp'];
          print('📨 Message from $from: $msg');
          break;
          
        case 'delivered':
          final to = message['to'];
          print('✅ Message delivered to $to');
          break;
          
        case 'error':
          print('❌ Server error: ${message['message']}');
          break;
          
        default:
          print('📩 Unknown message: $data');
      }
    } catch (e) {
      print('📩 Raw message: $data');
    }
  }
  
  void _handleError(error) {
    print('❌ WebSocket error: $error');
    _isConnected = false;
  }
  
  void _handleDisconnect() {
    print('🔌 Disconnected from server');
    _isConnected = false;
  }
  
  Future<bool> sendMessage(String targetId, String message) async {
    if (!_isConnected || _socket == null) {
      print('❌ Not connected to server');
      return false;
    }
    
    try {
      final formattedMessage = '$targetId::$message';
      _socket!.add(formattedMessage);
      print('📤 Sent: $formattedMessage');
      return true;
    } catch (e) {
      print('❌ Failed to send message: $e');
      return false;
    }
  }
  
  void disconnect() {
    _socket?.close();
    _isConnected = false;
    print('👋 Disconnected');
  }
  
  bool get isConnected => _isConnected;
}

// Example usage
void main() async {
  final client = ChatClient();
  
  // Connect to server
  final connected = await client.connect('dart_client_123');
  
  if (connected) {
    // Wait a bit for connection confirmation
    await Future.delayed(Duration(milliseconds: 500));
    
    // Send some test messages
    await client.sendMessage('alice', 'Hello Alice from Dart!');
    await client.sendMessage('bob', 'Hey Bob, how are you?');
    
    // Keep connection alive for a while to receive messages
    print('\n💬 Listening for messages... (Press Ctrl+C to exit)');
    
    // In a real app, you'd handle this differently
    // This is just for demo purposes
    await Future.delayed(Duration(seconds: 30));
    
    client.disconnect();
  }
} 