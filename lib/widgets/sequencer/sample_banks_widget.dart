import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sequencer_state.dart';

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
            
            // Use ALL available space - no minimums, just scale everything down
            final availableWidth = panelWidth - 16; // Container padding
            final buttonWidth = availableWidth / 8; // 8 buttons
            final buttonHeight = panelHeight * 0.8; // Use 80% of given height
            final letterSize = (buttonHeight * 0.35).clamp(10.0, double.infinity); // Scale with height, min 10px
            final iconSize = (buttonHeight * 0.25).clamp(8.0, double.infinity); // Scale with height, min 8px
            final padding = panelHeight * 0.05; // 5% of given height
            final borderRadius = buttonHeight * 0.15; // Scale with button height, similar to settings buttons
            
            return Container(
              padding: EdgeInsets.symmetric(horizontal: padding),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(8, (bank) {
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
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              String.fromCharCode(65 + bank), // A, B, C, etc.
                              style: TextStyle(
                                color: _getTextColor(isSelected, isActive, hasFile),
                                fontWeight: FontWeight.w600,
                                fontSize: letterSize,
                              ),
                            ),
                            if (hasFile) ...[
                              SizedBox(height: padding * 0.2),
                              Icon(
                                Icons.audiotrack,
                                size: iconSize,
                                color: _getIconColor(isSelected, isActive, hasFile),
                              ),
                            ],
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
                                color: sequencer.bankColors[bank].withOpacity(0.9),
                                borderRadius: BorderRadius.circular(borderRadius),
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      String.fromCharCode(65 + bank),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: letterSize,
                                      ),
                                    ),
                                    SizedBox(height: padding * 0.2),
                                    Icon(
                                      Icons.audiotrack,
                                      size: iconSize,
                                      color: Colors.white,
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
                                color: Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(borderRadius),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.4),
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
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w600,
                                        fontSize: letterSize,
                                      ),
                                    ),
                                    SizedBox(height: padding * 0.2),
                                    Icon(
                                      Icons.audiotrack,
                                      size: iconSize,
                                      color: Colors.grey,
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
    if (isSelected) {
      return Colors.orangeAccent; // Selected for placement - orange instead of yellow
    } else if (isActive) {
      return Colors.blueAccent; // Active sample - blue instead of white
    } else if (hasFile) {
      return sequencer.bankColors[bank].withOpacity(0.6); // Sample loaded - softer opacity
    } else {
      return Colors.grey.withOpacity(0.2); // Empty slot - similar to settings buttons
    }
  }

  Color _getBorderColor(bool isSelected, bool isActive, bool isPlaying) {
    if (isPlaying) {
      return Colors.greenAccent; // Playing - green border
    } else if (isSelected) {
      return Colors.orangeAccent; // Selected - orange border
    } else if (isActive) {
      return Colors.blueAccent; // Active - blue border
    } else {
      return Colors.grey.withOpacity(0.4); // Default - subtle grey border
    }
  }

  double _getBorderWidth(bool isSelected, bool isActive, bool isPlaying) {
    if (isPlaying || isSelected || isActive) {
      return 2.0; // Emphasized border for active states
    } else {
      return 1.0; // Subtle border for inactive
    }
  }

  Color _getTextColor(bool isSelected, bool isActive, bool hasFile) {
    return Colors.white; // Always white text for good contrast
  }

  Color _getIconColor(bool isSelected, bool isActive, bool hasFile) {
    return Colors.white70; // Slightly transparent white for icons
  }
} 