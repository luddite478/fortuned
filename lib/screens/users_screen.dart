import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_client.dart';
import '../services/user_profile_service.dart';
import '../services/auth_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'thread_screen.dart';
import 'user_profile_screen.dart';
import '../state/threads_state.dart';
import '../state/sequencer_state.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({Key? key}) : super(key: key);
  
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> with TickerProviderStateMixin {
  late ChatClient _chatClient;
  List<String> _onlineUserIds = [];
  List<UserProfile> _userProfiles = [];
  bool _isLoading = true;
  String? _error;

  // Animation controllers
  late AnimationController _lampAnimation;

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
    // Setup listeners for online users
    _chatClient.onlineUsersStream.listen((users) {
      setState(() {
        _onlineUserIds = users;
      });
    });

    _chatClient.errorStream.listen((error) {
      // Only show WebSocket error if we haven't successfully loaded user profiles from API
      if (_userProfiles.isEmpty) {
        setState(() {
          _error = error;
          _isLoading = false;
        });
      }
    });

    _chatClient.connectionStream.listen((connected) {
      if (connected) {
        _chatClient.requestOnlineUsers();
      }
    });

    // Connect to server (but don't wait for it)
    final clientId = '${dotenv.env['CLIENT_ID_PREFIX'] ?? 'flutter_user'}_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    _chatClient.connect(clientId);

    // Load user profiles from API
    await _loadUserProfiles();
  }

  Future<void> _loadUserProfiles() async {
    try {
      final response = await UserProfileService.getUserProfiles(limit: 50);
      setState(() {
        _userProfiles = response.profiles;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load user profiles: $e';
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

  List<User> get _users {
    final users = <User>[];
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.id;
    
    // Convert UserProfile from API to User for UI, excluding current user
    for (final profile in _userProfiles) {
      // Skip if this is the current user
      if (profile.id == currentUserId) continue;
      
      final isOnline = profile.isOnline || _onlineUserIds.contains(profile.id);
      final isWorking = _onlineUserIds.contains(profile.id) && (profile.id.hashCode.abs() % 3 == 0);
      
      users.add(User(
        id: profile.id,
        name: profile.name,
        isOnline: isOnline,
        isWorking: isWorking,
        project: profile.info, // Use info as project description
      ));
    }
    
    // Add additional online users that aren't in our profile list (excluding current user)
    for (final userId in _onlineUserIds) {
      if (userId != currentUserId && !users.any((u) => u.id == userId)) {
        users.add(User(
          id: userId,
          name: 'User ${userId.substring(0, 8)}', // Show partial ID as name
          isOnline: true,
          isWorking: userId.hashCode.abs() % 3 == 0,
          project: 'Online User',
        ));
      }
    }
    
    return users;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Light gray background
      body: SafeArea(
        child: Column(
          children: [
            // User indicator at the top
            _buildUserIndicator(),
            
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              child: _buildMySequencerButton(),
            ),
            
            // Users List
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
                                  _loadUserProfiles();
                                },
                                child: const Text('RETRY'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _users.length,
                          itemBuilder: (context, index) {
                            return _buildUserBar(_users[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserIndicator() {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        final currentUser = authService.currentUser;
        if (currentUser == null) return const SizedBox();
        
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 255, 255, 255),
            border: Border(
              bottom: BorderSide(
                color: const Color.fromARGB(255, 255, 255, 255)!,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // User avatar              
              const SizedBox(width: 12),
              
              // User info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentUser.name,
                      style: TextSt yle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color.fromARGB(255, 36, 63, 116),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Online indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.green[500],
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMySequencerButton() {
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
          onTap: () async {
            final threadsState = context.read<ThreadsState>();
            final sequencerState = context.read<SequencerState>();
            
            try {
              // Ensure we have an active solo thread for this user
              await threadsState.ensureActiveSoloThread(sequencerState);
              
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ThreadScreen(
                      threadId: threadsState.currentThread!.id,
                    ),
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error creating project: $e')),
                );
              }
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
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

  Widget _buildUserBar(User user) {
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

  void _startChat(User user) {
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

// Data model for users
class User {
  final String id;
  final String name;
  final bool isOnline;
  final bool isWorking;
  final String project;

  User({
    required this.id,
    required this.name,
    required this.isOnline,
    required this.isWorking,
    required this.project,
  });
}

