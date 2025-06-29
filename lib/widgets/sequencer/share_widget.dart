import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../../state/sequencer_state.dart';
import '../../state/threads_state.dart';

class ShareWidget extends StatelessWidget {
  const ShareWidget({super.key});

  // Configurable layout percentages
  static const double _headerHeightPercent = 0.20;      // 20% for header
  static const double _publishButtonHeightPercent = 0.15; // 15% for publish button (when visible)
  static const double _recordingsHeightPercent = 0.65;   // 65% for recordings (or 80% without publish)
  static const double _paddingPercent = 0.02;            // 2% padding
  static const double _spacingPercent = 0.015;           // 1.5% spacing

  @override
  Widget build(BuildContext context) {
    return Consumer2<SequencerState, ThreadsState>(
      builder: (context, sequencer, threadsState, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.maxHeight;
              final availableWidth = constraints.maxWidth;
              
              // Show publish button if:
              // 1. No active thread (standalone sequencer mode) - can always publish
              // 2. Unpublished solo thread
              final activeThread = threadsState.activeThread;
              final canPublish = activeThread == null || 
                                (activeThread.users.length == 1 && 
                                 activeThread.users.first.id == threadsState.currentUserId &&
                                 !(activeThread.metadata['is_public'] ?? false));
              
              // Calculate heights based on percentages
              final padding = availableHeight * _paddingPercent;
              final spacing = availableHeight * _spacingPercent;
              final headerHeight = availableHeight * _headerHeightPercent;
              final publishButtonHeight = canPublish ? availableHeight * _publishButtonHeightPercent : 0.0;
              final recordingsHeight = availableHeight * (canPublish ? _recordingsHeightPercent : (_recordingsHeightPercent + _publishButtonHeightPercent));
              
              // Calculate available content height (minus padding and spacing)
              final contentHeight = availableHeight - (padding * 2);
              final usedHeight = headerHeight + publishButtonHeight + recordingsHeight + (canPublish ? spacing * 2 : spacing);
              
              // Ensure we don't overflow
              final scaleFactor = usedHeight > contentHeight ? contentHeight / usedHeight : 1.0;
              final finalHeaderHeight = headerHeight * scaleFactor;
              final finalPublishHeight = publishButtonHeight * scaleFactor;
              final finalRecordingsHeight = recordingsHeight * scaleFactor;
              final finalSpacing = spacing * scaleFactor;
              
              // Font and icon sizing based on header height
              final fontSize = finalHeaderHeight * 0.3;
              final iconSize = finalHeaderHeight * 0.4;
              
              return Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  children: [
                    // Header with title and close button
                    SizedBox(
                      height: finalHeaderHeight,
                      child: Row(
                        children: [
                          const Spacer(),
                          
                          Text(
                            'Share',
                            style: TextStyle(
                              fontSize: fontSize.clamp(8.0, 16.0),
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                          
                          const Spacer(),
                          
                          GestureDetector(
                            onTap: () => sequencer.setShowShareWidget(false),
                            child: Container(
                              padding: EdgeInsets.all(finalHeaderHeight * 0.1),
                              child: Icon(
                                Icons.close,
                                color: Colors.grey,
                                size: iconSize.clamp(12.0, 20.0),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    if (canPublish) ...[
                      SizedBox(height: finalSpacing),
                      
                      // Publish button for unpublished solo threads
                      SizedBox(
                        height: finalPublishHeight,
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _publishProject(context, sequencer),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            'Publish',
                            style: TextStyle(
                              fontSize: (finalPublishHeight * 0.35).clamp(8.0, 14.0),
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                    
                    SizedBox(height: finalSpacing),
                    
                    // Recordings list
                    SizedBox(
                      height: finalRecordingsHeight,
                      child: _buildRecordingsList(context, sequencer, finalRecordingsHeight, availableWidth),
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

  void _publishProject(BuildContext context, SequencerState sequencer) async {
    try {
      // Close share widget
      sequencer.setShowShareWidget(false);
      
      // Show loading indicator
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Publishing project...'),
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 2),
        ),
      );

      print('🚀 Starting publish process...');
      
      // Get active thread info before publishing
      final threadsState = Provider.of<ThreadsState>(context, listen: false);
      final activeThread = threadsState.activeThread;
      
      print('📋 Active thread before publish: ${activeThread?.id}');
      print('📋 Active thread checkpoints count: ${activeThread?.checkpoints.length ?? 0}');
      print('👤 Current user ID: ${threadsState.currentUserId}');
      print('👤 Current user name: ${threadsState.currentUserName}');

      // Publish to database (title will be auto-generated as 6-char ID)
      final success = await sequencer.publishToDatabase(
        description: 'Published from mobile app',
        isPublic: true,
      );
      
      print('✅ Publish result: $success');
      
      // Check active thread after publishing
      final activeThreadAfter = threadsState.activeThread;
      print('📋 Active thread after publish: ${activeThreadAfter?.id}');
      print('📋 Active thread checkpoints count after: ${activeThreadAfter?.checkpoints.length ?? 0}');
      
      if (!context.mounted) return;
      
      if (success) {
        // Refresh threads to make sure we have the latest data
        await threadsState.loadThreads();
        print('🔄 Threads refreshed after publish');
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Project published successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to publish project'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Publish error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
} 