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
            final availableWidth = panelWidth - 8; // Minimal container padding
            final buttonWidth = availableWidth / 8; // 8 buttons, no clamp - use what's available
            final buttonHeight = panelHeight * 0.8; // Use 80% of given height
            final letterSize = (buttonHeight * 0.3).clamp(8.0, double.infinity); // Scale with height, min 8px
            final iconSize = (buttonHeight * 0.2).clamp(6.0, double.infinity); // Scale with height, min 6px
            final padding = panelHeight * 0.05; // 5% of given height
            final borderRadius = buttonHeight * 0.1; // Scale with button height
            
            return Container(
              padding: EdgeInsets.symmetric(horizontal: padding),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(borderRadius),
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
                      margin: EdgeInsets.symmetric(horizontal: padding * 0.25),
                      padding: EdgeInsets.symmetric(vertical: padding * 0.5),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.yellowAccent.withOpacity(0.8) // Selected for placement
                            : isActive
                                ? Colors.white
                                : hasFile
                                    ? sequencer.bankColors[bank].withOpacity(0.8)
                                    : const Color(0xFF404040),
                        borderRadius: BorderRadius.circular(borderRadius * 0.75),
                        border: isPlaying
                            ? Border.all(color: Colors.greenAccent, width: 2)
                            : isSelected
                                ? Border.all(color: Colors.yellowAccent, width: 2)
                                : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            String.fromCharCode(65 + bank), // A, B, C, etc.
                            style: TextStyle(
                              color: isSelected || isActive ? Colors.black : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: letterSize,
                            ),
                          ),
                          if (hasFile) ...[
                            SizedBox(height: padding * 0.25),
                            Icon(
                              Icons.audiotrack,
                              size: iconSize,
                              color: isSelected || isActive ? Colors.black54 : Colors.white70,
                            ),
                          ],
                        ],
                      ),
                    );

                    return hasFile 
                        ? Draggable<int>(
                            data: bank,
                            feedback: Container(
                              width: buttonWidth * 0.8,
                              height: buttonHeight,
                              decoration: BoxDecoration(
                                color: sequencer.bankColors[bank].withOpacity(0.9),
                                borderRadius: BorderRadius.circular(borderRadius * 0.75),
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    String.fromCharCode(65 + bank),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: letterSize,
                                    ),
                                  ),
                                  Icon(
                                    Icons.audiotrack,
                                    size: iconSize,
                                    color: Colors.white70,
                                  ),
                                ],
                              ),
                            ),
                            childWhenDragging: Container(
                              height: buttonHeight,
                              width: buttonWidth,
                              margin: EdgeInsets.symmetric(horizontal: padding * 0.25),
                              padding: EdgeInsets.symmetric(vertical: padding * 0.5),
                              decoration: BoxDecoration(
                                color: sequencer.bankColors[bank].withOpacity(0.3),
                                borderRadius: BorderRadius.circular(borderRadius * 0.75),
                                border: Border.all(color: Colors.grey, width: 1),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    String.fromCharCode(65 + bank),
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                      fontSize: letterSize,
                                    ),
                                  ),
                                  SizedBox(height: padding * 0.25),
                                  Icon(
                                    Icons.audiotrack,
                                    size: iconSize,
                                    color: Colors.grey,
                                  ),
                                ],
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
} 