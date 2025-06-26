import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/user_profile_service.dart';
import '../services/threads_service.dart';
import '../services/auth_service.dart';
import '../state/threads_state.dart';
import '../state/sequencer_state.dart';
import 'user_projects_screen.dart';
import 'sequencer_screen.dart';
import 'checkpoints_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const UserProfileScreen({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {

  UserProfile? _userProfile;
  List<Thread> _userThreads = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Load user profile first (required)
      final profile = await UserProfileService.getUserProfile(widget.userId);
      
      // Load threads separately (optional - don't fail if this fails)
      List<Thread> threads = [];
      try {
        threads = await ThreadsService.getUserThreads(widget.userId);
      } catch (threadsError) {
        print('Warning: Failed to load user threads: $threadsError');
        // Continue without threads - don't fail the whole profile load
      }

      setState(() {
        _userProfile = profile;
        _userThreads = threads;
        _isLoading = false;
      });

      // Check for common threads and auto-navigate if any exist
      _checkForCommonThreadsAndNavigate();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _checkForCommonThreadsAndNavigate() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.id;
    
    if (currentUserId == null || _userThreads.isEmpty) return;

    // Find common threads (threads where both current user and clicked user are participants)
    final commonThreads = _userThreads.where((thread) => 
      thread.hasUser(currentUserId) && thread.hasUser(widget.userId)
    ).toList();

    if (commonThreads.isNotEmpty) {
      // Sort by updated date to get the latest thread
      commonThreads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final latestThread = commonThreads.first;
      
      // Set the active thread in ThreadsState before navigating
      final threadsState = Provider.of<ThreadsState>(context, listen: false);
      threadsState.setActiveThread(latestThread);
      
      // Navigate to checkpoints screen for the latest common thread
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => CheckpointsScreen(
            threadId: latestThread.id,
          ),
        ),
      );
    }
    // If no common threads, stay on profile but we'll show the threads button in the UI
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.userName,
          style: const TextStyle(
            color: Color(0xFF374151),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Color(0xFF374151)),
            onPressed: () => _showOptionsMenu(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _buildProfileContent(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Color(0xFF9CA3AF),
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load profile',
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Unknown error',
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadUserProfile,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    if (_userProfile == null) return const SizedBox();

    return Column(
      children: [
        // Top threads bar (only show if no common threads)
        _buildThreadsTopBar(),
        
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProfileHeader(),
                const SizedBox(height: 24),
                _buildSeriesSection(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThreadsTopBar() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.id;
    
    if (currentUserId == null) return const SizedBox();
    
    // Check if there are common threads
    final commonThreads = _userThreads.where((thread) => 
      thread.hasUser(currentUserId) && thread.hasUser(widget.userId)
    ).toList();
    
    // Only show the bar if there are NO common threads but user has some threads
    if (commonThreads.isNotEmpty || _userThreads.isEmpty) {
      return const SizedBox();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF374151),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${widget.userName}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: _viewUserThreads,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 118, 41, 195),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text(
              'Threads',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    final profile = _userProfile!;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: profile.isOnline 
                      ? const Color.fromARGB(255, 222, 187, 255)
                      : const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: profile.isOnline 
                        ? const Color.fromARGB(255, 118, 41, 195)
                        : const Color(0xFFD1D5DB),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    profile.avatar,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Name and status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: const TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: profile.isOnline 
                                ? const Color.fromARGB(255, 118, 41, 195)
                                : const Color(0xFF9CA3AF),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          profile.isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            color: profile.isOnline 
                                ? const Color.fromARGB(255, 118, 41, 195)
                                : const Color(0xFF9CA3AF),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          if (profile.bio.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              profile.bio,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
          
          const SizedBox(height: 20),
          
                          // View Projects Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
                                onPressed: () => _viewAllProjects(),
              icon: const Icon(Icons.library_music_outlined, size: 18),
                                label: const Text('View All Projects'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF374151),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeriesSection() {
            if (_userThreads.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(
                Icons.music_note_outlined,
                size: 48,
                color: Color(0xFF9CA3AF),
              ),
              SizedBox(height: 12),
              Text(
                'No series yet',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
              itemCount: _userThreads.length,
        itemBuilder: (context, index) {
          return _buildSeriesCard(_userThreads[index]);
      },
    );
  }

  Widget _buildSeriesCard(Thread thread) {
    return Container(
      height: 76, // Slightly increased height to prevent overflow
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6), // Sharper corners
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openSeries(thread),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // Increased vertical padding
            child: Row(
              children: [
                // Thread cover with play button
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF9CA3AF), // Default color for threads
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _playSeries(thread),
                      borderRadius: BorderRadius.circular(4),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Thread info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Date and privacy indicator
                      Row(
                        children: [
                          Text(
                            _formatDate(thread.createdAt),
                            style: const TextStyle(
                              color: Color(0xFF374151),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (thread.status != ThreadStatus.active)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                thread.status.toString().split('.').last,
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                      
                      const SizedBox(height: 3), // Reduced spacing
                      
                      // Thread title/description
                      Text(
                        thread.title.isNotEmpty 
                            ? thread.title 
                            : 'Untitled Thread',
                        style: TextStyle(
                          color: thread.title.isNotEmpty 
                              ? const Color(0xFF6B7280) 
                              : const Color(0xFF9CA3AF),
                          fontSize: 11,
                          fontStyle: thread.title.isEmpty 
                              ? FontStyle.italic 
                              : FontStyle.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      const SizedBox(height: 3), // Reduced spacing
                      
                      // Stats row
                      Row(
                        children: [
                          Text(
                            '${thread.checkpoints.length} checkpoints',
                            style: const TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 10,
                            ),
                          ),
                          const Text(
                            ' • ',
                            style: TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 10,
                            ),
                          ),
                          const Icon(
                            Icons.group,
                            size: 10,
                            color: Color(0xFF9CA3AF),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${thread.users.length}',
                            style: const TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 8), // Add spacing before buttons
                
                // Action buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Improve button (can be locked)
                    Container(
                      width: 70, // Fixed width to ensure consistent size
                      height: 32,
                      decoration: BoxDecoration(
                        color: _canEditSeries(thread) 
                            ? const Color.fromARGB(255, 199, 195, 255) // Light purple for unlocked
                            : const Color(0xFFE5E7EB), // Light gray for locked
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _canEditSeries(thread) 
                              ? () => _editSeries(thread) 
                              : null,
                          borderRadius: BorderRadius.circular(6),
                          child: Center(
                            child: _canEditSeries(thread)
                                ? const Text(
                                    'IMPROVE',
                                    style: TextStyle(
                                      color: Color.fromARGB(255, 80, 91, 108), // Dark gray text for light purple background
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.lock,
                                    color: Color.fromARGB(255, 213, 216, 222),
                                    size: 16,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays < 1) {
      return 'Today';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}w ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '${months}mo ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '${years}y ago';
    }
  }

  int _getRandomPlays(String seriesId) {
    // Generate consistent random plays based on series ID
    final hash = seriesId.hashCode.abs();
    return (hash % 9999) + 100; // Between 100-10099
  }

  int _getRandomForks(String seriesId) {
    // Generate consistent random forks based on series ID
    final hash = seriesId.hashCode.abs();
    return (hash % 50) + 1; // Between 1-50
  }

  bool _canEditSeries(Thread thread) {
    return thread.status == ThreadStatus.active;
  }

  void _playSeries(Thread thread) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playing: ${thread.title}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _editSeries(Thread thread) async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Text('Starting thread...'),
            ],
          ),
          backgroundColor: const Color.fromARGB(255, 160, 160, 161),
          duration: const Duration(seconds: 3),
        ),
      );

      // Get sequencer and threads state from providers
      final sequencerState = Provider.of<SequencerState>(context, listen: false);
      final threadsState = Provider.of<ThreadsState>(context, listen: false);
      
      // Set current user (this would typically come from app state)
      final currentUserId = 'current_user_123'; // TODO: Get from user session
      final currentUserName = 'Current User'; // TODO: Get from user session
      threadsState.setCurrentUser(currentUserId);
      
      // Load the project into sequencer state if needed
      try {
        // For now, create a snapshot from current sequencer state
        final initialSnapshot = sequencerState.createSnapshot();
        
        // Create thread users list
        final users = <ThreadUser>[
          ThreadUser(
            id: widget.userId,
            name: widget.userName,
            joinedAt: DateTime.now(),
          ),
        ];
        
        // Add current user as collaborator if different from original author
        if (currentUserId != widget.userId) {
          users.add(ThreadUser(
            id: currentUserId,
            name: currentUserName,
            joinedAt: DateTime.now(),
          ));
        }
        
        // Start a new thread with the project
        final threadId = await threadsState.createThread(
          title: thread.title,
          authorId: widget.userId,
          authorName: widget.userName,
          collaboratorIds: currentUserId != widget.userId ? [currentUserId] : [],
          collaboratorNames: currentUserId != widget.userId ? [currentUserName] : [],
          initialSnapshot: initialSnapshot,
          metadata: {
            'original_project_id': thread.id,
            'project_type': 'collaboration',
            'genre': thread.metadata?['genre'] ?? 'Unknown',
          },
        );
        
        print('🚀 Started thread: $threadId');
        
      } catch (seriesLoadError) {
        print('Note: Could not load series data, using current sequencer state: $seriesLoadError');
        
        // Fallback: Use current sequencer state as initial state
        final initialSnapshot = sequencerState.createSnapshot();
        
        // Create thread users list
        final users = <ThreadUser>[
          ThreadUser(
            id: widget.userId,
            name: widget.userName,
            joinedAt: DateTime.now(),
          ),
        ];
        
        // Add current user as collaborator if different from original author
        if (currentUserId != widget.userId) {
          users.add(ThreadUser(
            id: currentUserId,
            name: currentUserName,
            joinedAt: DateTime.now(),
          ));
        }
        
        final threadId = await threadsState.createThread(
          title: thread.title,
          authorId: widget.userId,
          authorName: widget.userName,
          collaboratorIds: currentUserId != widget.userId ? [currentUserId] : [],
          collaboratorNames: currentUserId != widget.userId ? [currentUserName] : [],
          initialSnapshot: initialSnapshot,
          metadata: {
            'original_project_id': thread.id,
            'project_type': 'collaboration',
            'genre': thread.metadata?['genre'] ?? 'Unknown',
          },
        );
        
        print('🚀 Started thread with fallback: $threadId');
      }
      
      // Hide loading snackbar and show success
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🚀 Started thread for "${thread.title}"'),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 3),
        ),
      );

      // Navigate to sequencer screen
      Navigator.push(context, MaterialPageRoute(
        builder: (context) => const PatternScreen(),
      ));
      
    } catch (e) {
      // Hide loading snackbar and show error
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to start thread: ${e.toString()}'),
          backgroundColor: const Color(0xFFEF4444),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _openSeries(Thread thread) {
    // TODO: Navigate to series detail screen
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening series: ${thread.title}'),
        backgroundColor: const Color.fromARGB(255, 118, 41, 195),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _viewAllProjects() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProjectsScreen(
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );
  }

  void _viewUserThreads() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProjectsScreen(
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );
  }

  void _showOptionsMenu(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    
    // Only show logout if this is the current user's profile
    final isCurrentUser = currentUser?.id == widget.userId;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCurrentUser) ...[
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                ),
                onTap: () async {
                  Navigator.pop(context); // Close bottom sheet
                  
                  // Show confirmation dialog
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Logout'),
                      content: const Text('Are you sure you want to logout?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Logout'),
                        ),
                      ],
                    ),
                  );
                  
                  if (confirmed == true) {
                    await authService.logout();
                    if (mounted) {
                      // Navigate back to root and let AuthWrapper handle showing login
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  }
                },
              ),
              const Divider(),
            ],
            ListTile(
              leading: const Icon(Icons.share, color: Color(0xFF374151)),
              title: const Text('Share Profile'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Share profile feature coming soon')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.report, color: Color(0xFF374151)),
              title: const Text('Report User'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Report feature coming soon')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
} 