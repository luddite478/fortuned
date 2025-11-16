import 'package:flutter/material.dart';
// duplicate import removed
import 'package:provider/provider.dart';
import '../../../state/sequencer/section_settings.dart';
import '../../../state/sequencer/multitask_panel.dart';
import '../../../state/sequencer/undo_redo.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/playback.dart';
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
    final sectionSettings = context.watch<SectionSettingsState>();
    final multitaskPanel = context.watch<MultitaskPanelState>();
    final playbackState = context.watch<PlaybackState>();
    // final editState = context.watch<EditState>(); // reserved for future selection-mode awareness
    final undoRedo = context.watch<UndoRedoState>();
    final tableState = context.watch<TableState>();
    return Builder(
      builder: (context) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive button size based on available space
            final availableHeight = constraints.maxHeight;
            final availableWidth = constraints.maxWidth;
            
            final bool hideButtons = sectionSettings.isSectionCreationOpen || tableState.sectionsCount == 0;

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
              child: hideButtons
                  ? const SizedBox.shrink()
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: side == SideControlSide.left ? [
                  // Left Side: Section Control Button
                  _SectionControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    sectionNumber: tableState.uiSelectedSection + 1,
                    onPressed: () {
                      if (multitaskPanel.currentMode == MultitaskPanelMode.sectionSettings) {
                        multitaskPanel.showPlaceholder();
                      } else {
                        multitaskPanel.showSectionSettings();
                      }
                    },
                    tooltip: 'Section Settings',
                  ),
                   
                  SizedBox(height: buttonSpacing),
                  
                  // Middle Button - Loop/Song mode toggle
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.repeat,
                    color: playbackState.songModeNotifier.value == false 
                        ? Colors.white 
                        : AppColors.sequencerLightText,
                    onPressed: () {
                      playbackState.setSongMode(!(playbackState.songModeNotifier.value));
                    },
                    tooltip: (playbackState.songModeNotifier.value == false) 
                        ? 'Loop Mode (Active)'
                        : 'Song Mode (Click to Loop)',
                    backgroundColor: (playbackState.songModeNotifier.value == false) 
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
                    color: undoRedo.canRedo ? AppColors.sequencerAccent : AppColors.sequencerLightText,
                    onPressed: undoRedo.canRedo ? () => undoRedo.redo() : null,
                    tooltip: undoRedo.canRedo ? 'Redo' : 'Nothing to Redo',
                  ),
                  SizedBox(height: buttonSpacing),
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.undo,
                    color: undoRedo.canUndo ? AppColors.sequencerAccent : AppColors.sequencerLightText,
                    onPressed: undoRedo.canUndo ? () => undoRedo.undo() : null,
                    tooltip: undoRedo.canUndo ? 'Undo' : 'Nothing to Undo',
                  ),
                ] : [
                  // Right Side: Previous, Next, Redo
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.chevron_left,
                    color: tableState.sectionsCount > 1 
                        ? AppColors.sequencerLightText 
                        : AppColors.sequencerLightText.withOpacity(0.5),
                    onPressed: tableState.sectionsCount > 1 
                        ? () => tableState.setUiSelectedSection((tableState.uiSelectedSection - 1).clamp(0, tableState.sectionsCount - 1))
                        : null,
                    tooltip: tableState.sectionsCount > 1 
                        ? 'Previous Section (${tableState.uiSelectedSection + 1}/${tableState.sectionsCount})'
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
                      if (tableState.uiSelectedSection == tableState.sectionsCount - 1) {
                        sectionSettings.openSectionCreationOverlay();
                      } else {
                        tableState.setUiSelectedSection((tableState.uiSelectedSection + 1).clamp(0, tableState.sectionsCount - 1));
                      }
                    },
                    tooltip: tableState.uiSelectedSection == tableState.sectionsCount - 1 
                        ? 'New Section'
                        : 'Next Section (${tableState.uiSelectedSection + 2}/${tableState.sectionsCount})',
                  ),
                  SizedBox(height: buttonSpacing),
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.redo,
                    color: undoRedo.canRedo ? AppColors.sequencerAccent : AppColors.sequencerLightText,
                    onPressed: undoRedo.canRedo ? () => undoRedo.redo() : null,
                    tooltip: undoRedo.canRedo ? 'Redo' : 'Nothing to Redo',
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

}

// Stateful section control button with click feedback
class _SectionControlButton extends StatefulWidget {
  final double width;
  final double height;
  final int sectionNumber;
  final VoidCallback onPressed;
  final String tooltip;

  const _SectionControlButton({
    required this.width,
    required this.height,
    required this.sectionNumber,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  State<_SectionControlButton> createState() => _SectionControlButtonState();
}

class _SectionControlButtonState extends State<_SectionControlButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final playbackState = context.watch<PlaybackState>();
    
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: _isPressed 
              ? AppColors.sequencerPrimaryButton 
              : AppColors.sequencerSurfaceRaised,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: AppColors.sequencerBorder,
            width: 0.5,
          ),
          boxShadow: [
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
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${widget.sectionNumber}',
                style: TextStyle(
                  color: _isPressed 
                      ? Colors.white 
                      : AppColors.sequencerLightText,
                  fontSize: widget.width * 0.55,
                  fontWeight: FontWeight.w700,
                  height: 0.9,
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: playbackState.songModeNotifier,
                builder: (context, isSongMode, __) {
                  if (!isSongMode) {
                    // Loop mode: show infinity symbol
                    final color = Color.lerp(AppColors.menuErrorColor, AppColors.sequencerLightText, 0.5)!;
                    return Padding(
                      padding: EdgeInsets.only(top: widget.height * 0.08),
                      child: SizedBox(
                        height: widget.width * 0.7,
                        child: Text(
                          '∞',
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                            color: color,
                            fontSize: widget.width * 0.7,
                            fontWeight: FontWeight.w600,
                            height: 1.0,
                          ),
                        ),
                      ),
                    );
                  } else {
                    // Song mode: show loop counter
                    return ValueListenableBuilder<int>(
                      valueListenable: playbackState.currentSectionLoopNotifier,
                      builder: (context, currentLoopZeroBased, __) {
                        return ValueListenableBuilder<int>(
                          valueListenable: playbackState.currentSectionLoopsNumNotifier,
                          builder: (context, totalLoops, ___) {
                            final displayCurrent = (currentLoopZeroBased + 1).clamp(1, totalLoops);
                            final label = '$displayCurrent/$totalLoops';
                            final color = Color.lerp(AppColors.menuErrorColor, AppColors.sequencerLightText, 0.5)!;
                            return Padding(
                              padding: EdgeInsets.only(top: widget.height * 0.08),
                              child: SizedBox(
                                height: widget.width * 0.7,
                                child: Text(
                                  label,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: widget.width * 0.40,
                                    fontWeight: FontWeight.w600,
                                    height: 1.0,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
} 