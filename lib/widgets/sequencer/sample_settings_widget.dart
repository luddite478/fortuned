import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sequencer_state.dart';
import 'sound_settings.dart';

class SampleSettingsWidget extends StatelessWidget {
  const SampleSettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        final sampleWidget = CellOrSampleSettingsWidget.forSample();
        return CellOrSampleSettingsWidget(
          type: sampleWidget.type,
          title: sampleWidget.title,
          headerButtons: sampleWidget.headerButtons,
          infoTextBuilder: sampleWidget.infoTextBuilder,
          hasDataChecker: sampleWidget.hasDataChecker,
          indexProvider: sampleWidget.indexProvider,
          volumeGetter: sampleWidget.volumeGetter,
          volumeSetter: sampleWidget.volumeSetter,
          pitchGetter: sampleWidget.pitchGetter,
          pitchSetter: sampleWidget.pitchSetter,
          deleteActionProvider: sampleWidget.deleteActionProvider,
          closeAction: () => sequencer.setShowSampleSettings(false),
          noDataMessage: sampleWidget.noDataMessage,
          noDataIcon: sampleWidget.noDataIcon,
          showDeleteButton: sampleWidget.showDeleteButton,
          showCloseButton: sampleWidget.showCloseButton,
        );
      },
    );
  }
} 