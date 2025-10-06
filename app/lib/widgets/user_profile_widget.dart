import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/users_service.dart';
import '../utils/app_colors.dart';
import '../models/playlist_item.dart';
import '../models/thread/message.dart';
import '../state/audio_player_state.dart';

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
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

      // Load user profile
      final profile = await UsersService.getUserProfile(widget.userId);

      setState(() {
        _userProfile = profile;
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


  Widget _buildPlaylistsTab() {
    final playlist = _userProfile?.playlist ?? [];
    
    if (playlist.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.playlist_play_outlined, color: AppColors.menuLightText, size: 48),
            const SizedBox(height: 12),
            Text(
              'No tracks in playlist',
              style: GoogleFonts.sourceSans3(
                color: AppColors.menuLightText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Consumer<AudioPlayerState>(
      builder: (context, audioPlayer, _) {
        return ListView.builder(
          itemCount: playlist.length,
          itemBuilder: (context, index) {
            final item = playlist[index];
            final isPlaying = audioPlayer.currentlyPlayingRenderId == item.id && audioPlayer.isPlaying;
            
            return ListTile(
              leading: Icon(
                Icons.music_note,
                color: AppColors.menuText,
                size: 24,
              ),
              title: Text(
                item.name,
                style: GoogleFonts.sourceSans3(
                  color: isPlaying ? AppColors.menuOnlineIndicator : AppColors.menuText,
                  fontSize: 14,
                  fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              subtitle: item.duration != null
                  ? Text(
                      _formatDuration(item.duration!),
                      style: GoogleFonts.sourceSans3(
                        color: AppColors.menuLightText,
                        fontSize: 12,
                      ),
                    )
                  : null,
              onTap: () => _playPlaylistItem(item),
            );
          },
        );
      },
    );
  }
  
  String _formatDuration(double duration) {
    final minutes = (duration / 60).floor();
    final seconds = (duration % 60).floor();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
  
  Future<void> _playPlaylistItem(PlaylistItem item) async {
    final audioPlayer = context.read<AudioPlayerState>();
    
    // Create a minimal Render object for playback
    final render = Render(
      id: item.id,
      url: item.url,
      format: item.format,
      bitrate: item.bitrate,
      duration: item.duration,
      sizeBytes: item.sizeBytes,
      createdAt: item.createdAt,
    );
    
    await audioPlayer.playRender(
      messageId: 'playlist_${item.id}',
      render: render,
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

} 