import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';
import '../../../state/sequencer_state.dart';

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
            // Each button takes 1/4 of the buttons area with small spacing
            final buttonSpacing = buttonsAreaHeight * 0.04;
            final buttonHeight = (buttonsAreaHeight - (3 * buttonSpacing)) / 4;
            
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
                        final isSongMode = sequencer.isSongMode;
                        final label = isSongMode ? '$current/$total' : '∞';
                        final blended = Color.lerp(AppColors.menuErrorColor, AppColors.sequencerLightText, 0.5)!;
                        return Text(
                          label,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: GoogleFonts.sourceSans3(
                            color: blended,
                            fontSize: buttonWidth * 0.50,
                            fontWeight: FontWeight.w600,
                            height: 1.0,
                            letterSpacing: 0.2,
                          ),
                        );
                      },
                    ),
                  ),
                  
                  SizedBox(height: buttonSpacing),
                  
                  // Left Side: Loop Mode Toggle
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.repeat,
                    color: sequencer.sectionPlaybackMode == SectionPlaybackMode.loop 
                        ? AppColors.sequencerAccent 
                        : AppColors.sequencerLightText,
                    onPressed: () {
                      sequencer.toggleSectionPlaybackMode();
                    },
                    tooltip: sequencer.sectionPlaybackMode == SectionPlaybackMode.loop 
                        ? 'Loop Mode (Active)' 
                        : 'Song Mode (Click to Loop)',
                  ),
                  
                  SizedBox(height: buttonSpacing),
                  
                  // Left Side: Previous Section
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
                  
                  // Left Side: Undo
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
                  // Right Side: Keep existing 4-button layout (placeholder)
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.circle_outlined,
                    color: AppColors.sequencerLightText,
                    onPressed: () {
                      // TODO: Add functionality
                    },
                    tooltip: 'Right Control 1',
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
                         // On last section - open section creation overlay
                         sequencer.openSectionCreationOverlay();
                       } else {
                         // Not on last section - navigate to next
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
                    icon: Icons.circle_outlined,
                    color: AppColors.sequencerLightText,
                    onPressed: () {
                      // TODO: Add functionality
                    },
                    tooltip: 'Right Control 3',
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
  }) {
    final isEnabled = onPressed != null;
    
    return Container(
      width: width,
      height: height,
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
  }) {
    final isEnabled = onPressed != null;
    
    return Container(
      width: width,
      height: height,
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
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    text,
                    style: GoogleFonts.sourceSans3(
                      color: color,
                      fontSize: width * 0.55,
                      fontWeight: FontWeight.w700,
                      height: 0.9,
                    ),
                  ),
                  if (bottom != null) ...[
                    SizedBox(height: height * 0.02),
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