import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../state/sequencer_state.dart';
import '../../../state/threads_state.dart';
import '../../../screens/checkpoints_screen.dart';

// Darker Gray-Beige Telephone Book Color Scheme for Sequencer
class SequencerPhoneBookColors {
  static const Color pageBackground = Color(0xFF3A3A3A); // Dark gray background
  static const Color surfaceBase = Color(0xFF4A4A47); // Gray-beige base surface
  static const Color surfaceRaised = Color(0xFF525250); // Protruding surface color
  static const Color surfacePressed = Color(0xFF424240); // Pressed/active surface
  static const Color text = Color(0xFFE8E6E0); // Light text for contrast
  static const Color lightText = Color(0xFFB8B6B0); // Muted light text
  static const Color accent = Color(0xFF8B7355); // Brown accent for highlights
  static const Color border = Color(0xFF5A5A57); // Subtle borders
  static const Color shadow = Color(0xFF4A4A47); // Dark shadows for depth
  static const Color cellEmpty = Color(0xFF3E3E3B); // Empty grid cells
  static const Color cellFilled = Color(0xFF5C5A55); // Filled grid cells
}

class MessageBarWidget extends StatelessWidget {
  const MessageBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), // Reduced vertical padding
      decoration: BoxDecoration(
        color: SequencerPhoneBookColors.surfaceBase,
        border: Border(
          top: BorderSide(
            color: SequencerPhoneBookColors.border,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Consumer2<SequencerState, ThreadsState>(
          builder: (context, sequencerState, threadsState, child) {
            return Row(
              children: [
                // Oval button to navigate to checkpoints
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16), // Slightly smaller radius
                      onTap: () => _navigateToCheckpoints(context, sequencerState, threadsState),
                      child: Container(
                        height: 32, // Smaller height
                        decoration: BoxDecoration(
                          color: SequencerPhoneBookColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: SequencerPhoneBookColors.border,
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.format_list_bulleted,
                                color: SequencerPhoneBookColors.lightText,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'View Checkpoints',
                                style: GoogleFonts.sourceSans3(
                                  fontSize: 12, // Smaller font
                                  color: SequencerPhoneBookColors.lightText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // Send button (with save/send functionality)
                Container(
                  width: 32, // Smaller size
                  height: 32,
                  decoration: BoxDecoration(
                    color: SequencerPhoneBookColors.accent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _sendCheckpointAndNavigate(context, sequencerState, threadsState),
                      child: Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 16, // Smaller icon
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
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