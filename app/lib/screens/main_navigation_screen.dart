import 'package:flutter/material.dart';
import 'projects_screen.dart';
import '../utils/app_colors.dart';
import '../widgets/bottom_audio_player.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);
  
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.menuPageBackground,
      body: const ProjectsScreen(),
      bottomNavigationBar: const BottomAudioPlayer(showLoopButton: true),
    );
  }
} 