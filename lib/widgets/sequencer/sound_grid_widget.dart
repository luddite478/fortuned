import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../state/sequencer_state.dart';
import '../stacked_cards_widget.dart';

class SampleGridWidget extends StatefulWidget {
  const SampleGridWidget({super.key});

  @override
  State<SampleGridWidget> createState() => _SampleGridWidgetState();
}

enum GestureMode { undetermined, scrolling, selecting }

class _SampleGridWidgetState extends State<SampleGridWidget> {
  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;
  static const double _autoScrollSpeed = 8.0;
  static const Duration _autoScrollInterval = Duration(milliseconds: 12);
  static const double _edgeThreshold = 50.0;
  
  Offset? _gestureStartPosition;
  Offset? _currentPanPosition;
  GestureMode _gestureMode = GestureMode.undetermined;
  static const double _gestureThreshold = 15.0;

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _startAutoScroll(double direction, Offset initialPosition, SequencerState sequencer) {
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
      final clampedOffset = newOffset.clamp(0.0, maxOffset);
      
      if (clampedOffset != currentOffset) {
        _scrollController.jumpTo(clampedOffset);
        
        final positionToUse = _currentPanPosition ?? initialPosition;
        final cellIndex = sequencer.getCellIndexFromPosition(positionToUse, context, scrollOffset: clampedOffset);
        if (cellIndex != null) {
          sequencer.handleGridCellSelection(cellIndex, true);
        }
      } else {
        timer.cancel();
        _autoScrollTimer = null;
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _handlePanUpdate(DragUpdateDetails details, SequencerState sequencer) {
    final localPosition = details.localPosition;
    _currentPanPosition = localPosition;
    
    if (_gestureMode == GestureMode.undetermined && _gestureStartPosition != null) {
      final delta = localPosition - _gestureStartPosition!;
      
      if (delta.distance > _gestureThreshold) {
        final isVertical = delta.dy.abs() > delta.dx.abs();
        
        if (sequencer.isInSelectionMode) {
          _gestureMode = GestureMode.selecting;
        } else if (isVertical) {
          _gestureMode = GestureMode.scrolling;
        } else {
          _gestureMode = GestureMode.selecting;
        }
      }
    }
    
    if (_gestureMode == GestureMode.selecting) {
      _handleSelectionGesture(localPosition, sequencer);
    }
  }
  
  void _handleSelectionGesture(Offset localPosition, SequencerState sequencer) {
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final cellIndex = sequencer.getCellIndexFromPosition(localPosition, context, scrollOffset: scrollOffset);
    
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final containerHeight = renderBox.size.height;
      final yPosition = localPosition.dy;
      
      if (yPosition < _edgeThreshold && _scrollController.hasClients && _scrollController.offset > 0) {
        _startAutoScroll(-1.0, localPosition, sequencer);
        if (cellIndex != null) {
          sequencer.handleGridCellSelection(cellIndex, true);
        }
        return;
      } else if (yPosition > containerHeight - _edgeThreshold && _scrollController.hasClients && _scrollController.offset < _scrollController.position.maxScrollExtent) {
        _startAutoScroll(1.0, localPosition, sequencer);
        if (cellIndex != null) {
          sequencer.handleGridCellSelection(cellIndex, true);
        }
        return;
      } else {
        _stopAutoScroll();
      }
    }
    
    if (cellIndex != null) {
      sequencer.handleGridCellSelection(cellIndex, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        const int numSoundGrids = 3; // Can be changed to any number
        
        // Initialize sound grids if not already done or if number changed
        if (sequencer.soundGridOrder.length != numSoundGrids) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            sequencer.initializeSoundGrids(numSoundGrids);
          });
          return const Center(child: CircularProgressIndicator());
        }
        
        return StackedCardsWidget(
          numCards: numSoundGrids,
          cardWidthFactor: 0.9,
          cardHeightFactor: 0.9,
          offsetPerDepth: const Offset(0, -10),
          scaleFactorPerDepth: 0.02,
          borderRadius: 12.0,
          cardColors: const [
            Color(0xFF1f2937),
            Color(0xFF374151),
          ],
          activeCardIndex: sequencer.currentSoundGridIndex,
          cardBuilder: (index, width, height, depth) {
            // Get the actual sound grid ID for this position using the sound grid order
            final actualSoundGridId = sequencer.soundGridOrder[index];
            
            // Define unique colors for each card ID (expandable list)
            final availableColors = [
              Colors.red,
              Colors.blue,
              Colors.green,
              Colors.purple,
              Colors.orange,
              Colors.pink,
              Colors.cyan,
              Colors.lime,
              Colors.amber,
              Colors.indigo,
            ];
            final cardColor = availableColors[actualSoundGridId % availableColors.length];
            
            // The front card (highest index, depth 0) always shows the sound grid
            final isFrontCard = index == (numSoundGrids - 1); // Front card is at highest index (depth 0)
            
            // Non-front cards are just visual placeholders
            if (!isFrontCard) {
              return Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: const Color(0xFF374151).withOpacity(0.8 - 0.1 * depth),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cardColor.withOpacity(0.8),
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: cardColor.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.music_note,
                          color: Colors.white.withOpacity(0.3),
                          size: 40,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'SoundGrid ${actualSoundGridId + 1}', // Show the actual sound grid ID
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Grid ID: $actualSoundGridId, Pos: $index, Depth: $depth',
                          style: TextStyle(
                            color: Colors.yellow.withOpacity(0.7),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Front Grid: ${sequencer.currentSoundGridIndex + 1}',
                          style: TextStyle(
                            color: Colors.cyan.withOpacity(0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use button to switch',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            
            // Main interactive card - ACTIVE CARD WITH SOUND GRID
            return Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: const Color(0xFF1f2937),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sequencer.isInSelectionMode 
                      ? Colors.cyanAccent 
                      : cardColor,
                  width: 4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Debug header for active card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.yellowAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.yellowAccent, width: 1),
                      ),
                      child: Text(
                        'FRONT SOUND GRID: ID $actualSoundGridId (SoundGrid ${actualSoundGridId + 1}) - Pos $index, Depth $depth',
                        style: const TextStyle(
                          color: Colors.yellowAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Sound grid
                    Expanded(
                      child: GestureDetector(
                        onPanStart: (details) {
                          _gestureStartPosition = details.localPosition;
                          _gestureMode = GestureMode.undetermined;
                          
                          if (sequencer.isInSelectionMode) {
                            final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                            final cellIndex = sequencer.getCellIndexFromPosition(details.localPosition, context, scrollOffset: scrollOffset);
                            if (cellIndex != null) {
                              sequencer.handleGridCellSelection(cellIndex, true);
                            }
                          }
                        },
                        onPanUpdate: (details) {
                          _handlePanUpdate(details, sequencer);
                        },
                        onPanEnd: (details) {
                          _gestureStartPosition = null;
                          _currentPanPosition = null;
                          _gestureMode = GestureMode.undetermined;
                          _stopAutoScroll();
                          
                          if (sequencer.isInSelectionMode) {
                            sequencer.handlePanEnd();
                          }
                        },
                        child: GridView.builder(
                          controller: _scrollController,
                          physics: (sequencer.isInSelectionMode || _gestureMode == GestureMode.selecting)
                              ? const NeverScrollableScrollPhysics()
                              : const AlwaysScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: sequencer.gridColumns,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                            childAspectRatio: 2.5,
                          ),
                          itemCount: sequencer.gridSamples.length,
                          itemBuilder: (context, index) {
                            return _buildGridCell(context, sequencer, index);
                          },
                        ),
                      ),
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

  Widget _buildGridCell(BuildContext context, SequencerState sequencer, int index) {
    final row = index ~/ sequencer.gridColumns;
    final col = index % sequencer.gridColumns;
    final isActivePad = sequencer.activePad == index;
    final isCurrentStep = sequencer.currentStep == row && sequencer.isSequencerPlaying;
    final placedSample = sequencer.gridSamples[index];
    final hasPlacedSample = placedSample != null;
    final isSelected = sequencer.selectedGridCells.contains(index);
    
    Color cellColor;
    if (isActivePad) {
      cellColor = Colors.white.withOpacity(0.3);
    } else if (isCurrentStep) {
      cellColor = hasPlacedSample 
          ? sequencer.bankColors[placedSample!].withOpacity(0.4)
          : Colors.grey.withOpacity(0.3);
    } else if (hasPlacedSample) {
      cellColor = sequencer.bankColors[placedSample!].withOpacity(0.3);
    } else {
      cellColor = const Color(0xFF404040).withOpacity(0.2);
    }
    
    return DragTarget<int>(
      onAccept: (int sampleSlot) {
        sequencer.placeSampleInGrid(sampleSlot, index);
      },
      builder: (context, candidateData, rejectedData) {
        final bool isDragHovering = candidateData.isNotEmpty;
        
        return GestureDetector(
          onTap: () {
            sequencer.handlePadPress(index);
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