import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sequencer_state.dart';
import 'master_settings.dart';

class MasterSettingsWidget extends StatelessWidget {
  const MasterSettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        if (!sequencer.showMasterSettings) {
          return const SizedBox.shrink();
        }

        return MasterSettingsPanel(
          closeAction: () {
            sequencer.setShowMasterSettings(false);
          },
        );
      },
    );
  }
} 