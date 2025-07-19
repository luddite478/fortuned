import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../v1/sound_grid_widget.dart' as v1;
import 'sample_selection_widget.dart';
import 'sound_grid_side_control_widget.dart';
import '../../../state/sequencer_state.dart';
import 'package:flutter/material.dart';

// Body element modes for switching between different content
enum SequencerBodyMode {
  soundGrid,
  sampleSelection,
}

// Darker Gray-Beige Telephone Book Color Scheme for Sequencer
class SequencerPhoneBookColors {
  static const Color pageBackground = Color(0xFF3A3A3A); // Dark gray background
  static const Color surfaceBase = Color(0xFF4A4A47); // Gray-beige base surface
  static const Color surfaceRaised = Color(0xFF525250); // Protruding surface color
  static const Color surfacePressed = Color(0xFF424240); // Pressed/active surface
  static const Color text = Color(0xFFE8E6E0); // Light text for contrast
  static const Color lightText = Color(0xFFB8B6B0); // Muted light text
  static const Color accent = Color(0xFF8B7355); // Brown accent for highlights
  static const Color border = Color(0xFF5A5A57); // Subtle borders
  static const Color shadow = Color(0xFF2A2A2A); // Dark shadows for depth
}

class SequencerBodyElement extends StatelessWidget {
  const SequencerBodyElement({super.key});

  // 🎯 SIZING CONFIGURATION - Easy to control layout proportions
  static const double sideControlWidthPercent = 6.0; // Each side control takes 8% of total width
  static const double soundGridWidthPercent = 86.0; // Sound grid takes 84% of total width (nearly original size)
  
  // Convert percentages to flex ratios (multiply by 10 for better precision)
  static const int sideControlFlex = 60; // 6.0 * 10 = 60
  static const int soundGridFlex = 860; // 86.0 * 10 = 860

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