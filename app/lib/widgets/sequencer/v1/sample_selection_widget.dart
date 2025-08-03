import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';import '../../../state/sequencer_state.dart';
import '../../../utils/app_colors.dart';

class SampleSelectionWidget extends StatelessWidget {
  const SampleSelectionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencerState, child) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceBase,
            borderRadius: BorderRadius.circular(2), // Sharp corners
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 1,
            ),
            boxShadow: [
              // Protruding effect
              BoxShadow(
                color: AppColors.sequencerShadow,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: AppColors.sequencerSurfaceRaised,
                blurRadius: 1,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: _buildSampleBrowser(context, sequencerState),
        );
      },
    );
  }

  Widget _buildSampleBrowser(BuildContext context, SequencerState sequencerState) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with sample selection info
          Row(
            children: [
              if (sequencerState.currentSamplePath.isNotEmpty) ...[
                GestureDetector(
                  onTap: () => sequencerState.navigateBackInSamples(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.sequencerSurfaceRaised,
                      borderRadius: BorderRadius.circular(2), // Sharp corners
                      border: Border.all(
                        color: AppColors.sequencerBorder,
                        width: 0.5,
                      ),
                      boxShadow: [
                        // Protruding effect for back button
                        BoxShadow(
                          color: AppColors.sequencerShadow,
                          blurRadius: 1,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_back, 
                          color: AppColors.sequencerText, 
                          size: 12
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'BACK',
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.sequencerText,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  sequencerState.currentSamplePath.isEmpty 
                      ? 'samples/' 
                      : 'samples/${sequencerState.currentSamplePath.join('/')}/',
                  style: GoogleFonts.sourceSans3(
                    color: AppColors.sequencerLightText,
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => sequencerState.cancelSampleSelection(),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.sequencerSurfacePressed,
                    borderRadius: BorderRadius.circular(2), // Sharp corners
                    border: Border.all(
                      color: AppColors.sequencerAccent.withOpacity(0.8),
                      width: 0.5,
                    ),
                    boxShadow: [
                      // Recessed effect for close button
                      BoxShadow(
                        color: AppColors.sequencerShadow,
                        blurRadius: 1,
                        offset: const Offset(0, 0.5),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.close,
                    color: AppColors.sequencerAccent,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Horizontal scrollable sample list showing 3 full items + partial 4th
          Expanded(
            child: sequencerState.currentSampleItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open,
                          color: AppColors.sequencerLightText,
                          size: 24,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Loading samples...',
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.sequencerLightText,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Calculate item width: show 3 full items + 40% of 4th item
                      final itemWidth = (constraints.maxWidth - 24) / 3.4; // 3 items + 0.4 of next + margins
                      
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: sequencerState.currentSampleItems.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            
                            return Container(
                              width: itemWidth,
                              height: constraints.maxHeight,
                              margin: EdgeInsets.only(right: index < sequencerState.currentSampleItems.length - 1 ? 8 : 0),
                              child: GestureDetector(
                                onTap: () => sequencerState.selectSampleItem(item),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: item.isFolder 
                                        ? AppColors.sequencerSurfaceRaised
                                        : AppColors.sequencerAccent.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(2), // Sharp corners
                                    border: Border.all(
                                      color: item.isFolder 
                                          ? AppColors.sequencerBorder
                                          : AppColors.sequencerAccent.withOpacity(0.6),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      // Protruding effect for all items
                                      BoxShadow(
                                        color: AppColors.sequencerShadow,
                                        blurRadius: 2,
                                        offset: const Offset(0, 1),
                                      ),
                                      BoxShadow(
                                        color: AppColors.sequencerSurfaceRaised,
                                        blurRadius: 1,
                                        offset: const Offset(0, -0.5),
                                      ),
                                    ],
                                  ),
                                  child: item.isFolder 
                                      ? // Folder layout
                                        LayoutBuilder(
                                          builder: (context, itemConstraints) {
                                            final iconSize = itemConstraints.maxHeight * 0.3; // 30% of height
                                            final fontSize = itemConstraints.maxHeight * 0.12; // 12% of height
                                            
                                            return Center(
                                              child: Padding(
                                                padding: EdgeInsets.all(itemConstraints.maxHeight * 0.08), // 8% padding
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.folder,
                                                      color: AppColors.sequencerAccent,
                                                      size: iconSize.clamp(16.0, 32.0), // min 16, max 32
                                                    ),
                                                    SizedBox(height: itemConstraints.maxHeight * 0.08),
                                                    Flexible(
                                                      child: Text(
                                                        item.name,
                                                        style: GoogleFonts.sourceSans3(
                                                          color: AppColors.sequencerText,
                                                          fontSize: fontSize.clamp(8.0, 14.0), // min 8, max 14
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                        textAlign: TextAlign.center,
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        )
                                      : // File layout
                                        LayoutBuilder(
                                          builder: (context, itemConstraints) {
                                            final playButtonSize = itemConstraints.maxHeight * 0.4; // Play button size
                                            final fontSize = itemConstraints.maxHeight * 0.2; 
                                            final pickAreaWidth = itemConstraints.maxWidth * 0.66; // Left side - larger
                                            final playAreaWidth = itemConstraints.maxWidth * 0.34; // Right side - smaller
                                            final separatorWidth = 2.0; // Visual separator
                                            
                                            return Row(
                                              children: [
                                                // Left section - Pick area (larger, easier to target)
                                                GestureDetector(
                                                  onTap: () => sequencerState.selectSampleItem(item),
                                                  child: Container(
                                                    width: pickAreaWidth - separatorWidth,
                                                    height: double.infinity,
                                                    decoration: BoxDecoration(
                                                      color: AppColors.sequencerAccent.withOpacity(0.3),
                                                      borderRadius: const BorderRadius.only(
                                                        topLeft: Radius.circular(2),
                                                        bottomLeft: Radius.circular(2),
                                                      ),
                                                    ),
                                                    padding: EdgeInsets.symmetric(
                                                      horizontal: itemConstraints.maxWidth * 0.03,
                                                      vertical: itemConstraints.maxHeight * 0.08,
                                                    ),
                                                    child: Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        // File name
                                                        Flexible(
                                                          child: Text(
                                                            item.name,
                                                            style: GoogleFonts.sourceSans3(
                                                              color: AppColors.sequencerText,
                                                              fontSize: fontSize.clamp(6.0, 12.0),
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                            textAlign: TextAlign.left,
                                                            maxLines: 3,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        // "TAP TO SELECT" hint
                                                        Text(
                                                          'TAP TO SELECT',
                                                          style: GoogleFonts.sourceSans3(
                                                            color: AppColors.sequencerLightText,
                                                            fontSize: (fontSize * 0.6).clamp(5.0, 8.0),
                                                            fontWeight: FontWeight.w600,
                                                            letterSpacing: 0.5,
                                                          ),
                                                          textAlign: TextAlign.left,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                // Visual separator
                                                Container(
                                                  width: separatorWidth,
                                                  color: AppColors.sequencerBorder,
                                                ),
                                                // Right section - Play button area (smaller, focused)
                                                GestureDetector(
                                                  onTap: () => sequencerState.previewSample(item.path),
                                                  child: Container(
                                                    width: playAreaWidth - separatorWidth,
                                                    height: double.infinity,
                                                    decoration: BoxDecoration(
                                                      color: AppColors.sequencerSurfacePressed,
                                                      borderRadius: const BorderRadius.only(
                                                        topRight: Radius.circular(2),
                                                        bottomRight: Radius.circular(2),
                                                      ),
                                                    ),
                                                    child: Center(
                                                      child: Container(
                                                        width: playButtonSize,
                                                        height: playButtonSize,
                                                        decoration: BoxDecoration(
                                                          color: AppColors.sequencerAccent.withOpacity(0.9),
                                                          borderRadius: BorderRadius.circular(2),
                                                          border: Border.all(
                                                            color: AppColors.sequencerBorder,
                                                            width: 1,
                                                          ),
                                                          boxShadow: [
                                                            // Strong protruding effect for play button
                                                            BoxShadow(
                                                              color: AppColors.sequencerShadow,
                                                              blurRadius: 2,
                                                              offset: const Offset(0, 2),
                                                            ),
                                                            BoxShadow(
                                                              color: AppColors.sequencerSurfaceRaised,
                                                              blurRadius: 1,
                                                              offset: const Offset(0, -1),
                                                            ),
                                                          ],
                                                        ),
                                                        child: Icon(
                                                          Icons.play_arrow,
                                                          color: AppColors.sequencerPageBackground,
                                                          size: (playButtonSize * 0.6).clamp(10.0, 18.0),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
} 