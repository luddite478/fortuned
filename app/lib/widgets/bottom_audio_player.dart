import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/audio_player_state.dart';
import '../utils/app_colors.dart';

class BottomAudioPlayer extends StatefulWidget {
  const BottomAudioPlayer({Key? key}) : super(key: key);

  @override
  State<BottomAudioPlayer> createState() => _BottomAudioPlayerState();
}

class _BottomAudioPlayerState extends State<BottomAudioPlayer> {
  bool _isDragging = false;
  double _dragValue = 0.0;

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

        // Use drag value when dragging, otherwise use actual position
        final displayPosition = _isDragging 
            ? Duration(milliseconds: _dragValue.toInt())
            : position;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceRaised,
            border: Border(
              top: BorderSide(color: AppColors.sequencerBorder, width: 1),
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
                        _formatDuration(displayPosition),
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.sequencerLightText,
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
                            activeTrackColor: AppColors.sequencerAccent,
                            inactiveTrackColor: AppColors.sequencerBorder.withOpacity(0.5),
                            thumbColor: AppColors.sequencerText,
                            overlayColor: AppColors.sequencerAccent.withOpacity(0.2),
                          ),
                          child: Slider(
                            value: duration.inMilliseconds > 0
                                ? (_isDragging ? _dragValue : position.inMilliseconds.toDouble())
                                : 0.0,
                            min: 0.0,
                            max: duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
                            onChangeStart: (value) {
                              setState(() {
                                _isDragging = true;
                                _dragValue = value;
                              });
                            },
                            onChanged: (value) {
                              setState(() {
                                _dragValue = value;
                              });
                            },
                            onChangeEnd: (value) async {
                              await audioPlayer.seek(Duration(milliseconds: value.toInt()));
                              setState(() {
                                _isDragging = false;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDuration(duration),
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.sequencerLightText,
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
                              ? AppColors.sequencerAccent
                              : AppColors.sequencerLightText,
                          size: 20,
                        ),
                        onPressed: () => audioPlayer.toggleShuffle(),
                        padding: EdgeInsets.zero,
                      ),
                      // Previous button
                      IconButton(
                        icon: Icon(
                          Icons.skip_previous,
                          color: AppColors.sequencerText,
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
                            color: AppColors.sequencerAccent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            color: AppColors.sequencerPageBackground,
                            size: 24,
                          ),
                        ),
                      ),
                      // Next button
                      IconButton(
                        icon: Icon(
                          Icons.skip_next,
                          color: AppColors.sequencerText,
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
                              ? AppColors.sequencerAccent
                              : AppColors.sequencerLightText,
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
