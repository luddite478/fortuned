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

    // Horizontal scrollable layout with inherited sizing - following sample banks pattern
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use ALL available space - no minimums, just scale everything down
        final recordingCount = sequencer.localRecordings.length;
        final availableWidth = constraints.maxWidth;
        
        // Calculate item width to fit 2.5 items visible (like sample selection shows 3.4 items)
        final itemWidth = availableWidth / 2.5; // Show 2.5 items + scrolling hint
        final itemSpacing = availableWidth * 0.02; // 2% of available width
        final itemPadding = availableHeight * 0.03;
        
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: sequencer.localRecordings.asMap().entries.map((entry) {
              final index = entry.key;
              final recording = entry.value;
              
              return Container(
                width: itemWidth,
                height: availableHeight,
                margin: EdgeInsets.only(right: index < recordingCount - 1 ? itemSpacing : 0),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(availableHeight * 0.06),
                  border: Border.all(
                    color: Colors.green.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: _buildRecordingItem(context, sequencer, recording, index, availableHeight, itemPadding),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildRecordingItem(BuildContext context, SequencerState sequencer, String recording, int index, double availableHeight, double itemPadding) {
    return LayoutBuilder(
      builder: (context, itemConstraints) {
        // Calculate layout proportions based on available height
        final titleHeight = itemConstraints.maxHeight * 0.15;      // 15% for title
        final contentHeight = itemConstraints.maxHeight * 0.70;    // 70% for main content
        final paddingHeight = itemConstraints.maxHeight * 0.15;    // 15% for padding/spacing
        
        // Content area sizing
        final buttonAreaHeight = contentHeight * 0.45;             // 45% of content for buttons
        final conversionAreaHeight = contentHeight * 0.55;         // 55% of content for conversion
        
        final fontSize = titleHeight * 0.4;
        final buttonIconSize = buttonAreaHeight * 0.5;
        final progressBarHeight = conversionAreaHeight * 0.15;
        final statusFontSize = conversionAreaHeight * 0.12;
        
        return Padding(
          padding: EdgeInsets.all(itemPadding),
          child: Column(
            children: [
              // Title section
              SizedBox(
                height: titleHeight,
                child: Center(
                  child: Text(
                    'Take ${index + 1}',
                    style: TextStyle(
                      color: Colors.lightGreen,
                      fontSize: fontSize.clamp(6.0, 12.0),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              
              SizedBox(height: paddingHeight * 0.2),
              
              // Main content section
              SizedBox(
                height: contentHeight,
                child: Column(
                  children: [
                    // Action buttons section
                    SizedBox(
                      height: buttonAreaHeight,
                      child: Row(
                        children: [
                          // Play button
                          Expanded(
                            child: _buildCompactActionButton(
                              icon: Icons.play_arrow,
                              color: Colors.green,
                              iconSize: buttonIconSize,
                              borderRadius: availableHeight * 0.02,
                              onTap: () => _playRecording(recording),
                            ),
                          ),
                          
                          SizedBox(width: itemPadding * 0.3),
                          
                          // Convert button (if not converted and not converting)
                          Expanded(
                            child: _buildCompactActionButton(
                              icon: _getConversionIcon(sequencer, recording),
                              color: _getConversionColor(sequencer, recording),
                              iconSize: buttonIconSize,
                              borderRadius: availableHeight * 0.02,
                              onTap: _canConvert(sequencer, recording) 
                                  ? () => _convertRecording(sequencer, recording) 
                                  : null,
                            ),
                          ),
                          
                          SizedBox(width: itemPadding * 0.3),
                          
                          // Share button
                          Expanded(
                            child: _buildCompactActionButton(
                              icon: Icons.share,
                              color: Colors.blue,
                              iconSize: buttonIconSize,
                              borderRadius: availableHeight * 0.02,
                              onTap: () => _shareSpecificRecording(context, recording),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    SizedBox(height: paddingHeight * 0.3),
                    
                    // Conversion status section
                    SizedBox(
                      height: conversionAreaHeight,
                      child: _buildConversionStatus(
                        sequencer, 
                        recording, 
                        progressBarHeight, 
                        statusFontSize,
                        conversionAreaHeight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactActionButton({
    required IconData icon,
    required Color color,
    required double iconSize,
    required double borderRadius,
    required VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    final effectiveColor = isEnabled ? color : color.withOpacity(0.3);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: effectiveColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: effectiveColor.withOpacity(0.6),
            width: 1,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            color: effectiveColor,
            size: iconSize.clamp(8.0, 20.0),
          ),
        ),
      ),
    );
  }

  Widget _buildConversionStatus(SequencerState sequencer, String recording, double progressBarHeight, double fontSize, double availableHeight) {
    final isConverting = sequencer.isConverting && sequencer.lastRecordingPath == recording;
    final isConverted = _hasMP3Conversion(sequencer, recording);
    final hasError = sequencer.conversionError != null && sequencer.lastRecordingPath == recording;
    
    if (hasError) {
      return _buildErrorStatus(fontSize, availableHeight);
    } else if (isConverting) {
      return _buildProgressStatus(sequencer, progressBarHeight, fontSize, availableHeight);
    } else if (isConverted) {
      return _buildCompletedStatus(fontSize, availableHeight);
    } else {
      return _buildReadyStatus(fontSize, availableHeight);
    }
  }

  Widget _buildErrorStatus(double fontSize, double availableHeight) {
    return Container(
      padding: EdgeInsets.all(availableHeight * 0.08),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(availableHeight * 0.04),
        border: Border.all(color: Colors.red.withOpacity(0.5), width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.red,
              size: (availableHeight * 0.2).clamp(8.0, 16.0),
            ),
            SizedBox(height: availableHeight * 0.05),
            Text(
              'Error',
              style: TextStyle(
                color: Colors.red,
                fontSize: fontSize.clamp(6.0, 10.0),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressStatus(SequencerState sequencer, double progressBarHeight, double fontSize, double availableHeight) {
    return Container(
      padding: EdgeInsets.all(availableHeight * 0.08),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(availableHeight * 0.04),
        border: Border.all(color: Colors.orange.withOpacity(0.5), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: (availableHeight * 0.15).clamp(8.0, 16.0),
            height: (availableHeight * 0.15).clamp(8.0, 16.0),
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
            ),
          ),
          SizedBox(height: availableHeight * 0.08),
          SizedBox(
            height: progressBarHeight.clamp(2.0, 6.0),
            child: LinearProgressIndicator(
              value: sequencer.conversionProgress,
              backgroundColor: Colors.grey.withOpacity(0.3),
              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
            ),
          ),
          SizedBox(height: availableHeight * 0.08),
          Text(
            '${(sequencer.conversionProgress * 100).toInt()}%',
            style: TextStyle(
              color: Colors.orange,
              fontSize: fontSize.clamp(6.0, 10.0),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedStatus(double fontSize, double availableHeight) {
    return Container(
      padding: EdgeInsets.all(availableHeight * 0.08),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.2),
        borderRadius: BorderRadius.circular(availableHeight * 0.04),
        border: Border.all(color: Colors.green.withOpacity(0.5), width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              color: Colors.green,
              size: (availableHeight * 0.2).clamp(8.0, 16.0),
            ),
            SizedBox(height: availableHeight * 0.05),
            Text(
              'MP3 Ready',
              style: TextStyle(
                color: Colors.green,
                fontSize: fontSize.clamp(6.0, 10.0),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadyStatus(double fontSize, double availableHeight) {
    return Container(
      padding: EdgeInsets.all(availableHeight * 0.08),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(availableHeight * 0.04),
        border: Border.all(color: Colors.grey.withOpacity(0.3), width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.audiotrack,
              color: Colors.grey,
              size: (availableHeight * 0.2).clamp(8.0, 16.0),
            ),
            SizedBox(height: availableHeight * 0.05),
            Text(
              'WAV',
              style: TextStyle(
                color: Colors.grey,
                fontSize: fontSize.clamp(6.0, 10.0),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Helper methods for conversion logic
  IconData _getConversionIcon(SequencerState sequencer, String recording) {
    if (_hasMP3Conversion(sequencer, recording)) {
      return Icons.check;
    } else if (sequencer.isConverting && sequencer.lastRecordingPath == recording) {
      return Icons.hourglass_empty;
    } else {
      return Icons.audiotrack;
    }
  }

  Color _getConversionColor(SequencerState sequencer, String recording) {
    if (_hasMP3Conversion(sequencer, recording)) {
      return Colors.green;
    } else if (sequencer.isConverting && sequencer.lastRecordingPath == recording) {
      return Colors.orange;
    } else {
      return Colors.orangeAccent;
    }
  }

  bool _canConvert(SequencerState sequencer, String recording) {
    return !_hasMP3Conversion(sequencer, recording) && 
           !(sequencer.isConverting && sequencer.lastRecordingPath == recording);
  }

  bool _hasMP3Conversion(SequencerState sequencer, String recording) {
    // Check if this recording has been converted to MP3
    // This is a simplified check - you might need to implement proper MP3 tracking per recording
    return sequencer.lastMp3Path != null && sequencer.lastRecordingPath == recording;
  }

  void _convertRecording(SequencerState sequencer, String recording) {
    // Set this as the current recording and convert
    // This might need to be enhanced to handle multiple recordings
    if (sequencer.lastRecordingPath != recording) {
      // Would need to implement per-recording conversion tracking
      debugPrint('Converting recording: $recording');
    }
    sequencer.convertLastRecordingToMp3();
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