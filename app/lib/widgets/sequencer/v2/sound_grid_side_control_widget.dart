import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';import '../../../state/sequencer_state.dart';
import '../../../utils/app_colors.dart';

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
            // Compute layout per side
            final int buttonCount = side == SideControlSide.left ? 4 : 3;
            final buttonSpacing = buttonsAreaHeight * 0.05;
            final buttonHeight = (buttonsAreaHeight - ((buttonCount - 1) * buttonSpacing)) / buttonCount;
            
            // Button width should use most of available width
            final buttonWidth = availableWidth * 0.8;
            
            // Icon size based on button height
            final iconSize = (buttonHeight * 0.06).clamp(16.0, 32.0);
            
            return Container(
              width: availableWidth,
              height: availableHeight,
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: side == SideControlSide.left ? [
                  // Left Side: Section Control Button
                  _buildSideControlButtonWithText(
                    width: buttonWidth,
                    height: buttonHeight,
                    text: '${sequencer.currentSectionIndex + 1}',
                    color: sequencer.isSectionControlOverlayOpen 
                        ? AppColors.sequencerAccent 
                        : AppColors.sequencerLightText,
                    onPressed: () {
                      sequencer.toggleSectionControlOverlay();
                    },
                    tooltip: 'Section Settings',
                    bottom: ValueListenableBuilder<int>(
                      valueListenable: sequencer.currentStepNotifier,
                      builder: (context, _, __) {
                        final total = sequencer.getSectionLoopCount(sequencer.currentSectionIndex);
                        final current = (sequencer.currentSectionLoopCounter + 1).clamp(1, total);
                        final label = '$current/$total';
                        final color = Color.lerp(AppColors.menuErrorColor, AppColors.sequencerLightText, 0.5)!;
                        return Text(
                          label,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                            color: color,
                            fontSize: buttonWidth * 0.40,
                            fontWeight: FontWeight.w600,
                            height: 1.0,
                            letterSpacing: 0.2,
                          ),
                        );
                      },
                    ),
                  ),
                   
                  SizedBox(height: buttonSpacing),
                  
                  // Middle Button - Loop/Song mode toggle
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.repeat,
                    color: sequencer.sectionPlaybackMode == SectionPlaybackMode.loop 
                        ? Colors.white 
                        : AppColors.sequencerLightText,
                    onPressed: () {
                      sequencer.toggleSectionPlaybackMode();
                    },
                    tooltip: sequencer.sectionPlaybackMode == SectionPlaybackMode.loop 
                        ? 'Loop Mode (Active)'
                        : 'Song Mode (Click to Loop)',
                    backgroundColor: sequencer.sectionPlaybackMode == SectionPlaybackMode.loop 
                        ? AppColors.sequencerPrimaryButton 
                        : AppColors.sequencerSurfacePressed,
                  ),
                  
                  SizedBox(height: buttonSpacing),
                  
                  // Bottom two buttons: Redo above, Undo at bottom
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.redo,
                    color: sequencer.canRedo ? AppColors.sequencerAccent : AppColors.sequencerLightText,
                    onPressed: sequencer.canRedo ? () => sequencer.redo() : null,
                    tooltip: sequencer.canRedo ? 'Redo' : 'Nothing to Redo',
                  ),
                  SizedBox(height: buttonSpacing),
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.undo,
                    color: sequencer.canUndo ? AppColors.sequencerAccent : AppColors.sequencerLightText,
                    onPressed: sequencer.canUndo ? () => sequencer.undo() : null,
                    tooltip: sequencer.canUndo ? 'Undo: ${sequencer.currentUndoDescription}' : 'Nothing to Undo',
                  ),
                ] : [
                  // Right Side: Previous, Next, Redo
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.chevron_left,
                    color: sequencer.numSections > 1 
                        ? AppColors.sequencerLightText 
                        : AppColors.sequencerLightText.withOpacity(0.5),
                    onPressed: sequencer.numSections > 1 
                        ? () => sequencer.switchToPreviousSection()
                        : null,
                    tooltip: sequencer.numSections > 1 
                        ? 'Previous Section (${sequencer.currentSectionIndex + 1}/${sequencer.numSections})'
                        : 'Only 1 Section',
                  ),
                  SizedBox(height: buttonSpacing),
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.chevron_right,
                    color: AppColors.sequencerLightText,
                    onPressed: () {
                      if (sequencer.currentSectionIndex == sequencer.numSections - 1) {
                        sequencer.openSectionCreationOverlay();
                      } else {
                        sequencer.switchToNextSection();
                      }
                    },
                    tooltip: sequencer.currentSectionIndex == sequencer.numSections - 1 
                        ? 'Create New Section'
                        : 'Next Section (${sequencer.currentSectionIndex + 2}/${sequencer.numSections})',
                  ),
                  SizedBox(height: buttonSpacing),
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.redo,
                    color: sequencer.canRedo ? AppColors.sequencerAccent : AppColors.sequencerLightText,
                    onPressed: sequencer.canRedo ? () => sequencer.redo() : null,
                    tooltip: sequencer.canRedo ? 'Redo' : 'Nothing to Redo',
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
    Color? backgroundColor,
  }) {
    final isEnabled = onPressed != null;
    
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor ?? (isEnabled 
            ? AppColors.sequencerSurfaceRaised 
            : AppColors.sequencerSurfacePressed),
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

  Widget _buildSideControlButtonWithText({
    required double width,
    required double height,
    required String text,
    required Color color,
    required VoidCallback? onPressed,
    required String tooltip,
    Widget? bottom,
    Color? backgroundColor,
  }) {
    final isEnabled = onPressed != null;
    
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor ?? (isEnabled 
            ? AppColors.sequencerSurfaceRaised 
            : AppColors.sequencerSurfacePressed),
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
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      color: color,
                      fontSize: width * 0.55,
                      fontWeight: FontWeight.w700,
                      height: 0.9,
                    ),
                  ),
                  if (bottom != null) ...[
                    SizedBox(height: height * 0.08),
                    bottom,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
} 