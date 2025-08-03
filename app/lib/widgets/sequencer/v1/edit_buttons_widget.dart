import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';import '../../../state/sequencer_state.dart';
import '../../../utils/app_colors.dart';

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
                color: AppColors.sequencerSurfaceBase,
                borderRadius: BorderRadius.circular(2), // Sharp corners
                border: Border.all(
                  color: AppColors.sequencerBorder,
                  width: 0.5,
                ),
                boxShadow: [
                  // Protruding effect
                  BoxShadow(
                    color: AppColors.sequencerShadow,
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Undo button
                  _buildEditButton(
                    size: buttonSize,
                    iconSize: iconSize,
                    icon: Icons.undo,
                    color: sequencer.canUndo
                        ? AppColors.sequencerAccent
                        : AppColors.sequencerLightText,
                    onPressed: sequencer.canUndo
                        ? () => sequencer.undo()
                        : null,
                    tooltip: sequencer.canUndo 
                        ? 'Undo: ${sequencer.currentUndoDescription}'
                        : 'Nothing to Undo',
                  ),
                  // Redo button
                  _buildEditButton(
                    size: buttonSize,
                    iconSize: iconSize,
                    icon: Icons.redo,
                    color: sequencer.canRedo
                        ? AppColors.sequencerAccent
                        : AppColors.sequencerLightText,
                    onPressed: sequencer.canRedo
                        ? () => sequencer.redo()
                        : null,
                    tooltip: sequencer.canRedo 
                        ? 'Redo'
                        : 'Nothing to Redo',
                  ),
                  // Selection Mode Toggle button
                  _buildEditButton(
                    size: buttonSize,
                    iconSize: iconSize,
                    icon: sequencer.isInSelectionMode ? Icons.check_box : Icons.check_box_outline_blank,
                    color: sequencer.isInSelectionMode ? AppColors.sequencerAccent : AppColors.sequencerLightText,
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
                        ? AppColors.sequencerAccent.withOpacity(0.8)
                        : AppColors.sequencerLightText,
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
                        ? AppColors.sequencerAccent
                        : AppColors.sequencerLightText,
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
                        ? AppColors.sequencerAccent
                        : AppColors.sequencerLightText,
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
            ? AppColors.sequencerSurfaceRaised 
            : AppColors.sequencerSurfacePressed,
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 0.5,
        ),
        boxShadow: isEnabled
            ? [
                // Protruding effect for enabled buttons
                BoxShadow(
                  color: AppColors.sequencerShadow,
                  blurRadius: 1.5,
                  offset: const Offset(0, 1),
                ),
                BoxShadow(
                  color: AppColors.sequencerSurfaceRaised,
                  blurRadius: 0.5,
                  offset: const Offset(0, -0.5),
                ),
              ]
            : [
                // Recessed effect for disabled buttons
                BoxShadow(
                  color: AppColors.sequencerShadow,
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
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: sequencer.isStepInsertMode ? AppColors.sequencerAccent : AppColors.sequencerBorder,
          width: sequencer.isStepInsertMode ? 1.0 : 0.5,
        ),
        boxShadow: [
          // Protruding effect
          BoxShadow(
            color: AppColors.sequencerShadow,
            blurRadius: 1.5,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: AppColors.sequencerSurfaceRaised,
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
                        color: sequencer.isStepInsertMode ? AppColors.sequencerAccent : AppColors.sequencerLightText,
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
                      color: sequencer.isStepInsertMode ? AppColors.sequencerAccent : AppColors.sequencerLightText,
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