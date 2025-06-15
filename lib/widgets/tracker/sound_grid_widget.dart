import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../state/tracker_state.dart';

class SampleGridWidget extends StatefulWidget {
  const SampleGridWidget({super.key});

  @override
  State<SampleGridWidget> createState() => _SampleGridWidgetState();
}

enum GestureMode { undetermined, scrolling, selecting }

class _SampleGridWidgetState extends State<SampleGridWidget> {
  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;
  static const double _autoScrollSpeed = 8.0; // pixels per timer tick
  static const Duration _autoScrollInterval = Duration(milliseconds: 12); // ~83fps
  static const double _edgeThreshold = 50.0; // pixels from edge to trigger auto-scroll
  
  // Gesture direction detection
  Offset? _gestureStartPosition;
  Offset? _currentPanPosition; // Track current pan position for auto-scroll
  GestureMode _gestureMode = GestureMode.undetermined;
  static const double _gestureThreshold = 15.0; // pixels to determine gesture direction

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _startAutoScroll(double direction, Offset initialPosition, TrackerState tracker) {
    // Don't start a new timer if one is already running in the same direction
    if (_autoScrollTimer != null) {
      return;
    }
    
    _autoScrollTimer = Timer.periodic(_autoScrollInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        _autoScrollTimer = null;
        return;
      }

      final currentOffset = _scrollController.offset;
      final maxOffset = _scrollController.position.maxScrollExtent;
      final newOffset = currentOffset + (direction * _autoScrollSpeed);

      // Clamp to valid scroll range
      final clampedOffset = newOffset.clamp(0.0, maxOffset);
      
      if (clampedOffset != currentOffset) {
        _scrollController.jumpTo(clampedOffset);
        
        // Continue selection at the CURRENT pan position (not the initial position)
        // This ensures we select cells as the user continues to drag
        final positionToUse = _currentPanPosition ?? initialPosition;
        final cellIndex = tracker.getCellIndexFromPosition(positionToUse, context, scrollOffset: clampedOffset);
        if (cellIndex != null) {
          print('🎯 Auto-scroll selecting cell: $cellIndex at position: $positionToUse, scrollOffset: $clampedOffset');
          tracker.handleGridCellSelection(cellIndex, true);
        } else {
          print('⚠️ Auto-scroll could not find cell at position: $positionToUse, scrollOffset: $clampedOffset');
        }
      } else {
        // Reached scroll limit, stop auto-scroll
        timer.cancel();
        _autoScrollTimer = null;
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

    void _handlePanUpdate(DragUpdateDetails details, TrackerState tracker) {
    final localPosition = details.localPosition;
    _currentPanPosition = localPosition; // Store current position for auto-scroll
    
    // Determine gesture mode if still undetermined
    if (_gestureMode == GestureMode.undetermined && _gestureStartPosition != null) {
      final delta = localPosition - _gestureStartPosition!;
      
      if (delta.distance > _gestureThreshold) {
        final isVertical = delta.dy.abs() > delta.dx.abs();
        
        print('🎯 Gesture detected: delta=$delta, distance=${delta.distance}, isVertical=$isVertical, inSelectionMode=${tracker.isInSelectionMode}');
        
        // SIMPLIFIED Decision logic:
        // - If in selection mode: ALWAYS select (never scroll)
        // - If not in selection mode and vertical movement: scroll
        // - Otherwise: select
        if (tracker.isInSelectionMode) {
          _gestureMode = GestureMode.selecting;
          print('✅ Mode: SELECTING (forced by selection mode)');
        } else if (isVertical) {
          _gestureMode = GestureMode.scrolling;
          print('📜 Mode: SCROLLING (vertical movement, not in selection mode)');
        } else {
          _gestureMode = GestureMode.selecting;
          print('✅ Mode: SELECTING (horizontal movement)');
        }
      }
    }
    
    // Handle based on determined gesture mode
    if (_gestureMode == GestureMode.selecting) {
      _handleSelectionGesture(localPosition, tracker);
    }
    // If scrolling mode, let the GridView handle it naturally
  }
  
  void _handleSelectionGesture(Offset localPosition, TrackerState tracker) {
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final cellIndex = tracker.getCellIndexFromPosition(localPosition, context, scrollOffset: scrollOffset);
    
    // Check for edge scrolling during selection
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final containerHeight = renderBox.size.height;
      final yPosition = localPosition.dy;
      
      if (yPosition < _edgeThreshold && _scrollController.hasClients && _scrollController.offset > 0) {
        // Near top edge and can scroll up
        _startAutoScroll(-1.0, localPosition, tracker);
        // STILL process current cell selection even when starting auto-scroll
        if (cellIndex != null) {
          tracker.handleGridCellSelection(cellIndex, true);
        }
        return;
      } else if (yPosition > containerHeight - _edgeThreshold && _scrollController.hasClients && _scrollController.offset < _scrollController.position.maxScrollExtent) {
        // Near bottom edge and can scroll down
        _startAutoScroll(1.0, localPosition, tracker);
        // STILL process current cell selection even when starting auto-scroll
        if (cellIndex != null) {
          tracker.handleGridCellSelection(cellIndex, true);
        }
        return;
      } else {
        _stopAutoScroll();
      }
    }
    
    // Process cell selection if we're not auto-scrolling
    if (cellIndex != null) {
      tracker.handleGridCellSelection(cellIndex, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TrackerState>(
      builder: (context, tracker, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1f2937),
            borderRadius: BorderRadius.circular(12),
            // Add visual feedback for selection mode
            border: tracker.isInSelectionMode 
                ? Border.all(color: Colors.cyanAccent, width: 2)
                : null,
          ),
          child: GestureDetector(
            // Only enable pan gestures when in selection mode
            onPanStart: (details) {
              // Reset gesture state
              _gestureStartPosition = details.localPosition;
              _gestureMode = GestureMode.undetermined;
              
              // If in selection mode, start selection immediately
              if (tracker.isInSelectionMode) {
                final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                final cellIndex = tracker.getCellIndexFromPosition(details.localPosition, context, scrollOffset: scrollOffset);
                if (cellIndex != null) {
                  tracker.handleGridCellSelection(cellIndex, true);
                }
              }
            },
            onPanUpdate: (details) {
              _handlePanUpdate(details, tracker);
            },
            onPanEnd: (details) {
              // Reset gesture state and stop auto-scroll
              _gestureStartPosition = null;
              _currentPanPosition = null;
              _gestureMode = GestureMode.undetermined;
              _stopAutoScroll();
              
              // End selection if we were selecting
              if (tracker.isInSelectionMode) {
                tracker.handlePanEnd();
              }
            },
            child: GridView.builder(
              controller: _scrollController,
              // Smart physics based on selection mode and gesture mode
              physics: (tracker.isInSelectionMode || _gestureMode == GestureMode.selecting)
                  ? const NeverScrollableScrollPhysics() // Prevent user scrolling during selection
                  : const AlwaysScrollableScrollPhysics(), // Allow scrolling otherwise
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
                                  // 🚀 Use version with sequencer sync
                          tracker.placeSampleInGrid(sampleSlot, index);
      },
      builder: (context, candidateData, rejectedData) {
        final bool isDragHovering = candidateData.isNotEmpty;
        
        return GestureDetector(
          onTap: () {
            // Simply call handlePadPress - it now handles all selection logic including multi-select and double-tap
            tracker.handlePadPress(index);
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