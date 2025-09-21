import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/threads_service.dart';
import '../services/users_service.dart';
import '../services/auth_service.dart';
import '../state/threads_state.dart';
import '../utils/app_colors.dart';
import '../widgets/common_header_widget.dart';
import 'user_profile_screen.dart';
import '../models/thread/thread.dart';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({Key? key}) : super(key: key);
  
  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> with TickerProviderStateMixin {
  late ThreadsService _threadsService;
  late UsersService _usersService;
  List<String> _onlineUserIds = [];
  List<UserProfile> _userProfiles = [];
  List<UserProfile> _filteredUserProfiles = [];
  List<UserProfile> _followedUsers = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String? _error;
  
  final TextEditingController _searchController = TextEditingController();
  
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
    
    _threadsService = Provider.of<ThreadsService>(context, listen: false);
    _usersService = Provider.of<UsersService>(context, listen: false);
    
    // Initialize lamp animation (5-second cycle)
    _lampAnimation = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
    
    _setupThreadsServiceListeners();
    _setupSearchListener();
  }

  void _setupSearchListener() {
    _searchController.addListener(() {
      _handleSearch(_searchController.text);
    });
  }

  void _handleSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _filteredUserProfiles = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoading = false;
    });

    // First, check followed users for immediate matches
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.id;
    
    final followedMatches = _followedUsers
        .where((user) => user.username.toLowerCase().contains(query.toLowerCase()))
        .where((user) => user.id != currentUserId)
        .toList();

    setState(() {
      _filteredUserProfiles = followedMatches;
    });

    // If query is 4+ characters, also search all users
    if (query.length >= 4) {
      setState(() {
        _isLoading = true;
      });

      try {
        final searchResults = await UsersService.searchUsers(query, limit: 50);
        
        // Combine followed matches with search results, avoiding duplicates
        final allResults = <UserProfile>[...followedMatches];
        for (final user in searchResults.users) {
          if (user.id != currentUserId && 
              !allResults.any((existing) => existing.id == user.id)) {
            allResults.add(user);
          }
        }

        setState(() {
          _filteredUserProfiles = allResults;
          _isLoading = false;
        });
      } catch (e) {
        setState(() {
          _error = 'Search failed: $e';
          _isLoading = false;
        });
      }
    }
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

    // Load followed users first (priority)
    await _loadFollowedUsers();
    
    // Load threads to check for pending invitations
    await _loadThreadsAndCheckInvitations();
  }

  Future<void> _loadFollowedUsers() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;
      
      if (currentUserId == null) {
        setState(() {
          _error = 'Please log in to view followed users';
          _isLoading = false;
        });
        return;
      }

      final response = await UsersService.getFollowedUsers(currentUserId);
      setState(() {
        _followedUsers = response.users;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      // If loading followed users fails, show empty state but don't show error
      setState(() {
        _followedUsers = [];
        _isLoading = false;
        _error = null;
      });
      print('Failed to load followed users: $e');
    }
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
        if (invite.userId == currentUserId && invite.status == 'pending') {
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
    _searchController.dispose();
    super.dispose();
  }

  List<User> get _users {
    final users = <User>[];
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.id;
    
    // Determine which profiles to show based on whether we're searching
    final profilesToShow = _isSearching ? _filteredUserProfiles : _followedUsers;
    
    // Convert UserProfile from API to User for UI, excluding current user
    for (final profile in profilesToShow) {
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
        project: profile.info ?? '', // Use info as project description
      ));
    }
    
    return users;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.menuPageBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Common header
            const CommonHeaderWidget(),
            
            // Search bar
            _buildSearchBar(),
            
            // Users List
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: AppColors.menuLightText),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, color: AppColors.menuLightText, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                _error!, 
                                style: GoogleFonts.sourceSans3(
                                  color: AppColors.menuLightText,
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
                                  _loadFollowedUsers();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.menuButtonBackground,
                                ),
                                child: Text(
                                  'RETRY',
                                  style: GoogleFonts.sourceSans3(
                                    color: AppColors.menuText,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : _users.isEmpty
                          ? const SizedBox.shrink()
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

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.menuEntryBackground,
        border: Border(
          bottom: BorderSide(
            color: AppColors.menuBorder,
            width: 1,
          ),
        ),
      ),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.sourceSans3(
          color: AppColors.menuText,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: 'Search',
          hintStyle: GoogleFonts.sourceSans3(
            color: AppColors.menuLightText,
            fontSize: 14,
          ),
          prefixIcon: _isSearching 
              ? IconButton(
                  icon: Icon(Icons.arrow_back, color: AppColors.menuText, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _isSearching = false;
                      _filteredUserProfiles = [];
                    });
                    // Dismiss keyboard
                    FocusScope.of(context).unfocus();
                  },
                )
              : Icon(
                  Icons.search,
                  color: AppColors.menuLightText,
                  size: 20,
                ),
          filled: true,
          fillColor: AppColors.menuPageBackground,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: AppColors.menuBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: AppColors.menuBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: AppColors.menuText, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Get screen width for responsive calculations
        final screenWidth = constraints.maxWidth;
        
        // Calculate responsive dimensions as percentages of screen width
        final horizontalPadding = screenWidth * 0.04; // 4% of screen width
        final verticalPadding = screenWidth * 0.02; // 2% of screen width
        final nameSpacing = screenWidth * 0.03; // 3% spacing after name
        final indicatorSize = screenWidth * 0.015; // 1.5% for indicator size
        final expandButtonSize = screenWidth * 0.04; // 4% for expand button
        final notificationSpacing = screenWidth * 0.01; // 1% spacing between notifications
        
        return Container(
          height: 48, // Keep fixed height for consistency
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: AppColors.menuEntryBackground,
            border: Border(
              bottom: BorderSide(
                color: AppColors.menuBorder,
                width: 0.5,
              ),
            ),
          ),
          child: Stack(
            children: [
              // Animated background for working users
              if (user.isWorking) _buildAnimatedBackground(),
              
              // Content layer
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _startChat(user),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: verticalPadding,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Name section - takes up available space
                        Expanded(
                          flex: 6, // 60% of available width for name
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              user.name,
                              style: GoogleFonts.sourceSans3(
                                color: AppColors.menuText,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                        
                        // Spacer
                        SizedBox(width: nameSpacing),
                        
                        // Notifications and controls section - fixed width
                        Expanded(
                          flex: 4, // 40% of available width for controls
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Notification indicators container
                              if (_usersWithPendingInvites.contains(user.id) || 
                                  _usersWithNotifications.contains(user.id))
                                Container(
                                  constraints: BoxConstraints(
                                    maxWidth: screenWidth * 0.1, // Max 10% width for notifications
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Blue dot for pending invitations
                                      if (_usersWithPendingInvites.contains(user.id))
                                        Container(
                                          margin: EdgeInsets.only(right: notificationSpacing),
                                          width: indicatorSize.clamp(4.0, 8.0),
                                          height: indicatorSize.clamp(4.0, 8.0),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF3B82F6),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      
                                      // Red dot for unread thread messages
                                      if (_usersWithNotifications.contains(user.id))
                                        Container(
                                          margin: EdgeInsets.only(right: notificationSpacing),
                                          width: (indicatorSize * 1.2).clamp(5.0, 10.0),
                                          height: (indicatorSize * 1.2).clamp(5.0, 10.0),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFEF4444),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              
                              // Expand/collapse button
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
                                    padding: EdgeInsets.all(expandButtonSize * 0.2),
                                    margin: EdgeInsets.only(right: notificationSpacing),
                                    child: Icon(
                                      isExpanded ? Icons.expand_less : Icons.expand_more,
                                      color: AppColors.menuText,
                                      size: expandButtonSize.clamp(12.0, 20.0),
                                    ),
                                  ),
                                ),
                              
                              // Online indicator - always at the far right
                              Container(
                                width: indicatorSize.clamp(4.0, 8.0),
                                height: indicatorSize.clamp(4.0, 8.0),
                                decoration: BoxDecoration(
                                  color: user.isOnline 
                                      ? AppColors.menuOnlineIndicator 
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
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
      },
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
        AppColors.menuEntryBackground,
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
    final List<Thread> list = [];
    for (final t in threadsState.threads) {
      final userIds = t.users.map((u) => u.id).toList();
      if (userIds.contains(currentUserId) && userIds.contains(userId)) {
        list.add(t);
      }
    }
    return list;
  }

  Widget _buildThreadsList(User user, List<Thread> threads) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.id;
    
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 8, bottom: 2),
      decoration: BoxDecoration(
        color: AppColors.menuPageBackground.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.menuBorder, width: 0.5),
      ),
      child: Column(
        children: threads.map((thread) {
          // Check if user has pending invitation to this thread
          final hasPendingInvite = currentUserId != null &&
              thread.invites.any((i) => i.userId == currentUserId && i.status == 'pending');
          
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: thread == threads.last 
                      ? Colors.transparent 
                      : AppColors.menuBorder,
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
                        : AppColors.menuLightText,
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
                              'Project ${thread.id.substring(0, 8)}',
                              style: GoogleFonts.sourceSans3(
                                color: AppColors.menuText,
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
                            color: AppColors.menuLightText,
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                          ),
                        )
                      else
                        Text(
                          '${thread.messageIds.length} messages',
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.menuLightText,
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
                    color: AppColors.menuLightText,
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
    
    // Navigate to user profile screen
    debugPrint('👤 Opening profile for ${user.name}');
    final isUserOnline = _onlineUserIds.contains(user.id);
    
    final wasSearching = _isSearching;
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          userId: user.id,
          userName: user.name,
          isOnline: isUserOnline,
          onFollowStatusChanged: (isFollowing) {
            // Refresh followed users when follow status changes
            _loadFollowedUsers();
          },
        ),
      ),
    );
    
    // If user was found via search, clear search when coming back
    if (wasSearching) {
      _searchController.clear();
      setState(() {
        _isSearching = false;
        _filteredUserProfiles = [];
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
        debugPrint('   Thread ${thread.id}: users=$userIds');
      }
      
      // Find threads where both current user and target user are participants
      final commonThreads = targetUserThreads.where((thread) {
        final ids = thread.users.map((u) => u.id).toSet();
        return ids.contains(currentUserId) && ids.contains(targetUserId);
      }).toList();
      
      debugPrint('🤝 Found ${commonThreads.length} common threads');
      for (final thread in commonThreads) {
        debugPrint('   Common: ${thread.id}');
      }
      
      return commonThreads;
    } catch (e) {
      debugPrint('❌ Error getting common threads: $e');
      return [];
    }
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