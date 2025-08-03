import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';import 'dart:async';
import '../../../state/sequencer_state.dart';
import '../../../utils/app_colors.dart';import '../../stacked_cards_widget.dart';
import '../../../utils/app_colors.dart';

class SampleGridWidget extends StatefulWidget {
  const SampleGridWidget({super.key});

  // 🎯 SPACING CONFIGURATION - Percentage-based and easily controllable
  // All values are percentages of the container height for responsive scaling
  static const double topSpacingPercent = 6.0; // Space above labels (4% of height)
  static const double tabHeightPercent = 3.5; // Height allocated for tab labels (3.5% of height)
  static const double tabSpacingPercent = 5.0; // Gap between labels and sound grid (1% of height)
  
  // 🎯 TOTAL SPACING = topSpacingPercent + tabHeightPercent + tabSpacingPercent
  // Example: 4% + 3.5% + 1% = 8.5% of container height used for spacing
  
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

  Color _getSampleColorForGrid(int sampleSlot, SequencerState sequencer) {
    // Convert original bank colors to darker gray-beige variants for grid cells
    final originalColor = sequencer.bankColors[sampleSlot];
    return Color.lerp(originalColor, AppColors.sequencerCellFilled, 0.6) ?? AppColors.sequencerCellFilled;
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
              color: AppColors.sequencerBorder,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(2), // Sharp corners
            boxShadow: [
              // Protruding effect
              BoxShadow(
                color: AppColors.sequencerShadow,
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: StackedCardsWidget(
            numCards: numSoundGrids,
            cardWidthFactor: 1.0, // Use full width (was 0.9)
            cardHeightFactor: 1.0, // Use full height (was 0.9)
            offsetPerDepth: const Offset(0, -8),
            scaleFactorPerDepth: 0.02,
            borderRadius: 2.0, // Sharp corners
            cardColors: [
              AppColors.sequencerSurfaceBase,
              AppColors.sequencerSurfaceRaised,
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
            
            // Wrap everything in a container with configurable top spacing
            return SizedBox(
              width: width,
              height: height + 22, // Extra space for tab
              child: Stack(
                clipBehavior: Clip.none, // Allow tabs to be positioned outside bounds if needed
                children: [
                  // Main card positioned with percentage-based spacing
                  Positioned(
                    top: (height * SampleGridWidget.topSpacingPercent / 100) + 
                          (height * SampleGridWidget.tabHeightPercent / 100) + 
                          (height * SampleGridWidget.tabSpacingPercent / 100),
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
                  // Clickable tab label positioned with percentage-based spacing
                  // Use actualSoundGridId for positioning to maintain fixed horizontal positions
                  Positioned(
                    top: height * SampleGridWidget.topSpacingPercent / 100, // Top spacing only
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

  // 🎯 PERFORMANCE: Cell that only rebuilds when current step changes
  Widget _buildEnhancedGridCell(BuildContext context, SequencerState sequencer, int index) {
    final row = index ~/ sequencer.gridColumns;
    
    return ValueListenableBuilder<int>(
      valueListenable: sequencer.currentStepNotifier,
      builder: (context, currentStep, child) {
        final isActivePad = sequencer.activePad == index;
        final isCurrentStep = currentStep == row && sequencer.isSequencerPlaying;
        final placedSample = sequencer.gridSamples[index];
        final hasPlacedSample = placedSample != null;
        final isSelected = sequencer.selectedGridCells.contains(index);
        
        // 🎯 PERFORMANCE: Light bulb-bluish-white highlight for current step
        Color cellColor;
        if (isActivePad) {
          cellColor = AppColors.sequencerAccent.withOpacity(0.6);
                 } else if (isCurrentStep) {
           // Light bulb-bluish-white highlight for current step
           cellColor = hasPlacedSample 
               ? _getSampleColorForGrid(placedSample, sequencer).withOpacity(0.9)
               : const Color(0xFF87CEEB).withOpacity(0.4); // Light blue highlight
         } else if (hasPlacedSample) {
           cellColor = _getSampleColorForGrid(placedSample, sequencer);
        } else {
          cellColor = AppColors.sequencerCellEmpty;
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
                      ? AppColors.sequencerAccent.withOpacity(0.8)
                      : cellColor,
                  borderRadius: BorderRadius.circular(2),
                  border: isSelected 
                      ? Border.all(color: AppColors.sequencerAccent, width: 1.5)
                      : isCurrentStep 
                          ? Border.all(color: const Color(0xFF87CEEB), width: 1.5) // Light blue border for current step
                          : isDragHovering
                              ? Border.all(color: AppColors.sequencerAccent, width: 1.5)
                              : hasPlacedSample && !isActivePad
                                  ? Border.all(color: AppColors.sequencerBorder, width: 0.5)
                                  : Border.all(color: AppColors.sequencerBorder.withOpacity(0.3), width: 0.5),
                  boxShadow: isSelected 
                      ? [
                          BoxShadow(
                            color: AppColors.sequencerAccent.withOpacity(0.4),
                            blurRadius: 3,
                            spreadRadius: 0,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : isCurrentStep
                          ? [
                              // Extra glow for current step - light bulb effect
                              BoxShadow(
                                color: const Color(0xFF87CEEB).withOpacity(0.3),
                                blurRadius: 4,
                                spreadRadius: 1,
                                offset: const Offset(0, 0),
                              ),
                              BoxShadow(
                                color: AppColors.sequencerShadow,
                                blurRadius: 1,
                                offset: const Offset(0, 0.5),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: AppColors.sequencerShadow,
                                blurRadius: 1,
                                offset: const Offset(0, 0.5),
                              ),
                            ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                                             Text(
                         hasPlacedSample 
                             ? String.fromCharCode(65 + placedSample)
                             : '${row + 1}',
                        style: GoogleFonts.sourceSans3(
                          color: (isActivePad || isDragHovering) 
                              ? AppColors.sequencerPageBackground 
                              : isCurrentStep
                                  ? Colors.white // Bright white text for current step
                                  : AppColors.sequencerText,
                          fontWeight: isCurrentStep ? FontWeight.bold : FontWeight.w600,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (isSelected) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.sequencerAccent,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ] else ...[
                        Text(
                          'C-4',
                          style: GoogleFonts.sourceSans3(
                            color: (isActivePad || isDragHovering)
                                ? AppColors.sequencerPageBackground
                                : isCurrentStep
                                    ? Colors.white.withOpacity(0.8) // Bright text for current step
                                    : AppColors.sequencerLightText.withOpacity(0.6),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3,
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
      },
    );
  }

  Widget _buildGridCell(BuildContext context, SequencerState sequencer, int index) {
    // 🎯 PERFORMANCE: Use enhanced cell that listens to currentStepNotifier
    return _buildEnhancedGridCell(context, sequencer, index);
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
              ? AppColors.sequencerSurfaceRaised // Active tab protruding
              : AppColors.sequencerSurfaceBase, // Inactive tabs recessed
          borderRadius: BorderRadius.circular(2), // Sharp corners
          border: Border.all(
            color: isFrontCard 
                ? AppColors.sequencerAccent // Brown accent for active
                : AppColors.sequencerBorder, // Subtle border for inactive
            width: isFrontCard ? 1.0 : 0.5,
          ),
          boxShadow: isFrontCard 
              ? [
                  BoxShadow(
                    color: AppColors.sequencerShadow,
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                  // Extra highlight for protruding effect
                  BoxShadow(
                    color: AppColors.sequencerSurfaceRaised,
                    blurRadius: 1,
                    offset: const Offset(0, -0.5),
                  ),
                ]
              : [
                  BoxShadow(
                    color: AppColors.sequencerShadow,
                    blurRadius: 1,
                    offset: const Offset(0, 0.5),
                  ),
                ],
        ),
        child: Center(
          child: Text(
            'L${gridIndex + 1}',
            style: GoogleFonts.sourceSans3(
              color: isFrontCard 
                  ? AppColors.sequencerText // Light text for active tab
                  : AppColors.sequencerLightText, // Muted text for inactive tab
              fontSize: 12,
              fontWeight: isFrontCard ? FontWeight.bold : FontWeight.w600,
              letterSpacing: 1,
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
          color: AppColors.sequencerSurfaceBase.withOpacity(0.4 - 0.1 * depth), // Muted background
          borderRadius: BorderRadius.circular(2), // Sharp corners
          border: Border.all(
            color: AppColors.sequencerBorder.withOpacity(0.6),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.sequencerShadow.withOpacity(0.3),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(4), // Reduced margin from 16 to 4
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfacePressed.withOpacity(0.1),
            borderRadius: BorderRadius.circular(2), // Sharp corners
            border: Border.all(
              color: AppColors.sequencerBorder.withOpacity(0.3),
              width: 0.5,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.music_note,
                  color: AppColors.sequencerLightText.withOpacity(0.3),
                  size: 40,
                ),
                const SizedBox(height: 8),
                Text(
                  sequencer.getGridLabel(actualSoundGridId),
                  style: GoogleFonts.sourceSans3(
                    color: AppColors.sequencerLightText.withOpacity(0.4),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
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
        color: AppColors.sequencerSurfaceRaised, // Gray-beige surface
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: sequencer.isInSelectionMode 
              ? AppColors.sequencerAccent 
              : AppColors.sequencerBorder, // Brown accent or subtle border
          width: sequencer.isInSelectionMode ? 2 : 1, // Thicker border when in selection mode
        ),
        boxShadow: [
          // Strong protruding effect for front card
          BoxShadow(
            color: AppColors.sequencerShadow,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: AppColors.sequencerSurfaceRaised,
            blurRadius: 2,
            offset: const Offset(0, -1),
          ),
          // Additional highlight for selection mode
          if (sequencer.isInSelectionMode)
            BoxShadow(
              color: AppColors.sequencerAccent.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 0),
            ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.zero, // Removed padding to take full available space
        child: Column(
          children: [
            // Sound grid (no internal spacing needed - whole structure moves together)
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