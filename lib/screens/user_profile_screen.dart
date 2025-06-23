import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/user_profile_service.dart';
import '../services/threads_service.dart';
import '../state/threads_state.dart';
import '../state/sequencer_state.dart';
import 'user_projects_screen.dart';
import 'sequencer_screen.dart';

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
  List<UserSeries> _userSeries = [];
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

      final profile = await UserProfileService.getUserProfile(widget.userId);
      final series = await UserProfileService.getUserSeries(widget.userId);

      setState(() {
        _userProfile = profile;
        _userSeries = series;
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
            onPressed: () {
              // TODO: Show user options menu
            },
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileHeader(),
          const SizedBox(height: 24),
          _buildSeriesSection(),
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
    if (_userSeries.isEmpty) {
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
      itemCount: _userSeries.length,
      itemBuilder: (context, index) {
        return _buildSeriesCard(_userSeries[index]);
      },
    );
  }

  Widget _buildSeriesCard(UserSeries series) {
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
          onTap: () => _openSeries(series),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // Increased vertical padding
            child: Row(
              children: [
                // Series cover with play button
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(series.coverColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _playSeries(series),
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
                
                // Series info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Date and privacy indicator
                      Row(
                        children: [
                          Text(
                            _formatDate(series.createdDate),
                            style: const TextStyle(
                              color: Color(0xFF374151),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!series.isPublic)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'Private',
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                      
                      const SizedBox(height: 3), // Reduced spacing
                      
                      // Author comment space
                      Text(
                        series.description.isNotEmpty 
                            ? series.description 
                            : 'No comment yet...',
                        style: TextStyle(
                          color: series.description.isNotEmpty 
                              ? const Color(0xFF6B7280) 
                              : const Color(0xFF9CA3AF),
                          fontSize: 11,
                          fontStyle: series.description.isEmpty 
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
                            '${_getRandomPlays(series.id)} plays',
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
                          Icon(
                            Icons.call_split,
                            size: 10,
                            color: const Color(0xFF9CA3AF),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${_getRandomForks(series.id)}',
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
                        color: _canEditSeries(series) 
                            ? const Color.fromARGB(255, 199, 195, 255) // Light purple for unlocked
                            : const Color(0xFFE5E7EB), // Light gray for locked
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _canEditSeries(series) 
                              ? () => _editSeries(series) 
                              : null,
                          borderRadius: BorderRadius.circular(6),
                          child: Center(
                            child: _canEditSeries(series)
                                ? Text(
                                    'IMPROVE',
                                    style: TextStyle(
                                      color: const Color.fromARGB(255, 80, 91, 108), // Dark gray text for light purple background
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

  bool _canEditSeries(UserSeries series) {
    // Check if series is not locked
    return !series.isLocked;
  }

  void _playSeries(UserSeries series) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎵 Playing: ${series.title}'),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _editSeries(UserSeries series) async {
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
              Text('Starting collaborative thread...'),
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
      
      // Load the sound series into sequencer state
      // Note: This assumes you have a loadProject method in SequencerState
      // If not, you might need to implement it or load the samples manually
      try {
        // For now, create a basic snapshot - you can enhance this to load actual series data
        final initialSnapshot = sequencerState.createSnapshot();
        
        // Start a new collaborative thread with the current sequencer state
        final threadId = await threadsState.startThread(
          originalProjectId: series.id,
          originalUserId: widget.userId,
          originalUserName: widget.userName,
          collaboratorUserId: currentUserId,
          collaboratorUserName: currentUserName,
          projectTitle: series.title,
          initialState: initialSnapshot,
        );
        
        print('🚀 Started collaborative thread: $threadId');
        
      } catch (seriesLoadError) {
        print('Note: Could not load series data, using current sequencer state: $seriesLoadError');
        
        // Fallback: Use current sequencer state as initial state
        final initialSnapshot = sequencerState.createSnapshot();
        
        final threadId = await threadsState.startThread(
          originalProjectId: series.id,
          originalUserId: widget.userId,
          originalUserName: widget.userName,
          collaboratorUserId: currentUserId,
          collaboratorUserName: currentUserName,
          projectTitle: series.title,
          initialState: initialSnapshot,
        );
        
        print('🚀 Started collaborative thread with fallback: $threadId');
      }
      
      // Hide loading snackbar and show success
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🚀 Started collaborative thread for "${series.title}"'),
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

  void _openSeries(UserSeries series) {
    // TODO: Navigate to series detail screen
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening series: ${series.title}'),
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
} 