import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/users_service.dart';
import '../utils/app_colors.dart';

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

} 