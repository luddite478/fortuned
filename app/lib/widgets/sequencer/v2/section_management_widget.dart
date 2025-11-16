import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/playback.dart';
import '../../../state/sequencer/ui_selection.dart';
import '../../../utils/app_colors.dart';

class SectionManagementWidget extends StatelessWidget {
  const SectionManagementWidget({super.key});

  // Responsive sizing percentages
  static const double _contentHeightPercent = 1.0; // 100% for section tape (no header)
  static const double _paddingPercent = 0.03; // 3% padding around entire panel
  static const double _innerPaddingPercent = 0.02; // 2% inner padding for section tape
  
  // Section rectangle sizing
  static const double _sectionWidthPercent = 0.20; // 20% of available width per section
  static const double _gapWidthPercent = 0.08; // 8% of available width per gap
  static const double _sectionHeightPercent = 0.65; // 65% of content area height

  @override
  Widget build(BuildContext context) {
    return Consumer3<TableState, PlaybackState, UiSelectionState>(
      builder: (context, tableState, playbackState, uiSelection, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final panelHeight = constraints.maxHeight;
            final panelWidth = constraints.maxWidth;
            
            // Padding & ratios
            final padding = panelHeight * _paddingPercent;
            final innerHeight = panelHeight - padding * 2;
            final borderThickness = 1.0;
            final innerHeightAdj = innerHeight - borderThickness * 2;
            
            // Full height for section tape (no header)
            final contentHeight = innerHeightAdj * _contentHeightPercent;
            
            final sectionNumberFontSize = (contentHeight * _sectionHeightPercent * 0.45).clamp(12.0, 18.0);

            return Container(
              padding: EdgeInsets.all(padding),
              decoration: BoxDecoration(
                color: AppColors.sequencerSurfaceBase,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: AppColors.sequencerBorder,
                  width: 1,
                ),
                boxShadow: [
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
              child: _buildSectionTape(
                tableState,
                playbackState,
                uiSelection,
                contentHeight,
                panelWidth,
                sectionNumberFontSize,
                context,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSectionTape(
    TableState tableState,
    PlaybackState playbackState,
    UiSelectionState uiSelection,
    double contentHeight,
    double panelWidth,
    double fontSize,
    BuildContext context,
  ) {
    final sectionWidth = panelWidth * _sectionWidthPercent;
    final gapWidth = panelWidth * _gapWidthPercent;
    final sectionHeight = contentHeight * _sectionHeightPercent;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: panelWidth * _innerPaddingPercent,
        vertical: contentHeight * _innerPaddingPercent,
      ),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.sequencerBorder, width: 1),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _buildSectionElements(
            tableState,
            playbackState,
            uiSelection,
            sectionWidth,
            gapWidth,
            sectionHeight,
            fontSize,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSectionElements(
    TableState tableState,
    PlaybackState playbackState,
    UiSelectionState uiSelection,
    double sectionWidth,
    double gapWidth,
    double sectionHeight,
    double fontSize,
  ) {
    final sectionsCount = tableState.sectionsCount;
    final isPlaying = playbackState.isPlaying;
    final currentPlayingSection = playbackState.currentSection;
    final selectedSection = uiSelection.selectedSection;
    final uiSelectedSection = tableState.uiSelectedSection;
    
    final elements = <Widget>[];

    for (int i = 0; i < sectionsCount; i++) {
      // Gap before section
      elements.add(_buildGap(i - 1, gapWidth, sectionHeight, tableState, uiSelection, playbackState));
      
      // Section tile
      elements.add(
        _buildSectionRectangle(
          sectionIndex: i,
          isPlaying: isPlaying && i == currentPlayingSection,
          isSelected: selectedSection == i,
          isUiSelected: uiSelectedSection == i,
          width: sectionWidth,
          height: sectionHeight,
          fontSize: fontSize,
          onTap: () => _onSectionTap(i, tableState, playbackState, uiSelection),
        ),
      );
    }
    
    // Final gap after last section
    elements.add(_buildGap(sectionsCount - 1, gapWidth, sectionHeight, tableState, uiSelection, playbackState));

    return elements;
  }

  Widget _buildSectionRectangle({
    required int sectionIndex,
    required bool isPlaying,
    required bool isSelected,
    required bool isUiSelected,
    required double width,
    required double height,
    required double fontSize,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          // Light gray when UI selected (currently viewing), matching bottom bar chain
          color: isUiSelected ? AppColors.sequencerLightText : AppColors.sequencerSurfaceBase,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isSelected ? AppColors.sequencerSelectionBorder : AppColors.sequencerBorder,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? null : [
            BoxShadow(
              color: AppColors.sequencerShadow,
              blurRadius: 1,
              offset: const Offset(0, 0.5),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '${sectionIndex + 1}',
            style: GoogleFonts.sourceSans3(
              color: isPlaying
                  ? AppColors.sequencerAccent
                  : (isUiSelected 
                      ? AppColors.sequencerText // Dark text on light background
                      : AppColors.sequencerLightText),
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGap(
    int gapIndex,
    double width,
    double height,
    TableState tableState,
    UiSelectionState uiSelection,
    PlaybackState playbackState,
  ) {
    return GestureDetector(
      onTap: () => _onGapTap(gapIndex, tableState, uiSelection, playbackState),
      child: Container(
        width: width,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        child: Center(
          child: Icon(
            Icons.add,
            color: AppColors.sequencerLightText.withOpacity(0.5),
            size: height * 0.3,
          ),
        ),
      ),
    );
  }

  void _onSectionTap(
    int index,
    TableState tableState,
    PlaybackState playbackState,
    UiSelectionState uiSelection,
  ) {
    // Select the section (this will clear other selections via UiSelectionState)
    uiSelection.selectSection(index);
    
    // Switch sequencer view to this section
    tableState.setUiSelectedSection(index);
    
    // Switch playback to this section
    playbackState.switchToSection(index);
  }

  void _onGapTap(int gapIndex, TableState tableState, UiSelectionState uiSelection, PlaybackState playbackState) {
    tableState.addSectionAfter(gapIndex);
    final newIndex = gapIndex + 1;
    uiSelection.selectSection(newIndex);
    playbackState.switchToSection(newIndex);
  }
}

