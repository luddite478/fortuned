import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/tracker_state.dart';
import 'recording_widget.dart';
import 'sample_selection_widget.dart';

class MultitaskPanelWidget extends StatelessWidget {
  const MultitaskPanelWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TrackerState>(
      builder: (context, trackerState, child) {
        if (trackerState.isSelectingSample) {
          // Show sample selection widget
          return const SampleSelectionWidget();
        } else if (trackerState.lastRecordingPath != null) {
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
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1f2937),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
} 