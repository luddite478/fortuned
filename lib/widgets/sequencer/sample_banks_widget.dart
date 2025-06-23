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
            // Calculate responsive sizes based on available height
            final panelHeight = constraints.maxHeight;
            final buttonHeight = (panelHeight * 0.7).clamp(40.0, 80.0); // 70% of panel height, clamped between 40-80px
            final letterSize = (buttonHeight * 0.25).clamp(12.0, 20.0); // 25% of button height
            final iconSize = (buttonHeight * 0.2).clamp(10.0, 16.0); // 20% of button height
            final padding = (panelHeight * 0.1).clamp(4.0, 12.0); // 10% of panel height
            final borderRadius = (panelHeight * 0.1).clamp(4.0, 8.0); // 10% of panel height
            
            return Container(
              padding: EdgeInsets.symmetric(horizontal: padding),
              decoration: BoxDecoration(
                color: const Color(0xFF1f2937),
                borderRadius: BorderRadius.circular(borderRadius),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(8, (bank) {
              final isActive = sequencer.activeBank == bank;
              final isSelected = sequencer.selectedSampleSlot == bank;
              final hasFile = sequencer.fileNames[bank] != null;
              final isPlaying = sequencer.slotPlaying[bank];
              
                  Widget sampleButton = Container(
                    height: buttonHeight,
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

                  return Expanded(
                    child: hasFile 
                        ? Draggable<int>(
                            data: bank,
                            feedback: Container(
                              width: buttonHeight * 0.6,
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
                          ),
                  );
                }),
              ),
            );
          },
        );
      },
    );
  }
} 