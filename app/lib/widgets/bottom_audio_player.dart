import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/audio_player_state.dart';
import '../utils/app_colors.dart';

class BottomAudioPlayer extends StatelessWidget {
  const BottomAudioPlayer({Key? key}) : super(key: key);

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioPlayerState>(
      builder: (context, audioPlayer, _) {
        // Only show if something is loaded (playing or paused)
        if (audioPlayer.currentlyPlayingMessageId == null && 
            audioPlayer.currentlyPlayingRenderId == null) {
          return const SizedBox.shrink();
        }

        final isPlaying = audioPlayer.isPlaying;
        final position = audioPlayer.position;
        final duration = audioPlayer.duration;

        return Container(
          height: 70,
          decoration: BoxDecoration(
            color: AppColors.menuEntryBackground,
            border: Border(
              top: BorderSide(
                color: AppColors.menuBorder,
                width: 1,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Play/Pause button
                GestureDetector(
                  onTap: () async {
                    // Access audio player state to trigger play/pause
                    if (isPlaying) {
                      audioPlayer.pause();
                    } else {
                      // If at or near end, restart from beginning
                      if (duration.inMilliseconds > 0 && 
                          position.inMilliseconds >= duration.inMilliseconds - 100) {
                        await audioPlayer.seek(Duration.zero);
                      }
                      await audioPlayer.resume();
                    }
                  },
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
                
                const SizedBox(width: 16),
                
                // Seek bar with thumb (interactive)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: AppColors.menuText.withOpacity(0.7),
                          inactiveTrackColor: AppColors.menuBorder.withOpacity(0.3),
                          thumbColor: AppColors.menuText,
                          overlayColor: AppColors.menuText.withOpacity(0.1),
                        ),
                        child: Slider(
                          value: duration.inMilliseconds > 0
                              ? position.inMilliseconds.toDouble()
                              : 0.0,
                          min: 0.0,
                          max: duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
                          onChanged: (value) async {
                            await audioPlayer.seek(Duration(milliseconds: value.toInt()));
                          },
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Time labels
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(position),
                              style: GoogleFonts.sourceSans3(
                                color: AppColors.menuLightText,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: GoogleFonts.sourceSans3(
                                color: AppColors.menuLightText,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // Stop button
                GestureDetector(
                  onTap: () async {
                    await audioPlayer.stop();
                  },
                  child: Icon(
                    Icons.close,
                    color: AppColors.menuText,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

