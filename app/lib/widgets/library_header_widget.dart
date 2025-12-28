import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../state/audio_player_state.dart';

class LibraryHeaderWidget extends StatelessWidget {
  const LibraryHeaderWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 66, 66, 66),
        border: Border(
          bottom: BorderSide(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Left side - Back button
          IconButton(
            onPressed: () async {
              // Stop audio when navigating back to ProjectsScreen
              final audioPlayer = context.read<AudioPlayerState>();
              await audioPlayer.stop();
              Navigator.pop(context);
            },
            icon: Icon(
              Icons.arrow_back,
              color: AppColors.sequencerText,
              size: 24,
            ),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          
          // Center - Title
          const Expanded(
            child: Center(
              child: Text(
                'LIBRARY',
                style: TextStyle(
                  color: AppColors.sequencerText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
          
          // Right side - Empty space for symmetry
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}
