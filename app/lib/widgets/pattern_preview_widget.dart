import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../models/thread/thread.dart';
import '../state/user_state.dart';

class PatternPreviewWidget extends StatelessWidget {
  final Thread project;
  final Future<Map<String, dynamic>?> Function(String) getProjectSnapshot;
  final List<Color> Function(Map<String, dynamic>) getSampleBankColors;
  final Color? fadeOverlayColor; // Background color to use for fade overlays (defaults to white)
  final EdgeInsets innerPadding; // Padding between widget border and cells
  
  // ============================================================================
  // CELL DIMENSIONS CONTROL
  // ============================================================================
  // Cell spacing (in pixels, not percent)
  // Recommended: 0.2-0.6px for tight grids, 0.8-1.2px for spacious grids
  static const double patternCellMargin = 0.4;
  
  // Cell aspect ratio - NO LONGER USED, cells now fill available space
  // Kept for reference only
  // static const double cellAspectRatio = 1.0; // Square cells
  
  // Layer boundary styling
  static const double layerBoundaryWidth = 2.0;
  static const Color layerBoundaryColor = Color.fromARGB(255, 65, 65, 65);
  
  // Empty cell colors
  static const Color patternEmptyCellColor = Color.fromARGB(255, 152, 152, 152);
  
  // Pattern preview fade gradient (horizontal)
  // Gradient now spans 17 columns to cover column 17
  // Column 16 starts at 15/17 = 88.24%, column 17 is 94.12%-100%
  static const bool enablePatternFadeGradient = true;
  static const double patternFadeStartPercent = 90.0; // Start fade in column 15 (14/17 * 100%)
  static const double patternFadeEndPercent = 100.0; // End fade at end of column 17, fully transparent
  static const bool enablePatternVerticalFade = true;
  static const double patternVerticalFadeStartPercent = 70.0; // Start fade in later rows
  static const double patternVerticalFadeEndPercent = 100.0; // End fade at bottom, fully transparent
  
  // Pattern preview layer header
  static const bool showPatternLayerHeader = true;
  static const double patternLayerHeaderHeight = 12.0;
  static const double patternLayerHeaderFontSize = 8.0;

  const PatternPreviewWidget({
    Key? key,
    required this.project,
    required this.getProjectSnapshot,
    required this.getSampleBankColors,
    this.fadeOverlayColor,
    this.innerPadding = EdgeInsets.zero,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: getProjectSnapshot(project.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.sequencerCellEmpty.withOpacity(0.3),
            ),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.menuLightText.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.sequencerCellEmpty.withOpacity(0.3),
            ),
            child: Center(
              child: Icon(
                Icons.error_outline,
                color: AppColors.menuLightText.withOpacity(0.5),
                size: 16,
              ),
            ),
          );
        }

        return _buildPatternPreviewFromSnapshot(snapshot.data!);
      },
    );
  }

  Widget _buildPatternPreviewFromSnapshot(Map<String, dynamic> snapshotData) {
    debugPrint('📸 [PREVIEW] Building pattern preview, snapshot has ${snapshotData.length} keys');
    debugPrint('📸 [PREVIEW] Snapshot keys: ${snapshotData.keys.toList()}');
    
    final source = snapshotData['source'] as Map<String, dynamic>?;
    debugPrint('📸 [PREVIEW] Source is ${source == null ? "NULL" : "present with ${source.keys.length} keys"}');
    
    if (source == null) {
      return Container(
        decoration: const BoxDecoration(
          color: AppColors.sequencerCellEmpty,
        ),
        child: Center(
          child: Text(
            'No source',
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuLightText,
              fontSize: 8,
            ),
          ),
        ),
      );
    }
    
    final table = source['table'] as Map<String, dynamic>?;
    if (table == null) {
      return Container(
        decoration: const BoxDecoration(
          color: AppColors.sequencerCellEmpty,
        ),
        child: Center(
          child: Text(
            'No table',
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuLightText,
              fontSize: 8,
            ),
          ),
        ),
      );
    }
    
    final tableCells = table['table_cells'] as List<dynamic>? ?? [];
    final sections = table['sections'] as List<dynamic>? ?? [];
    final layers = table['layers'] as List<dynamic>? ?? [];
    
    if (sections.isEmpty || tableCells.isEmpty) {
      return Container(
        decoration: const BoxDecoration(
          color: AppColors.sequencerCellEmpty,
        ),
        child: Center(
          child: Text(
            'No data',
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuLightText,
              fontSize: 8,
            ),
          ),
        ),
      );
    }
    
    final firstSection = sections[0] as Map<String, dynamic>;
    final numSteps = firstSection['num_steps'] as int? ?? 16;
    final startStep = firstSection['start_step'] as int? ?? 0;
    
    int totalCols = 16;
    List<int> layerBoundaries = [];
    
    try {
      if (layers.isNotEmpty) {
        final firstSectionLayers = layers[0];
        if (firstSectionLayers is List) {
          totalCols = 0;
          for (var layer in firstSectionLayers) {
            if (layer is Map<String, dynamic>) {
              final len = layer['len'] as int? ?? 4;
              totalCols += len;
              layerBoundaries.add(totalCols - 1);
            } else if (layer is int) {
              totalCols += layer;
              layerBoundaries.add(totalCols - 1);
            }
          }
          totalCols = totalCols.clamp(1, 100);
        }
      }
    } catch (e) {
      debugPrint('⚠️ [PREVIEW] Error parsing layers: $e, using default 16 cols');
      totalCols = 16;
      layerBoundaries = [3, 7, 11, 15];
    }
    
    final sampleBankColors = getSampleBankColors(snapshotData);
    final rowsToShow = (numSteps).clamp(1, 8);
    
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          
          // Apply inner padding (space between widget border and cells)
          final availableWidthAfterPadding = availableWidth - innerPadding.horizontal;
          
          // Determine columns to show based on 16 columns, but show 17 when there are more (17th will be faded)
          final needsHorizontalFade = totalCols > 16;
          final columnsToShow = needsHorizontalFade ? 17.clamp(1, totalCols) : totalCols.clamp(1, 16);
          
          // NEW: Cells now fill available space using Expanded widgets (no fixed aspect ratio)
          // Calculate cell width for layer header positioning
          final cellWidth = availableWidthAfterPadding / columnsToShow;
          
          // Determine if vertical fade is needed
          final needsVerticalFade = rowsToShow >= 8;
          
          // Build layer info for header (only for visible columns)
        List<Map<String, dynamic>> layerInfo = [];
        if (showPatternLayerHeader) {
          int currentCol = 0;
          for (int i = 0; i < layerBoundaries.length; i++) {
            final endCol = layerBoundaries[i];
            final layerWidth = endCol - currentCol + 1;
            
            // Check if this layer starts beyond visible columns
            if (currentCol >= columnsToShow) {
              break;
            }
            
            layerInfo.add({
              'index': i,
              'startCol': currentCol,
              'endCol': endCol,
              'width': layerWidth,
            });
            currentCol = endCol + 1;
          }
        }
        
        return Padding(
          padding: innerPadding,
          child: Stack(
            children: [
              // Main content column
              Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Layer header row
              if (showPatternLayerHeader)
                SizedBox(
                  height: patternLayerHeaderHeight,
                  child: Stack(
                    alignment: Alignment.topLeft,
                    children: [
                      // Regular layer headers - use absolute positioning for proper alignment
                      ...layerInfo.where((layer) => layer['startCol'] < columnsToShow).map<Widget>((layer) {
                        final startCol = layer['startCol'] as int;
                        final endCol = (layer['endCol'] as int).clamp(0, columnsToShow - 1);
                        final visibleColumns = endCol - startCol + 1;
                        
                        if (startCol >= columnsToShow) return const SizedBox.shrink();
                        
                        return Positioned(
                          left: cellWidth * startCol,
                          top: 0,
                          child: SizedBox(
                            width: cellWidth * visibleColumns,
                            height: patternLayerHeaderHeight,
                            child: Container(
                              alignment: Alignment.center,
                              child: Text(
                                '${layer['index'] + 1}',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.sourceSans3(
                                  color: AppColors.menuLightText.withOpacity(0.6),
                                  fontSize: patternLayerHeaderFontSize,
                                  fontWeight: FontWeight.w500,
                                  height: 1.0, // Tight line height for better alignment
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              
              // Pattern grid with fade overlays - uses Expanded to fill available space
              Expanded(
                child: Stack(
                  alignment: Alignment.topLeft,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // Pattern grid rows - use Expanded to fill available space
                    Column(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List.generate(rowsToShow, (row) {
                        return Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: List.generate(columnsToShow, (col) {
                                final isLayerBoundary = layerBoundaries.contains(col) && col < columnsToShow - 1;
                                final isPreviousLayerBoundary = col > 0 && layerBoundaries.contains(col - 1);
                                
                                final absoluteStep = startStep + row;
                                Color cellColor = patternEmptyCellColor;
                                
                                if (absoluteStep < tableCells.length) {
                                  final rowCells = tableCells[absoluteStep] as List<dynamic>?;
                                  if (rowCells != null && col < rowCells.length) {
                                    final cellData = rowCells[col] as Map<String, dynamic>?;
                                    if (cellData != null) {
                                      final sampleSlot = cellData['sample_slot'] as int? ?? -1;
                                      if (sampleSlot >= 0 && sampleSlot < sampleBankColors.length) {
                                        cellColor = sampleBankColors[sampleSlot];
                                      }
                                    }
                                  }
                                }
                                
                                return Expanded(
                                  child: Container(
                                    margin: EdgeInsets.only(
                                      left: isPreviousLayerBoundary ? 0 : patternCellMargin,
                                      top: patternCellMargin,
                                      bottom: patternCellMargin,
                                      right: isLayerBoundary ? 0 : patternCellMargin,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cellColor,
                                      borderRadius: BorderRadius.circular(0),
                                      border: isLayerBoundary 
                                        ? Border(
                                            right: BorderSide(
                                              color: layerBoundaryColor,
                                              width: patternCellMargin * 2,
                                            ),
                                          )
                                        : null,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          );
                        }),
                      ),
                  
                  // Horizontal fade overlay - fill entire grid area
                  if (enablePatternFadeGradient && needsHorizontalFade)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              stops: [
                                patternFadeStartPercent / 100,
                                patternFadeEndPercent / 100,
                              ],
                              colors: [
                                (fadeOverlayColor ?? Colors.white).withOpacity(0.0),
                                (fadeOverlayColor ?? Colors.white).withOpacity(1.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  
                  // Vertical fade overlay - fill entire grid area
                  if (enablePatternVerticalFade && needsVerticalFade)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [
                                patternVerticalFadeStartPercent / 100,
                                patternVerticalFadeEndPercent / 100,
                              ],
                              colors: [
                                (fadeOverlayColor ?? Colors.white).withOpacity(0.0),
                                (fadeOverlayColor ?? Colors.white).withOpacity(1.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
              
              // Participant chip overlay (centered on top of pattern)
              _buildParticipantChip(context),
            ],
          ),
        );
        },
      ),
    );
  }
  
  Widget _buildParticipantChip(BuildContext context) {
    // Get current user to filter out self
    final userState = context.read<UserState>();
    final currentUserId = userState.currentUser?.id ?? '';
    
    // Get other participants (exclude current user)
    final otherParticipants = project.users
        .where((u) => u.id != currentUserId)
        .toList();
    
    // Only show if there are other participants
    if (otherParticipants.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final firstUsername = otherParticipants.first.username;
    final hasMore = otherParticipants.length > 1;
    
    // Build text based on number of participants
    final chipText = hasMore 
        ? 'w/ $firstUsername and others'
        : 'w/ $firstUsername';
    
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.9, // Use 90% of available width to prevent overflow
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.menuEntryBackground.withOpacity(0.95),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.menuBorder.withOpacity(0.5),
                width: 0.5,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                chipText,
                style: GoogleFonts.sourceSans3(
                  color: AppColors.menuText,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

