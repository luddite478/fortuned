import 'package:flutter/foundation.dart';
import 'dart:collection';

// Models for Sample Slots
class SampleSlot {
  final int index;
  final String? filePath;
  final String? fileName;
  final bool isLoaded;
  final bool isPlaying;
  final int memoryUsage; // in bytes
  final DateTime? loadedAt;

  const SampleSlot({
    required this.index,
    this.filePath,
    this.fileName,
    this.isLoaded = false,
    this.isPlaying = false,
    this.memoryUsage = 0,
    this.loadedAt,
  });

  SampleSlot copyWith({
    int? index,
    String? filePath,
    String? fileName,
    bool? isLoaded,
    bool? isPlaying,
    int? memoryUsage,
    DateTime? loadedAt,
  }) {
    return SampleSlot(
      index: index ?? this.index,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      isLoaded: isLoaded ?? this.isLoaded,
      isPlaying: isPlaying ?? this.isPlaying,
      memoryUsage: memoryUsage ?? this.memoryUsage,
      loadedAt: loadedAt ?? this.loadedAt,
    );
  }

  bool get isEmpty => filePath == null;
  bool get hasFile => filePath != null;
}

// Models for Chat System
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

class ChatConversation {
  final String contactId;
  final String contactName;
  final List<ChatMessage> messages;
  final DateTime lastActivity;
  final int unreadCount;
  final bool isOnline;

  const ChatConversation({
    required this.contactId,
    required this.contactName,
    this.messages = const [],
    required this.lastActivity,
    this.unreadCount = 0,
    this.isOnline = false,
  });

  ChatConversation copyWith({
    String? contactId,
    String? contactName,
    List<ChatMessage>? messages,
    DateTime? lastActivity,
    int? unreadCount,
    bool? isOnline,
  }) {
    return ChatConversation(
      contactId: contactId ?? this.contactId,
      contactName: contactName ?? this.contactName,
      messages: messages ?? this.messages,
      lastActivity: lastActivity ?? this.lastActivity,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

// Main State Management Classes
class SampleSlotsState extends ChangeNotifier {
  static const int maxSlots = 8;
  
  final Map<int, SampleSlot> _slots = {};
  int _selectedSlotIndex = 0;
  int _activeBank = 0;

  // Initialize with empty slots
  SampleSlotsState() {
    for (int i = 0; i < maxSlots; i++) {
      _slots[i] = SampleSlot(index: i);
    }
  }

  // Getters
  UnmodifiableMapView<int, SampleSlot> get slots => UnmodifiableMapView(_slots);
  SampleSlot getSlot(int index) => _slots[index] ?? SampleSlot(index: index);
  int get selectedSlotIndex => _selectedSlotIndex;
  int get activeBank => _activeBank;
  
  List<SampleSlot> get loadedSlots => _slots.values.where((slot) => slot.isLoaded).toList();
  List<SampleSlot> get playingSlots => _slots.values.where((slot) => slot.isPlaying).toList();
  int get totalMemoryUsage => _slots.values.fold(0, (sum, slot) => sum + slot.memoryUsage);
  int get loadedSlotsCount => _slots.values.where((slot) => slot.isLoaded).length;

  // Sample Slot Operations
  void loadSample(int slotIndex, String filePath, String fileName) {
    if (slotIndex < 0 || slotIndex >= maxSlots) return;
    
    _slots[slotIndex] = _slots[slotIndex]!.copyWith(
      filePath: filePath,
      fileName: fileName,
      isLoaded: false, // Will be set to true when actually loaded by miniaudio
      loadedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void updateSlotLoadStatus(int slotIndex, bool isLoaded, {int? memoryUsage}) {
    if (slotIndex < 0 || slotIndex >= maxSlots) return;
    
    _slots[slotIndex] = _slots[slotIndex]!.copyWith(
      isLoaded: isLoaded,
      memoryUsage: memoryUsage ?? _slots[slotIndex]!.memoryUsage,
    );
    notifyListeners();
  }

  void updateSlotPlayStatus(int slotIndex, bool isPlaying) {
    if (slotIndex < 0 || slotIndex >= maxSlots) return;
    
    _slots[slotIndex] = _slots[slotIndex]!.copyWith(isPlaying: isPlaying);
    notifyListeners();
  }

  void clearSlot(int slotIndex) {
    if (slotIndex < 0 || slotIndex >= maxSlots) return;
    
    _slots[slotIndex] = SampleSlot(index: slotIndex);
    notifyListeners();
  }

  void stopAllSlots() {
    for (int i = 0; i < maxSlots; i++) {
      if (_slots[i]!.isPlaying) {
        _slots[i] = _slots[i]!.copyWith(isPlaying: false);
      }
    }
    notifyListeners();
  }

  void setSelectedSlot(int slotIndex) {
    if (slotIndex < 0 || slotIndex >= maxSlots) return;
    
    _selectedSlotIndex = slotIndex;
    _activeBank = slotIndex; // Keep in sync for now
    notifyListeners();
  }

  void setActiveBank(int bankIndex) {
    if (bankIndex < 0 || bankIndex >= maxSlots) return;
    
    _activeBank = bankIndex;
    notifyListeners();
  }

  // Memory management helpers
  String formatMemorySize(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }
}

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
          contactId: conversationId,
          contactName: conversationId, // Use ID as name for now
          lastActivity: message.timestamp,
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
          contactId: conversationId,
          contactName: conversationId,
          lastActivity: messages.last.timestamp,
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

// Combined App State
class AppState extends ChangeNotifier {
  final SampleSlotsState _sampleSlots = SampleSlotsState();
  final ChatState _chat = ChatState();

  // Getters
  SampleSlotsState get sampleSlots => _sampleSlots;
  ChatState get chat => _chat;

  AppState() {
    // Listen to changes in child states and bubble them up
    _sampleSlots.addListener(notifyListeners);
    _chat.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _sampleSlots.removeListener(notifyListeners);
    _chat.removeListener(notifyListeners);
    _sampleSlots.dispose();
    _chat.dispose();
    super.dispose();
  }
} 