import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/user_profile_service.dart';
import '../services/threads_service.dart';
import '../services/auth_service.dart';
import '../state/threads_state.dart';
import '../state/sequencer_state.dart';
import '../screens/sequencer_screen.dart';
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

  @override
  void didUpdateWidget(UserProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh profile if userId changed
    if (oldWidget.userId != widget.userId) {
      _loadUserProfile();
    }
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
        print('🔍 Loading threads for user ID: ${widget.userId}');
        threads = await ThreadsService.getUserThreads(widget.userId);
        print('📋 Found ${threads.length} threads for user ${widget.userId}');
        for (final thread in threads) {
          print('  - Thread: ${thread.title} (ID: ${thread.id})');
        }
      } catch (threadsError) {
        print('Warning: Failed to load user threads: $threadsError');
        // Continue without threads - don't fail the whole profile load
      }

      setState(() {
        _userProfile = profile;
        _userThreads = threads;
        _isLoading = false;
      });

      // Note: Common threads auto-navigation will be implemented later
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Thread> _getCommonThreads() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.id;
    
    if (currentUserId == null || _userThreads.isEmpty) return [];

    // Find common threads (threads where both current user and clicked user are participants)
    return _userThreads.where((thread) => 
      thread.hasUser(currentUserId) && thread.hasUser(widget.userId)
    ).toList();
  }

  Future<void> _checkForCommonThreadsAndNavigate() async {
    final commonThreads = _getCommonThreads();
    
    print('🔍 Found ${commonThreads.length} common threads between current user and ${widget.userName}');
    for (final thread in commonThreads) {
      print('  - Thread: ${thread.title} (ID: ${thread.id})');
    }

    if (commonThreads.isNotEmpty) {
      // Sort by updated date to get the latest thread
      commonThreads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final latestThread = commonThreads.first;
      
      print('🚀 Auto-navigating to latest common thread: ${latestThread.title}');
      
      // Set the active thread in ThreadsState before navigating
      final threadsState = Provider.of<ThreadsState>(context, listen: false);
      threadsState.setActiveThread(latestThread);
      
      // Navigate to checkpoints screen for the latest common thread
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => CheckpointsScreenWithUserContext(
            threadId: latestThread.id,
            targetUserId: widget.userId,
            targetUserName: widget.userName,
            commonThreads: commonThreads,
          ),
        ),
      );
    } else {
      print('📋 No common threads found - staying on profile with Profile button');
    }
  }

  void _viewUserProfile() {
    // Refresh the user profile and projects
    _loadUserProfile();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Refreshing profile...'),
        backgroundColor: Color.fromARGB(255, 118, 41, 195),
        duration: Duration(seconds: 1),
      ),
    );
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
          ElevatedButton(
            onPressed: _viewUserProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 118, 41, 195),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text(
              'Profile',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 16),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileHeader(),
          const SizedBox(height: 24),
          _buildPublishedProjects(),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    final profile = _userProfile!;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: profile.isOnline 
                  ? const Color.fromARGB(255, 222, 187, 255)
                  : const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(24),
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
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Name and status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  style: const TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: profile.isOnline 
                            ? const Color.fromARGB(255, 118, 41, 195)
                            : const Color(0xFF9CA3AF),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      profile.isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        color: profile.isOnline 
                            ? const Color.fromARGB(255, 118, 41, 195)
                            : const Color(0xFF9CA3AF),
                        fontSize: 12,
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
    );
  }

  Widget _buildPublishedProjects() {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.library_music_outlined,
                color: Color(0xFF374151),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Projects',
                style: TextStyle(
                  color: Color(0xFF374151),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${_userThreads.length}',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          if (_userThreads.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(
                      Icons.music_note_outlined,
                      size: 48,
                      color: Color(0xFF9CA3AF),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No projects published yet',
                      style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _userThreads.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final project = _userThreads[index];
                return _buildProjectCard(project);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildProjectCard(Thread project) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project.title,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${project.checkpoints.length}',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.history,
                size: 10,
                color: Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 8),
              Text(
                '${project.metadata['plays_num'] ?? 0}',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.play_arrow,
                size: 10,
                color: Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 8),
              Text(
                '${project.users.length}',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.group,
                size: 10,
                color: Color(0xFF9CA3AF),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _openProject(project),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF374151),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    minimumSize: const Size(0, 28),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    'Listen',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _collaborateOnProject(project),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color.fromARGB(255, 118, 41, 195),
                    side: const BorderSide(color: Color.fromARGB(255, 118, 41, 195)),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    minimumSize: const Size(0, 28),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    'Source',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openProject(Thread project) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening project: ${project.title}'),
        backgroundColor: const Color(0xFF374151),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _collaborateOnProject(Thread project) async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading project...'),
          backgroundColor: Color.fromARGB(255, 118, 41, 195),
          duration: Duration(seconds: 2),
        ),
      );

      // Load the project into sequencer
      final sequencerState = context.read<SequencerState>();
      final success = await sequencerState.loadFromThread(project.id);

      if (success && context.mounted) {
        // Navigate to sequencer screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const PatternScreen(),
          ),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load project'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
} 