import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/threads_service.dart';
import '../services/users_service.dart';
import '../services/auth_service.dart';
import '../services/threads_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'user_profile_screen.dart';
import 'sequencer_screen_v2.dart';
import 'checkpoints_screen.dart';
import '../state/threads_state.dart';
import '../state/sequencer_state.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/app_colors.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({Key? key}) : super(key: key);
  
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> with TickerProviderStateMixin {
  late ThreadsService _threadsService;
  late UsersService _usersService;
  List<String> _onlineUserIds = [];
  List<UserProfile> _userProfiles = [];
  bool _isLoading = true;
  String? _error;
  
  // Track users with unread thread messages
  Set<String> _usersWithNotifications = {};
  
  // Track users with pending invitations
  Set<String> _usersWithPendingInvites = {};

  // Track expanded contact tiles
  Set<String> _expandedContacts = {};

  // Animation controllers
  late AnimationController _lampAnimation;

  @override
  void initState() {
    super.initState();
    
          // Use the global ThreadsService and UsersService from Provider instead of creating new ones
    _threadsService = Provider.of<ThreadsService>(context, listen: false);
    _usersService = Provider.of<UsersService>(context, listen: false);
    
    // Initialize lamp animation (5-second cycle)
    _lampAnimation = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
    
    _setupThreadsServiceListeners();
  }

  void _setupThreadsServiceListeners() async {
    // Setup listeners for online users from UsersService
    _usersService.onlineUsersStream.listen((users) {
      setState(() {
        _onlineUserIds = users;
      });
    });

    _usersService.errorStream.listen((error) {
      // Only show WebSocket error if we haven't successfully loaded user profiles from API
      if (_userProfiles.isEmpty) {
        setState(() {
          _error = error;
          _isLoading = false;
        });
      }
    });

    _usersService.connectionStream.listen((connected) {
      if (connected) {
        _usersService.requestOnlineUsers();
      }
    });

    // Listen for thread messages (collaboration notifications)
    _threadsService.threadNotificationStream.listen((threadMessage) {
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

    // Listen for thread invitations
    _threadsService.threadInvitationStream.listen((invitation) {
      setState(() {
        _usersWithPendingInvites.add(invitation.fromUserId);
      });
      
      // Show snackbar notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${invitation.fromUserName} invited you to collaborate on "${invitation.threadTitle}"'),
            backgroundColor: const Color(0xFF3B82F6), // Blue color for invitations
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'VIEW',
              textColor: Colors.white,
              onPressed: () {
                // TODO: Navigate to invitations screen or thread
                debugPrint('Navigate to invitation for thread: ${invitation.threadId}');
              },
            ),
          ),
        );
      }
    });

    // No need to connect here - it's already connected globally
    debugPrint('📡 Using global ThreadsService connection in users screen');

    // Load user profiles from API
    await _loadUserProfiles();
    
    // Load threads to check for pending invitations
    await _loadThreadsAndCheckInvitations();
  }

  Future<void> _loadUserProfiles() async {
    try {
      final response = await UsersService.getUserProfiles(limit: 50);
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

  Future<void> _loadThreadsAndCheckInvitations() async {
    try {
      final threadsState = Provider.of<ThreadsState>(context, listen: false);
      
      // Load threads from server to get latest invitation data
      await threadsState.loadThreads();
      
      // Check for pending invitations
      _checkPendingInvitations();
    } catch (e) {
      debugPrint('Failed to load threads: $e');
      // Still check local state for invitations
      _checkPendingInvitations();
    }
  }

  void _checkPendingInvitations() {
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.id;
    
    if (currentUserId == null) return;
    
    // Check all threads for pending invitations to current user
    final usersWithInvites = <String>{};
    for (final thread in threadsState.threads) {
      for (final invite in thread.invites) {
        if (invite.userId == currentUserId && invite.status == InviteStatus.pending) {
          usersWithInvites.add(invite.invitedBy);
        }
      }
    }
    
    setState(() {
      _usersWithPendingInvites = usersWithInvites;
    });
  }

  @override
  void dispose() {
    _lampAnimation.dispose();
    // Don't dispose the global ThreadsService - it's managed at app level
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
      
      // Now we can properly match online status since WebSocket uses real user IDs
      final isOnline = profile.isOnline || _onlineUserIds.contains(profile.id);
      final isWorking = false; // Simplified - remove the random working status
      
      users.add(User(
        id: profile.id,
        name: profile.name,
        isOnline: isOnline,
        isWorking: isWorking,
        project: profile.info, // Use info as project description
      ));
    }
    
    
    return users;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.menupageBackground,
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
                  ? Center(
                      child: CircularProgressIndicator(color: AppColors.menulightText),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, color: AppColors.menulightText, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                _error!, 
                                style: GoogleFonts.sourceSans3(
                                  color: AppColors.menulightText,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _isLoading = true;
                                    _error = null;
                                  });
                                  _loadUserProfiles();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.menubuttonBackground,
                                ),
                                child: Text(
                                  'RETRY',
                                  style: GoogleFonts.sourceSans3(
                                    color: AppColors.menutext,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _users.length,
                          itemBuilder: (context, index) {
                            return _buildExpandableUserCard(_users[index]);
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
            color: AppColors.menuentryBackground,
            border: Border(
              bottom: BorderSide(
                color: AppColors.menuborder,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // User info - clickable to view own profile
              Expanded(
                child: GestureDetector(
                  onTap: () => _viewMyProfile(currentUser),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentUser.name,
                        style: GoogleFonts.sourceSans3(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.menutext,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Logout button
              GestureDetector(
                onTap: () async {
                  final authService = Provider.of<AuthService>(context, listen: false);
                  await authService.logout();
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.logout,
                    size: 16,
                    color: AppColors.menutext,
                  ),
                ),
              ),
              
              const SizedBox(width: 8),
              
              // Online indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.menuonlineIndicator,
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
      height: 70, // Slightly taller to emphasize importance
      decoration: BoxDecoration(
        color: AppColors.menubuttonBackground,
        borderRadius: BorderRadius.circular(4), // Sharp, boxy corners like old directories
        border: Border.all(
          color: AppColors.menubuttonBorder,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 4,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Navigate to V2 sequencer implementation
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SequencerScreenV2(),
              ),
            );
          },
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'MY SEQUENCER',
                    style: GoogleFonts.sourceSans3(
                      color: AppColors.menutext,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward,
                  color: AppColors.menutext,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandableUserCard(User user) {
    final isExpanded = _expandedContacts.contains(user.id);
    final commonThreads = _getCommonThreadsWithUserSync(user.id);
    
    return Column(
      children: [
        _buildUserBar(user, isExpanded, commonThreads.isNotEmpty),
        if (isExpanded && commonThreads.isNotEmpty)
          _buildThreadsList(user, commonThreads),
      ],
    );
  }

  Widget _buildUserBar(User user, bool isExpanded, bool hasThreads) {
    return Container(
      height: 48, // Compact like phone book entries
      margin: const EdgeInsets.only(bottom: 2), // Tight spacing like phone book
      decoration: BoxDecoration(
        color: AppColors.menuentryBackground,
        border: Border(
          bottom: BorderSide(
            color: AppColors.menuborder,
            width: 0.5,
          ),
        ),
      ),
      child: Stack(
        children: [
          // Animated background for working users (simplified)
          if (user.isWorking) _buildAnimatedBackground(),
          
          // Content layer
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _startChat(user),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Name (main content)
                    Expanded(
                      child: Text(
                        user.name,
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.menutext,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 12),
                    
                    // Notification indicators
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Blue dot for pending invitations
                        if (_usersWithPendingInvites.contains(user.id))
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF3B82F6), // Blue color for invitations
                              shape: BoxShape.circle,
                            ),
                          ),
                        
                        // Red dot for unread thread messages
                        if (_usersWithNotifications.contains(user.id))
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444), // Red color for notifications
                              shape: BoxShape.circle,
                            ),
                          ),
                        
                        // Add spacing if there are notifications
                        if (_usersWithNotifications.contains(user.id) || _usersWithPendingInvites.contains(user.id))
                          const SizedBox(width: 4),
                      ],
                    ),
                    
                    // Expand/collapse button (only show if user has threads)
                    if (hasThreads)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedContacts.remove(user.id);
                            } else {
                              _expandedContacts.add(user.id);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          margin: const EdgeInsets.only(right: 4),
                          child: Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            color: AppColors.menutext,
                            size: 16,
                          ),
                        ),
                      ),
                    
                    // Online indicator - small dot like phone book annotations
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: user.isOnline 
                            ? AppColors.menuonlineIndicator 
                            : Colors.transparent,
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
        AppColors.menuentryBackground,
        const Color(0xFFF5F0D0), // Slightly highlighted yellow when active
        intensity,
      ),
    );
  }

  List<Thread> _getCommonThreadsWithUserSync(String userId) {
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.id;
    
    if (currentUserId == null) return [];
    
    // Find threads where both current user and the target user are participants
    return threadsState.threads.where((thread) {
      final userIds = thread.users.map((u) => u.id).toList();
      return userIds.contains(currentUserId) && userIds.contains(userId);
    }).toList();
  }

  Widget _buildThreadsList(User user, List<Thread> threads) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.id;
    
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 8, bottom: 2),
      decoration: BoxDecoration(
        color: AppColors.menupageBackground.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.menuborder, width: 0.5),
      ),
      child: Column(
        children: threads.map((thread) {
          // Check if user has pending invitation to this thread
          final hasPendingInvite = currentUserId != null && 
              thread.hasPendingInvite(currentUserId);
          
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: thread == threads.last 
                      ? Colors.transparent 
                      : AppColors.menuborder,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                // Thread icon - smaller, phone book style
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: hasPendingInvite 
                        ? const Color(0xFF3B82F6) 
                        : AppColors.menulightText,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Icon(
                    hasPendingInvite ? Icons.mail : Icons.folder,
                    color: Colors.white,
                    size: 10,
                  ),
                ),
                const SizedBox(width: 8),
                
                // Thread info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              thread.title,
                              style: GoogleFonts.sourceSans3(
                                color: AppColors.menutext,
                                fontSize: 12,
                                fontWeight: hasPendingInvite 
                                    ? FontWeight.w600 
                                    : FontWeight.w500,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          if (hasPendingInvite)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'NEW',
                                style: GoogleFonts.sourceSans3(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (hasPendingInvite)
                        Text(
                          'Invitation to collaborate',
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.menulightText,
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                          ),
                        )
                      else
                        Text(
                          '${thread.checkpoints.length} checkpoints',
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.menulightText,
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
                
                // Timestamp - phone book style
                Text(
                  _formatThreadTimestamp(thread.updatedAt),
                  style: GoogleFonts.sourceSans3(
                    color: AppColors.menulightText,
                    fontSize: 9,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _formatThreadTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays > 0) {
      if (difference.inDays == 1) {
        return 'Yesterday';
      } else {
        return '${difference.inDays}d ago';
      }
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Now';
    }
  }

  void _startChat(User user) async {
    // Clear notifications for this user
    setState(() {
      _usersWithNotifications.remove(user.id);
      _usersWithPendingInvites.remove(user.id);
    });
    
    // Check for common threads with this user
    final commonThreads = await _getCommonThreadsWithUser(user.id);
    
    if (commonThreads.isNotEmpty) {
      // We have collaborations - navigate directly to checkpoints screen
      debugPrint('🤝 Found ${commonThreads.length} common threads with ${user.name}');
      
      // Sort by updated date to get the latest thread
      commonThreads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final latestThread = commonThreads.first;
      
      debugPrint('📋 Opening checkpoints for latest thread: ${latestThread.title}');
      
      // Set the active thread in ThreadsState before navigating
      final threadsState = Provider.of<ThreadsState>(context, listen: false);
      threadsState.setActiveThread(latestThread);
      
      // Navigate to checkpoints screen (chat-like interface)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckpointsScreenWithUserContext(
            threadId: latestThread.id,
            targetUserId: user.id,
            targetUserName: user.name,
            commonThreads: commonThreads,
          ),
        ),
      );
    } else {
      // No collaborations - navigate to user profile
      debugPrint('👤 No common threads with ${user.name}, opening profile');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          userId: user.id,
          userName: user.name,
          ),
        ),
      ).then((_) {
        // Refresh pending invitations when returning from user profile
        _checkPendingInvitations();
      });
    }
  }

  /// Get common threads between current user and target user
  Future<List<Thread>> _getCommonThreadsWithUser(String targetUserId) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;
      
      debugPrint('🔍 Checking common threads: current=$currentUserId, target=$targetUserId');
      
      if (currentUserId == null) {
        debugPrint('❌ No current user ID');
        return [];
      }

      // Get threads for the target user
      final targetUserThreads = await ThreadsService.getUserThreads(targetUserId);
      debugPrint('📋 Found ${targetUserThreads.length} threads for target user');
      
      // Debug: Print thread participants
      for (final thread in targetUserThreads) {
        final userIds = thread.users.map((u) => u.id).toList();
        debugPrint('   Thread "${thread.title}": users=$userIds');
      }
      
      // Find threads where both current user and target user are participants
      final commonThreads = targetUserThreads.where((thread) => 
        thread.hasUser(currentUserId) && thread.hasUser(targetUserId)
      ).toList();
      
      debugPrint('🤝 Found ${commonThreads.length} common threads');
      for (final thread in commonThreads) {
        debugPrint('   Common: "${thread.title}" (${thread.id})');
      }
      
      return commonThreads;
    } catch (e) {
      debugPrint('❌ Error getting common threads: $e');
      return [];
    }
  }

  void _viewMyProfile(UserProfile currentUser) {
    // Navigate to own profile
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          userId: currentUser.id,
          userName: currentUser.name,
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

