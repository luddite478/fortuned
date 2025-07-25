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

class EditButtonsWidget extends StatelessWidget {
  const EditButtonsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive button size based on available height
            final panelHeight = constraints.maxHeight;
            final buttonSize = (panelHeight * 0.6).clamp(20.0, 48.0); // 60% of panel height, clamped between 20-48px
            final iconSize = (buttonSize * 0.6).clamp(16.0, 32.0); // 60% of button size
            final badgeSize = (buttonSize * 0.25).clamp(8.0, 16.0); // 25% of button size
            final fontSize = (badgeSize * 0.6).clamp(6.0, 12.0); // 60% of badge size
            
            return Container(
              padding: EdgeInsets.symmetric(horizontal: panelHeight * 0.1), // Only horizontal padding
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Selection Mode Toggle button
                  _buildEditButton(
                    size: buttonSize,
                    iconSize: iconSize,
                    icon: sequencer.isInSelectionMode ? Icons.check_box : Icons.check_box_outline_blank,
                    color: sequencer.isInSelectionMode ? SequencerPhoneBookColors.accent : SequencerPhoneBookColors.lightText,
                    onPressed: () => sequencer.toggleSelectionMode(),
                    tooltip: sequencer.isInSelectionMode ? 'Exit Selection Mode' : 'Enter Selection Mode',
                  ),
                  // Step Insert Mode Toggle button with settings access
                  _buildStepInsertToggleButton(
                    size: buttonSize,
                    iconSize: iconSize,
                    sequencer: sequencer,
                  ),
                  // Delete button
                  _buildEditButton(
                    size: buttonSize,
                    iconSize: iconSize,
                    icon: Icons.delete,
                    color: sequencer.selectedGridCells.isNotEmpty
                        ? SequencerPhoneBookColors.accent.withOpacity(0.8)
                        : SequencerPhoneBookColors.lightText,
                    onPressed: sequencer.selectedGridCells.isNotEmpty
                        ? () => sequencer.deleteSelectedCells()
                        : null,
                    tooltip: 'Delete Selected Cells',
                  ),
                  // Copy button
                  _buildEditButton(
                    size: buttonSize,
                    iconSize: iconSize,
                    icon: Icons.copy,
                    color: sequencer.selectedGridCells.isNotEmpty
                        ? SequencerPhoneBookColors.accent
                        : SequencerPhoneBookColors.lightText,
                    onPressed: sequencer.selectedGridCells.isNotEmpty
                        ? () => sequencer.copySelectedCells()
                        : null,
                    tooltip: 'Copy Selected Cells',
                  ),
                  // Paste button
                  _buildEditButton(
                    size: buttonSize,
                    iconSize: iconSize,
                    icon: Icons.paste,
                    color: sequencer.hasClipboardData && sequencer.selectedGridCells.isNotEmpty
                        ? SequencerPhoneBookColors.accent
                        : SequencerPhoneBookColors.lightText,
                    onPressed: sequencer.hasClipboardData && sequencer.selectedGridCells.isNotEmpty
                        ? () => sequencer.pasteToSelectedCells()
                        : null,
                    tooltip: 'Paste to Selected Cells',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEditButton({
    required double size,
    required double iconSize,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    final isEnabled = onPressed != null;
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isEnabled 
            ? SequencerPhoneBookColors.surfaceRaised 
            : SequencerPhoneBookColors.surfacePressed,
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: SequencerPhoneBookColors.border,
          width: 0.5,
        ),
        boxShadow: isEnabled
            ? [
                // Protruding effect for enabled buttons
                BoxShadow(
                  color: SequencerPhoneBookColors.shadow,
                  blurRadius: 1.5,
                  offset: const Offset(0, 1),
                ),
                BoxShadow(
                  color: SequencerPhoneBookColors.surfaceRaised,
                  blurRadius: 0.5,
                  offset: const Offset(0, -0.5),
                ),
              ]
            : [
                // Recessed effect for disabled buttons
                BoxShadow(
                  color: SequencerPhoneBookColors.shadow,
                  blurRadius: 1,
                  offset: const Offset(0, 0.5),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(2),
          child: Container(
            padding: EdgeInsets.zero,
            child: Icon(
              icon,
              color: color,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
      }
  
  Widget _buildStepInsertToggleButton({
    required double size,
    required double iconSize,
    required SequencerState sequencer,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SequencerPhoneBookColors.surfaceRaised,
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: sequencer.isStepInsertMode ? SequencerPhoneBookColors.accent : SequencerPhoneBookColors.border,
          width: sequencer.isStepInsertMode ? 1.0 : 0.5,
        ),
        boxShadow: [
          // Protruding effect
          BoxShadow(
            color: SequencerPhoneBookColors.shadow,
            blurRadius: 1.5,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: SequencerPhoneBookColors.surfaceRaised,
            blurRadius: 0.5,
            offset: const Offset(0, -0.5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => sequencer.toggleStepInsertMode(),
          borderRadius: BorderRadius.circular(2),
          child: Container(
            padding: EdgeInsets.zero,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2), // Add 4 pixels top margin
                    child: Text(
                      '${sequencer.stepInsertSize}',
                      style: GoogleFonts.sourceSans3(
                        color: sequencer.isStepInsertMode ? SequencerPhoneBookColors.accent : SequencerPhoneBookColors.lightText,
                        fontSize: iconSize * 0.8,
                        fontWeight: FontWeight.w600,
                        height: 0.7,
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -2), // Move arrow up by 2 pixels
                    child: Icon(
                      Icons.keyboard_double_arrow_down,
                      color: sequencer.isStepInsertMode ? SequencerPhoneBookColors.accent : SequencerPhoneBookColors.lightText,
                      size: iconSize * 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
 
  } 