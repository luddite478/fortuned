import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sequencer_state.dart';
import 'recording_widget.dart';
import 'sample_selection_widget.dart';
import 'share_widget.dart';

class MultitaskPanelWidget extends StatelessWidget {
  const MultitaskPanelWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencerState, child) {
        if (sequencerState.isSelectingSample) {
          // Show sample selection widget
          return const SampleSelectionWidget();
        } else if (sequencerState.isShowingShareWidget) {
          // Show share widget
          return const ShareWidget();
        } else if (sequencerState.lastRecordingPath != null) {
          // Show recording widget
          return const RecordingWidget();
        } else {
          // Show placeholder
          return _buildPlaceholder();
        }
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Text(
          'Pattern ready to share',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
} 