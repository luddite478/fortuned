import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/tracker_state.dart';

class EditButtonsWidget extends StatelessWidget {
  const EditButtonsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TrackerState>(
      builder: (context, tracker, child) {
        return Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1f2937),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Card Switch button
              IconButton(
                icon: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.layers, color: Colors.orangeAccent),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.yellowAccent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange, width: 1),
                        ),
                        child: Center(
                          child: Text(
                            '${tracker.currentCardIndex + 1}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                onPressed: () => tracker.shuffleToNextCard(),
                tooltip: 'Shuffle Cards (Front: Card ${tracker.currentCardIndex + 1}/${tracker.cardOrder.length})',
              ),
              // Selection Mode Toggle button
              IconButton(
                icon: Icon(
                  tracker.isInSelectionMode ? Icons.check_box : Icons.check_box_outline_blank,
                  color: tracker.isInSelectionMode ? Colors.cyanAccent : Colors.grey,
                ),
                onPressed: () => tracker.toggleSelectionMode(),
                tooltip: tracker.isInSelectionMode ? 'Exit Selection Mode' : 'Enter Selection Mode',
              ),
              // Delete button
              IconButton(
                icon: Icon(
                  Icons.delete,
                  color: tracker.selectedGridCells.isNotEmpty
                      ? Colors.redAccent
                      : Colors.grey,
                ),
                onPressed: tracker.selectedGridCells.isNotEmpty
                    ? () => tracker.deleteSelectedCells()
                    : null,
                tooltip: 'Delete Selected Cells',
              ),
              // Copy button
              IconButton(
                icon: Icon(
                  Icons.copy,
                  color: tracker.selectedGridCells.isNotEmpty
                      ? Colors.cyanAccent
                      : Colors.grey,
                ),
                onPressed: tracker.selectedGridCells.isNotEmpty
                    ? () => tracker.copySelectedCells()
                    : null,
                tooltip: 'Copy Selected Cells',
              ),
              // Paste button
              IconButton(
                icon: Icon(
                  Icons.paste,
                  color: tracker.hasClipboardData && tracker.selectedGridCells.isNotEmpty
                      ? Colors.greenAccent
                      : Colors.grey,
                ),
                onPressed: tracker.hasClipboardData && tracker.selectedGridCells.isNotEmpty
                    ? () => tracker.pasteToSelectedCells()
                    : null,
                tooltip: 'Paste to Selected Cells',
              ),
            ],
          ),
        );
      },
    );
  }
} 