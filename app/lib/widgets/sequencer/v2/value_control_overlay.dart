import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../state/sequencer_state.dart';

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

class ValueControlOverlay extends StatelessWidget {
  const ValueControlOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: sequencer.sliderInteractionNotifier,
          builder: (context, isInteracting, child) {
            if (!isInteracting) {
              return const SizedBox.shrink();
            }

            return Stack(
              children: [
                // Dark overlay background
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.6),
                  ),
                ),
                
                // Value display overlay
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40.0,
                        vertical: 30.0,
                      ),
                      decoration: BoxDecoration(
                        color: SequencerPhoneBookColors.surfaceBase.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: SequencerPhoneBookColors.border,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: SequencerPhoneBookColors.shadow.withOpacity(0.8),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: SequencerPhoneBookColors.surfaceRaised.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Setting name
                          ValueListenableBuilder<String>(
                            valueListenable: sequencer.sliderSettingNotifier,
                            builder: (context, setting, child) {
                              return Text(
                                setting,
                                style: GoogleFonts.sourceSans3(
                                  color: SequencerPhoneBookColors.lightText,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 1.0,
                                ),
                              );
                            },
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Value display
                          ValueListenableBuilder<String>(
                            valueListenable: sequencer.sliderValueNotifier,
                            builder: (context, value, child) {
                              return Text(
                                value,
                                style: GoogleFonts.sourceSans3(
                                  color: SequencerPhoneBookColors.accent,
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2.0,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
} 