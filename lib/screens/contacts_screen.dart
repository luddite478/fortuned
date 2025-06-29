import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_client.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'thread_screen.dart';
import 'user_profile_screen.dart';
import 'sequencer_screen.dart';
import '../state/threads_state.dart';
import '../state/sequencer_state.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({Key? key}) : super(key: key);
  
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> with TickerProviderStateMixin {
  late ChatClient _chatClient;
  List<String> _onlineUserIds = [];
  bool _isLoading = true;
  String? _error;
  
  // Track users with unread thread messages
  Set<String> _usersWithNotifications = {};

  // Animation controllers
  late AnimationController _lampAnimation;

  // Contact names - removed avatars since we'll use play buttons
  final List<String> _names = [
    'Alex Beat', 'Maya Synth', 'Jordan Mix', 'Sam Drums', 'Riley Bass',
    'Casey Keys', 'Morgan Vocal', 'Taylor Horn', 'Quinn Strings', 'River Sax'
  ];
  final List<String> _projects = [
    'Lo-fi Chill', 'Trap Beats', 'House Vibes', 'Jazz Fusion', 'Ambient Flow',
    'Hip-Hop Classic', 'Electronic Dream', 'Acoustic Soul', 'Synthwave Night', 'Drum & Bass'
  ];

  @override
  void initState() {
    super.initState();
    _chatClient = ChatClient();
    
    // Initialize lamp animation (5-second cycle)
    _lampAnimation = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
    
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

    // Listen for thread messages (collaboration notifications)
    _chatClient.threadMessageStream.listen((threadMessage) {
      setState(() {
        _usersWithNotifications.add(threadMessage.from);
      });
      
      // Show snackbar notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${threadMessage.from} shared a project: ${threadMessage.threadTitle}'),
            backgroundColor: const Color(0xFF7C3AED),
            duration: const Duration(seconds: 3),
          ),
        );
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
    _lampAnimation.dispose();
    _chatClient.dispose();
    super.dispose();
  }

  List<ContactUser> get _contacts {
    final contacts = <ContactUser>[];
    
          // Add some mock users for demonstration
      final mockUsers = [
      ContactUser(id: 'alex_beat', name: 'Alex Beat', isOnline: false, isWorking: false, project: 'Lo-fi Chill'),
      ContactUser(id: 'maya_synth', name: 'Maya Synth', isOnline: true, isWorking: true, project: ''),
      ContactUser(id: 'jordan_mix', name: 'Jordan Mix', isOnline: false, isWorking: false, project: ''),
      ContactUser(id: 'sam_drums', name: 'Sam Drums', isOnline: false, isWorking: false, project: ''),
      ContactUser(id: 'riley_bass', name: 'Riley Bass', isOnline: false, isWorking: false, project: ''),
      ContactUser(id: 'casey_keys', name: 'Casey Keys', isOnline: false, isWorking: false, project: ''),
      ContactUser(id: 'riley_bass', name: 'Riley Bass', isOnline: false, isWorking: false, project: ''),
      ContactUser(id: 'casey_keys', name: 'Casey Keys', isOnline: false, isWorking: false, project: ''),
      ContactUser(id: 'riley_bass', name: 'Riley Bass', isOnline: false, isWorking: false, project: ''),
      ContactUser(id: 'casey_keys', name: 'Casey Keys', isOnline: false, isWorking: false, project: ''),
    ];
    
          contacts.addAll(mockUsers);
    
    // Add online users from chat client
    for (final userId in _onlineUserIds) {
      if (!contacts.any((c) => c.id == userId)) {
        final index = userId.hashCode.abs() % _names.length;
        final projectIndex = userId.hashCode.abs() % _projects.length;
        
        contacts.add(ContactUser(
          id: userId,
          name: _names[index],
          isOnline: true,
          isWorking: userId.hashCode.abs() % 3 == 0, // Randomly working
          project: _projects[projectIndex],
        ));
      }
    }
    
    return contacts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Light gray background
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              child: _buildMySeriesButton(),
            ),
            
            // Contacts List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF6B7280)),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, color: Color(0xFF6B7280), size: 48),
                              const SizedBox(height: 12),
                              Text(_error!, style: const TextStyle(color: Color(0xFF6B7280))),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _isLoading = true;
                                    _error = null;
                                  });
                                  _setupChatClient();
                                },
                                child: const Text('RETRY'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _contacts.length,
                          itemBuilder: (context, index) {
                            return _buildUserBar(_contacts[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMySeriesButton() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB), // Light gray
        borderRadius: BorderRadius.circular(8), // Sharper corners
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Just navigate to sequencer - no need to create threads locally
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PatternScreen(),
              ),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF9CA3AF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'My Sequencer',
                    style: TextStyle(
                      color: Color(0xFF374151),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Color(0xFF9CA3AF),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserBar(ContactUser user) {
    return Container(
      height: 56, // Smaller height
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8), // Sharper corners
        border: Border.all(
                      color: user.isWorking 
                ? const Color.fromARGB(255, 215, 215, 215).withOpacity(0.3) 
                : const Color(0xFFD1D5DB),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            // Animated background with 4 parts (only for working users)
            if (user.isWorking) _buildAnimatedBackground(),
            
            // Static background for non-working users
            if (!user.isWorking)
              Container(
                width: double.infinity,
                height: double.infinity,
                color: const Color(0xFFE5E7EB),
              ),
            
            // Content layer
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _startChat(user),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      // Play button avatar - same color for all users
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: user.isOnline 
                                ? const Color.fromARGB(255, 222, 187, 255) 
                                : const Color(0xFFD1D5DB), 
                          borderRadius: BorderRadius.circular(15), // Almost circular (half of width/height)
                          border: Border.all(
                            color: user.isOnline 
                                ? const Color.fromARGB(255, 255, 255, 255) 
                                : const Color(0xFFD1D5DB), 
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.play_arrow,
                          color: user.isOnline 
                                ? const Color.fromARGB(255, 123, 22, 156) 
                                : const Color.fromARGB(255, 119, 119, 119), 
                          size: 20,
                        ),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // Name
                      Expanded(
                        child: Text(
                          user.name,
                          style: const TextStyle(
                            color: Color(0xFF374151), // Same gray color for all users
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      
                      // Notification indicator - red dot for unread thread messages
                      if (_usersWithNotifications.contains(user.id))
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444), // Red color for notifications
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              '!',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      
                      // Online indicator - small purple circle
                      if (user.isOnline)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color.fromARGB(255, 118, 41, 195), // Purple color for online
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _lampAnimation,
      builder: (context, child) {
        return Row(
          children: [
            Expanded(child: _buildBackgroundSection(0)),
            Expanded(child: _buildBackgroundSection(1)),
            Expanded(child: _buildBackgroundSection(2)),
            Expanded(child: _buildBackgroundSection(3)),
          ],
        );
      },
    );
  }

  Widget _buildBackgroundSection(int index) {
    // Pattern: 132423142314231423121423 (converted to 0-indexed: 021312031203021312010312)
    final pattern = [0, 2, 1, 3, 1, 2, 0, 3, 1, 2, 0, 3, 0, 2, 1, 3, 1, 2, 0, 1, 0, 3, 1, 2];
    final cyclePosition = _lampAnimation.value * pattern.length;
    
    double intensity = 0.0;
    
    // Calculate smooth transitions between states with proper wrapping
    for (int i = 0; i < pattern.length; i++) {
      final nextI = (i + 1) % pattern.length;
      
      if (cyclePosition >= i && cyclePosition < (i + 1)) {
        final progress = cyclePosition - i;
        
        if (pattern[i] == index) {
          // Fading out from this section
          intensity = 1.0 - progress;
        }
        if (pattern[nextI] == index) {
          // Fading in to this section
          intensity = progress;
        }
        break;
      }
    }
    
    // Handle the wrap-around case (from last to first pattern element)
    if (cyclePosition >= pattern.length - 1) {
      final progress = cyclePosition - (pattern.length - 1);
      final lastIndex = pattern[pattern.length - 1];
      final firstIndex = pattern[0];
      
      if (lastIndex == index) {
        // Fading out from last section
        intensity = 1.0 - progress;
      }
      if (firstIndex == index) {
        // Fading in to first section
        intensity = progress;
      }
    }
    
    // Ensure smooth curves for background effect
    intensity = Curves.easeInOut.transform(intensity.clamp(0.0, 1.0));
    
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Color.lerp(
        const Color(0xFFE5E7EB), // Base light gray
        const Color.fromARGB(255, 199, 195, 255), // Light purple when active
        intensity,
      ),
    );
  }

  void _startChat(ContactUser user) {
    // Clear notification for this user
    setState(() {
      _usersWithNotifications.remove(user.id);
    });
    
    // Navigate to user profile instead of chat
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          userId: user.id,
          userName: user.name,
        ),
      ),
    );
  }
}

// Data model for contacts
class ContactUser {
  final String id;
  final String name;
  final bool isOnline;
  final bool isWorking;
  final String project;

  ContactUser({
    required this.id,
    required this.name,
    required this.isOnline,
    required this.isWorking,
    required this.project,
  });
}

