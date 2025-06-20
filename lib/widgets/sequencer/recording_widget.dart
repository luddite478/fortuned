import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import '../../state/sequencer_state.dart';

class RecordingWidget extends StatelessWidget {
  const RecordingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencerState, child) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sequencerState.lastRecordingPath != null
                ? const Color(0xFF1f2937).withOpacity(0.9)
                : const Color(0xFF1f2937),
            borderRadius: BorderRadius.circular(8),
          ),
          child: sequencerState.lastRecordingPath != null
              ? _buildRecordingVisualization(context, sequencerState)
              : _buildPlaceholder(),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      height: 80,
      child: const Center(
        child: Text(
          'No Recording',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingVisualization(BuildContext context, SequencerState sequencerState) {
    final fileName = path.basename(sequencerState.lastRecordingPath!);
    
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with file info and action button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                                         Text(
                       'Duration: ${sequencerState.formattedRecordingDuration}',
                       style: const TextStyle(
                         color: Colors.grey,
                         fontSize: 12,
                       ),
                     ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () => _showRecordingOptionsDialog(context, sequencerState),
                tooltip: 'Recording Options',
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Conversion status and controls
          Column(
            children: [
              // Error message (if any)
              if (sequencerState.conversionError != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Conversion failed: ${sequencerState.conversionError}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              
              // Action buttons row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Convert to MP3 button
                  if (sequencerState.lastMp3Path == null && !sequencerState.isConverting)
                    _buildActionButton(
                      icon: Icons.audiotrack,
                      label: 'Convert MP3',
                      color: Colors.orangeAccent,
                      onTap: () => sequencerState.convertLastRecordingToMp3(),
                    ),
                    
                  // Play/Pause button
                  _buildActionButton(
                    icon: Icons.play_arrow,
                    label: 'Play',
                    color: Colors.greenAccent,
                    onTap: () {
                      // TODO: Implement playback
                    },
                  ),
                  
                  // Delete button
                  _buildActionButton(
                    icon: Icons.delete,
                    label: 'Delete',
                    color: Colors.redAccent,
                    onTap: () => _confirmDeleteRecording(context, sequencerState),
                  ),
                ],
              ),
              
              // Conversion progress (if converting)
              if (sequencerState.isConverting) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange, width: 1),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Converting to MP3...',
                            style: const TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: sequencerState.conversionProgress,
                        backgroundColor: Colors.grey.withOpacity(0.3),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(sequencerState.conversionProgress * 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              // MP3 ready indicator and share button
              if (sequencerState.lastMp3Path != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green, width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 16),
                          const SizedBox(width: 8),
                          const Text(
                            'MP3 Ready',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => sequencerState.shareRecordedAudioAsMp3(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.share, color: Colors.green, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                sequencerState.lastMp3Path != null ? 'Share MP3' : 'Share',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showRecordingOptionsDialog(BuildContext context, SequencerState sequencerState) {
    final fileName = path.basename(sequencerState.lastRecordingPath!);
    final hasMP3 = sequencerState.lastMp3Path != null;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1f2937),
          title: Text(
            fileName,
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.play_arrow, color: Colors.greenAccent),
                title: const Text('Play Recording', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  // TODO: Implement playback
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.audiotrack,
                  color: hasMP3 ? Colors.grey : Colors.orangeAccent,
                ),
                title: Text(
                  hasMP3 ? 'Already Converted' : 'Convert to MP3',
                  style: TextStyle(
                    color: hasMP3 ? Colors.grey : Colors.white,
                  ),
                ),
                onTap: hasMP3 ? null : () {
                  Navigator.of(context).pop();
                  if (!hasMP3 && !sequencerState.isConverting)
                    sequencerState.convertLastRecordingToMp3();
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.cyanAccent),
                title: const Text('Share', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  sequencerState.shareRecordedAudioAsMp3();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.redAccent),
                title: const Text('Delete', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  sequencerState.clearLastRecording();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close', style: TextStyle(color: Colors.cyanAccent)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteRecording(BuildContext context, SequencerState sequencerState) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1f2937),
          title: const Text('Delete Recording', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Are you sure you want to delete this recording? This action cannot be undone.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.cyanAccent)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                sequencerState.clearLastRecording();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );
  }
} 