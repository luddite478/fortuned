import 'package:flutter/material.dart';
// duplicate import removed
import 'package:provider/provider.dart';
import '../../../state/sequencer/multitask_panel.dart';
import '../../../state/sequencer/recording.dart';
import 'recording_widget.dart';
import 'sample_selection_widget.dart';
import 'share_widget.dart';
import 'sound_settings.dart';
import 'step_insert_settings_widget.dart';
import '../../../utils/app_colors.dart';

class MultitaskPanelWidget extends StatelessWidget {
  const MultitaskPanelWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MultitaskPanelState, RecordingState>(
      builder: (context, panelState, recordingState, child) {
        switch (panelState.currentMode) {
          case MultitaskPanelMode.sampleSelection:
            return const SampleSelectionWidget();
          
          case MultitaskPanelMode.cellSettings:
            final cellSettings = SoundSettingsWidget.forCell();
            return SoundSettingsWidget(
              type: cellSettings.type,
              title: cellSettings.title,
              headerButtons: cellSettings.headerButtons,
              closeAction: () => context.read<MultitaskPanelState>().showPlaceholder(),
              noDataMessage: cellSettings.noDataMessage,
              noDataIcon: cellSettings.noDataIcon,
              showDeleteButton: cellSettings.showDeleteButton,
              showCloseButton: cellSettings.showCloseButton,
            );
          
          case MultitaskPanelMode.sampleSettings:
            final sampleSettings = SoundSettingsWidget.forSample();
            return SoundSettingsWidget(
              type: sampleSettings.type,
              title: sampleSettings.title,
              headerButtons: sampleSettings.headerButtons,
              closeAction: () => context.read<MultitaskPanelState>().showPlaceholder(),
              noDataMessage: sampleSettings.noDataMessage,
              noDataIcon: sampleSettings.noDataIcon,
              showDeleteButton: sampleSettings.showDeleteButton,
              showCloseButton: sampleSettings.showCloseButton,
            );
          
          case MultitaskPanelMode.masterSettings:
            final masterSettings = SoundSettingsWidget.forMaster();
            return SoundSettingsWidget(
              type: masterSettings.type,
              title: masterSettings.title,
              headerButtons: masterSettings.headerButtons,
              closeAction: () => context.read<MultitaskPanelState>().showPlaceholder(),
              noDataMessage: masterSettings.noDataMessage,
              noDataIcon: masterSettings.noDataIcon,
              showDeleteButton: masterSettings.showDeleteButton,
              showCloseButton: masterSettings.showCloseButton,
            );
          
          case MultitaskPanelMode.stepInsertSettings:
            return const StepInsertSettingsWidget();
          
          case MultitaskPanelMode.shareWidget:
            return const ShareWidget();
          
          case MultitaskPanelMode.recordingWidget:
            return const RecordingWidget();
          
          case MultitaskPanelMode.placeholder:
            // Always show placeholder; recording overlay is rendered above grid, not here
            return _buildPlaceholder();
        }
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 0.5,
        ),
        boxShadow: [
          // Protruding effect with multiple shadows
          BoxShadow(
            color: AppColors.sequencerShadow,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: AppColors.sequencerSurfaceBase,
            blurRadius: 1,
            offset: const Offset(0, -1),
          ),
        ],
      ),
    );
  }
} 