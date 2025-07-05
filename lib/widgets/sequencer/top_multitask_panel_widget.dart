import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sequencer_state.dart';
import 'recording_widget.dart';
import 'sample_selection_widget.dart';
import 'share_widget.dart';
import 'sample_settings_widget.dart';
import 'cell_settings_widget.dart';

class MultitaskPanelWidget extends StatelessWidget {
  const MultitaskPanelWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencerState, child) {
        // Priority order: sample selection > cell settings > sample settings > share > recording > placeholder
        if (sequencerState.isSelectingSample) {
          // Show sample selection widget (highest priority)
          return const SampleSelectionWidget();
        } else if (sequencerState.isShowingCellSettings) {
          // Show cell settings widget
          return const CellSettingsWidget();
        } else if (sequencerState.isShowingSampleSettings) {
          // Show sample settings widget
          return const SampleSettingsWidget();
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