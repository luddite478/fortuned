import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/threads_service.dart';
import '../services/users_service.dart';
import '../state/user_state.dart';
import '../state/threads_state.dart';
import '../state/followed_state.dart';
import '../utils/app_colors.dart';
import '../widgets/common_header_widget.dart';
import 'user_profile_screen.dart';

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
  bool _isSearching = false;
  String? _error;
  
  final TextEditingController _searchController = TextEditingController();
  
  // Track users with unread thread messages
  Set<String> _usersWithNotifications = {};
  
  // Track users with pending invitations
  Set<String> _usersWithPendingInvites = {};

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
    });

    // First, check followed users for immediate matches
    final userState = Provider.of<UserState>(context, listen: false);
    final followedState = Provider.of<FollowedState>(context, listen: false);
    final currentUserId = userState.currentUser?.id;
    
    final followedMatches = followedState.followedUsers
        .where((user) => user.username.toLowerCase().contains(query.toLowerCase()))
        .where((user) => user.id != currentUserId)
        .toList();

    setState(() {
      _filteredUserProfiles = followedMatches;
    });

    // If query is 4+ characters, also search all users
    if (query.length >= 4) {
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
        });
      } catch (e) {
        setState(() {
          _error = 'Search failed: $e';
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

    // Load followed users (cached if available)
    await _loadFollowedUsers();
    
    // Refresh in background if already loaded
    final followedState = Provider.of<FollowedState>(context, listen: false);
    final userState = Provider.of<UserState>(context, listen: false);
    if (followedState.hasLoaded && userState.currentUser?.id != null) {
      followedState.refreshFollowedUsersInBackground(userState.currentUser!.id);
    }
    
    // Load threads to check for pending invitations
    await _loadThreadsAndCheckInvitations();
  }

  Future<void> _loadFollowedUsers() async {
    final userState = Provider.of<UserState>(context, listen: false);
    final followedState = Provider.of<FollowedState>(context, listen: false);
    final currentUserId = userState.currentUser?.id;
    
    if (currentUserId == null) {
      return;
    }

    // Load from FollowedState (returns cached data immediately if available)
    await followedState.loadFollowedUsers(userId: currentUserId);
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
    final userState = Provider.of<UserState>(context, listen: false);
    final currentUserId = userState.currentUser?.id;
    
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
              child: Consumer<FollowedState>(
                builder: (context, followedState, _) {
                  // Show loading only on first load (no cached data)
                  if (followedState.isLoading && !followedState.hasLoaded) {
                    return Center(
                      child: CircularProgressIndicator(color: AppColors.menuLightText),
                    );
                  }
                  
                  // Show error (rare, only if initial load fails)
                  if (_error != null) {
                    return Center(
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
                    );
                  }
                  
                  // Get users to display - either search results or followed users
                  final usersToDisplay = _isSearching 
                      ? _filteredUserProfiles
                      : followedState.followedUsers;
                  
                  return Stack(
                    children: [
                      usersToDisplay.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.people_outline,
                                    color: AppColors.menuLightText,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _isSearching ? 'No results found' : 'No followed users',
                                    style: GoogleFonts.sourceSans3(
                                      color: AppColors.menuLightText,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: usersToDisplay.length,
                              itemBuilder: (context, index) {
                                return _buildExpandableUserCard(_convertToUser(usersToDisplay[index]));
                              },
                            ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Helper method to convert UserProfile to User
  User _convertToUser(UserProfile profile) {
    final isOnline = _onlineUserIds.contains(profile.id);
    final isWorking = false; // Placeholder
    
    return User(
      id: profile.id,
      name: profile.name,
      isOnline: isOnline,
      isWorking: isWorking,
      project: profile.profile.bio,
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
    return _buildUserBar(user);
  }

  Widget _buildUserBar(User user) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Get screen width for responsive calculations
        final screenWidth = constraints.maxWidth;
        
        // Calculate responsive dimensions as percentages of screen width
        final horizontalPadding = screenWidth * 0.04; // 4% of screen width
        final verticalPadding = screenWidth * 0.02; // 2% of screen width
        final nameSpacing = screenWidth * 0.03; // 3% spacing after name
        final indicatorSize = screenWidth * 0.015; // 1.5% for indicator size
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
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserProfileScreen(
                          userId: user.id,
                          userName: user.name,
                          isOnline: user.isOnline,
                        ),
                      ),
                    );
                  },
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