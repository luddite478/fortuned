import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state/sequencer_state.dart';
import 'recording_widget.dart';
import 'sample_selection_widget.dart';
import 'share_widget.dart';
import 'sample_settings_widget.dart';
import 'cell_settings_widget.dart';

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

class MultitaskPanelWidget extends StatelessWidget {
  const MultitaskPanelWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencerState, child) {
        // Priority order: sample selection > cell settings > sample settings > share > recording > placeholder
        if (sequencerState.isSelectingSample) {
          // Show sample selection widget (highest priority)
          return const SampleSelectionWidget();
        } else if (sequencerState.isShowingCellSettings) {
          // Show cell settings widget
          return const CellSettingsWidget();
        } else if (sequencerState.isShowingSampleSettings) {
          // Show sample settings widget
          return const SampleSettingsWidget();
        } else if (sequencerState.isShowingShareWidget) {
          // Show share widget
          return const ShareWidget();
        } else if (sequencerState.lastRecordingPath != null) {
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
      decoration: BoxDecoration(
        color: SequencerPhoneBookColors.surfaceRaised,
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: SequencerPhoneBookColors.border,
          width: 0.5,
        ),
        boxShadow: [
          // Protruding effect with multiple shadows
          BoxShadow(
            color: SequencerPhoneBookColors.shadow,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: SequencerPhoneBookColors.surfaceBase,
            blurRadius: 1,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          'Pattern ready to share',
          style: GoogleFonts.sourceSans3(
            color: SequencerPhoneBookColors.lightText,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
} 