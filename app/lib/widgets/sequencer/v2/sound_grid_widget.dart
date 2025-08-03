import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';import 'dart:async';
import 'dart:math' as math;
import '../../../state/sequencer_state.dart';
import '../../../utils/app_colors.dart';import '../../stacked_cards_widget.dart';
import '../../../utils/app_colors.dart';
// Custom ScrollPhysics to retain position when content changes
class PositionRetainedScrollPhysics extends ScrollPhysics {
  final bool shouldRetain;
  const PositionRetainedScrollPhysics({super.parent, this.shouldRetain = true});

  @override
  PositionRetainedScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return PositionRetainedScrollPhysics(
      parent: buildParent(ancestor),
      shouldRetain: shouldRetain,
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final position = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );

    final diff = newPosition.maxScrollExtent - oldPosition.maxScrollExtent;

    // Always retain position when content is added (diff > 0), regardless of scroll position
    if (diff > 0 && shouldRetain) {
      return position + diff;
    } else {
      return position;
    }
  }
}


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

  // CONFIGURABLE GRID DIMENSIONS - Easy to control cell sizing
  static const double cellWidthPercent = 98.0; // Cell width as % of available column space (reduced to make room for row numbers)
  static const double cellHeightPercent = 60.0; // Cell height as % of available row space  
  static const double cellSpacingPercent = 0.0; // Spacing between cells as % of available space
  static const double rowSpacingPercent = 0.0; // Spacing between rows as % of available space
  static const double rowNumberColumnWidthPercent = 6.0; // Row number column width as % of total width
  static const Color rowNumberColumnColor = Color.fromARGB(121, 40, 46, 39); // Color for row number column
  
  // CONFIGURABLE CONTENT SIZING - Control text and element sizes
  static const double sampleLetterFontSize = 14.0; // Font size for sample letters (A, B, C, etc.)
  static const double effectsFontSize = 8.0; // Font size for effects text (V45, K-4, etc.)
  static const double cellPaddingPercent = 0.0; // Internal padding as % of cell size
  
  // CONFIGURATION EXAMPLES - Uncomment and modify as needed:
  // 
  // COMPACT GRID (smaller cells, more spacing):
  // static const double cellWidthPercent = 85.0;
  // static const double cellHeightPercent = 30.0;
  // static const double cellSpacingPercent = 15.0;
  // static const double rowSpacingPercent = 10.0;
  // static const double sampleLetterFontSize = 12.0;
  // static const double effectsFontSize = 7.0;
  //
  // LARGE GRID (bigger cells, less spacing):
  // static const double cellWidthPercent = 98.0;
  // static const double cellHeightPercent = 60.0;
  // static const double cellSpacingPercent = 2.0;
  // static const double rowSpacingPercent = 2.0;
  // static const double sampleLetterFontSize = 16.0;
  // static const double effectsFontSize = 9.0;
  //
  // RECTANGULAR CELLS (wider than tall):
  // static const double cellAspectRatio = 1.5; // 1.5:1 ratio (wider cells)
  // static const double cellAspectRatio = 0.75; // 3:4 ratio (taller cells)

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    _stopAllActions(); // Clean up button press timer
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
          margin: const EdgeInsets.only(top: 0, bottom: 0), // Move entire sound grid structure
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 0,
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
            cardWidthFactor: 0.98,
            cardHeightFactor: 0.98,
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
            
            // Wrap everything in a container with minimal extra space for the label tab
            return SizedBox(
              width: width,
              height: height + 100, // More space for tabs positioned lower
              child: Stack(
                clipBehavior: Clip.none, // Allow tabs to be positioned outside bounds if needed
                children: [
                  // Main card positioned to leave space for tab at top
                  Positioned(
                    top: 37, // More space for tab positioned lower
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
                    top: 15, // Positioned lower to stay within container bounds
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
          // Alternate cell color for every 4th row (1, 5, 9, etc. in 1-indexed terms)
          final isAlternateRow = row % 4 == 0;
          cellColor = isAlternateRow 
              ? AppColors.sequencerCellEmptyAlternate 
              : AppColors.sequencerCellEmpty;
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
              child: Container(
                width: double.infinity, // Fill available width
                height: double.infinity, // Fill available height
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final actualPadding = math.min(constraints.maxWidth, constraints.maxHeight) * (cellPaddingPercent / 100.0);
                    return Padding(
                      padding: EdgeInsets.all(actualPadding), // Use percentage-based padding relative to cell size
                      child: hasPlacedSample ? _buildSampleCellContent(sequencer, index, placedSample!, isActivePad, isCurrentStep, isDragHovering) : _buildEmptyCellContent(),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSampleCellContent(SequencerState sequencer, int index, int sampleSlot, bool isActivePad, bool isCurrentStep, bool isDragHovering) {
    // Get volume and pitch values
    final cellVolume = sequencer.getCellVolume(index);
    final sampleVolume = sequencer.getSampleVolume(sampleSlot);
    final cellPitch = sequencer.getCellPitch(index);
    final samplePitch = sequencer.getSamplePitch(sampleSlot);
    
    // Check if values are non-default (cell overrides)
    final hasVolumeOverride = (cellVolume - sampleVolume).abs() > 0.001;
    final hasPitchOverride = (cellPitch - samplePitch).abs() > 0.001;
    
    // Only show table if there are non-default values
    final showEffectsTable = hasVolumeOverride || hasPitchOverride;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Sample letter (always shown on the left)
        Text(
          String.fromCharCode(65 + sampleSlot),
          style: GoogleFonts.sourceSans3(
            color: (isActivePad || isDragHovering) 
                ? AppColors.sequencerPageBackground 
                : isCurrentStep
                    ? Colors.white // Bright white text for current step
                    : AppColors.sequencerText,
            fontWeight: isCurrentStep ? FontWeight.bold : FontWeight.w600,
            fontSize: sampleLetterFontSize,
            letterSpacing: 0.5,
          ),
        ),
        
        // Effects table (only shown if there are non-default values, positioned on the right)
        if (showEffectsTable) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.sequencerPageBackground.withOpacity(0.3),
              borderRadius: BorderRadius.circular(1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasVolumeOverride) ...[
                  Text(
                    'V${(cellVolume * 100).round()}',
                    style: GoogleFonts.sourceSans3(
                      color: (isActivePad || isDragHovering)
                          ? AppColors.sequencerPageBackground
                          : isCurrentStep
                              ? Colors.white.withOpacity(0.9)
                              : AppColors.sequencerLightText,
                      fontSize: effectsFontSize,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
                if (hasPitchOverride) ...[
                  Text(
                    _formatPitchDisplay(cellPitch),
                    style: GoogleFonts.sourceSans3(
                      color: (isActivePad || isDragHovering)
                          ? AppColors.sequencerPageBackground
                          : isCurrentStep
                              ? Colors.white.withOpacity(0.9)
                              : AppColors.sequencerLightText,
                      fontSize: effectsFontSize,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyCellContent() {
    // Return a simple container to maintain consistent cell size
    return const SizedBox.shrink();
  }

  String _formatPitchDisplay(double pitchRatio) {
    // Convert pitch ratio to semitones from center (1.0 = 0 semitones)
    final semitones = 12.0 * (math.log(pitchRatio) / math.ln2);
    final semitonesRounded = semitones.round();
    
    if (semitonesRounded == 0) {
      return 'K0';
    } else if (semitonesRounded > 0) {
      return 'K+$semitonesRounded';
    } else {
      return 'K$semitonesRounded'; // Negative sign is included in the number
    }
  }

  Widget _buildGridCell(BuildContext context, SequencerState sequencer, int index) {
    // 🎯 PERFORMANCE: Use enhanced cell that listens to currentStepNotifier
    return _buildEnhancedGridCell(context, sequencer, index);
  }

  Widget _buildGridRow(BuildContext context, SequencerState sequencer, int rowIndex) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate dimensions based on percentages
        final availableWidth = constraints.maxWidth;
        final baseRowHeight = 50.0; // Base height for percentage calculation
        final actualRowHeight = baseRowHeight * (cellHeightPercent / 100.0);
        final actualCellSpacing = availableWidth * (cellSpacingPercent / 100.0);
        final actualRowSpacing = baseRowHeight * (rowSpacingPercent / 100.0);
        
        // Calculate row number column width and grid area
        final actualRowNumberColumnWidth = availableWidth * (rowNumberColumnWidthPercent / 100.0);
        final availableWidthForGrid = availableWidth - actualRowNumberColumnWidth;
        final totalHorizontalSpacing = actualCellSpacing * (sequencer.gridColumns - 1);
        final availableWidthForCells = availableWidthForGrid - totalHorizontalSpacing;
        final fullCellWidth = availableWidthForCells / sequencer.gridColumns;
        final actualCellWidth = fullCellWidth * (cellWidthPercent / 100.0);
        
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: 0, 
            vertical: actualRowSpacing / 2, // Use calculated row spacing
          ),
          child: Row(
            children: [
              // Row number column on the left
              Container(
                width: actualRowNumberColumnWidth,
                height: actualRowHeight,
                decoration: BoxDecoration(
                  color: rowNumberColumnColor,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Center(
                  child: Text(
                    '${rowIndex + 1}',
                    style: GoogleFonts.sourceSans3(
                      color: AppColors.sequencerText,
                      fontSize: 9,
                      // fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              // Grid cells
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(sequencer.gridColumns, (colIndex) {
                    final cellIndex = rowIndex * sequencer.gridColumns + colIndex;
                    return Container(
                      width: actualCellWidth,
                      height: actualRowHeight,
                      margin: EdgeInsets.symmetric(
                        horizontal: actualCellSpacing / 2, // Use calculated cell spacing
                      ),
                      child: _buildGridCell(context, sequencer, cellIndex),
                    );
                  }),
                ),
              ),
            ],
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
          color: AppColors.sequencerSurfaceBase, // Full opacity background
          borderRadius: BorderRadius.circular(2), // Sharp corners
          border: Border.all(
            color: AppColors.sequencerBorder,
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.sequencerShadow,
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfacePressed,
            borderRadius: BorderRadius.circular(2), // Sharp corners
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 0.5,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.music_note,
                  color: AppColors.sequencerLightText,
                  size: 40,
                ),
                const SizedBox(height: 8),
                Text(
                  sequencer.getGridLabel(actualSoundGridId),
                  style: GoogleFonts.sourceSans3(
                    color: AppColors.sequencerLightText,
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
        padding: const EdgeInsets.all(2), // Reduced padding
        child: Column(
          children: [
            // Minimal space for tab label above
            const SizedBox(height: 8),
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
      child: ListView.builder(
        controller: _scrollController,
        physics: (sequencer.isInSelectionMode || _gestureMode == GestureMode.selecting)
            ? const NeverScrollableScrollPhysics()
            : const PositionRetainedScrollPhysics(), // Prevents jumping when rows are added/removed
        itemCount: sequencer.gridRows + 1, // +1 for the control buttons at the bottom
        itemBuilder: (context, index) {
          if (index < sequencer.gridRows) {
            // Build a row of grid cells
            return _buildGridRow(context, sequencer, index);
          } else {
            // Control buttons at the bottom
            return RepaintBoundary(
              child: Container(
                margin: const EdgeInsets.only(left: 16, right: 16, bottom: 60, top: 4),
                child: _buildGridRowControls(sequencer),
              ),
            );
          }
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

  // Grid row control buttons - styled like test page buttons
  Timer? _buttonPressTimer;
  bool _isLongPressing = false;
  bool _isDecreasePressed = false;
  bool _isIncreasePressed = false;
  
  Widget _buildGridRowControls(SequencerState sequencer) {
    return Container(
      height: 30, // Reduced height from 40 to 30
      margin: const EdgeInsets.symmetric(horizontal: 16), // Full width like grid rows
      child: Row(
        children: [
          // Remove rows button - left half
          Expanded(
            child: _buildControlButton(
              isEnabled: sequencer.gridRows > 4,
              onAction: () => _handleDecreaseRows(sequencer),
              icon: Icons.remove,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                bottomLeft: Radius.circular(6),
              ),
              isPressed: _isDecreasePressed,
              buttonType: 'decrease',
            ),
          ),
          
          // Add rows button - right half
          Expanded(
            child: _buildControlButton(
              isEnabled: sequencer.gridRows < sequencer.maxGridRows,
              onAction: () => _handleIncreaseRows(sequencer),
              icon: Icons.add,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(6),
                bottomRight: Radius.circular(6),
              ),
              isPressed: _isIncreasePressed,
              buttonType: 'increase',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required bool isEnabled,
    required VoidCallback onAction,
    required IconData icon,
    required BorderRadius borderRadius,
    required bool isPressed,
    required String buttonType,
  }) {
    return Listener(
      onPointerDown: isEnabled ? (event) {
        // Update pressed state
        setState(() {
          if (buttonType == 'decrease') {
            _isDecreasePressed = true;
          } else {
            _isIncreasePressed = true;
          }
        });
        
        // Start single action immediately
        onAction();
        
        // Start long press timer for continuous action
        _buttonPressTimer?.cancel();
        _buttonPressTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted) {
            _isLongPressing = true;
            _startContinuousAction(onAction);
          }
        });
      } : null,
      onPointerUp: (event) {
        _stopAllActions();
        
        // Reset pressed state
        setState(() {
          _isDecreasePressed = false;
          _isIncreasePressed = false;
        });
      },
      onPointerCancel: (event) {
        _stopAllActions();
        
        // Reset pressed state
        setState(() {
          _isDecreasePressed = false;
          _isIncreasePressed = false;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: _getButtonColor(isEnabled, isPressed),
          borderRadius: borderRadius,
          border: Border.all(
            color: isPressed 
                ? AppColors.sequencerAccent 
                : AppColors.sequencerBorder,
            width: isPressed ? 1.5 : 1,
          ),
          boxShadow: isPressed 
              ? [
                  // Pressed (inset) shadow effect
                  BoxShadow(
                    color: AppColors.sequencerShadow,
                    blurRadius: 2,
                    offset: const Offset(0, -1),
                  ),
                ]
              : [
                  // Normal (protruding) shadow effect
                  BoxShadow(
                    color: AppColors.sequencerShadow,
                    blurRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Center(
          child: Icon(
            icon,
            color: isEnabled 
                ? (isPressed ? AppColors.sequencerAccent : AppColors.sequencerText)
                : AppColors.sequencerLightText.withOpacity(0.5),
            size: 18, // Slightly smaller icon for reduced button height
          ),
        ),
      ),
    );
  }

  Color _getButtonColor(bool isEnabled, bool isPressed) {
    if (!isEnabled) {
      return AppColors.sequencerCellEmpty.withOpacity(0.3);
    }
    
    if (isPressed) {
      return AppColors.sequencerSurfacePressed; // Darker when pressed
    }
    
    return AppColors.sequencerCellEmpty; // Normal state
  }
  

  
  void _handleIncreaseRows(SequencerState sequencer) {
    // Check limits - if at limit, stop continuous action
    if (sequencer.gridRows >= sequencer.maxGridRows) {
      _isLongPressing = false;
      _stopContinuousAction();
      return;
    }
    sequencer.increaseGridRows();
    
    // Check if we just reached the limit and stop
    if (sequencer.gridRows >= sequencer.maxGridRows) {
      _isLongPressing = false;
      _stopContinuousAction();
    }
  }
  
  void _handleDecreaseRows(SequencerState sequencer) {
    // Check limits - if at limit, stop continuous action
    if (sequencer.gridRows <= 4) {
      _isLongPressing = false;
      _stopContinuousAction();
      return;
    }
    sequencer.decreaseGridRows();
    
    // Check if we just reached the limit and stop
    if (sequencer.gridRows <= 4) {
      _isLongPressing = false;
      _stopContinuousAction();
    }
  }
  
  void _startContinuousAction(VoidCallback action) {
    _buttonPressTimer?.cancel();
    _buttonPressTimer = null;
    
    _buttonPressTimer = Timer.periodic(const Duration(milliseconds: 75), (timer) {
      if (!mounted) {
        timer.cancel();
        _buttonPressTimer = null;
        _isLongPressing = false;
        return;
      }
      
      if (_isLongPressing) {
        action();
      } else {
        timer.cancel();
        _buttonPressTimer = null;
      }
    });
  }
  
  void _stopContinuousAction() {
    _isLongPressing = false;
    if (_buttonPressTimer != null) {
      _buttonPressTimer!.cancel();
      _buttonPressTimer = null;
    }
  }

  void _stopAllActions() {
    _isLongPressing = false;
    
    if (_buttonPressTimer != null) {
      _buttonPressTimer!.cancel();
      _buttonPressTimer = null;
    }
  }
} 