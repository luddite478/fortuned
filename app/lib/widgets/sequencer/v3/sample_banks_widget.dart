import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';
import '../../../state/sequencer_state.dart';

class SampleBanksWidget extends StatefulWidget {
  const SampleBanksWidget({super.key});

  @override
  State<SampleBanksWidget> createState() => _SampleBanksWidgetState();
}

class _SampleBanksWidgetState extends State<SampleBanksWidget> {
  int _startIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final panelHeight = constraints.maxHeight;
            final panelWidth = constraints.maxWidth;

            final padding = panelHeight * 0.05;
            final baseButtonsWidth = panelWidth; // container has zero padding
            final preferredButtonWidth = baseButtonsWidth / 7.5; // baseline
            final buttonHeight = panelHeight * 0.8;
            final letterSize = (buttonHeight * 0.35).clamp(10.0, double.infinity);
            const borderRadius = 2.0;

            final arrowWidth = preferredButtonWidth * 0.8;
            final arrowHeight = buttonHeight * 0.8;
            final sampleMarginH = padding * 0.3;
            // Zero inner margin between arrows and tiles
            final leftArrowMarginLeft = 0.0;
            final leftArrowMarginRight = 0.0;
            final rightArrowMarginLeft = 0.0;
            final rightArrowMarginRight = 0.0;

            final totalArrowMargins = leftArrowMarginLeft + leftArrowMarginRight + rightArrowMarginLeft + rightArrowMarginRight;
            final availableRowWidth = baseButtonsWidth - (arrowWidth * 2) - totalArrowMargins;
            final preferredTileWithMargins = preferredButtonWidth + 2 * sampleMarginH;
            int visibleCount = availableRowWidth > 0
                ? (availableRowWidth / preferredTileWithMargins).floor().clamp(1, 16)
                : 1;
            if (visibleCount < 1) visibleCount = 1;
            final totalInterTileMargins = (visibleCount - 1) * (2 * sampleMarginH);
            final buttonWidth = ((availableRowWidth - totalInterTileMargins) / visibleCount).floorToDouble();

            final maxStart = (16 - visibleCount).clamp(0, 16);
            final startIndex = _startIndex.clamp(0, maxStart);
            final endIndex = (startIndex + visibleCount).clamp(0, 16);
            final effectiveCount = (endIndex - startIndex).clamp(0, visibleCount);

            void goLeft() {
              if (startIndex > 0) {
                setState(() {
                  _startIndex = (startIndex - visibleCount).clamp(0, maxStart);
                });
              }
            }

            void goRight() {
              if (startIndex < maxStart) {
                setState(() {
                  _startIndex = (startIndex + visibleCount).clamp(0, maxStart);
                });
              }
            }

            return Container(
              padding: EdgeInsets.zero,
              decoration: BoxDecoration(
                color: AppColors.sequencerSurfaceBase,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: AppColors.sequencerBorder,
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.sequencerShadow,
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: panelHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ArrowTile(
                      enabled: startIndex > 0,
                      onTap: goLeft,
                      icon: Icons.chevron_left,
                      width: arrowWidth,
                      height: arrowHeight,
                      marginLeft: leftArrowMarginLeft,
                      marginRight: leftArrowMarginRight,
                      borderRadius: borderRadius,
                    ),
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (int i = 0; i < effectiveCount; i++)
                            _buildBankButton(
                              context: context,
                              sequencer: sequencer,
                              bank: startIndex + i,
                              buttonHeight: buttonHeight,
                              buttonWidth: buttonWidth,
                              leftMargin: i == 0 ? 0.0 : sampleMarginH,
                              rightMargin: i == effectiveCount - 1 ? 0.0 : sampleMarginH,
                              borderRadius: borderRadius,
                              letterSize: letterSize,
                            ),
                        ],
                      ),
                    ),
                    _ArrowTile(
                      enabled: startIndex < maxStart,
                      onTap: goRight,
                      icon: Icons.chevron_right,
                      width: arrowWidth,
                      height: arrowHeight,
                      marginLeft: rightArrowMarginLeft,
                      marginRight: rightArrowMarginRight,
                      borderRadius: borderRadius,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBankButton({
    required BuildContext context,
    required SequencerState sequencer,
    required int bank,
    required double buttonHeight,
    required double buttonWidth,
    required double leftMargin,
    required double rightMargin,
    required double borderRadius,
    required double letterSize,
  }) {
    final isActive = sequencer.activeBank == bank;
    final isSelected = sequencer.selectedSampleSlot == bank;
    final hasFile = sequencer.fileNames[bank] != null;
    final isPlaying = sequencer.slotPlaying[bank];

    Widget sampleButton = Container(
      height: buttonHeight,
      width: buttonWidth,
      margin: EdgeInsets.only(left: leftMargin, right: rightMargin),
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
              String.fromCharCode(65 + bank),
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
                border: Border.all(color: AppColors.sequencerAccent, width: 2),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      String.fromCharCode(65 + bank),
                      style: GoogleFonts.sourceSans3(
                        color: AppColors.sequencerText,
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
              margin: EdgeInsets.only(left: leftMargin, right: rightMargin),
              decoration: BoxDecoration(
                color: AppColors.sequencerSurfacePressed,
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: AppColors.sequencerBorder,
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
                        color: AppColors.sequencerLightText,
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
  }

  Color _getButtonColor(bool isSelected, bool isActive, bool hasFile, int bank, SequencerState sequencer) {
    if (hasFile) {
      return _getButtonColorForBank(bank, sequencer);
    } else {
      return AppColors.sequencerSurfacePressed;
    }
  }

  Color _getButtonColorForBank(int bank, SequencerState sequencer) {
    final originalColor = sequencer.bankColors[bank];
    return Color.lerp(originalColor, AppColors.sequencerSurfaceRaised, 0.7) ?? AppColors.sequencerSurfaceRaised;
  }

  Color _getBorderColor(bool isSelected, bool isActive, bool isPlaying) {
    if (isSelected) {
      return AppColors.sequencerAccent;
    } else if (isPlaying) {
      return AppColors.sequencerAccent.withOpacity(0.8);
    } else {
      return AppColors.sequencerBorder;
    }
  }

  double _getBorderWidth(bool isSelected, bool isActive, bool isPlaying) {
    if (isSelected || isPlaying) {
      return 1.5;
    } else {
      return 0.5;
    }
  }

  List<BoxShadow>? _getBoxShadow(bool isSelected, bool isActive, bool isPlaying) {
    if (isSelected) {
      return [
        BoxShadow(
          color: AppColors.sequencerAccent.withOpacity(0.4),
          blurRadius: 3,
          spreadRadius: 0,
          offset: const Offset(0, 1),
        )
      ];
    } else {
      return [
        BoxShadow(
          color: AppColors.sequencerShadow,
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: AppColors.sequencerSurfaceRaised,
          blurRadius: 1,
          offset: const Offset(0, -0.5),
        ),
      ];
    }
  }

  Color _getTextColor(bool isSelected, bool isActive, bool hasFile) {
    return AppColors.sequencerText;
  }
}

class _ArrowTile extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;
  final IconData icon;
  final double width;
  final double height;
  final double marginLeft;
  final double marginRight;
  final double borderRadius;

  const _ArrowTile({
    required this.enabled,
    required this.onTap,
    required this.icon,
    required this.width,
    required this.height,
    required this.marginLeft,
    required this.marginRight,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: EdgeInsets.only(left: marginLeft, right: marginRight),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfacePressed,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.sequencerShadow,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: AppColors.sequencerSurfaceRaised,
            blurRadius: 1,
            offset: const Offset(0, -0.5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Center(
            child: Icon(
              icon,
              size: height * 0.5,
              color: enabled ? AppColors.sequencerText : AppColors.sequencerLightText,
            ),
          ),
        ),
      ),
    );
  }
} 