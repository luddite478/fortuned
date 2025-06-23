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
        const int numSoundGrids = 4; // Can be changed to any number
        
        // Initialize sound grids if not already done or if number changed
        if (sequencer.soundGridOrder.length != numSoundGrids) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            sequencer.initializeSoundGrids(numSoundGrids);
          });
          return const Center(child: CircularProgressIndicator());
        }
        
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color.fromARGB(255, 51, 51, 51), // Bright red border to make it visible
              width: 2,
            ),
          ),
          child: StackedCardsWidget(
            numCards: numSoundGrids,
            cardWidthFactor: 0.9,
            cardHeightFactor: 0.9,
            offsetPerDepth: const Offset(0, -8),
            scaleFactorPerDepth: 0.02,
            borderRadius: 12.0,
            cardColors: const [
              Color(0xFF1f2937),
              Color(0xFF374151),
            ],
            activeCardIndex: sequencer.currentSoundGridIndex,
          cardBuilder: (index, width, height, depth) {
            // INVERSION LOGIC: Stack index 0 = back card, but we want L1 to be front
            // So we need to invert: front card (highest stack index) = L1 (first grid)
            final invertedIndex = numSoundGrids - 1 - index;
            final actualSoundGridId = sequencer.soundGridOrder[invertedIndex];
            
            // Define subtle colors for each card ID (non-vibrant, more professional)
            final availableColors = [
              const Color(0xFF4B5563), // Gray-600
              const Color(0xFF6B7280), // Gray-500  
              const Color(0xFF374151), // Gray-700
              const Color(0xFF9CA3AF), // Gray-400
              const Color(0xFF1F2937), // Gray-800
              const Color(0xFF111827), // Gray-900
              const Color(0xFFD1D5DB), // Gray-300
              const Color(0xFFF3F4F6), // Gray-100
              const Color(0xFF6B7280), // Gray-500 (repeat for more grids)
              const Color(0xFF374151), // Gray-700 (repeat for more grids)
            ];
            final cardColor = availableColors[actualSoundGridId % availableColors.length];
            
            // The front card is the one that matches the current sound grid index
            final isFrontCard = actualSoundGridId == sequencer.currentSoundGridIndex;
            
            // Wrap everything in a container with minimal extra space for the label tab
            return SizedBox(
              width: width,
              height: height + 22, // Reduced extra space for tab
              child: Stack(
                clipBehavior: Clip.none, // Allow tabs to be positioned outside bounds if needed
                children: [
                  // Main card positioned to leave minimal space for tab at top
                  Positioned(
                    top: 18, // Reduced space for tab
                    left: 0,
                    child: _buildMainCard(
                      width: width,
                      height: height,
                      cardColor: cardColor,
                      isFrontCard: isFrontCard,
                      depth: depth,
                      actualSoundGridId: actualSoundGridId,
                      index: index,
                      sequencer: sequencer,
                    ),
                  ),
                  // Clickable tab label positioned above the card
                  // Use actualSoundGridId for positioning to maintain fixed horizontal positions
                  Positioned(
                    top: 0, // At the very top
                    left: _calculateTabPosition(actualSoundGridId, width, numSoundGrids),
                    child: _buildClickableTabLabel(
                      gridIndex: actualSoundGridId,
                      cardColor: cardColor,
                      isFrontCard: isFrontCard,
                      depth: depth,
                      tabWidth: _calculateTabWidth(width, numSoundGrids),
                      sequencer: sequencer,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
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



  Widget _buildClickableTabLabel({
    required int gridIndex,
    required Color cardColor,
    required bool isFrontCard,
    required int depth,
    required double tabWidth,
    required SequencerState sequencer,
  }) {
    return GestureDetector(
      onTap: () {
        // Bring this grid to front when its label is tapped
        sequencer.bringGridToFront(gridIndex);
      },
      child: Container(
        width: tabWidth,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: isFrontCard 
              ? Colors.white // Solid white for active tab
              : const Color(0xFFF3F4F6), // Light gray for inactive tabs
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isFrontCard 
                ? const Color(0xFF374151) // Dark gray border for active
                : const Color(0xFF9CA3AF), // Medium gray border for inactive
            width: isFrontCard ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isFrontCard ? 0.15 : 0.05),
              blurRadius: isFrontCard ? 2 : 1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Text(
            'L${gridIndex + 1}',
            style: TextStyle(
              color: isFrontCard 
                  ? const Color(0xFF374151) // Dark text for active tab
                  : const Color(0xFF6B7280), // Gray text for inactive tab
              fontSize: 12,
              fontWeight: isFrontCard ? FontWeight.bold : FontWeight.w600,
              letterSpacing: 1,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildTabLabel({
    required int gridIndex,
    required Color cardColor,
    required bool isFrontCard,
    required int depth,
    required double tabWidth,
  }) {
    return Container(
      width: tabWidth,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: cardColor.withOpacity(0.8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          'L${gridIndex + 1}',
          style: TextStyle(
            color: cardColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            fontFamily: 'monospace',
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildMainCard({
    required double width,
    required double height,
    required Color cardColor,
    required bool isFrontCard,
    required int depth,
    required int actualSoundGridId,
    required int index,
    required SequencerState sequencer,
  }) {
    // Non-front cards are grayed out but still visible
    if (!isFrontCard) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF374151).withOpacity(0.6 - 0.1 * depth), // Less grayed out, more visible
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF9CA3AF).withOpacity(0.6), // More visible border
            width: 1.5, // Slightly thicker border
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF6B7280).withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF6B7280).withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.music_note,
                  color: Colors.white.withOpacity(0.15),
                  size: 40,
                ),
                const SizedBox(height: 8),
                Text(
                  sequencer.getGridLabel(actualSoundGridId),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.25),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Front card - clearly highlighted as selected
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF1f2937), // Clean dark background
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: sequencer.isInSelectionMode 
              ? Colors.cyanAccent 
              : const Color(0xFFE5E7EB), // Bright highlight border for selected card
          width: 3, // Thicker border to show selection
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          // Additional glow effect for front card
          BoxShadow(
            color: const Color(0xFFE5E7EB).withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12), // Reduced padding
        child: Column(
          children: [
            // Minimal space for tab label above
            const SizedBox(height: 4),
            // Sound grid
            Expanded(
              child: _buildGridContent(sequencer),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridContent(SequencerState sequencer) {
    return GestureDetector(
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
    );
  }

  double _calculateTabPosition(int index, double width, int numSoundGrids) {
    // Calculate tab width with relative spacing
    final tabWidth = _calculateTabWidth(width, numSoundGrids);
    final spacingBetweenTabs = _calculateTabSpacing(width, numSoundGrids);
    
    // Position from left to right with spacing
    final leftMargin = 8.0; // Small left margin
    
    // Important: Use only the available card width for positioning
    // The cards may be transformed by StackedCardsWidget but tabs need to align with card boundaries
    return leftMargin + (tabWidth + spacingBetweenTabs) * index;
  }

  double _calculateTabWidth(double width, int numSoundGrids) {
    // Calculate available width for tabs (leaving small margins)
    final leftMargin = 8.0;
    final rightMargin = 8.0;
    final availableWidth = width - leftMargin - rightMargin;
    
    // Calculate spacing between tabs (relative to number of tabs)
    final spacingBetweenTabs = _calculateTabSpacing(width, numSoundGrids);
    final totalSpacing = spacingBetweenTabs * (numSoundGrids - 1);
    
    // Calculate tab width with relative spacing
    final tabWidth = (availableWidth - totalSpacing) / numSoundGrids;
    
    // Ensure minimum tab width
    return tabWidth.clamp(40.0, double.infinity);
  }

  double _calculateTabSpacing(double width, int numSoundGrids) {
    // Relative spacing based on number of tabs and available width
    // More tabs = smaller spacing, fewer tabs = more spacing
    final baseSpacing = width * 0.1; // 2% of card width as base
    final scaleFactor = 1.0 / numSoundGrids; // Reduce spacing as tabs increase
    
    return (baseSpacing * scaleFactor).clamp(2.0, 12.0); // Min 2px, Max 12px
  }
} 