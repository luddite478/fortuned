import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import '../../../utils/app_colors.dart';
import '../../../state/sequencer/recording.dart';

class RecordingWidget extends StatelessWidget {
  const RecordingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RecordingState>(
      builder: (context, recording, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive sizes based on available space - INHERIT from parent
            final panelHeight = constraints.maxHeight;
            final panelWidth = constraints.maxWidth;
            
            // Use ALL available space - no minimums, just scale everything down
            final padding = panelHeight * 0.06; // 6% of given height
            final borderRadius = panelHeight * 0.08; // Scale with height
            
            return Container(
              decoration: BoxDecoration(
                color: AppColors.sequencerSurfaceBase,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: AppColors.sequencerBorder,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.sequencerShadow,
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: AppColors.sequencerSurfaceRaised,
                    blurRadius: 1,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: recording.currentRecordingPath != null 
                  ? _buildRecordingMenu(context, recording, panelHeight, panelWidth, padding, borderRadius)
                  : _buildEmptyState(panelHeight, panelWidth, padding, borderRadius),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(double panelHeight, double panelWidth, double padding, double borderRadius) {
    final fontSize = (panelHeight * 0.25).clamp(10.0, double.infinity);
    final verticalSpacing = panelHeight * 0.02; // Minimal vertical spacing (2%)
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding, // Only horizontal padding like sample_banks_widget  
        vertical: verticalSpacing, // Minimal vertical spacing
      ),
      child: Center(
        child: Text(
          'No Recording',
          style: TextStyle(
            color: Colors.grey,
            fontSize: fontSize,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingMenu(BuildContext context, RecordingState recording, 
      double panelHeight, double panelWidth, double padding, double borderRadius) {
    
    final fileName = path.basename(recording.currentRecordingPath ?? 'recording.wav');
    
    // Follow sample_banks_widget pattern: only horizontal padding to avoid overflow
    final horizontalPadding = padding;
    final verticalSpacing = panelHeight * 0.02; // Minimal vertical spacing (2%)
    
    // Calculate available height after minimal spacing
    final availableHeight = panelHeight - (verticalSpacing * 2); // Top and bottom spacing
    
    // Single recording layout: compact header and buttons, no list
    final titleHeight = availableHeight * 0.20;
    final buttonAreaHeight = availableHeight * 0.55;
    
    final titleFontSize = (titleHeight * 0.24).clamp(10.0, 20.0);
    final buttonSize = (buttonAreaHeight * 0.4).clamp(28.0, 56.0);
    final iconSize = (buttonSize * 0.4).clamp(12.0, 24.0);
    // final statusFontSize = (availableHeight * 0.14).clamp(8.0, 14.0);
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding, // Only horizontal padding like sample_banks_widget
        vertical: verticalSpacing, // Minimal vertical spacing
      ),
      child: Column(
        children: [
          // File name row (left title, right close)
          Container(
            height: titleHeight,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    fileName,
                    style: TextStyle(
                      color: AppColors.sequencerText,
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Consumer<RecordingState>(
                    builder: (context, rec, _) => GestureDetector(
                      onTap: rec.hideOverlay,
                      child: Container(
                        width: titleHeight * 0.6,
                        height: titleHeight * 0.6,
                        decoration: BoxDecoration(
                          color: AppColors.sequencerSurfacePressed,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.sequencerAccent.withOpacity(0.8), width: 1),
                        ),
                        child: Icon(
                          Icons.close,
                          color: AppColors.sequencerAccent,
                          size: iconSize,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Buttons section (4 compact buttons centered) for new take
          Container(
            height: buttonAreaHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSequencerButton(icon: Icons.play_arrow, onTap: () => _playRecording(recording), iconColor: Colors.greenAccent),
                SizedBox(width: horizontalPadding * 0.5),
                _buildSequencerButton(icon: Icons.delete, onTap: () => _showDeleteConfirmation(context, recording), iconColor: Colors.redAccent),
                SizedBox(width: horizontalPadding * 0.5),
                _buildSequencerButton(icon: Icons.share, onTap: () => _shareRecording(recording.currentRecordingPath), iconColor: Colors.cyanAccent),
                SizedBox(width: horizontalPadding * 0.5),
                _buildSequencerButton(icon: Icons.audiotrack, onTap: null, iconColor: Colors.grey),
              ],
            ),
          ),
          // Optional footer space to avoid cramped look
          SizedBox(height: verticalSpacing),
        ],
      ),
    );
  }

  Widget _buildSequencerButton({
    required IconData icon,
    required VoidCallback? onTap,
    required Color iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.sequencerSurfacePressed,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.sequencerBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.sequencerShadow,
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Icon(icon, color: onTap == null ? Colors.grey : iconColor, size: 20),
        ),
      ),
    );
  }

  // Removed old action button in favor of sequencer-styled button

  // Removed status area (not used)

  void _playRecording(RecordingState recording) {
    // TODO: Implement audio playback functionality
    // For now, show a placeholder message
    debugPrint('🎵 Play recording: ${recording.currentRecordingPath}');
  }

  void _showDeleteConfirmation(BuildContext context, RecordingState recording) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1f2937),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            'Delete Recording?', 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
          ),
          content: const Text(
            'This will permanently delete the recording. This action cannot be undone.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel', 
                style: TextStyle(color: Colors.cyanAccent)
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                recording.clearRecording();
              },
              child: const Text(
                'Delete', 
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)
              ),
            ),
          ],
        );
      },
    );
  }

  void _shareRecording(String? filePath) async {
    try {
      if (filePath == null) return;
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Check out my track created with NIYYA!',
        subject: 'NIYYA Track',
      );
    } catch (e) {
      debugPrint('Failed to share recording: $e');
    }
  }
} 