import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/audio_player_state.dart';
import '../utils/app_colors.dart';

class BottomAudioPlayer extends StatelessWidget {
  final bool showLoopButton;
  
  const BottomAudioPlayer({
    Key? key,
    this.showLoopButton = false,
  }) : super(key: key);

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

        // Get screen dimensions for responsive sizing
        final media = MediaQuery.of(context);
        final screenWidth = media.size.width;

        // Calculate responsive button size (between 40-48px)
        final buttonSize = (screenWidth * 0.11).clamp(40.0, 48.0);
        
        // Calculate responsive horizontal spacing (2-3% of screen width)
        final horizontalSpacing = (screenWidth * 0.025).clamp(12.0, 16.0);
        
        // Calculate responsive side padding (3-4% of screen width)
        final sidePadding = (screenWidth * 0.035).clamp(12.0, 16.0);

        return Container(
          decoration: BoxDecoration(
            color: AppColors.menuEntryBackground,
            border: Border(
              top: BorderSide(
                color: AppColors.menuBorder,
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: sidePadding,
                vertical: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Main controls row: centers of buttons aligned with slider
                  Row(
                    children: [
                      // Play/Pause button
                      GestureDetector(
                        onTap: () async {
                          if (isPlaying) {
                            await audioPlayer.pause();
                          } else {
                            await audioPlayer.resume();
                          }
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: buttonSize,
                          height: buttonSize,
                          decoration: BoxDecoration(
                            color: AppColors.menuText.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(buttonSize / 2),
                          ),
                          child: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            color: AppColors.menuPageBackground,
                            size: buttonSize * 0.42,
                          ),
                        ),
                      ),
                      SizedBox(width: horizontalSpacing),
                      // Seek bar with thumb (interactive)
                      Expanded(
                        child: SliderTheme(
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
                      ),
                      SizedBox(width: horizontalSpacing),
                      // Loop button (conditionally shown before close button)
                      if (showLoopButton) ...[
                        GestureDetector(
                          onTap: () {
                            audioPlayer.toggleLoop();
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: buttonSize,
                            height: buttonSize,
                            decoration: BoxDecoration(
                              color: audioPlayer.isLooping 
                                  ? AppColors.menuOnlineIndicator.withOpacity(0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(buttonSize / 2),
                            ),
                            child: Icon(
                              Icons.repeat,
                              color: audioPlayer.isLooping 
                                  ? AppColors.menuOnlineIndicator 
                                  : AppColors.menuLightText,
                              size: buttonSize * 0.45,
                            ),
                          ),
                        ),
                        SizedBox(width: horizontalSpacing),
                      ],
                      // Stop button aligned with slider
                      GestureDetector(
                        onTap: () async {
                          await audioPlayer.stop();
                        },
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          width: buttonSize,
                          height: buttonSize,
                          child: Center(
                            child: Icon(
                              Icons.close,
                              color: AppColors.menuText,
                              size: buttonSize * 0.42,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Time labels row
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: sidePadding * 0.5),
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
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

