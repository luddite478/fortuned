import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sequencer_state.dart';
import 'cell_or_sample_settings.dart';

class CellSettingsWidget extends StatelessWidget {
  const CellSettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        final cellWidget = CellOrSampleSettingsWidget.forCell();
        return CellOrSampleSettingsWidget(
          type: cellWidget.type,
          title: cellWidget.title,
          infoTextBuilder: cellWidget.infoTextBuilder,
          hasDataChecker: cellWidget.hasDataChecker,
          indexProvider: cellWidget.indexProvider,
          volumeGetter: cellWidget.volumeGetter,
          volumeSetter: cellWidget.volumeSetter,
          pitchGetter: cellWidget.pitchGetter,
          pitchSetter: cellWidget.pitchSetter,
          deleteActionProvider: cellWidget.deleteActionProvider,
          closeAction: () => sequencer.setShowCellSettings(false),
          noDataMessage: cellWidget.noDataMessage,
          noDataIcon: cellWidget.noDataIcon,
        );
      },
    );
  }
 } 