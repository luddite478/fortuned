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
              // Test button (placeholder)
              IconButton(
                icon: const Icon(Icons.science, color: Colors.grey),
                onPressed: null, // No logic for now
                tooltip: 'Test (Coming Soon)',
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