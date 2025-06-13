import 'package:flutter/foundation.dart';
import '../models/app_state.dart';
import 'chat_client.dart';

class AppStateService {
  final EditorState _editorState;
  final ChatsState _chatsState;
  final ChatClient _chatClient;

  AppStateService({
    required EditorState editorState,
    required ChatsState chatsState,
    required ChatClient chatClient,
  }) : _editorState = editorState,
       _chatsState = chatsState,
       _chatClient = chatClient {
    _initializeChatListeners();
  }

  // Getters for easy access
  EditorState get editorState => _editorState;
  ChatsState get chatsState => _chatsState;
  ChatClient get chatClient => _chatClient;

  // Sample Slots Bridge Methods - Direct access to editor
  void loadSample(int slotIndex, String filePath, String fileName) {
    _editorState.loadSample(slotIndex, filePath, fileName);
  }

  void updateSlotLoadStatus(int slotIndex, bool isLoaded, {int? memoryUsage}) {
    _editorState.updateSlotLoadStatus(slotIndex, isLoaded, memoryUsage: memoryUsage);
  }

  void updateSlotPlayStatus(int slotIndex, bool isPlaying) {
    _editorState.updateSlotPlayStatus(slotIndex, isPlaying);
  }

  void stopAllSlots() {
    _editorState.stopAllSlots();
  }

  void setSelectedSlot(int slotIndex) {
    _editorState.setSelectedSlot(slotIndex);
  }

  void setActiveBank(int bankIndex) {
    _editorState.setActiveBank(bankIndex);
  }

  SampleSlot getSampleSlot(int index) {
    return _editorState.getSlot(index);
  }

  // Chat Bridge Methods - Direct access to chats
  void _initializeChatListeners() {
    _chatClient.connectionStream.listen((isConnected) {
      _chatsState.setConnectionStatus(isConnected);
    });

    _chatClient.messageStream.listen((ChatMessage message) {
      _chatsState.addMessage(message);
    });

    _chatClient.onlineUsersStream.listen((users) {
      _chatsState.updateOnlineUsers(users);
    });

    _chatClient.chatHistoryStream.listen((historyResponse) {
      _chatsState.addMessages(historyResponse.withUser, historyResponse.messages);
    });

    _chatClient.deliveryStream.listen((delivery) {
      _chatsState.markMessageDelivered(delivery.to, delivery.message);
    });
  }

  Future<bool> connectChat(String userId) async {
    final connected = await _chatClient.connect(userId);
    if (connected) {
      _chatsState.setCurrentUser(userId);
    }
    return connected;
  }

  Future<bool> sendMessage(String targetId, String message) {
    return _chatClient.sendMessage(targetId, message);
  }

  Future<bool> requestOnlineUsers() {
    return _chatClient.requestOnlineUsers();
  }

  Future<bool> requestChatHistory(String withUser) {
    return _chatClient.requestChatHistory(withUser);
  }

  void setActiveConversation(String? conversationId) {
    _chatsState.setActiveConversation(conversationId);
  }

  void dispose() {
    _chatClient.dispose();
  }
} 