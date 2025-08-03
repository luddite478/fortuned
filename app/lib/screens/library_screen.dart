import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/app_colors.dart';
import '../widgets/common_header_widget.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({Key? key}) : super(key: key);
  
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.album,
            color: AppColors.menuLightText,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Playlists',
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