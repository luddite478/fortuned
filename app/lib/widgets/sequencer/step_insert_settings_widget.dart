import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state/sequencer_state.dart';

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

class StepInsertSettingsWidget extends StatelessWidget {
  const StepInsertSettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        return Container(
          decoration: BoxDecoration(
            color: SequencerPhoneBookColors.surfaceBase,
            borderRadius: BorderRadius.circular(2), // Sharp corners
            border: Border.all(
              color: SequencerPhoneBookColors.border,
              width: 0.5,
            ),
            boxShadow: [
              // Protruding effect
              BoxShadow(
                color: SequencerPhoneBookColors.shadow,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: SequencerPhoneBookColors.surfaceRaised,
                blurRadius: 1,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final panelHeight = constraints.maxHeight;
              final sliderHeight = panelHeight * 0.7;
              final textHeight = panelHeight * 0.3;
              
              return Column(
                children: [
                  // Title and close button
                  Container(
                    height: textHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Step Insert: ${sequencer.stepInsertSize} steps',
                            style: GoogleFonts.sourceSans3(
                              color: SequencerPhoneBookColors.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => sequencer.setPanelMode(MultitaskPanelMode.placeholder),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              color: SequencerPhoneBookColors.lightText,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Slider
                  Container(
                    height: sliderHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          '1',
                          style: GoogleFonts.sourceSans3(
                            color: SequencerPhoneBookColors.lightText,
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: SequencerPhoneBookColors.accent,
                              inactiveTrackColor: SequencerPhoneBookColors.border,
                              thumbColor: SequencerPhoneBookColors.accent,
                              overlayColor: SequencerPhoneBookColors.accent.withOpacity(0.3),
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: sequencer.stepInsertSize.toDouble(),
                              min: 1,
                              max: 16,
                              divisions: 15,
                              onChanged: (value) {
                                sequencer.setStepInsertSize(value.round());
                              },
                            ),
                          ),
                        ),
                        Text(
                          '16',
                          style: GoogleFonts.sourceSans3(
                            color: SequencerPhoneBookColors.lightText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
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