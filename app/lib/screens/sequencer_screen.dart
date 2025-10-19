import 'package:flutter/material.dart';
import 'sequencer_screen_v1.dart';

/// Main sequencer screen that routes to the appropriate layout version
/// based on the selected layout in SequencerState
class PatternScreen extends StatelessWidget {
  const PatternScreen({super.key});

  @override
  Widget build(BuildContext context) => const SequencerScreenV1();
}