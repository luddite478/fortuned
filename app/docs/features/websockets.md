# WebSocket Messaging System

Real-time messaging architecture for Fortuned using centralized message routing.

## Architecture

**Single WebSocketClient** routes messages to services based on message type:

```
UI Screens → Services → WebSocketClient → Server
  ↓           ↓           ↓
UsersScreen   UsersService    • Message Routing
ContactsScreen ThreadsService • Handler Registration  
ThreadScreen  NotificationSvc • Connection Management
```

## Core Components

### WebSocketClient (`lib/services/ws_client.dart`)
Central client managing connections and routing messages to registered handlers.

**Key Methods:**
```dart
void registerMessageHandler(String messageType, Function handler)
Future<bool> sendMessage(dynamic message)
Future<bool> connect(String clientId)
```

### Services
Services register handlers for specific message types:

**UsersService** - Online users, authentication, profiles
**ThreadsService** - Direct messages, threads, delivery confirmations

## Message Types

### Current Types

| Type | Purpose | Service |
|------|---------|---------|
| `online_users` | List of online users | UsersService |
| `message` | Direct user messages | ThreadsService |
| `delivered` | Message delivery confirmation | ThreadsService |
| `thread_history` | Historical thread messages | ThreadsService |
| `thread_message` | Thread sharing notification | ThreadsService |
| `connected` | Connection confirmation | System |

### Message Examples

**Online Users:**
```json
// Server → Client
{"type": "online_users", "users": ["user1", "user2"], "timestamp": 1674123456}

// Client → Server  
{"type": "list_users"}
```

**Direct Message:**
```json
// Server → Client
{"type": "message", "from": "user1", "message": "Hello!", "timestamp": 1674123456}

// Client → Server
"user2::Hello!"
```

## Adding New Message Types

### 1. Create Handler
```dart
void _handleNewMessageType(Map<String, dynamic> message) {
  // Process message
  _controller.add(processedData);
}
```

### 2. Register Handler
```dart
// In service constructor
_wsClient.registerMessageHandler('new_message_type', _handleNewMessageType);
```

### 3. Create Stream (if needed)
```dart
final _controller = StreamController<DataType>.broadcast();
Stream<DataType> get dataStream => _controller.stream;
```

### 4. Use in UI
```dart
final service = Provider.of<ServiceName>(context, listen: false);
service.dataStream.listen((data) => updateUI(data));
```

## Service Integration

### Provider Setup
```dart
MultiProvider(
  providers: [
    Provider(create: (context) => WebSocketClient()),
    Provider(create: (context) => ThreadsService(
      wsClient: Provider.of<WebSocketClient>(context, listen: false))),
    Provider(create: (context) => UsersService(
      wsClient: Provider.of<WebSocketClient>(context, listen: false))),
  ],
)
```

### Service Example
```dart
class UsersService {
  final WebSocketClient _wsClient;
  final _onlineUsersController = StreamController<List<String>>.broadcast();
  
  UsersService({required WebSocketClient wsClient}) : _wsClient = wsClient {
    _wsClient.registerMessageHandler('online_users', _handleOnlineUsers);
  }

  void _handleOnlineUsers(Map<String, dynamic> message) {
    final users = List<String>.from(message['users'] ?? []);
    _onlineUsersController.add(users);
  }

  Stream<List<String>> get onlineUsersStream => _onlineUsersController.stream;
}
```

## Connection Flow

1. **App Startup** - WebSocketClient created but not connected
2. **User Login** - `connectRealtime(userId)` called after authentication  
3. **Handler Registration** - Services register handlers on creation
4. **Message Routing** - Incoming messages routed to appropriate handlers
5. **User Logout** - Connection closed, services disposed

## Best Practices

### Message Types
- Use lowercase with underscores: `user_typing`, `system_alert`
- Be descriptive and domain-specific

### Handlers
- Always check if controllers are closed before adding events
- Handle malformed messages gracefully
- Use try-catch for complex parsing

### Services
- Group related message types in same service
- Unregister handlers in dispose methods
- Use broadcast streams for multiple listeners

## Error Handling

- **Handler Errors**: Isolated - one failing handler doesn't affect others
- **Connection Errors**: Propagated to service error streams  
- **Malformed Messages**: Logged but don't crash app

## Security

- Validate message structure before processing
- Verify WebSocket connection is authenticated
- Check user permissions for sensitive operations

## Troubleshooting

**Messages not received?**
- Check handler registration
- Verify WebSocket connection
- Check message type spelling (case-sensitive)

**Handler not called?**  
- Verify service instantiation
- Check handler registration timing
- Enable message logging for debugging

**Debug logging:**
```dart
_wsClient.messageStream.listen((msg) => print('📩 $msg'));
```

## Future Extensions

**Planned message types:**
- `user_typing` - Typing indicators
- `user_status` - Status updates (online/away/busy)  
- `system_notification` - Server announcements
- `friend_request` - Social features

**Improvements:**
- Message queuing when disconnected
- Automatic reconnection with backoff
- Message compression for large payloads 