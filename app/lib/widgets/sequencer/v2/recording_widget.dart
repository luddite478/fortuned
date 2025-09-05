import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
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
                color: Colors.black,
                borderRadius: BorderRadius.circular(borderRadius),
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
    
    // Responsive sizing calculations from available height (not total height)
    final titleHeight = availableHeight * 0.25; // 25% of available height
    final buttonAreaHeight = availableHeight * 0.55; // 55% of available height
    final statusHeight = availableHeight * 0.20; // 20% of available height
    
    final titleFontSize = (titleHeight * 0.4).clamp(8.0, double.infinity);
    final buttonSize = (buttonAreaHeight * 0.6).clamp(20.0, double.infinity);
    final iconSize = (buttonSize * 0.5).clamp(10.0, double.infinity);
    final statusFontSize = (statusHeight * 0.3).clamp(8.0, double.infinity);
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding, // Only horizontal padding like sample_banks_widget
        vertical: verticalSpacing, // Minimal vertical spacing
      ),
      child: Column(
        children: [
          // File name section
          Container(
            height: titleHeight,
            child: Center(
              child: Text(
                fileName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          
          // Buttons section
          Container(
            height: buttonAreaHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Play button
                _buildActionButton(
                  icon: Icons.play_arrow,
                  color: Colors.greenAccent,
                  size: buttonSize,
                  iconSize: iconSize,
                  onTap: () => _playRecording(recording),
                ),
                
                // Delete button  
                _buildActionButton(
                  icon: Icons.delete,
                  color: Colors.redAccent,
                  size: buttonSize,
                  iconSize: iconSize,
                  onTap: () => _showDeleteConfirmation(context, recording),
                ),
                
                // Share button
                _buildActionButton(
                  icon: Icons.share,
                  color: Colors.cyanAccent,
                  size: buttonSize,
                  iconSize: iconSize,
                  onTap: () => _shareRecording(recording.currentRecordingPath),
                ),
                
                // Convert to MP3 button
                // Convert button not available in new state yet
                _buildActionButton(
                  icon: Icons.audiotrack,
                  color: Colors.grey,
                  size: buttonSize,
                  iconSize: iconSize,
                  onTap: null,
                ),
              ],
            ),
          ),
          
          // Status section
          Container(
            height: statusHeight,
            child: _buildStatusArea(recording, statusFontSize, iconSize, horizontalPadding),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required double size,
    required double iconSize,
    VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null;
    final effectiveColor = isDisabled ? Colors.grey : color;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: effectiveColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(size * 0.2),
          border: Border.all(
            color: effectiveColor.withOpacity(0.6),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            color: effectiveColor,
            size: iconSize,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusArea(RecordingState recording, double fontSize, double iconSize, double horizontalPadding) {
    // Conversion status not implemented in new state yet
    if (false) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding * 0.5, vertical: horizontalPadding * 0.3),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(horizontalPadding * 0.5),
          border: Border.all(color: Colors.red.withOpacity(0.5), width: 1),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, color: Colors.red, size: iconSize),
              SizedBox(width: horizontalPadding * 0.3),
              Flexible(
                child: Text(
                  'Conversion failed',
                  style: TextStyle(color: Colors.red, fontSize: fontSize),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    } 
    
    if (false) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding * 0.5, vertical: horizontalPadding * 0.3),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.15),
          borderRadius: BorderRadius.circular(horizontalPadding * 0.5),
          border: Border.all(color: Colors.orange.withOpacity(0.5), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Progress bar
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                child: LinearProgressIndicator(
                  value: 0.0,
                  backgroundColor: Colors.orange.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  minHeight: iconSize * 0.3,
                ),
              ),
            ),
            
            SizedBox(height: horizontalPadding * 0.2),
            
            // Progress text
            Expanded(
              flex: 2,
              child: Text(
                'Converting: 0%',
                style: TextStyle(color: Colors.orange, fontSize: fontSize),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
    
    if (false) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding * 0.5, vertical: horizontalPadding * 0.3),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.15),
          borderRadius: BorderRadius.circular(horizontalPadding * 0.5),
          border: Border.all(color: Colors.green.withOpacity(0.5), width: 1),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: iconSize),
              SizedBox(width: horizontalPadding * 0.3),
              Text(
                'MP3 Ready',
                style: TextStyle(color: Colors.green, fontSize: fontSize),
              ),
            ],
          ),
        ),
      );
    }
    
    // Empty status area
    return Container();
  }

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
    // TODO: Move to a shared service; kept minimal here
    try {
      if (filePath == null) return;
      // No dependency here to Share; widget may not import share_plus
      debugPrint('Share recording: $filePath');
    } catch (e) {
      debugPrint('Failed to share recording: $e');
    }
  }
} 