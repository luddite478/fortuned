import 'package:flutter/material.dart';
import '../services/chat_client.dart';

class ChatConversationScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUserDisplayName;
  final String myUserId;
  final ChatClient chatClient;
  
  const ChatConversationScreen({
    Key? key,
    required this.otherUserId,
    required this.otherUserDisplayName,
    required this.myUserId,
    required this.chatClient,
  }) : super(key: key);
  
  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setupChatListeners();
    _loadChatHistory();
  }

  void _setupChatListeners() {
    // Listen for new messages
    widget.chatClient.messageStream.listen((message) {
      if (message.from == widget.otherUserId || message.to == widget.otherUserId) {
        setState(() {
          _messages.add(message);
        });
        _scrollToBottom();
      }
    });

    // Listen for chat history
    widget.chatClient.chatHistoryStream.listen((historyResponse) {
      if (historyResponse.withUser == widget.otherUserId) {
        setState(() {
          _messages = historyResponse.messages;
          _isLoading = false;
          _error = null;
        });
        _scrollToBottom();
      }
    });

    // Listen for delivery confirmations
    widget.chatClient.deliveryStream.listen((delivery) {
      if (delivery.to == widget.otherUserId) {
        // Could show delivery status in UI
        print('✅ Message delivered to ${widget.otherUserId}');
      }
    });

    // Listen for errors
    widget.chatClient.errorStream.listen((error) {
      setState(() {
        _error = error;
        _isLoading = false;
      });
    });
  }

  void _loadChatHistory() async {
    final success = await widget.chatClient.requestChatHistory(widget.otherUserId);
    if (!success) {
      setState(() {
        _error = 'Failed to load chat history';
        _isLoading = false;
      });
    }
  }

  void _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    // Add message to local list immediately (optimistic update)
    final chatMessage = ChatMessage(
      from: widget.myUserId,
      to: widget.otherUserId,
      message: message,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(chatMessage);
    });
    _messageController.clear();
    _scrollToBottom();

    // Send message to server
    final success = await widget.chatClient.sendMessage(widget.otherUserId, message);
    if (!success) {
      // Could show error state or retry mechanism
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send message'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.cyanAccent,
              radius: 18,
              child: Text(
                widget.otherUserDisplayName.isNotEmpty 
                    ? widget.otherUserDisplayName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUserDisplayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.otherUserId,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
            onPressed: _loadChatHistory,
            tooltip: 'Refresh Chat',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              Colors.grey.shade900,
            ],
          ),
        ),
        child: Column(
          children: [
            // Messages area
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.cyanAccent),
                          SizedBox(height: 16),
                          Text(
                            'Loading chat history...',
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.redAccent,
                                size: 64,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Error',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontFamily: 'monospace',
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontFamily: 'monospace',
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isMyMessage = message.from == widget.myUserId;
                            return _buildMessageBubble(message, isMyMessage);
                          },
                        ),
            ),
            
            // Message input area
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                border: Border(
                  top: BorderSide(
                    color: Colors.grey.shade800,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: const TextStyle(
                          color: Colors.grey,
                          fontFamily: 'monospace',
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade900,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                      maxLines: null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    backgroundColor: Colors.cyanAccent,
                    radius: 24,
                    child: IconButton(
                      icon: const Icon(
                        Icons.send,
                        color: Colors.black,
                      ),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMyMessage) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMyMessage
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isMyMessage) ...[
            CircleAvatar(
              backgroundColor: Colors.greenAccent,
              radius: 16,
              child: Text(
                message.from.isNotEmpty ? message.from[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: isMyMessage
                    ? Colors.cyanAccent
                    : const Color(0xFF1f2937),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.message,
                    style: TextStyle(
                      color: isMyMessage ? Colors.black : Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      color: isMyMessage 
                          ? Colors.black54 
                          : Colors.grey.shade400,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMyMessage) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.cyanAccent,
              radius: 16,
              child: Text(
                widget.myUserId.isNotEmpty ? widget.myUserId[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    if (messageDate == today) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.day}/${timestamp.month} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
}