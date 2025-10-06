import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'projects_screen.dart';
import 'library_screen.dart';
import 'network_screen.dart';
import '../utils/app_colors.dart';
import '../widgets/bottom_audio_player.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);
  
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  
  final List<Widget> _screens = [
    const ProjectsScreen(),
    const LibraryScreen(),
    const NetworkScreen(),
  ];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.menuPageBackground,
      body: _screens[_currentIndex],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BottomAudioPlayer(),
          Container(
        decoration: BoxDecoration(
          color: AppColors.menuEntryBackground,
          border: Border(
            top: BorderSide(
              color: AppColors.menuBorder,
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: AppColors.menuEntryBackground,
          selectedItemColor: AppColors.menuText,
          unselectedItemColor: AppColors.menuLightText,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: GoogleFonts.sourceSans3(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
          unselectedLabelStyle: GoogleFonts.sourceSans3(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.library_music_outlined),
              activeIcon: Icon(Icons.library_music),
              label: 'PLAY',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder_outlined),
              activeIcon: Icon(Icons.folder),
              label: 'LIBRARY',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'NETWORK',
            ),
          ],
        ),
      ),
        ],
      ),
    );
  }
} 