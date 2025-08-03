import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';import '../../../state/sequencer_state.dart';
import '../../../utils/app_colors.dart';import 'recording_widget.dart';
import '../../../utils/app_colors.dart';import 'sample_selection_widget.dart';
import '../../../utils/app_colors.dart';import 'share_widget.dart';
import '../../../utils/app_colors.dart';import 'sound_settings.dart';
import '../../../utils/app_colors.dart';import 'step_insert_settings_widget.dart';
import '../../../utils/app_colors.dart';

class MultitaskPanelWidget extends StatelessWidget {
  const MultitaskPanelWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencerState, child) {
        switch (sequencerState.currentPanelMode) {
          case MultitaskPanelMode.sampleSelection:
            return const SampleSelectionWidget();
          
          case MultitaskPanelMode.cellSettings:
            final cellSettings = SoundSettingsWidget.forCell();
            return SoundSettingsWidget(
              type: cellSettings.type,
              title: cellSettings.title,
              headerButtons: cellSettings.headerButtons,
              infoTextBuilder: cellSettings.infoTextBuilder,
              hasDataChecker: cellSettings.hasDataChecker,
              indexProvider: cellSettings.indexProvider,
              volumeGetter: cellSettings.volumeGetter,
              volumeSetter: cellSettings.volumeSetter,
              pitchGetter: cellSettings.pitchGetter,
              pitchSetter: cellSettings.pitchSetter,
              deleteActionProvider: cellSettings.deleteActionProvider,
              closeAction: () => sequencerState.setPanelMode(MultitaskPanelMode.placeholder),
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
              infoTextBuilder: sampleSettings.infoTextBuilder,
              hasDataChecker: sampleSettings.hasDataChecker,
              indexProvider: sampleSettings.indexProvider,
              volumeGetter: sampleSettings.volumeGetter,
              volumeSetter: sampleSettings.volumeSetter,
              pitchGetter: sampleSettings.pitchGetter,
              pitchSetter: sampleSettings.pitchSetter,
              deleteActionProvider: sampleSettings.deleteActionProvider,
              closeAction: () => sequencerState.setPanelMode(MultitaskPanelMode.placeholder),
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
              infoTextBuilder: masterSettings.infoTextBuilder,
              hasDataChecker: masterSettings.hasDataChecker,
              indexProvider: masterSettings.indexProvider,
              volumeGetter: masterSettings.volumeGetter,
              volumeSetter: masterSettings.volumeSetter,
              pitchGetter: masterSettings.pitchGetter,
              pitchSetter: masterSettings.pitchSetter,
              deleteActionProvider: masterSettings.deleteActionProvider,
              closeAction: () => sequencerState.setPanelMode(MultitaskPanelMode.placeholder),
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
          default:
            // Show recording widget if there's a recent recording, otherwise placeholder
            if (sequencerState.lastRecordingPath != null) {
              return const RecordingWidget();
            }
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
      child: Center(
        child: Text(
          'Pattern ready to share',
          style: GoogleFonts.sourceSans3(
            color: AppColors.sequencerLightText,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
} 