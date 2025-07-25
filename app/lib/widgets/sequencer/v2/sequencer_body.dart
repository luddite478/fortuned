import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../v2/sound_grid_widget.dart' as v1;
import 'sample_selection_widget.dart';
import 'sound_grid_side_control_widget.dart';
import '../../../state/sequencer_state.dart';
import 'package:flutter/material.dart';

// Body element modes for switching between different content
enum SequencerBodyMode {
  soundGrid,
  sampleSelection,
}

class SequencerBody extends StatelessWidget {
  const SequencerBody({super.key});

  // 🎯 SIZING CONFIGURATION - Easy to control layout proportions
  static const double sideControlWidthPercent = 8.0; // Each side control takes 8% of total width
  static const double soundGridWidthPercent = 84.0; // Sound grid takes 84% of total width (nearly original size)
  
  // Convert percentages to flex ratios (multiply by 10 for better precision)
  static const int sideControlFlex = 80; // 6.0 * 10 = 60
  static const int soundGridFlex = 840; // 86.0 * 10 = 860

  @override
  Widget build(BuildContext context) {
    return Selector<SequencerState, bool>(
      selector: (context, state) => state.isBodyElementSampleBrowserOpen,
      builder: (context, isBodyBrowserOpen, child) {
        return isBodyBrowserOpen
            ? const SampleSelectionWidget()
            : RepaintBoundary(
                child: Selector<SequencerState, ({List<int?> currentGridSamples, Set<int> selectedCells})>(
                  selector: (context, state) => (
                    currentGridSamples: state.currentGridSamplesForSelector,
                    selectedCells: state.selectedGridCellsForSelector,
                  ),
                  builder: (context, data, child) {
                    // Use Row to place left side control, sound grid, and right side control
                    return Row(
                      children: [
                        // Left side control widget - small width
                        Expanded(
                          flex: sideControlFlex, // 6% of total width
                          child: const SoundGridSideControlWidget(side: SideControlSide.left),
                        ),
                        
                        // Sound grid - maintains nearly original size
                        Expanded(
                          flex: soundGridFlex, // 88% of total width (nearly original)
                          child: const v1.SampleGridWidget(),
                        ),
                        
                        // Right side control widget - small width  
                        Expanded(
                          flex: sideControlFlex, // 6% of total width
                          child: const SoundGridSideControlWidget(side: SideControlSide.right),
                        ),
                      ],
                    );
                  },
                ),
              );
      },
    );
  }
} 