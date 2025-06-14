import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/tracker_state.dart';

class SampleGridWidget extends StatelessWidget {
  const SampleGridWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TrackerState>(
      builder: (context, tracker, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1f2937),
            borderRadius: BorderRadius.circular(12),
          ),
          child: GestureDetector(
            onPanStart: (details) {
              // Find which cell we started in
              final localPosition = details.localPosition;
              final cellIndex = tracker.getCellIndexFromPosition(localPosition, context);
              if (cellIndex != null) {
                tracker.handleGridCellSelection(cellIndex, true);
              }
            },
            onPanUpdate: (details) {
              // Find which cell we're currently over
              final localPosition = details.localPosition;
              final cellIndex = tracker.getCellIndexFromPosition(localPosition, context);
              if (cellIndex != null) {
                tracker.handleGridCellSelection(cellIndex, true);
              }
            },
            onPanEnd: (details) {
              tracker.handleGridCellSelection(0, false); // End selection
            },
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: tracker.gridColumns,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
                childAspectRatio: 2.5,
              ),
              itemCount: tracker.gridSamples.length,
              itemBuilder: (context, index) {
                return _buildGridCell(context, tracker, index);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridCell(BuildContext context, TrackerState tracker, int index) {
    final row = index ~/ tracker.gridColumns;
    final col = index % tracker.gridColumns;
    final isActivePad = tracker.activePad == index;
    final isCurrentStep = tracker.currentStep == row && tracker.isSequencerPlaying;
    final placedSample = tracker.gridSamples[index];
    final hasPlacedSample = placedSample != null;
    final isSelected = tracker.selectedGridCells.contains(index);
    
    // Keep original colors for cells, selection only affects border
    Color cellColor;
    if (isActivePad) {
      cellColor = Colors.white;
    } else if (isCurrentStep) {
      cellColor = hasPlacedSample 
          ? tracker.bankColors[placedSample!].withOpacity(0.8)
          : Colors.grey.withOpacity(0.6); // Highlight current step
    } else if (hasPlacedSample) {
      cellColor = tracker.bankColors[placedSample!];
    } else {
      cellColor = const Color(0xFF404040); // Default gray for empty cells
    }
    
    return DragTarget<int>(
      onAccept: (int sampleSlot) {
        tracker.placeSampleInGrid(sampleSlot, index);
      },
      builder: (context, candidateData, rejectedData) {
        final bool isDragHovering = candidateData.isNotEmpty;
        
        return GestureDetector(
          onTap: () {
            if (tracker.selectedGridCells.isNotEmpty && !tracker.selectedGridCells.contains(index)) {
              // Clear all selections if tapping on unselected cell
              tracker.handlePadPress(index);
            } else {
              // Normal tap behavior - always prioritize selection
              tracker.handlePadPress(index);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              color: isDragHovering 
                  ? Colors.greenAccent.withOpacity(0.6)
                  : cellColor,
              borderRadius: BorderRadius.circular(4),
              border: isSelected 
                  ? Border.all(color: Colors.yellowAccent, width: 2)
                  : isCurrentStep 
                      ? Border.all(color: Colors.yellowAccent, width: 2)
                      : isDragHovering
                          ? Border.all(color: Colors.greenAccent, width: 2)
                          : hasPlacedSample && !isActivePad
                              ? Border.all(color: Colors.white24, width: 1)
                              : Border.all(color: Colors.transparent, width: 1),
              boxShadow: isSelected 
                  ? [
                      BoxShadow(
                        color: Colors.yellowAccent.withOpacity(0.3),
                        blurRadius: 4,
                        spreadRadius: 0,
                      )
                    ]
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    hasPlacedSample 
                        ? String.fromCharCode(65 + placedSample!)
                        : '${row + 1}',
                    style: TextStyle(
                      color: (isActivePad || isDragHovering) ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  if (isSelected) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.yellowAccent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ] else ...[
                    Text(
                      'C-4',
                      style: TextStyle(
                        color: (isActivePad || isDragHovering)
                            ? Colors.black54
                            : Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
} 