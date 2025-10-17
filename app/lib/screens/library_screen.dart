import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/app_colors.dart';
import '../widgets/common_header_widget.dart';
import '../models/playlist_item.dart';
import '../models/thread/message.dart';
import '../state/audio_player_state.dart';
import '../state/library_state.dart';
import '../state/user_state.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({Key? key}) : super(key: key);
  
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late TabController _tabController;
  bool _isCallbackActive = false;
  
  @override
  bool get wantKeepAlive => true;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPlaylist();
    _setupAudioPlayerCallback();
    WidgetsBinding.instance.addObserver(this);
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
    if (state == AppLifecycleState.resumed && mounted) {
      _setupAudioPlayerCallback();
    } else if (state == AppLifecycleState.paused) {
      _clearAudioPlayerCallback();
    }
  }
  
  Future<void> _loadPlaylist() async {
    final userState = context.read<UserState>();
    final userId = userState.currentUser?.id;
    
    if (userId == null) return;
    
    final libraryState = context.read<LibraryState>();
    
    // Load playlist (only loads once on first call)
    await libraryState.loadPlaylist(userId: userId);
  }
  
  void _setupAudioPlayerCallback() {
    if (_isCallbackActive) return; // Don't set up if already active
    
    // Set up callback for auto-advance when track completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final audioPlayer = context.read<AudioPlayerState>();
      audioPlayer.setTrackCompletionCallback(() {
        if (mounted && _isCallbackActive) {
          _playNextTrack();
        }
      });
      _isCallbackActive = true;
    });
  }
  
  void _clearAudioPlayerCallback() {
    if (!_isCallbackActive) return;
    
    try {
      final audioPlayer = context.read<AudioPlayerState>();
      audioPlayer.setTrackCompletionCallback(null);
      _isCallbackActive = false;
    } catch (_) {}
  }
  
  void _playNextTrack() {
    final libraryState = context.read<LibraryState>();
    final audioPlayer = context.read<AudioPlayerState>();
    final playlist = libraryState.playlist;
    
    if (playlist.isEmpty) return;
    
    // Find current track index
    final currentRenderId = audioPlayer.currentlyPlayingRenderId;
    if (currentRenderId == null) return;
    
    final currentIndex = playlist.indexWhere((item) => item.id == currentRenderId);
    if (currentIndex == -1) return;
    
    // Move to next track (or just pause at the end, don't close player)
    final nextIndex = currentIndex + 1;
    if (nextIndex >= playlist.length) {
      // Just pause - keep the player visible
      audioPlayer.pause();
      return;
    }
    
    // Play next track
    final nextItem = playlist[nextIndex];
    _playPlaylistItem(nextItem);
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearAudioPlayerCallback();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
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
                  Tab(text: 'PLAYLIST'),
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
    return Consumer2<LibraryState, AudioPlayerState>(
      builder: (context, libraryState, audioPlayer, _) {
        // Show loading indicator only on initial load
        if (libraryState.isLoading && !libraryState.hasLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        
        // Show empty state
        if (libraryState.playlist.isEmpty) {
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
        
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: libraryState.playlist.length,
          itemBuilder: (context, index) {
            final item = libraryState.playlist[index];
            final isPlaying = audioPlayer.currentlyPlayingRenderId == item.id && audioPlayer.isPlaying;
        
            return Container(
              height: 60,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: isPlaying 
                    ? AppColors.menuOnlineIndicator.withOpacity(0.1)
                    : AppColors.menuEntryBackground,
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.menuBorder,
                    width: 0.5,
                  ),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _playPlaylistItem(item),
                  onLongPress: () => _showRemoveDialog(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        // Static note icon (no circle background)
                        Icon(
                          Icons.music_note,
                          color: AppColors.menuText,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        
                        // Item info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                item.name,
                                style: GoogleFonts.sourceSans3(
                                  color: AppColors.menuText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (item.duration != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _formatDuration(item.duration!),
                                  style: GoogleFonts.sourceSans3(
                                    color: AppColors.menuLightText,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        
                        const SizedBox(width: 8),
                        
                        // Share button
                        IconButton(
                          icon: Icon(
                            Icons.share,
                            color: AppColors.menuLightText,
                            size: 20,
                          ),
                          onPressed: () => _sharePlaylistItem(item),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                      ],
                    ),
                  ),
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
  
  void _showRemoveDialog(PlaylistItem item) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.menuPageBackground,
          title: Text(
            'Remove from Playlist',
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Are you sure you want to remove "${item.name}" from your playlist?',
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuLightText,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.sourceSans3(
                  color: AppColors.menuLightText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _removeFromPlaylist(item);
              },
              child: Text(
                'Remove',
                style: GoogleFonts.sourceSans3(
                  color: Colors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  
  Future<void> _removeFromPlaylist(PlaylistItem item) async {
    final userState = context.read<UserState>();
    final userId = userState.currentUser?.id;
    
    if (userId == null) return;
    
    final libraryState = context.read<LibraryState>();
    final success = await libraryState.removeFromPlaylist(
      userId: userId,
      renderId: item.id,
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Removed from playlist' : 'Failed to remove'),
          backgroundColor: success ? AppColors.menuBorder : Colors.red.shade900,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }
  
  Future<void> _sharePlaylistItem(PlaylistItem item) async {
    try {
      // Share the URL of the audio file with the item name
      await Share.share(
        item.url,
        subject: item.name,
      );
    } catch (e) {
      debugPrint('❌ Failed to share playlist item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 2),
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