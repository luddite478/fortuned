import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/users_service.dart';
import '../services/threads_service.dart';
import '../state/threads_state.dart';
import '../screens/thread_screen.dart';
import '../utils/app_colors.dart';
import '../models/thread/thread.dart';

class UserProfileWidget extends StatefulWidget {
  final String userId;
  final String userName;
  final bool isOnline;

  const UserProfileWidget({
    Key? key,
    required this.userId,
    required this.userName,
    this.isOnline = false,
  }) : super(key: key);

  @override
  State<UserProfileWidget> createState() => _UserProfileWidgetState();
}

class _UserProfileWidgetState extends State<UserProfileWidget> with TickerProviderStateMixin {
  late TabController _tabController;
  UserProfile? _userProfile;
  List<Thread> _userThreads = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Load user profile first (required)
      final profile = await UsersService.getUserProfile(widget.userId);
      
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
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        _buildTabBar(),
        
        // Tab content
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
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _loadUserProfile,
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
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildProjectsTab(),
                        _buildPlaylistsTab(),
                        _buildSamplesTab(),
                      ],
                    ),
        ),
      ],
    );
  }



  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.menuEntryBackground,
        border: Border(
          bottom: BorderSide(
            color: AppColors.menuBorder,
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'PROJECTS'),
          Tab(text: 'PLAYLISTS'),
          Tab(text: 'SAMPLES'),
        ],
        labelColor: AppColors.menuText,
        unselectedLabelColor: AppColors.menuLightText,
        labelStyle: GoogleFonts.sourceSans3(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
        unselectedLabelStyle: GoogleFonts.sourceSans3(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.5,
        ),
        indicatorColor: AppColors.menuText,
        indicatorWeight: 2,
      ),
    );
  }

  Widget _buildProjectsTab() {
    if (_userThreads.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_outlined, color: AppColors.menuLightText, size: 48),
            const SizedBox(height: 12),
            Text(
              'No projects yet',
              style: GoogleFonts.sourceSans3(
                color: AppColors.menuLightText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _userThreads.length,
      itemBuilder: (context, index) {
        return _buildProjectTile(_userThreads[index]);
      },
    );
  }

  Widget _buildProjectTile(Thread project) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.menuEntryBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.menuBorder,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Project header
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatProjectTimestamp(project.updatedAt),
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.menuLightText,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Project ${project.id.substring(0, 8)}',
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.menuText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Source button
                OutlinedButton(
                  onPressed: () => _collaborateOnProject(project),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.menuText,
                    side: BorderSide(color: AppColors.menuText),
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    minimumSize: const Size(0, 28),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    'Source',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          // Renders section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.menuPageBackground,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: Text(
              'Renders: 0', // Keep empty for now as requested
              style: GoogleFonts.sourceSans3(
                color: AppColors.menuLightText,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.playlist_play_outlined, color: AppColors.menuLightText, size: 48),
          const SizedBox(height: 12),
          Text(
            'Coming soon',
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuLightText,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSamplesTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_music_outlined, color: AppColors.menuLightText, size: 48),
          const SizedBox(height: 12),
          Text(
            'Coming soon',
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuLightText,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatProjectTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _collaborateOnProject(Thread project) async {
    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Loading project...'),
            backgroundColor: AppColors.menuText,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Load the thread and navigate to thread screen
      final threadsState = context.read<ThreadsState>();
      await threadsState.loadThread(project.id);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ThreadScreen(threadId: project.id),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.menuErrorColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
} 