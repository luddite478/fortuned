import 'package:flutter/material.dart';
import '../services/chat_client.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'chat_conversation_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({Key? key}) : super(key: key);
  
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late ChatClient _chatClient;
  List<String> _onlineUserIds = [];
  bool _isLoading = true;
  String? _error;

  // Music-themed avatars for different users
  final List<String> _avatars = ['🎵', '🥁', '🎧', '🎹', '🎸', '🎛️', '🎤', '🎺', '🎻', '🎷'];
  final List<String> _statuses = ['In Studio', 'Creating beats', 'Mixing tracks', 'Jamming', 'Online', 'Recording'];

  @override
  void initState() {
    super.initState();
    _chatClient = ChatClient();
    _setupChatClient();
  }

  void _setupChatClient() async {
    // Setup listeners
    _chatClient.onlineUsersStream.listen((users) {
      setState(() {
        _onlineUserIds = users;
        _isLoading = false;
        _error = null;
      });
    });

    _chatClient.errorStream.listen((error) {
      setState(() {
        _error = error;
        _isLoading = false;
      });
    });

    _chatClient.connectionStream.listen((connected) {
      if (connected) {
        // Request online users when connected
        _chatClient.requestOnlineUsers();
      }
    });

    // Connect to server
    final clientId = '${dotenv.env['CLIENT_ID_PREFIX'] ?? 'flutter_user'}_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final success = await _chatClient.connect(clientId);
    
    if (!success) {
      setState(() {
        _error = 'Failed to connect to server';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _chatClient.dispose();
    super.dispose();
  }

  List<OnlineUser> get _onlineUsers {
    return _onlineUserIds.map((userId) {
      final avatarIndex = userId.hashCode.abs() % _avatars.length;
      final statusIndex = userId.hashCode.abs() % _statuses.length;
      
      return OnlineUser(
        id: userId,
        username: _formatUsername(userId),
        status: _statuses[statusIndex],
        lastSeen: DateTime.now().subtract(Duration(minutes: (userId.hashCode.abs() % 30) + 1)),
        isOnline: true,
        avatar: _avatars[avatarIndex],
      );
    }).toList();
  }

  String _formatUsername(String userId) {
    // Convert client IDs to more readable usernames
    if (userId.contains('flutter_user')) {
      final suffix = userId.split('_').last;
      return 'User_$suffix';
    }
    return userId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: const Text(
          'CONTACTS',
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
            onPressed: () {
              if (_chatClient.isConnected) {
                _chatClient.requestOnlineUsers();
              }
            },
            tooltip: 'Refresh Users',
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${_onlineUsers.length} ONLINE',
                  style: const TextStyle(
                    color: Colors.green,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
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
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.cyanAccent),
                    SizedBox(height: 16),
                    Text(
                      'Connecting to server...',
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontFamily: 'monospace',
                        fontSize: 16,
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
                          'Connection Error',
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
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _isLoading = true;
                              _error = null;
                            });
                            _setupChatClient();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('RETRY'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Online Users Section
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '🟢 ONLINE USERS (${_onlineUsers.length})',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _onlineUsers.isEmpty
                            ? const Center(
                                child: Text(
                                  'No users online',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontFamily: 'monospace',
                                    fontSize: 16,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: _onlineUsers.length,
                                itemBuilder: (context, index) {
                                  final user = _onlineUsers[index];
                                  return _buildUserCard(user, isOnline: true);
                                },
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildUserCard(OnlineUser user, {required bool isOnline}) {
    final cardColor = isOnline 
        ? const Color(0xFF1f2937) 
        : const Color(0xFF0f1419);
    
    final textColor = isOnline ? Colors.white : Colors.grey.shade600;
    final statusColor = isOnline ? Colors.greenAccent : Colors.grey;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: isOnline 
            ? Border.all(color: Colors.greenAccent.withOpacity(0.3), width: 1)
            : null,
        boxShadow: isOnline 
            ? [
                BoxShadow(
                  color: Colors.greenAccent.withOpacity(0.2),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isOnline ? Colors.greenAccent : Colors.grey.shade700,
          radius: 25,
          child: Text(
            user.avatar,
            style: const TextStyle(fontSize: 20),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                user.username,
                style: TextStyle(
                  color: textColor,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              user.status,
              style: TextStyle(
                color: statusColor,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatLastSeen(user.lastSeen),
              style: TextStyle(
                color: Colors.grey.shade600,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
          ],
        ),
        trailing: isOnline 
            ? IconButton(
                icon: const Icon(Icons.message, color: Colors.cyanAccent),
                onPressed: () => _startChat(user),
                tooltip: 'Start Chat',
              )
            : null,
        onTap: isOnline ? () => _viewUserProfile(user) : null,
      ),
    );
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  void _startChat(OnlineUser user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatConversationScreen(
          otherUserId: user.id,
          otherUserDisplayName: user.username,
          myUserId: _chatClient.clientId ?? 'unknown',
          chatClient: _chatClient,
        ),
      ),
    );
  }

  void _viewUserProfile(OnlineUser user) {
    // TODO: Implement user profile view
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('👤 Viewing ${user.username}\'s profile...'),
        backgroundColor: Colors.greenAccent.withOpacity(0.8),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// Data model for online users
class OnlineUser {
  final String id;
  final String username;
  final String status;
  final DateTime lastSeen;
  final bool isOnline;
  final String avatar;

  OnlineUser({
    required this.id,
    required this.username,
    required this.status,
    required this.lastSeen,
    required this.isOnline,
    required this.avatar,
  });
}

