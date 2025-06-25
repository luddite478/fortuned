import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sequencer_state.dart';

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
                color: const Color.fromARGB(255, 0, 0, 0),
                borderRadius: BorderRadius.circular(8),
                // border: Border.all(
                //   color: const Color.fromARGB(255, 17, 181, 22).withOpacity(0.3),
                //   width: 4,
                // ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Selection Mode Toggle button
                  SizedBox(
                    width: buttonSize,
                    height: buttonSize,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        sequencer.isInSelectionMode ? Icons.check_box : Icons.check_box_outline_blank,
                        color: sequencer.isInSelectionMode ? Colors.cyanAccent : Colors.grey,
                        size: iconSize,
                      ),
                      onPressed: () => sequencer.toggleSelectionMode(),
                      tooltip: sequencer.isInSelectionMode ? 'Exit Selection Mode' : 'Enter Selection Mode',
                    ),
                  ),
                  // Delete button
                  SizedBox(
                    width: buttonSize,
                    height: buttonSize,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.delete,
                        color: sequencer.selectedGridCells.isNotEmpty
                            ? Colors.redAccent
                            : Colors.grey,
                        size: iconSize,
                      ),
                      onPressed: sequencer.selectedGridCells.isNotEmpty
                          ? () => sequencer.deleteSelectedCells()
                          : null,
                      tooltip: 'Delete Selected Cells',
                    ),
                  ),
                  // Copy button
                  SizedBox(
                    width: buttonSize,
                    height: buttonSize,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.copy,
                        color: sequencer.selectedGridCells.isNotEmpty
                            ? Colors.cyanAccent
                            : Colors.grey,
                        size: iconSize,
                      ),
                      onPressed: sequencer.selectedGridCells.isNotEmpty
                          ? () => sequencer.copySelectedCells()
                          : null,
                      tooltip: 'Copy Selected Cells',
                    ),
                  ),
                  // Paste button
                  SizedBox(
                    width: buttonSize,
                    height: buttonSize,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.paste,
                        color: sequencer.hasClipboardData && sequencer.selectedGridCells.isNotEmpty
                            ? Colors.greenAccent
                            : Colors.grey,
                        size: iconSize,
                      ),
                      onPressed: sequencer.hasClipboardData && sequencer.selectedGridCells.isNotEmpty
                          ? () => sequencer.pasteToSelectedCells()
                          : null,
                      tooltip: 'Paste to Selected Cells',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
} 