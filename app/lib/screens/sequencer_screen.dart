import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/sequencer_state.dart';
import 'sequencer_screen_v1.dart';
import 'sequencer_screen_v2.dart';
import 'sequencer_screen_v3.dart';

/// Main sequencer screen that routes to the appropriate layout version
/// based on the selected layout in SequencerState
class PatternScreen extends StatelessWidget {
  const PatternScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<SequencerState, SequencerLayoutVersion>(
      selector: (context, state) => state.selectedLayout,
      builder: (context, selectedLayout, child) {
        debugPrint('🎯 Routing to sequencer layout: ${selectedLayout.displayName}');
        
        switch (selectedLayout) {
          case SequencerLayoutVersion.v1:
            return const SequencerScreenV1();
          case SequencerLayoutVersion.v2:
            return const SequencerScreenV2();
          case SequencerLayoutVersion.v3:
            return const SequencerScreenV3();
        }
      },
    );
  }
} 