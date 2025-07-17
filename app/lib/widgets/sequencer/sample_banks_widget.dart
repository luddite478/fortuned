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

class SampleBanksWidget extends StatelessWidget {
  const SampleBanksWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive sizes based on available space - INHERIT from parent
            final panelHeight = constraints.maxHeight;
            final panelWidth = constraints.maxWidth;
            
            // Show 7.5 buttons (7 full + 0.5 partial) to indicate scrollability
            final availableWidth = panelWidth - 16; // Container padding
            final buttonWidth = availableWidth / 7.5; // 7.5 buttons visible
            final buttonHeight = panelHeight * 0.8; // Use 80% of given height
            final letterSize = (buttonHeight * 0.35).clamp(10.0, double.infinity); // Scale with height, min 10px
            final padding = panelHeight * 0.05; // 5% of given height
            final borderRadius = 2.0; // Sharp corners for telephone book feel
            
            return Container(
              padding: EdgeInsets.symmetric(horizontal: padding),
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
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(16, (bank) {
                    final isActive = sequencer.activeBank == bank;
                    final isSelected = sequencer.selectedSampleSlot == bank;
                    final hasFile = sequencer.fileNames[bank] != null;
                    final isPlaying = sequencer.slotPlaying[bank];
                    
                    Widget sampleButton = Container(
                      height: buttonHeight,
                      width: buttonWidth,
                      margin: EdgeInsets.symmetric(horizontal: padding * 0.3),
                      decoration: BoxDecoration(
                        color: _getButtonColor(isSelected, isActive, hasFile, bank, sequencer),
                        borderRadius: BorderRadius.circular(borderRadius),
                        border: Border.all(
                          color: _getBorderColor(isSelected, isActive, isPlaying),
                          width: _getBorderWidth(isSelected, isActive, isPlaying),
                        ),
                        boxShadow: _getBoxShadow(isSelected, isActive, isPlaying),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              String.fromCharCode(65 + bank), // A, B, C, etc.
                              style: GoogleFonts.sourceSans3(
                                color: _getTextColor(isSelected, isActive, hasFile),
                                fontWeight: FontWeight.w600,
                                fontSize: letterSize,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );

                    return hasFile 
                        ? Draggable<int>(
                            data: bank,
                            feedback: Container(
                              width: buttonWidth * 0.9,
                              height: buttonHeight,
                              decoration: BoxDecoration(
                                color: _getButtonColorForBank(bank, sequencer).withOpacity(0.9),
                                borderRadius: BorderRadius.circular(borderRadius),
                                border: Border.all(color: SequencerPhoneBookColors.accent, width: 2),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      String.fromCharCode(65 + bank),
                                      style: GoogleFonts.sourceSans3(
                                        color: SequencerPhoneBookColors.text,
                                        fontWeight: FontWeight.w600,
                                        fontSize: letterSize,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            childWhenDragging: Container(
                              height: buttonHeight,
                              width: buttonWidth,
                              margin: EdgeInsets.symmetric(horizontal: padding * 0.3),
                              decoration: BoxDecoration(
                                color: SequencerPhoneBookColors.surfacePressed,
                                borderRadius: BorderRadius.circular(borderRadius),
                                border: Border.all(
                                  color: SequencerPhoneBookColors.border,
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      String.fromCharCode(65 + bank),
                                      style: GoogleFonts.sourceSans3(
                                        color: SequencerPhoneBookColors.lightText,
                                        fontWeight: FontWeight.w600,
                                        fontSize: letterSize,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            child: GestureDetector(
                              onTap: () => sequencer.handleBankChange(bank, context),
                              onLongPress: () => sequencer.pickFileForSlot(bank, context),
                              child: sampleButton,
                            ),
                          )
                        : GestureDetector(
                            onTap: () => sequencer.handleBankChange(bank, context),
                            onLongPress: () => sequencer.pickFileForSlot(bank, context),
                            child: sampleButton,
                          );
                  }),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _getButtonColor(bool isSelected, bool isActive, bool hasFile, int bank, SequencerState sequencer) {
    if (hasFile) {
      return _getButtonColorForBank(bank, sequencer); // Sample loaded - use bank color
    } else {
      return SequencerPhoneBookColors.surfacePressed; // Empty slot
    }
  }

  Color _getButtonColorForBank(int bank, SequencerState sequencer) {
    // Convert original bank colors to darker gray-beige variants
    final originalColor = sequencer.bankColors[bank];
    // Create a muted variant that fits the telephone book theme
    return Color.lerp(originalColor, SequencerPhoneBookColors.surfaceRaised, 0.7) ?? SequencerPhoneBookColors.surfaceRaised;
  }

  Color _getBorderColor(bool isSelected, bool isActive, bool isPlaying) {
    if (isSelected) {
      return SequencerPhoneBookColors.accent; // Selected - brown accent
    } else if (isPlaying) {
      return SequencerPhoneBookColors.accent.withOpacity(0.8); // Playing - muted accent
    } else {
      return SequencerPhoneBookColors.border; // Default - subtle border
    }
  }

  double _getBorderWidth(bool isSelected, bool isActive, bool isPlaying) {
    if (isSelected || isPlaying) {
      return 1.5; // Emphasized border for selected/playing
    } else {
      return 0.5; // Subtle border for default
    }
  }

  List<BoxShadow>? _getBoxShadow(bool isSelected, bool isActive, bool isPlaying) {
    if (isSelected) {
      return [
        BoxShadow(
          color: SequencerPhoneBookColors.accent.withOpacity(0.4),
          blurRadius: 3,
          spreadRadius: 0,
          offset: const Offset(0, 1),
        )
      ];
    } else {
      // All buttons get protruding effect
      return [
        BoxShadow(
          color: SequencerPhoneBookColors.shadow,
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: SequencerPhoneBookColors.surfaceRaised,
          blurRadius: 1,
          offset: const Offset(0, -0.5),
        ),
      ];
    }
  }

  Color _getTextColor(bool isSelected, bool isActive, bool hasFile) {
    return SequencerPhoneBookColors.text; // Light text for contrast
  }
} 