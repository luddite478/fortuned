import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../../state/sequencer_state.dart';
import '../../screens/publish_screen.dart';

class ShareWidget extends StatelessWidget {
  const ShareWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                // Top row: Publish button centered with close button
                Row(
                  children: [
                    const Spacer(),
                    
                    // Less vibrant, centered publish button
                    ElevatedButton(
                      onPressed: () => _publishProject(context, sequencer),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade600,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_upload, size: 14, color: Colors.white70),
                          SizedBox(width: 4),
                          Text(
                            'Publish',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const Spacer(),
                    
                    GestureDetector(
                      onTap: () => sequencer.setShowShareWidget(false),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.close,
                          color: Colors.grey,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // Recordings list
                Expanded(
                  child: _buildRecordingsList(context, sequencer),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecordingsList(BuildContext context, SequencerState sequencer) {
    if (sequencer.localRecordings.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.mic_off,
                color: Colors.grey,
                size: 24,
              ),
              SizedBox(height: 4),
              Text(
                'No recordings yet',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Horizontal scrollable layout similar to sample files
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: sequencer.localRecordings.asMap().entries.map((entry) {
          final index = entry.key;
          final recording = entry.value;
          final fileName = path.basename(recording);
          
          return Container(
            width: 100,
            height: double.infinity,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.green.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  // File name at top
                  Text(
                    'Take ${index + 1}',
                    style: const TextStyle(
                      color: Colors.lightGreen,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const Spacer(),
                  
                  // Horizontal row of rectangular buttons
                  Row(
                    children: [
                      // Play button - rectangular tile
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _playRecording(recording),
                          child: Container(
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.6),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.play_arrow,
                              color: Colors.green,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 4),
                      
                      // Share button - rectangular tile
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _shareSpecificRecording(context, recording),
                          child: Container(
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.blue.withOpacity(0.6),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.share,
                              color: Colors.blue,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _shareToApps(BuildContext context, SequencerState sequencer) async {
    if (sequencer.localRecordings.isEmpty) return;
    
    try {
      // Share the most recent recording
      final latestRecording = sequencer.localRecordings.last;
      final file = File(latestRecording);
      
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(latestRecording)],
          text: 'Check out my track created with NIYYA!',
          subject: 'NIYYA Track',
        );
      } else {
        _showError(context, 'Recording file not found');
      }
    } catch (e) {
      _showError(context, 'Failed to share recording: $e');
    }
  }

  void _publishProject(BuildContext context, SequencerState sequencer) {
    // Close share widget and open publish screen
    sequencer.setShowShareWidget(false);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PublishScreen(),
      ),
    );
  }

  void _playRecording(String filePath) async {
    try {
      // TODO: Implement audio playback using your audio player
      // For now, just show a placeholder message
      debugPrint('Playing recording: $filePath');
    } catch (e) {
      debugPrint('Failed to play recording: $e');
    }
  }

  void _shareSpecificRecording(BuildContext context, String filePath) async {
    try {
      final file = File(filePath);
      
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(filePath)],
          text: 'Check out my track created with NIYYA!',
          subject: 'NIYYA Track',
        );
      } else {
        _showError(context, 'Recording file not found');
      }
    } catch (e) {
      _showError(context, 'Failed to share recording: $e');
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }
} 