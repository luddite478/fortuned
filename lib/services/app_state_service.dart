import 'package:flutter/foundation.dart';
import '../state/app_state.dart';
import '../services/chat_client.dart';

class AppStateService {
  final AppState _appState;
  final ChatClient _chatClient;

  AppStateService({
    required AppState appState,
    required ChatClient chatClient,
  }) : _appState = appState,
       _chatClient = chatClient {
    _initializeChatListeners();
  }

  // Getters for easy access
  AppState get appState => _appState;
  ChatClient get chatClient => _chatClient;

  // Sample Slots Bridge Methods
  void loadSample(int slotIndex, String filePath, String fileName) {
    _appState.sampleSlots.loadSample(slotIndex, filePath, fileName);
  }

  void updateSlotLoadStatus(int slotIndex, bool isLoaded, {int? memoryUsage}) {
    _appState.sampleSlots.updateSlotLoadStatus(slotIndex, isLoaded, memoryUsage: memoryUsage);
  }

  void updateSlotPlayStatus(int slotIndex, bool isPlaying) {
    _appState.sampleSlots.updateSlotPlayStatus(slotIndex, isPlaying);
  }

  void stopAllSlots() {
    _appState.sampleSlots.stopAllSlots();
  }

  void setSelectedSlot(int slotIndex) {
    _appState.sampleSlots.setSelectedSlot(slotIndex);
  }

  void setActiveBank(int bankIndex) {
    _appState.sampleSlots.setActiveBank(bankIndex);
  }

  SampleSlot getSampleSlot(int index) {
    return _appState.sampleSlots.getSlot(index);
  }

  // Chat Bridge Methods
  void _initializeChatListeners() {
    _chatClient.connectionStream.listen((isConnected) {
      _appState.chat.setConnectionStatus(isConnected);
    });

    _chatClient.messageStream.listen((message) {
      _appState.chat.addMessage(message);
    });

    _chatClient.onlineUsersStream.listen((users) {
      _appState.chat.updateOnlineUsers(users);
    });

    _chatClient.chatHistoryStream.listen((historyResponse) {
      _appState.chat.addMessages(historyResponse.withUser, historyResponse.messages);
    });

    _chatClient.deliveryStream.listen((delivery) {
      _appState.chat.markMessageDelivered(delivery.to, delivery.message);
    });
  }

  Future<bool> connectChat(String userId) async {
    final connected = await _chatClient.connect(userId);
    if (connected) {
      _appState.chat.setCurrentUser(userId);
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
    _appState.chat.setActiveConversation(conversationId);
  }

  void dispose() {
    _chatClient.dispose();
  }
} 