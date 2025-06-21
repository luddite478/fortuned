import 'package:flutter/foundation.dart';
import 'dart:collection';

// Chat message data model
class ChatMessage {
  final String from;
  final String? to;
  final String message;
  final DateTime timestamp;
  final bool isDelivered;
  final bool isRead;

  const ChatMessage({
    required this.from,
    this.to,
    required this.message,
    required this.timestamp,
    this.isDelivered = false,
    this.isRead = false,
  });

  ChatMessage copyWith({
    String? from,
    String? to,
    String? message,
    DateTime? timestamp,
    bool? isDelivered,
    bool? isRead,
  }) {
    return ChatMessage(
      from: from ?? this.from,
      to: to ?? this.to,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isDelivered: isDelivered ?? this.isDelivered,
      isRead: isRead ?? this.isRead,
    );
  }
}

// Chat conversation data model
class ChatConversation {
  final String conversationId;
  final String userId;
  final String userName;
  final List<ChatMessage> messages;
  final DateTime lastActivity;
  final int unreadCount;
  final bool isOnline;

  const ChatConversation({
    required this.conversationId,
    required this.userId,
    required this.userName,
    this.messages = const [],
    required this.lastActivity,
    this.unreadCount = 0,
    this.isOnline = false,
  });

  ChatConversation copyWith({
    String? conversationId,
    String? userId,
    String? userName,
    List<ChatMessage>? messages,
    DateTime? lastActivity,
    int? unreadCount,
    bool? isOnline,
  }) {
    return ChatConversation(
      conversationId: conversationId ?? this.conversationId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      messages: messages ?? this.messages,
      lastActivity: lastActivity ?? this.lastActivity,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

// Chat state management - Independent ChangeNotifier for all chat functionality
class ChatState extends ChangeNotifier {
  final Map<String, ChatConversation> _conversations = {};
  final Set<String> _onlineUsers = {};
  bool _isConnected = false;
  String? _currentUserId;
  String? _activeConversationId;

  // Getters
  UnmodifiableMapView<String, ChatConversation> get conversations => 
      UnmodifiableMapView(_conversations);
  UnmodifiableSetView<String> get onlineUsers => UnmodifiableSetView(_onlineUsers);
  bool get isConnected => _isConnected;
  String? get currentUserId => _currentUserId;
  String? get activeConversationId => _activeConversationId;
  
  ChatConversation? get activeConversation => 
      _activeConversationId != null ? _conversations[_activeConversationId] : null;
  
  int get totalUnreadCount => 
      _conversations.values.fold(0, (sum, conv) => sum + conv.unreadCount);
  
  List<ChatConversation> get conversationsList => 
      _conversations.values.toList()..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));

  // Connection Management
  void setConnectionStatus(bool isConnected) {
    _isConnected = isConnected;
    notifyListeners();
  }

  void setCurrentUser(String userId) {
    _currentUserId = userId;
    notifyListeners();
  }

  // Online Users Management
  void updateOnlineUsers(List<String> users) {
    _onlineUsers.clear();
    _onlineUsers.addAll(users);
    
    // Update online status for existing conversations
    for (String userId in _conversations.keys) {
      final conversation = _conversations[userId]!;
      _conversations[userId] = conversation.copyWith(
        isOnline: _onlineUsers.contains(userId),
      );
    }
    notifyListeners();
  }

  void setUserOnline(String userId, bool isOnline) {
    if (isOnline) {
      _onlineUsers.add(userId);
    } else {
      _onlineUsers.remove(userId);
    }
    
    // Update conversation if it exists
    if (_conversations.containsKey(userId)) {
      final conversation = _conversations[userId]!;
      _conversations[userId] = conversation.copyWith(isOnline: isOnline);
    }
    notifyListeners();
  }

  // Conversation Management
  void setActiveConversation(String? conversationId) {
    _activeConversationId = conversationId;
    
    // Mark messages as read when opening conversation
    if (conversationId != null && _conversations.containsKey(conversationId)) {
      final conversation = _conversations[conversationId]!;
      if (conversation.unreadCount > 0) {
        _conversations[conversationId] = conversation.copyWith(unreadCount: 0);
      }
    }
    notifyListeners();
  }

  void addMessage(ChatMessage message) {
    final conversationId = message.from == _currentUserId ? message.to! : message.from;
    
    // Get or create conversation
    ChatConversation conversation = _conversations[conversationId] ?? 
        ChatConversation(
          conversationId: conversationId,
          userId: conversationId,
          userName: conversationId, // Use ID as name for now
          messages: const [],
          lastActivity: message.timestamp,
          unreadCount: 0,
          isOnline: _onlineUsers.contains(conversationId),
        );

    // Add message to conversation
    final updatedMessages = List<ChatMessage>.from(conversation.messages)..add(message);
    final isIncoming = message.from != _currentUserId;
    final shouldIncreaseUnread = isIncoming && _activeConversationId != conversationId;
    
    _conversations[conversationId] = conversation.copyWith(
      messages: updatedMessages,
      lastActivity: message.timestamp,
      unreadCount: shouldIncreaseUnread ? conversation.unreadCount + 1 : conversation.unreadCount,
    );
    notifyListeners();
  }

  void addMessages(String conversationId, List<ChatMessage> messages) {
    if (messages.isEmpty) return;
    
    // Get or create conversation
    ChatConversation conversation = _conversations[conversationId] ?? 
        ChatConversation(
          conversationId: conversationId,
          userId: conversationId,
          userName: conversationId,
          messages: const [],
          lastActivity: messages.last.timestamp,
          unreadCount: 0,
          isOnline: _onlineUsers.contains(conversationId),
        );

    // Merge messages (avoid duplicates by timestamp)
    final existingMessages = conversation.messages;
    final newMessages = <ChatMessage>[];
    
    for (final message in messages) {
      final exists = existingMessages.any((m) => 
          m.timestamp == message.timestamp && 
          m.from == message.from && 
          m.message == message.message);
      if (!exists) {
        newMessages.add(message);
      }
    }
    
    if (newMessages.isNotEmpty) {
      final allMessages = List<ChatMessage>.from(existingMessages)..addAll(newMessages);
      allMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      _conversations[conversationId] = conversation.copyWith(
        messages: allMessages,
        lastActivity: allMessages.last.timestamp,
      );
      notifyListeners();
    }
  }

  void markMessageDelivered(String to, String messageText) {
    if (!_conversations.containsKey(to)) return;
    
    final conversation = _conversations[to]!;
    final updatedMessages = conversation.messages.map((message) {
      if (message.to == to && message.message == messageText && !message.isDelivered) {
        return message.copyWith(isDelivered: true);
      }
      return message;
    }).toList();
    
    _conversations[to] = conversation.copyWith(messages: updatedMessages);
    notifyListeners();
  }

  void clearConversation(String conversationId) {
    if (_conversations.containsKey(conversationId)) {
      _conversations[conversationId] = _conversations[conversationId]!.copyWith(
        messages: [],
        unreadCount: 0,
      );
      notifyListeners();
    }
  }

  void removeConversation(String conversationId) {
    if (_conversations.containsKey(conversationId)) {
      _conversations.remove(conversationId);
      if (_activeConversationId == conversationId) {
        _activeConversationId = null;
      }
      notifyListeners();
    }
  }
} 