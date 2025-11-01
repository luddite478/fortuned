import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../state/sequencer/sample_bank.dart';
// TableState not currently used here

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
    final sampleBank = context.read<SampleBankState>();
    
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
          valueListenable: sampleBank.getSampleVolumeNotifier(sampleIndex),
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
                sampleBank.setSampleSettings(sampleIndex, volume: value);
              },
            );
          },
        ),
        
        // Volume percentage display
        ValueListenableBuilder<double>(
          valueListenable: sampleBank.getSampleVolumeNotifier(sampleIndex),
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
    final sampleBank = context.read<SampleBankState>();
    
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
          valueListenable: sampleBank.getSamplePitchNotifier(sampleIndex),
          builder: (context, pitch, child) {
            return Slider(
              value: pitch,
              min: 0.03125, // C0
              max: 32.0,    // C10
              divisions: 200,
              label: '${pitch.toStringAsFixed(2)}x',
              onChanged: (value) {
                // This call updates the ValueNotifier immediately for instant UI feedback
                sampleBank.setSampleSettings(sampleIndex, pitch: value);
              },
            );
          },
        ),
        
        // Pitch multiplier display
        ValueListenableBuilder<double>(
          valueListenable: sampleBank.getSamplePitchNotifier(sampleIndex),
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
    // TODO: wire to TableState cell overrides when available
    
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
          valueListenable: ValueNotifier<double>(1.0),
          builder: (context, volume, child) {
            return Slider(
              value: volume,
              min: 0.0,
              max: 1.0,
              divisions: 100,
              label: '${(volume * 100).round()}%',
              onChanged: (value) {
                // TODO: Wire to TableState cell volume when available
              },
            );
          },
        ),
        
        // Reset button
        const SizedBox(),
      ],
    );
  }
}

// 🎯 PERFORMANCE: Playback state indicators
class PlaybackIndicator extends StatelessWidget {
  const PlaybackIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    // Playback indicator uses external playback controls; no local state needed here
    
    return Row(
      children: [
        // Play/Stop button that only rebuilds when playback state changes
        const SizedBox(),
        
        const SizedBox(width: 16),
        
        // Step indicator that only rebuilds when current step changes
        const SizedBox(),
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
    final sampleBank = context.read<SampleBankState>();
    
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
            ValueListenableBuilder<List<bool>>(
              valueListenable: sampleBank.slotsLoadedNotifier,
              builder: (context, fileName, child) {
                final name = sampleBank.getSlotName(sampleIndex);
                return Text(
                  name ?? 'Empty',
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