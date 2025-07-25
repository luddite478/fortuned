import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

enum SideControlSide { left, right }

class SoundGridSideControlWidget extends StatelessWidget {
  final SideControlSide side;
  
  const SoundGridSideControlWidget({
    super.key,
    this.side = SideControlSide.left,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive button size based on available space
            final availableHeight = constraints.maxHeight;
            final availableWidth = constraints.maxWidth;
            
            // Use 90% of available height for buttons, leaving small margins
            final buttonsAreaHeight = availableHeight * 0.9;
            // Each button takes 1/3 of the buttons area with small spacing
            final buttonSpacing = buttonsAreaHeight * 0.05;
            final buttonHeight = (buttonsAreaHeight - (2 * buttonSpacing)) / 3;
            
            // Button width should use most of available width
            final buttonWidth = availableWidth * 0.8;
            
            // Icon size based on button height
            final iconSize = (buttonHeight * 0.06).clamp(16.0, 32.0);
            
            return Container(
              width: availableWidth,
              height: availableHeight,
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Top Button - Keep blank with icon
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.circle_outlined, // Generic placeholder icon
                    color: SequencerPhoneBookColors.lightText,
                    onPressed: () {
                      // TODO: Add functionality
                    },
                    tooltip: side == SideControlSide.left ? 'Left Control 1' : 'Right Control 1',
                  ),
                  
                  SizedBox(height: buttonSpacing),
                  
                  // Middle Button - Minus on left, Plus on right
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: side == SideControlSide.left ? Icons.chevron_left : Icons.chevron_right,
                    color: SequencerPhoneBookColors.lightText,
                    onPressed: () {
                      // TODO: Add functionality
                    },
                    tooltip: side == SideControlSide.left ? 'Remove' : 'Add',
                  ),
                  
                  SizedBox(height: buttonSpacing),
                  
                  // Bottom Button - Undo on left, Redo on right
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: side == SideControlSide.left ? Icons.undo : Icons.redo,
                    color: side == SideControlSide.left 
                        ? (sequencer.canUndo ? SequencerPhoneBookColors.accent : SequencerPhoneBookColors.lightText)
                        : (sequencer.canRedo ? SequencerPhoneBookColors.accent : SequencerPhoneBookColors.lightText),
                    onPressed: side == SideControlSide.left
                        ? (sequencer.canUndo ? () => sequencer.undo() : null)
                        : (sequencer.canRedo ? () => sequencer.redo() : null),
                    tooltip: side == SideControlSide.left 
                        ? (sequencer.canUndo ? 'Undo: ${sequencer.currentUndoDescription}' : 'Nothing to Undo')
                        : (sequencer.canRedo ? 'Redo' : 'Nothing to Redo'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSideControlButton({
    required double width,
    required double height,
    required double iconSize,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    final isEnabled = onPressed != null;
    
    return Container(
      width: width,
      height: height,
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
            child: Center(
              child: Icon(
                icon,
                color: color,
                size: iconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
} 