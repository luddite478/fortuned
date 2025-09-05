import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sequencer/playback.dart';
import '../../state/sequencer/table.dart';
import '../../utils/app_colors.dart';

/// Simplified playback controls for testing
/// 
/// Contains basic play/stop, BPM control, and song/loop mode toggle
class PlaybackControls extends StatelessWidget {
  const PlaybackControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<PlaybackState, TableState>(
      builder: (context, playback, tableState, child) {
        return Row(
          children: [
            // Play/Stop button
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: playback.isPlaying ? Colors.red : Colors.green,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: AppColors.sequencerBorder,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: playback.initialized ? () => playback.togglePlayback() : null,
                icon: Icon(
                  playback.isPlaying ? Icons.stop : Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            
            const SizedBox(width: 16),
            
            // BPM control
            Expanded(
              flex: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BPM: ${playback.bpm}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Slider(
                    value: playback.bpm.toDouble(),
                    min: 60,
                    max: 300,
                    divisions: 240,
                    onChanged: (value) {
                      playback.setBpm(value.toInt());
                    },
                    activeColor: AppColors.sequencerAccent,
                    inactiveColor: AppColors.sequencerBorder,
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Song/Loop mode toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.sequencerSurfaceRaised,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: AppColors.sequencerBorder,
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    playback.songMode ? 'Song' : 'Loop',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Switch(
                    value: playback.songMode,
                    onChanged: (value) {
                      playback.setSongMode(value);
                    },
                    activeColor: AppColors.sequencerAccent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Current step indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.sequencerSurfacePressed,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: AppColors.sequencerBorder,
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Step',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${playback.currentStep + 1}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    '/ ${tableState.getSectionStepCount()}',
                    style: const TextStyle(
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
