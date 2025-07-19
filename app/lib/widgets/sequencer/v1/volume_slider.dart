import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../state/sequencer_state.dart';

// 🎯 PERFORMANCE: Volume slider using ValueListenableBuilder
// This widget only rebuilds when the specific volume value changes,
// not when any other part of SequencerState changes.

class SampleVolumeSlider extends StatelessWidget {
  final int sampleIndex;
  final String label;
  
  const SampleVolumeSlider({
    super.key,
    required this.sampleIndex,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final sequencerState = context.read<SequencerState>();
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 4),
        
        // 🎯 PERFORMANCE: Only this slider rebuilds when volume changes
        ValueListenableBuilder<double>(
          valueListenable: sequencerState.getSampleVolumeNotifier(sampleIndex),
          builder: (context, volume, child) {
            return Slider(
              value: volume,
              min: 0.0,
              max: 1.0,
              divisions: 100,
              label: '${(volume * 100).round()}%',
              onChanged: (value) {
                // This call updates the ValueNotifier immediately for instant UI feedback
                // and uses batched notifications for other widgets
                sequencerState.setSampleVolume(sampleIndex, value);
              },
            );
          },
        ),
        
        // Volume percentage display
        ValueListenableBuilder<double>(
          valueListenable: sequencerState.getSampleVolumeNotifier(sampleIndex),
          builder: (context, volume, child) {
            return Text(
              '${(volume * 100).round()}%',
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            );
          },
        ),
      ],
    );
  }
}

// 🎯 PERFORMANCE: Pitch slider using ValueListenableBuilder
class SamplePitchSlider extends StatelessWidget {
  final int sampleIndex;
  final String label;
  
  const SamplePitchSlider({
    super.key,
    required this.sampleIndex,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final sequencerState = context.read<SequencerState>();
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 4),
        
        // 🎯 PERFORMANCE: Only this slider rebuilds when pitch changes
        ValueListenableBuilder<double>(
          valueListenable: sequencerState.getSamplePitchNotifier(sampleIndex),
          builder: (context, pitch, child) {
            return Slider(
              value: pitch,
              min: 0.03125, // C0
              max: 32.0,    // C10
              divisions: 200,
              label: '${pitch.toStringAsFixed(2)}x',
              onChanged: (value) {
                // This call updates the ValueNotifier immediately for instant UI feedback
                sequencerState.setSamplePitch(sampleIndex, value);
              },
            );
          },
        ),
        
        // Pitch multiplier display
        ValueListenableBuilder<double>(
          valueListenable: sequencerState.getSamplePitchNotifier(sampleIndex),
          builder: (context, pitch, child) {
            return Text(
              '${pitch.toStringAsFixed(2)}x',
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            );
          },
        ),
      ],
    );
  }
}

// 🎯 PERFORMANCE: Cell volume slider (for individual cell overrides)
class CellVolumeSlider extends StatelessWidget {
  final int cellIndex;
  final String label;
  
  const CellVolumeSlider({
    super.key,
    required this.cellIndex,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final sequencerState = context.read<SequencerState>();
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 4),
        
        // 🎯 PERFORMANCE: Only this slider rebuilds when cell volume changes
        ValueListenableBuilder<double>(
          valueListenable: sequencerState.getCellVolumeNotifier(cellIndex),
          builder: (context, volume, child) {
            return Slider(
              value: volume,
              min: 0.0,
              max: 1.0,
              divisions: 100,
              label: '${(volume * 100).round()}%',
              onChanged: (value) {
                sequencerState.setCellVolume(cellIndex, value);
              },
            );
          },
        ),
        
        // Reset button
        ValueListenableBuilder<double>(
          valueListenable: sequencerState.getCellVolumeNotifier(cellIndex),
          builder: (context, volume, child) {
            // Show reset button if cell has a volume override
            final hasOverride = sequencerState.getCellVolume(cellIndex) != 
                               sequencerState.getSampleVolume(
                                 sequencerState.currentGridSamplesForSelector[cellIndex] ?? 0
                               );
            
            if (!hasOverride) return const SizedBox.shrink();
            
            return TextButton(
              onPressed: () => sequencerState.resetCellVolume(cellIndex),
              child: const Text('Reset', style: TextStyle(fontSize: 10)),
            );
          },
        ),
      ],
    );
  }
}

// 🎯 PERFORMANCE: Playback state indicators
class PlaybackIndicator extends StatelessWidget {
  const PlaybackIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final sequencerState = context.read<SequencerState>();
    
    return Row(
      children: [
        // Play/Stop button that only rebuilds when playback state changes
        ValueListenableBuilder<bool>(
          valueListenable: sequencerState.isSequencerPlayingNotifier,
          builder: (context, isPlaying, child) {
            return IconButton(
              onPressed: () {
                if (isPlaying) {
                  sequencerState.stopSequencer();
                } else {
                  sequencerState.startSequencer();
                }
              },
              icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
            );
          },
        ),
        
        const SizedBox(width: 16),
        
        // Step indicator that only rebuilds when current step changes
        ValueListenableBuilder<int>(
          valueListenable: sequencerState.currentStepNotifier,
          builder: (context, currentStep, child) {
            return Text(
              currentStep >= 0 ? 'Step: ${currentStep + 1}' : 'Stopped',
              style: const TextStyle(fontSize: 14, color: Colors.white),
            );
          },
        ),
      ],
    );
  }
}

// 🎯 PERFORMANCE: Example of combining multiple ValueListenableBuilders efficiently
class SampleControl extends StatelessWidget {
  final int sampleIndex;
  
  const SampleControl({
    super.key,
    required this.sampleIndex,
  });

  @override
  Widget build(BuildContext context) {
    final sequencerState = context.read<SequencerState>();
    
    return RepaintBoundary( // Isolate repaints of this control
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sample name (only rebuilds when sample bank changes)
            Selector<SequencerState, String?>(
              selector: (context, state) => state.fileNamesForSelector[sampleIndex],
              builder: (context, fileName, child) {
                return Text(
                  fileName ?? 'Empty',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                );
              },
            ),
            
            const SizedBox(height: 8),
            
            // Volume control (only rebuilds when this sample's volume changes)
            SampleVolumeSlider(
              sampleIndex: sampleIndex,
              label: 'Vol',
            ),
            
            const SizedBox(height: 8),
            
            // Pitch control (only rebuilds when this sample's pitch changes)
            SamplePitchSlider(
              sampleIndex: sampleIndex,
              label: 'Pitch',
            ),
          ],
        ),
      ),
    );
  }
} 