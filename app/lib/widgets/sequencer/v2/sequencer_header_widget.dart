import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../state/sequencer/playback.dart';
import '../../../state/threads_state.dart';
import '../../../screens/sequencer_settings_screen.dart';
import '../../../screens/thread_screen.dart';
import '../../../utils/app_colors.dart';

class SequencerHeaderWidget extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onBack;
  final dynamic threadsService;

  const SequencerHeaderWidget({
    super.key,
    this.onBack,
    this.threadsService,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.menuBorder,
            width: 1,
          ),
        ),
      ),
      child: AppBar(
        backgroundColor: AppColors.sequencerSurfaceBase,
        foregroundColor: AppColors.sequencerText,
        elevation: 0,
        leading: onBack != null 
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back, 
                  color: AppColors.sequencerText,
                ),
                onPressed: onBack,
                iconSize: 20,
              )
            : null,
        title: const SizedBox.shrink(), // No title for sequencer mode to save space
        actions: _buildActions(context),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      // Settings button
      IconButton(
        icon: Icon(
          Icons.settings,
          color: AppColors.sequencerAccent,
        ),
        onPressed: () => _navigateToSequencerSettings(context),
        iconSize: 18,
        padding: const EdgeInsets.all(2),
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      ),
      
      const SizedBox(width: 4),
      
      // Thread button (3 lines without dots)
      IconButton(
        icon: Icon(
          Icons.reorder,
          color: AppColors.sequencerAccent,
        ),
        onPressed: () => _navigateToThread(context),
        iconSize: 22,
        padding: const EdgeInsets.all(2),
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      ),
      
      const SizedBox(width: 4),
      
      // Send message button (plus sign)
      IconButton(
        icon: Icon(
          Icons.add,
          color: AppColors.sequencerAccent,
        ),
        onPressed: () => _sendMessageAndNavigate(context),
        iconSize: 22,
        padding: const EdgeInsets.all(2),
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      ),
    ];
  }

  void _navigateToSequencerSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SequencerSettingsScreen(),
      ),
    );
  }

  void _navigateToThread(BuildContext context) {
    // Stop playback if active before navigating
    final playbackState = Provider.of<PlaybackState>(context, listen: false);
    if (playbackState.isPlaying) {
      playbackState.stop();
    }

    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    final thread = threadsState.activeThread;
    
    if (thread != null) {
      // Set the active thread in ThreadsState
      threadsState.setActiveThread(thread);
      
      // Navigate to thread screen for this thread
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ThreadScreen(
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

  void _sendMessageAndNavigate(BuildContext context) {
    // Stop playback if active before sending and navigating
    final playbackState = Provider.of<PlaybackState>(context, listen: false);
    if (playbackState.isPlaying) {
      playbackState.stop();
    }

    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    final activeThread = threadsState.activeThread;
    if (activeThread != null) {
      // Start upload in background (don't await)
      threadsState.sendMessageFromSequencer(threadId: activeThread.id).catchError((e) {
        // Silent error handling - status will be shown in UI
        debugPrint('Error sending message: $e');
      });
      
      // Navigate immediately
      _navigateToThreadWithHighlight(context, threadsState);
    }
  }

  void _navigateToThreadWithHighlight(BuildContext context, ThreadsState threadsState) {
    // Same as _navigateToThread but with highlight for newest checkpoint
    final thread = threadsState.activeThread;
    
    if (thread != null) {
      // Set the active thread in ThreadsState
      threadsState.setActiveThread(thread);
      
      // Navigate to thread screen with highlight for newest message
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ThreadScreen(
            threadId: thread.id,
            highlightNewest: true,
          ),
        ),
      );
    }
  }
}

