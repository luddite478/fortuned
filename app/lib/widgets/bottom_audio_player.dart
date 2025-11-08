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
  
  IconData _getLoopIcon(LoopMode mode) {
    switch (mode) {
      case LoopMode.single:
        return Icons.repeat_one;
      case LoopMode.playlist:
        return Icons.repeat;
      case LoopMode.off:
        return Icons.repeat;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioPlayerState>(
      builder: (context, audioPlayer, _) {
        if (audioPlayer.currentlyPlayingMessageId == null && 
            audioPlayer.currentlyPlayingRenderId == null) {
          return const SizedBox.shrink();
        }

        final isPlaying = audioPlayer.isPlaying;
        final position = audioPlayer.position;
        final duration = audioPlayer.duration;
        final loopMode = audioPlayer.loopMode;
        final shuffleEnabled = audioPlayer.shuffleEnabled;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.menuEntryBackground,
            border: Border(
              top: BorderSide(color: AppColors.menuBorder, width: 1),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress bar with time labels
                  Row(
                    children: [
                      Text(
                        _formatDuration(position),
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.menuLightText,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
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
                      ),
                      const SizedBox(width: 8),
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
                  const SizedBox(height: 8),
                  // Control buttons row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Shuffle button
                      IconButton(
                        icon: Icon(
                          Icons.shuffle,
                          color: shuffleEnabled
                              ? AppColors.menuOnlineIndicator
                              : AppColors.menuLightText,
                          size: 20,
                        ),
                        onPressed: () => audioPlayer.toggleShuffle(),
                        padding: EdgeInsets.zero,
                      ),
                      // Previous button
                      IconButton(
                        icon: Icon(
                          Icons.skip_previous,
                          color: AppColors.menuText,
                          size: 28,
                        ),
                        onPressed: () => audioPlayer.playPrevious(),
                        padding: EdgeInsets.zero,
                      ),
                      // Play/Pause button (larger)
                      GestureDetector(
                        onTap: () async {
                          if (isPlaying) {
                            await audioPlayer.pause();
                          } else {
                            await audioPlayer.resume();
                          }
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.menuText.withOpacity(0.8),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            color: AppColors.menuPageBackground,
                            size: 24,
                          ),
                        ),
                      ),
                      // Next button
                      IconButton(
                        icon: Icon(
                          Icons.skip_next,
                          color: AppColors.menuText,
                          size: 28,
                        ),
                        onPressed: () => audioPlayer.playNext(),
                        padding: EdgeInsets.zero,
                      ),
                      // Loop button with modes
                      IconButton(
                        icon: Icon(
                          _getLoopIcon(loopMode),
                          color: loopMode != LoopMode.off
                              ? AppColors.menuOnlineIndicator
                              : AppColors.menuLightText,
                          size: 20,
                        ),
                        onPressed: () => audioPlayer.toggleLoopMode(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
