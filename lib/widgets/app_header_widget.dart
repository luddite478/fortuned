import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/sequencer_state.dart';
import '../state/threads_state.dart';

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
  });

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
      // Share button
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
              
              // Play/Pause button
              IconButton(
                icon: Icon(
                  sequencer.isSequencerPlaying ? Icons.pause : Icons.play_arrow,
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
              
              // Stop button (only show when playing)
              if (sequencer.isSequencerPlaying)
                IconButton(
                  icon: const Icon(Icons.stop, color: Colors.redAccent),
                  onPressed: () => sequencer.stopSequencer(),
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
} 