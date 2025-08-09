import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';import '../../../state/sequencer_state.dart';
import '../../../utils/app_colors.dart';import '../../../state/threads_state.dart';
import '../../../utils/app_colors.dart';import '../../../screens/checkpoints_screen.dart';
import '../../../utils/app_colors.dart';

class MessageBarWidget extends StatelessWidget {
  // Configuration variables for easy control
  // Container space allocation (must sum to 1.0 or less)
  static const double leftButtonContainerPercent = 0.15; // 15% of bar width
  static const double centerButtonContainerPercent = 0.7; // 65% of bar width  
  static const double rightButtonContainerPercent = 0.15; // 20% of bar width
  
  // Button positioning within containers (0.0 = left/top, 1.0 = right/bottom)
  static const double leftButtonHorizontalPosition = 0.8; // Center horizontally
  static const double centerButtonHorizontalPosition = 0.5; // Center horizontally
  static const double rightButtonHorizontalPosition = 0.5; // Center horizontally
  
  // Button sizes (as percentage of container size)
  static const double leftButtonWidthPercent = 0.9; // 80% of container width
  static const double leftButtonHeightPercent = 0.7; // 80% of container height
  static const double centerButtonWidthPercent = 1; // 90% of container width
  static const double centerButtonHeightPercent = 0.7; // 80% of container height
  static const double rightButtonSizePercent = 0.5; // 80% of container size (square)
  
  // Border radius controls
  static const double leftButtonsBorderRadiusPercent = 0.1; // 0.0 = square, 0.5 = fully round
  static const double rightButtonBorderRadiusPercent = 0.5; // 50% for perfect circle
  
  // Container background colors
  // static const Color leftContainerBackgroundColor = Color.fromARGB(255, 168, 168, 45);
  // static const Color centerContainerBackgroundColor = Color.fromARGB(255, 154, 14, 14);
  // static const Color rightContainerBackgroundColor = Color.fromARGB(255, 82, 11, 104);

  static const Color leftContainerBackgroundColor = AppColors.sequencerCellEmpty;
  static const Color centerContainerBackgroundColor = AppColors.sequencerCellEmpty;
  static const Color rightContainerBackgroundColor = Color.fromARGB(255, 67, 65, 65);
  
  // Parent container settings
  static const double parentContainerWidthPercent = 0.975; // 90% of bar width
  static const double parentContainerHeightPercent = 1; // 100% of bar height
  static const Color parentContainerBackgroundColor = Color.fromARGB(255, 255, 3, 3);
  static const double parentContainerBorderRadiusPercent = 0.5; // 0.0 = square, 0.5 = fully round
  
  const MessageBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4), // Removed horizontal padding
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceBase,
        border: Border(
          top: BorderSide(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Consumer2<SequencerState, ThreadsState>(
          builder: (context, sequencerState, threadsState, child) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final barHeight = constraints.maxHeight;
                final barWidth = constraints.maxWidth;
                
                // Calculate container sizes
                final leftContainerWidth = barWidth * leftButtonContainerPercent;
                final centerContainerWidth = barWidth * centerButtonContainerPercent;
                final rightContainerWidth = barWidth * rightButtonContainerPercent;
                
                // Calculate button sizes
                final leftButtonWidth = leftContainerWidth * leftButtonWidthPercent;
                final leftButtonHeight = barHeight * leftButtonHeightPercent;
                final centerButtonWidth = centerContainerWidth * centerButtonWidthPercent;
                final centerButtonHeight = barHeight * centerButtonHeightPercent;
                final rightButtonSize = rightContainerWidth * rightButtonSizePercent;
                
                // Calculate border radius
                final leftBorderRadius = leftButtonHeight * leftButtonsBorderRadiusPercent;
                final rightBorderRadius = rightButtonSize * rightButtonBorderRadiusPercent;
                
                // Calculate parent container size
                final parentContainerWidth = barWidth * parentContainerWidthPercent;
                final parentContainerHeight = barHeight * parentContainerHeightPercent;
                final parentBorderRadius = parentContainerHeight * parentContainerBorderRadiusPercent;
                
                return Center(
                  child: Container(
                    width: parentContainerWidth,
                    height: parentContainerHeight,
                    decoration: BoxDecoration(
                      color: parentContainerBackgroundColor,
                      borderRadius: BorderRadius.circular(parentBorderRadius),
                    ),
                    child: Row(
                      children: [
                        // Left button container
                        Expanded(
                          flex: (leftButtonContainerPercent * 100).round(),
                          child: Container(
                            height: barHeight,
                            color: leftContainerBackgroundColor,
                            child: Align(
                              alignment: Alignment(leftButtonHorizontalPosition * 2 - 1, 0),
                              child: Container(
                                width: leftButtonWidth,
                                height: leftButtonHeight,
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(255, 57, 57, 57),
                                  borderRadius: BorderRadius.circular(leftBorderRadius),
                                  border: Border.all(
                                    color: const Color.fromARGB(255, 57, 57, 57),
                                    width: 1,
                                  ),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(leftBorderRadius),
                                    onTap: () => _navigateToCheckpoints(context, sequencerState, threadsState),
                                    child: Center(
                                      child: Icon(
                                        Icons.format_list_bulleted,
                                        color: AppColors.sequencerLightText,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        
                        // Center button container
                        Expanded(
                          flex: (centerButtonContainerPercent * 100).round(),
                          child: Container(
                            height: barHeight,
                            color: centerContainerBackgroundColor,
                            child: Align(
                              alignment: Alignment(centerButtonHorizontalPosition * 2 - 1, 0),
                              child: Container(
                                width: centerButtonWidth,
                                height: centerButtonHeight,
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(255, 53, 53, 53),
                                  borderRadius: BorderRadius.circular(leftBorderRadius),
                                  border: Border.all(
                                    color: const Color.fromARGB(255, 57, 57, 57),
                                    width: 1,
                                  ),
                                ),
                                child: Center(
                                  child: _buildSectionChain(sequencerState.numSections),
                                ),
                              ),
                            ),
                          ),
                        ),
                        
                        // Right button container
                        Expanded(
                          flex: (rightButtonContainerPercent * 100).round(),
                          child: Container(
                            height: barHeight,
                            color: rightContainerBackgroundColor,
                            child: Align(
                              alignment: Alignment(rightButtonHorizontalPosition * 2 - 1, 0),
                              child: Container(
                                width: rightButtonSize,
                                height: rightButtonSize,
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(255, 90, 111, 114),
                                  borderRadius: BorderRadius.circular(rightBorderRadius),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color.fromARGB(255, 130, 130, 130).withOpacity(0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(rightBorderRadius),
                                    onTap: () => _sendCheckpointAndNavigate(context, sequencerState, threadsState),
                                    child: Center(
                                      child: CustomPaint(
                                        size: Size(rightButtonSize * 0.4, rightButtonSize * 0.4),
                                        painter: TrianglePainter(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionChain(int numSections) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(numSections * 2 - 1, (index) {
        if (index.isEven) {
          // Square representing a section
          return Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 90, 111, 114),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: AppColors.sequencerBorder,
                width: 1,
              ),
            ),
          );
        } else {
          // Horizontal line connecting sections
          return Container(
            width: 8,
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: AppColors.sequencerLightText,
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }
      }),
    );
  }

  void _navigateToCheckpoints(BuildContext context, SequencerState sequencer, ThreadsState threadsState) {
    // Same logic as in app_header_widget.dart
    final thread = sequencer.sourceThread ?? threadsState.activeThread;
    
    if (thread != null) {
      // Set the active thread in ThreadsState so CheckpointsScreen can access it
      threadsState.setActiveThread(thread);
      
      // Navigate to checkpoints screen for this thread
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckpointsScreen(
            threadId: thread.id,
          ),
        ),
      );
    } else {
      // No active thread - show message that user needs to publish first
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Publish your project first to create checkpoints'),
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _navigateToCheckpointsWithHighlight(BuildContext context, SequencerState sequencer, ThreadsState threadsState) {
    // Same as _navigateToCheckpoints but with highlight for newest checkpoint
    final thread = sequencer.sourceThread ?? threadsState.activeThread;
    
    if (thread != null) {
      // Set the active thread in ThreadsState so CheckpointsScreen can access it
      threadsState.setActiveThread(thread);
      
      // Navigate to checkpoints screen with highlight for newest checkpoint
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckpointsScreen(
            threadId: thread.id,
            highlightNewest: true, // Flag to highlight the newest checkpoint
          ),
        ),
      );
    }
  }

  void _sendCheckpointAndNavigate(BuildContext context, SequencerState sequencer, ThreadsState threadsState) async {
    // Same save/send logic as in app_header_widget.dart but without popups
    final activeThread = threadsState.activeThread;
    final sourceThread = sequencer.sourceThread;
    
    try {
      if (sourceThread != null) {
        // Case: Sourced project - create fork with modifications (SEND)
        final success = await sequencer.createProjectFork(
          comment: 'Modified version',
          threadsService: null, // Use default threads service
        );
        
        if (success && context.mounted) {
          // Navigate to checkpoints after successful send
          _navigateToCheckpointsWithHighlight(context, sequencer, threadsState);
        }
        return; // Exit early after handling sourced project
      } else if (activeThread != null) {
        // Check if this is unpublished solo thread (SAVE) or published/collaborative (SEND)
        final isUnpublishedSolo = activeThread.users.length == 1 && 
                                 activeThread.users.first.id == threadsState.currentUserId &&
                                 !(activeThread.metadata['is_public'] ?? false);
        
        if (isUnpublishedSolo) {
          // Case: Unpublished solo thread - add checkpoint to same thread (SAVE)
          final success = await threadsState.addCheckpointFromSequencer(
            activeThread.id,
            'Saved changes',
            sequencer,
          );
          
          if (context.mounted) {
            // Navigate to checkpoints after successful save
            _navigateToCheckpointsWithHighlight(context, sequencer, threadsState);
          }
        } else {
          // Case: Published/collaborative thread - create fork or add checkpoint (SEND)
          final success = await threadsState.addCheckpointFromSequencer(
            activeThread.id,
            'New contribution',
            sequencer,
          );
          
          if (context.mounted) {
            // Navigate to checkpoints after successful send
            _navigateToCheckpointsWithHighlight(context, sequencer, threadsState);
          }
        }
      }
    } catch (e) {
      // Silent error handling - no popups
      debugPrint('Error saving checkpoint: $e');
    }
  }
}

// Custom painter for outlined triangle pointing downward
class TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color.fromARGB(255, 209, 246, 245)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path();
    
    // path.moveTo(size.width * 0.0, size.height * 0.2);
    // path.lineTo(size.width * 0.8, size.height * 1); 
    // path.lineTo(size.width * 0.8, size.height * 0.0); 
    
    // path.moveTo(size.width * 0.2, size.height * 0.2); 
    // path.lineTo(size.width * 0.5, size.height * 0.8); 
    // path.lineTo(size.width * 0.8, size.height * 0.2); 

    path.moveTo(size.width * 0.0, size.height * 0.0); // Top-left
    path.lineTo(size.width * 1, size.height * 0.5); // Middle-right (point)
    path.lineTo(size.width * 0.0, size.height * 1); // Bottom-left

    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
} 