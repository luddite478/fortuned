import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'dart:math' as math;
import '../../state/tracker_state.dart';

class FuturePanelWidget extends StatelessWidget {
  const FuturePanelWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TrackerState>(
      builder: (context, trackerState, child) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1f2937),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: trackerState.lastRecordingPath != null 
                ? Colors.purpleAccent.withOpacity(0.3)
                : Colors.transparent,
              width: 1,
            ),
          ),
          child: trackerState.lastRecordingPath != null
              ? _buildRecordingVisualization(context, trackerState)
              : _buildPlaceholder(),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.graphic_eq,
            color: Colors.grey,
            size: 32,
          ),
          SizedBox(height: 8),
          Text(
            'Record your pattern\nto see it here',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingVisualization(BuildContext context, TrackerState trackerState) {
    final fileName = path.basename(trackerState.lastRecordingPath!);
    final recordingTime = trackerState.lastRecordingTime!;
    final timeAgo = DateTime.now().difference(recordingTime);

    String formatTimeAgo(Duration duration) {
      if (duration.inMinutes < 1) {
        return 'Just now';
      } else if (duration.inHours < 1) {
        return '${duration.inMinutes}m ago';
      } else if (duration.inDays < 1) {
        return '${duration.inHours}h ago';
      } else {
        return '${duration.inDays}d ago';
      }
    }

    return GestureDetector(
      onLongPress: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1f2937),
            title: const Text(
              'Clear Recording?',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'This will remove the recording from the Future Panel. The audio file will remain saved on your device.',
              style: TextStyle(color: Colors.grey),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  trackerState.clearLastRecording();
                  Navigator.pop(context);
                },
                child: const Text(
                  'Clear',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );
      },
      child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with recording info
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.audiotrack, color: Colors.purpleAccent, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'RECORDED',
                      style: TextStyle(
                        color: Colors.purpleAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                formatTimeAgo(timeAgo),
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Audio waveform visualization (simulated)
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: CustomPaint(
                painter: WaveformPainter(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          
          // Bottom row with filename and share button
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName.replaceAll('niyya_recording_', '').replaceAll('.wav', ''),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text(
                      'WAV Audio',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => trackerState.shareRecordedAudio(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.purpleAccent.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.share,
                        color: Colors.purpleAccent,
                        size: 14,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Share',
                        style: TextStyle(
                          color: Colors.purpleAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
                 ],
       ),
      ),
    );
  }
}

// Custom painter for waveform visualization
class WaveformPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.purpleAccent.withOpacity(0.6)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final centerY = size.height / 2;
    final barWidth = 2.0;
    final barSpacing = 1.0;
    final totalBars = (size.width / (barWidth + barSpacing)).floor();

    // Create a simulated waveform pattern
    for (int i = 0; i < totalBars; i++) {
      final x = i * (barWidth + barSpacing);
      
      // Generate pseudo-random height based on position
      final normalizedX = i / totalBars;
      var amplitude = 0.3;
      
      // Create some variation in the waveform
      amplitude *= (0.5 + 0.5 * (1 + math.sin(normalizedX * math.pi * 4)) / 2);
      amplitude *= (0.7 + 0.3 * (1 + math.sin(normalizedX * math.pi * 12)) / 2);
      
      final barHeight = size.height * amplitude;
      
      // Draw the bar
      canvas.drawLine(
        Offset(x + barWidth / 2, centerY - barHeight / 2),
        Offset(x + barWidth / 2, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
} 