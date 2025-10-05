import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../widgets/common_header_widget.dart';
import '../services/playlist_service.dart';
import '../services/audio_cache_service.dart';
import '../models/playlist_item.dart';
import '../models/thread/message.dart';
import '../state/audio_player_state.dart';
import '../services/auth_service.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({Key? key}) : super(key: key);
  
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  List<PlaylistItem> _playlist = [];
  bool _isLoading = false;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPlaylist();
  }
  
  Future<void> _loadPlaylist() async {
    final auth = context.read<AuthService>();
    final userId = auth.currentUser?.id;
    
    if (userId == null) return;
    
    setState(() => _isLoading = true);
    
    final playlist = await PlaylistService.getPlaylist(userId: userId);
    
    setState(() {
      _playlist = playlist;
      _isLoading = false;
    });
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.menuPageBackground,
      body: SafeArea(
        child: Column(
          children: [
            // User indicator at the top
            const CommonHeaderWidget(),
            
            // Tab bar
            Container(
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
            ),
            
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPlaylistsTab(),
                  _buildSamplesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildPlaylistsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_playlist.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.library_music_outlined,
              color: AppColors.menuLightText,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'Your playlist is empty',
              style: GoogleFonts.sourceSans3(
                color: AppColors.menuLightText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add audio renders from messages',
              style: GoogleFonts.sourceSans3(
                color: AppColors.menuLightText,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    
    return Consumer<AudioPlayerState>(
      builder: (context, audioPlayer, _) {
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _playlist.length,
          itemBuilder: (context, index) {
            final item = _playlist[index];
            final isPlaying = audioPlayer.currentlyPlayingRenderId == item.id && audioPlayer.isPlaying;
            final isThisTrack = audioPlayer.currentlyPlayingRenderId == item.id;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.menuEntryBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: AppColors.menuBorder,
                  width: 0.5,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                leading: GestureDetector(
                  onTap: () => _playPlaylistItem(item),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.menuText.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: AppColors.menuPageBackground,
                      size: 20,
                    ),
                  ),
                ),
                title: Text(
                  item.name,
                  style: GoogleFonts.sourceSans3(
                    color: AppColors.menuText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: item.duration != null
                    ? Text(
                        _formatDuration(item.duration!),
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.menuLightText,
                          fontSize: 11,
                        ),
                      )
                    : null,
                trailing: PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: AppColors.menuText, size: 20),
                  color: AppColors.menuEntryBackground,
                  onSelected: (value) {
                    if (value == 'remove') {
                      _removeFromPlaylist(item);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'remove',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: AppColors.menuText),
                          const SizedBox(width: 8),
                          Text(
                            'Remove from playlist',
                            style: GoogleFonts.sourceSans3(color: AppColors.menuText),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
      messageId: 'playlist', // Use 'playlist' as a special message ID
      render: render,
    );
  }
  
  Future<void> _removeFromPlaylist(PlaylistItem item) async {
    final auth = context.read<AuthService>();
    final userId = auth.currentUser?.id;
    
    if (userId == null) return;
    
    final success = await PlaylistService.removeFromPlaylist(
      userId: userId,
      renderId: item.id,
    );
    
    if (success) {
      setState(() {
        _playlist.removeWhere((i) => i.id == item.id);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed from playlist'),
            backgroundColor: AppColors.menuBorder,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Widget _buildSamplesTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_note,
            color: AppColors.menuLightText,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Samples',
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuLightText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming soon',
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuLightText,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
} 