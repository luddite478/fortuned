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
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Use the actual constraints from parent (20% of screen height)
              final availableHeight = constraints.maxHeight;
              final availableWidth = constraints.maxWidth;
              
              // Responsive sizing based on available space
              final headerHeight = availableHeight * 0.35; // 35% for header
              final listHeight = availableHeight * 0.60; // 60% for recordings list  
              final padding = availableHeight * 0.015; // 1.5% padding
              final verticalSpacing = availableHeight * 0.01; // 1% spacing
              
              // Icon and text sizing
              final iconSize = headerHeight * 0.4;
              final fontSize = headerHeight * 0.25;
              
              return Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  children: [
                    // Top row: Publish button centered with close button
                    SizedBox(
                      height: headerHeight,
                      child: Row(
                        children: [
                          const Spacer(),
                          
                          // Responsive publish button
                          ElevatedButton(
                            onPressed: () => _publishProject(context, sequencer),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade600,
                              padding: EdgeInsets.symmetric(
                                horizontal: headerHeight * 0.25,
                                vertical: headerHeight * 0.1,
                              ),
                              minimumSize: Size(0, headerHeight * 0.7),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(headerHeight * 0.12),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cloud_upload, 
                                  size: iconSize.clamp(8.0, 14.0), 
                                  color: Colors.white70,
                                ),
                                SizedBox(width: headerHeight * 0.08),
                                Text(
                                  'Publish',
                                  style: TextStyle(
                                    fontSize: fontSize.clamp(6.0, 12.0),
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
                              padding: EdgeInsets.all(headerHeight * 0.08),
                              child: Icon(
                                Icons.close,
                                color: Colors.grey,
                                size: iconSize.clamp(10.0, 16.0),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    SizedBox(height: verticalSpacing),
                    
                    // Recordings list - constrained to fit
                    SizedBox(
                      height: listHeight,
                      child: _buildRecordingsList(context, sequencer, listHeight, availableWidth),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildRecordingsList(BuildContext context, SequencerState sequencer, double availableHeight, double availableWidth) {
    if (sequencer.localRecordings.isEmpty) {
      final emptyIconSize = availableHeight * 0.25;
      final emptyFontSize = availableHeight * 0.12;
      
      return Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(availableHeight * 0.03),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.mic_off,
                color: Colors.grey,
                size: emptyIconSize.clamp(12.0, 24.0),
              ),
              SizedBox(height: availableHeight * 0.03),
              Text(
                'No recordings yet',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: emptyFontSize.clamp(6.0, 12.0),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Horizontal scrollable layout with inherited sizing
    final itemWidth = availableHeight * 0.9; // Item width based on available height
    final itemPadding = availableHeight * 0.04;
    final buttonHeight = availableHeight * 0.28;
    final titleFontSize = availableHeight * 0.1;
    final buttonIconSize = availableHeight * 0.15;
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: sequencer.localRecordings.asMap().entries.map((entry) {
          final index = entry.key;
          final recording = entry.value;
          
          return Container(
            width: itemWidth,
            height: availableHeight,
            margin: EdgeInsets.only(right: itemPadding),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.3),
              borderRadius: BorderRadius.circular(availableHeight * 0.06),
              border: Border.all(
                color: Colors.green.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(itemPadding),
              child: Column(
                children: [
                  // File name at top
                  Text(
                    'Take ${index + 1}',
                    style: TextStyle(
                      color: Colors.lightGreen,
                      fontSize: titleFontSize.clamp(6.0, 12.0),
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
                            height: buttonHeight,
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(availableHeight * 0.03),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.6),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.play_arrow,
                              color: Colors.green,
                              size: buttonIconSize.clamp(8.0, 16.0),
                            ),
                          ),
                        ),
                      ),
                      
                      SizedBox(width: itemPadding * 0.5),
                      
                      // Share button - rectangular tile
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _shareSpecificRecording(context, recording),
                          child: Container(
                            height: buttonHeight,
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(availableHeight * 0.03),
                              border: Border.all(
                                color: Colors.blue.withOpacity(0.6),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.share,
                              color: Colors.blue,
                              size: buttonIconSize.clamp(6.0, 14.0),
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