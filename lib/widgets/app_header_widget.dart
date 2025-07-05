import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/sequencer_state.dart';
import '../state/threads_state.dart';
import '../screens/checkpoints_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFF111827),
      foregroundColor: Colors.white,
      elevation: 0,
      leading: onBack != null 
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.orangeAccent),
              onPressed: onBack,
              iconSize: 20,
            )
          : null,
      title: _buildTitle(context),
      actions: _buildActions(context),
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (subtitle != null || thread != null)
                  Text(
                    subtitle ?? '${thread?.users.length ?? 0} collaborators • ${thread?.checkpoints.length ?? 0} checkpoints',
                    style: TextStyle(
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
    return [
      // Checkpoints menu button
      Consumer2<SequencerState, ThreadsState>(
        builder: (context, sequencer, threadsState, child) {
          // Always show in sequencer mode - if no thread exists, we'll handle it in navigation
          return IconButton(
            icon: const Icon(
              Icons.format_list_bulleted, // 3 horizontal lines with dots
              color: Colors.orangeAccent,
            ),
            onPressed: () => _navigateToCheckpoints(context, sequencer, threadsState),
            iconSize: 18,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          );
        },
      ),
      

      
      // Save/Send button (always visible, context-aware icon)
      Consumer2<SequencerState, ThreadsState>(
        builder: (context, sequencer, threadsState, child) {
          // Check thread context for Save vs Send
          final activeThread = threadsState.activeThread;
          final sourceThread = sequencer.sourceThread;
          
          // Show SEND icon when:
          // 1. There's a sourceThread (working on someone else's project)
          // 2. There's an active thread with more than 1 user (collaborative thread)
          bool showSendIcon = false;
          
          if (sourceThread != null) {
            // Case 1: Working on a sourced project - always show SEND
            showSendIcon = true;
          } else if (activeThread != null && activeThread.users.length > 1) {
            // Case 2: Collaborative thread - show SEND
            showSendIcon = true;
          }
          
          // Show SAVE icon for:
          // - No active thread (new/unpublished project)
          // - Unpublished solo thread (only current user, not public)
          
          return IconButton(
            icon: Icon(
              showSendIcon ? Icons.send : Icons.save,
              color: Colors.orangeAccent,
            ),
            onPressed: () => _sendCheckpoint(context, sequencer, threadsState),
            iconSize: 18,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          );
        },
      ),
      
      // Share button (only recordings menu)
      Consumer<SequencerState>(
        builder: (context, sequencer, child) {
          return TextButton(
            onPressed: () => sequencer.setShowShareWidget(!sequencer.isShowingShareWidget),
            child: Text(
              'Share',
              style: TextStyle(
                color: sequencer.isShowingShareWidget ? Colors.purpleAccent : Colors.purpleAccent.withOpacity(0.7),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          );
        },
      ),
      
      // Combined recording + sequencer controls in one Consumer
      Consumer<SequencerState>(
        builder: (context, sequencer, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Recording control - compact version
              if (sequencer.isRecording) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        sequencer.formattedRecordingDuration,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 8,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 1),
              ],
              
              // Recording button
              IconButton(
                icon: Icon(
                  sequencer.isRecording ? Icons.stop : Icons.fiber_manual_record,
                  color: Colors.red,
                ),
                onPressed: () {
                  if (sequencer.isRecording) {
                    sequencer.stopRecording();
                  } else {
                    sequencer.startRecording();
                  }
                },
                iconSize: 16,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              
              // Play/Stop button (changed from Play/Pause)
              IconButton(
                icon: Icon(
                  sequencer.isSequencerPlaying ? Icons.stop : Icons.play_arrow,
                  color: Colors.greenAccent,
                ),
                onPressed: () {
                  if (sequencer.isSequencerPlaying) {
                    sequencer.stopSequencer();
                  } else {
                    sequencer.startSequencer();
                  }
                },
                iconSize: 16,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          );
        },
      ),
      
      // Save checkpoint - only show when callback provided
      if (onSave != null)
        IconButton(
          icon: const Icon(Icons.save, color: Colors.amberAccent),
          onPressed: onSave,
          iconSize: 16,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
    ];
  }

  List<Widget> _buildThreadActions(BuildContext context) {
    return [
      if (showProjectInfo && onInfo != null)
        IconButton(
          icon: const Icon(Icons.info_outline),
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