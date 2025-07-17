import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/sequencer_state.dart';
import '../state/threads_state.dart';
import '../screens/checkpoints_screen.dart';
import '../screens/sequencer_settings_screen.dart';

// Telephone book color scheme - same as other screens
class PhoneBookColors {
  static const Color pageBackground = Color.fromARGB(255, 250, 248, 236); // Aged paper yellow
  static const Color entryBackground = Color.fromARGB(255, 251, 247, 231); // Slightly lighter
  static const Color text = Color(0xFF2C2C2C); // Dark gray/black text
  static const Color lightText = Color.fromARGB(255, 161, 161, 161); // Lighter text
  static const Color border = Color(0xFFE8E0C7); // Aged border
  static const Color onlineIndicator = Color(0xFF8B4513); // Brown instead of purple
  static const Color buttonBackground = Color.fromARGB(255, 246, 244, 226); // Khaki for main button
  static const Color buttonBorder = Color.fromARGB(255, 248, 246, 230); // Golden border
}

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
  static const Color shadow = Color(0xFF2A2A2A); // Dark shadows for depth
}

enum HeaderMode {
  checkpoints,
  sequencer,
  thread,
}

class AppHeaderWidget extends StatelessWidget implements PreferredSizeWidget {
  final HeaderMode mode;
  final String? title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onSave;
  final VoidCallback? onInfo;
  final bool showProjectInfo;

  const AppHeaderWidget({
    super.key,
    required this.mode,
    this.title,
    this.subtitle,
    this.onBack,
    this.onSave,
    this.onInfo,
    this.showProjectInfo = false,
    this.chatClient, // Add optional ChatClient parameter
  });

  final dynamic chatClient;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  bool get _isPhoneBookMode => mode == HeaderMode.checkpoints;
  bool get _isSequencerMode => mode == HeaderMode.sequencer;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _isPhoneBookMode 
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: PhoneBookColors.border,
                  width: 1,
                ),
              ),
            )
          : _isSequencerMode
              ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: SequencerPhoneBookColors.border,
                      width: 1,
                    ),
                  ),
                )
              : null,
      child: AppBar(
        backgroundColor: _isPhoneBookMode 
            ? PhoneBookColors.entryBackground 
            : _isSequencerMode 
                ? SequencerPhoneBookColors.surfaceBase
                : const Color(0xFF111827),
        foregroundColor: _isPhoneBookMode 
            ? PhoneBookColors.text 
            : _isSequencerMode 
                ? SequencerPhoneBookColors.text
                : Colors.white,
        elevation: 0,
        leading: onBack != null 
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back, 
                  color: _isPhoneBookMode 
                      ? PhoneBookColors.text 
                      : _isSequencerMode 
                          ? SequencerPhoneBookColors.text
                          : Colors.orangeAccent,
                ),
                onPressed: onBack,
                iconSize: 20,
              )
            : null,
        title: _buildTitle(context),
        actions: _buildActions(context),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    switch (mode) {
      case HeaderMode.sequencer:
        // No title for sequencer mode to save space
        return const SizedBox.shrink();
      case HeaderMode.checkpoints:
      case HeaderMode.thread:
        return Consumer<ThreadsState>(
          builder: (context, threadsState, child) {
            final thread = threadsState.currentThread;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title ?? thread?.title ?? 'Thread',
                  style: _isPhoneBookMode 
                      ? GoogleFonts.sourceSans3(
                          fontSize: 16, 
                          fontWeight: FontWeight.w700,
                          color: PhoneBookColors.text,
                          letterSpacing: 0.5,
                        )
                      : const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (subtitle != null || thread != null)
                  Text(
                    subtitle ?? '${thread?.users.length ?? 0} collaborators • ${thread?.checkpoints.length ?? 0} checkpoints',
                    style: _isPhoneBookMode
                        ? GoogleFonts.sourceSans3(
                            fontSize: 11,
                            color: PhoneBookColors.lightText,
                            fontWeight: FontWeight.w400,
                          )
                        : TextStyle(
                            fontSize: 11,
                            color: Colors.grey[300],
                          ),
                  ),
              ],
            );
          },
        );
    }
  }

  List<Widget> _buildActions(BuildContext context) {
    switch (mode) {
      case HeaderMode.sequencer:
        return _buildSequencerActions(context);
      case HeaderMode.checkpoints:
      case HeaderMode.thread:
        return _buildThreadActions(context);
    }
  }

  List<Widget> _buildSequencerActions(BuildContext context) {
    // 🎛️ MASTER SPACING CONTROL: Adjust this one variable (0.5% to 3.0% of screen width)
    final double spacingPercentage = 0; // ← Change this to control all spacing
    
    final screenWidth = MediaQuery.of(context).size.width;
    final spacingWidth = screenWidth * (spacingPercentage / 100);
    
    return [
      // Settings gear button - access to all other functions
      IconButton(
        icon: Icon(
          Icons.settings,
          color: SequencerPhoneBookColors.accent,
        ),
        onPressed: () => _navigateToSequencerSettings(context),
        iconSize: 14,
        padding: const EdgeInsets.all(2),
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      ),
      
      // Percentage-based spacing
      SizedBox(width: spacingWidth),
      
      // Checkpoints menu button
      Consumer2<SequencerState, ThreadsState>(
        builder: (context, sequencer, threadsState, child) {
          return IconButton(
            icon: Icon(
              Icons.format_list_bulleted,
              color: SequencerPhoneBookColors.accent,
            ),
            onPressed: () => _navigateToCheckpoints(context, sequencer, threadsState),
            iconSize: 14,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          );
        },
      ),
      
      // Percentage-based spacing
      SizedBox(width: spacingWidth),
      
      // Save/Send button
      Consumer2<SequencerState, ThreadsState>(
        builder: (context, sequencer, threadsState, child) {
          return IconButton(
            icon: Icon(
              Icons.save,
              color: SequencerPhoneBookColors.accent,
            ),
            onPressed: () => _sendCheckpoint(context, sequencer, threadsState),
            iconSize: 14,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          );
        },
      ),
      
      // Percentage-based spacing
      SizedBox(width: spacingWidth),
      
      // Share button
      Consumer<SequencerState>(
        builder: (context, sequencer, child) {
          return IconButton(
            icon: Icon(
              Icons.share,
              color: SequencerPhoneBookColors.accent,
            ),
            onPressed: () => sequencer.setShowShareWidget(!sequencer.isShowingShareWidget),
            iconSize: 14,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          );
        },
      ),
      
      // Percentage-based spacing
      SizedBox(width: spacingWidth),
      
      // Mix (Master Settings) button
      Consumer<SequencerState>(
        builder: (context, sequencer, child) {
          return IconButton(
            icon: Icon(
              Icons.tune,
              color: SequencerPhoneBookColors.accent,
            ),
            onPressed: () => sequencer.setShowMasterSettings(!sequencer.showMasterSettings),
            iconSize: 14,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          );
        },
      ),
      
      // Percentage-based spacing
      SizedBox(width: spacingWidth),
      
      // Recording controls - core functionality
      Consumer<SequencerState>(
        builder: (context, sequencer, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Recording status dot when recording
              if (sequencer.isRecording) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: SequencerPhoneBookColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: spacingWidth * 0.3), // Smaller spacing within controls
              ],
              
              // Recording button
              IconButton(
                icon: Icon(
                  sequencer.isRecording ? Icons.stop : Icons.fiber_manual_record,
                  color: SequencerPhoneBookColors.accent,
                ),
                onPressed: () {
                  if (sequencer.isRecording) {
                    sequencer.stopRecording();
                  } else {
                    sequencer.startRecording();
                  }
                },
                iconSize: 16,
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              
              // Smaller spacing between recording controls
              SizedBox(width: spacingWidth * 0.3),
              
              // Play/Stop button
              IconButton(
                icon: Icon(
                  sequencer.isSequencerPlaying ? Icons.stop : Icons.play_arrow,
                  color: SequencerPhoneBookColors.accent,
                ),
                onPressed: () {
                  if (sequencer.isSequencerPlaying) {
                    sequencer.stopSequencer();
                  } else {
                    sequencer.startSequencer();
                  }
                },
                iconSize: 16,
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          );
        },
      ),
    ];
  }

  List<Widget> _buildThreadActions(BuildContext context) {
    return [
      if (showProjectInfo && onInfo != null)
        IconButton(
          icon: Icon(
            Icons.info_outline,
            color: _isPhoneBookMode ? PhoneBookColors.text : Colors.white,
          ),
          onPressed: onInfo,
          iconSize: 18,
        ),
    ];
  }

  void _navigateToCheckpoints(BuildContext context, SequencerState sequencer, ThreadsState threadsState) {
    // Determine which thread to open
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

  void _navigateToSequencerSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SequencerSettingsScreen(),
      ),
    );
  }

  void _sendCheckpoint(BuildContext context, SequencerState sequencer, ThreadsState threadsState) async {
    // Determine context and create checkpoint accordingly
    final activeThread = threadsState.activeThread;
    final sourceThread = sequencer.sourceThread;
    
    try {
      if (sourceThread != null) {
        // Case: Sourced project - create fork with modifications (SEND)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Creating fork...'),
            backgroundColor: Colors.orangeAccent,
            duration: Duration(seconds: 1),
          ),
        );
        
        final success = await sequencer.createProjectFork(
          comment: 'Modified version',
          chatClient: chatClient,
        );
        
        if (success) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Fork created successfully! 🎉'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to create fork'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
        return; // Exit early after handling sourced project
      } else if (activeThread != null) {
        // Check if this is unpublished solo thread (SAVE) or published/collaborative (SEND)
        final isUnpublishedSolo = activeThread.users.length == 1 && 
                                 activeThread.users.first.id == threadsState.currentUserId &&
                                 !(activeThread.metadata['is_public'] ?? false);
        
        if (isUnpublishedSolo) {
          // Case: Unpublished solo thread - add checkpoint to same thread (SAVE)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saving checkpoint...'),
              backgroundColor: Colors.orangeAccent,
              duration: Duration(seconds: 1),
            ),
          );
          
          final success = await threadsState.addCheckpointFromSequencer(
            activeThread.id,
            'Saved changes',
            sequencer,
          );
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Checkpoint saved! 💾'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          // Case: Published/collaborative thread - create fork or add checkpoint (SEND)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Adding to collaboration...'),
              backgroundColor: Colors.orangeAccent,
              duration: Duration(seconds: 1),
            ),
          );
          
          final success = await threadsState.addCheckpointFromSequencer(
            activeThread.id,
            'New contribution',
            sequencer,
          );
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Contribution added! 📤'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        // No active thread - this shouldn't happen now with auto-creation
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No active project to save'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
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