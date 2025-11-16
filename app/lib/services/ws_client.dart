import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/log.dart';

class WebSocketClient {
  WebSocket? _socket;
  String? _clientId;
  bool _isConnected = false;
  
  // Stream controllers for low-level WebSocket events
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  
  // Message routing system
  final Map<String, List<Function(Map<String, dynamic>)>> _messageHandlers = {};
  
  // Simple server configuration from environment
  static String get serverUrl {
    final host = dotenv.env['WEBSOCKET_HOST'] ?? '';
    final port = dotenv.env['WEBSOCKET_PORT'] ?? '8765';
    // Use wss for 443 or when explicitly configured; otherwise ws
    final isSecure = (dotenv.env['WEBSOCKET_SECURE'] ?? '').toLowerCase() == 'true' || port == '443';
    final protocol = isSecure ? 'wss' : 'ws';
    final portSuffix = port == '443' ? '' : ':$port';
    return '$protocol://$host$portSuffix';
  }
  
  static String get authToken => dotenv.env['API_TOKEN'] ?? '';
  static String get clientIdPrefix => dotenv.env['CLIENT_ID_PREFIX'] ?? 'flutter_user';
  
  // Getters for streams (for listening in higher-level services)
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get errorStream => _errorController.stream;
  bool get isConnected => _isConnected;
  String? get clientId => _clientId;

  // Register a handler for a specific message type
  void registerMessageHandler(String messageType, Function(Map<String, dynamic>) handler) {
    _messageHandlers.putIfAbsent(messageType, () => []).add(handler);
    Log.d('Registered handler for message type: $messageType', 'WS');
  }

  // Unregister a specific handler for a message type
  void unregisterMessageHandler(String messageType, Function(Map<String, dynamic>) handler) {
    _messageHandlers[messageType]?.remove(handler);
    if (_messageHandlers[messageType]?.isEmpty == true) {
      _messageHandlers.remove(messageType);
    }
    Log.d('Unregistered handler for message type: $messageType', 'WS');
  }

  // Unregister all handlers for a message type
  void unregisterAllHandlers(String messageType) {
    _messageHandlers.remove(messageType);
    Log.d('Unregistered all handlers for message type: $messageType', 'WS');
  }
  
  Future<bool> connect(String clientId) async {
    try {
      _clientId = clientId;
      Log.d('Connecting to $serverUrl as $clientId...', 'WS');
      
      // Connect to WebSocket
      _socket = await WebSocket.connect(serverUrl);
      
      // Send authentication message
      final authMessage = jsonEncode({
        'token': authToken,
        'client_id': clientId,
      });
      
      _socket!.add(authMessage);
      Log.d('Sent authentication', 'WS');
      
      // Listen for messages
      _socket!.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );
      
      // Ensure we surface server error messages
      registerMessageHandler('error', (msg) {
        final m = msg['message'] ?? 'unknown error';
        if (!_errorController.isClosed) {
          _errorController.add('Server error: $m');
        }
      });
      
      // Wait for server confirmation (with timeout)
      try {
        await _connectionController.stream.firstWhere(
          (connected) => connected == true,
          orElse: () => false,
        ).timeout(const Duration(seconds: 10));
        
        Log.i('WebSocket connection fully established and authenticated', 'WS');
        return true;
      } catch (e) {
        Log.w('Connection timeout or failed to get confirmation: $e', 'WS');
        // Still return true if socket is connected, just log the issue
        return _socket != null;
      }
      
    } catch (e) {
      _errorController.add('Connection failed: $e');
      return false;
    }
  }

  // No normalization: caller must provide 24-hex clientId.
  
  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data as String);
      final type = message['type'];
      
      // Handle connection confirmation at WebSocket level
      if (type == 'connected') {
        _isConnected = true;
        if (!_connectionController.isClosed) {
          _connectionController.add(true);
        }
        Log.i('${message['message']}', 'WS');
        return;
      }
      
      // Route message to registered handlers
      final handlers = _messageHandlers[type];
      if (handlers != null && handlers.isNotEmpty) {
        Log.d('Routing message type "$type" to ${handlers.length} handler(s)', 'WS');
        for (final handler in handlers) {
          try {
            handler(message);
          } catch (e) {
            Log.e('Error in handler for message type "$type"', 'WS', e);
          }
        }
      } else {
        Log.d('No handlers registered for message type: $type', 'WS');
      }
      
      // Also forward to generic message stream for backward compatibility
      if (!_messageController.isClosed) {
        _messageController.add(message);
      }
    } catch (e) {
      Log.d('Raw message (parse error): $data', 'WS');
      Log.d('Parse error: $e', 'WS');
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
  
  // Send raw message (JSON or string)
  Future<bool> sendMessage(dynamic message) async {
    if (!_isConnected || _socket == null) {
      if (!_errorController.isClosed) {
        _errorController.add('Not connected to server');
      }
      return false;
    }
    
    try {
      if (message is Map<String, dynamic>) {
        _socket!.add(jsonEncode(message));
      } else {
        _socket!.add(message.toString());
      }
      return true;
    } catch (e) {
      if (!_errorController.isClosed) {
        _errorController.add('Failed to send message: $e');
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
  }
} 