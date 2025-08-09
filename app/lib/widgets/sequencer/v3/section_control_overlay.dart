import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';
import '../../../state/sequencer_state.dart';

class SectionControlOverlay extends StatelessWidget {
  const SectionControlOverlay({super.key});

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              _buildHeader(context, sequencerState),
              
              // Current section settings
              _buildCurrentSectionSettings(context, sequencerState),
              
              // Footer with controls
              _buildFooter(context, sequencerState),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, SequencerState sequencerState) {
    final screenSize = MediaQuery.of(context).size;
    final headerHeight = screenSize.height * 0.08;
    
    return Container(
      height: headerHeight,
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        border: Border(
          bottom: BorderSide(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: screenSize.width * 0.02),
        child: Row(
          children: [
            // Title
            Expanded(
              child: Text(
                'Section Settings',
                style: GoogleFonts.sourceSans3(
                  color: AppColors.sequencerLightText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            
                         // Close button
             GestureDetector(
               onTap: () {
                 sequencerState.closeSectionControlOverlay();
               },
              child: Container(
                width: screenSize.width * 0.06,
                height: screenSize.width * 0.06,
                decoration: BoxDecoration(
                  color: AppColors.sequencerSurfacePressed,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: AppColors.sequencerBorder,
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  Icons.close,
                  color: AppColors.sequencerLightText,
                  size: screenSize.width * 0.03,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentSectionSettings(BuildContext context, SequencerState sequencerState) {
    final screenSize = MediaQuery.of(context).size;
    final currentSectionIndex = sequencerState.currentSectionIndex;
    
    return Container(
      padding: EdgeInsets.all(screenSize.width * 0.04),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Current section title
          Container(
            padding: EdgeInsets.symmetric(vertical: screenSize.height * 0.02),
            child: Text(
              'Section ${currentSectionIndex + 1}',
              style: GoogleFonts.sourceSans3(
                color: AppColors.sequencerAccent,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          
          // Loop count controls
          Container(
            padding: EdgeInsets.symmetric(vertical: screenSize.height * 0.02),
            child: Column(
              children: [
                // Loop count label
                Text(
                  'Loop Count',
                  style: GoogleFonts.sourceSans3(
                    color: AppColors.sequencerLightText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                
                SizedBox(height: screenSize.height * 0.02),
                
                // Loop count controls: left arrow - number - right arrow
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Left arrow button
                    _buildArrowButton(
                      context,
                      icon: Icons.chevron_left,
                      onTap: () {
                        final currentCount = sequencerState.getSectionLoopCount(currentSectionIndex);
                        if (currentCount > 1) {
                          sequencerState.setSectionLoopCount(currentSectionIndex, currentCount - 1);
                        }
                      },
                      enabled: sequencerState.getSectionLoopCount(currentSectionIndex) > 1,
                    ),
                    
                    SizedBox(width: screenSize.width * 0.06),
                    
                    // Current loop count
                    Container(
                      width: screenSize.width * 0.15,
                      height: screenSize.height * 0.06,
                      decoration: BoxDecoration(
                        color: AppColors.sequencerSurfacePressed,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.sequencerAccent,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${sequencerState.getSectionLoopCount(currentSectionIndex)}',
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.sequencerAccent,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    
                    SizedBox(width: screenSize.width * 0.06),
                    
                    // Right arrow button
                    _buildArrowButton(
                      context,
                      icon: Icons.chevron_right,
                      onTap: () {
                        final currentCount = sequencerState.getSectionLoopCount(currentSectionIndex);
                        if (currentCount < 16) {
                          sequencerState.setSectionLoopCount(currentSectionIndex, currentCount + 1);
                        }
                      },
                      enabled: sequencerState.getSectionLoopCount(currentSectionIndex) < 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArrowButton(BuildContext context, {
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    final screenSize = MediaQuery.of(context).size;
    
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: screenSize.width * 0.12,
        height: screenSize.height * 0.06,
        decoration: BoxDecoration(
          color: enabled 
              ? AppColors.sequencerSurfaceRaised
              : AppColors.sequencerSurfacePressed,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: enabled 
                ? AppColors.sequencerAccent
                : AppColors.sequencerBorder,
            width: 2,
          ),
          boxShadow: enabled ? [
            BoxShadow(
              color: AppColors.sequencerShadow,
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ] : null,
        ),
        child: Center(
          child: Icon(
            icon,
            color: enabled 
                ? AppColors.sequencerAccent
                : AppColors.sequencerBorder,
            size: screenSize.width * 0.06,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, SequencerState sequencerState) {
    final screenSize = MediaQuery.of(context).size;
    final footerHeight = screenSize.height * 0.08;
    
    return Container(
      height: footerHeight,
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        border: Border(
          top: BorderSide(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: screenSize.width * 0.02),
        child: Row(
          children: [
            const Spacer(),
            
            // Current mode indicator
            Text(
              sequencerState.sectionPlaybackMode == SectionPlaybackMode.loop ? 'Loop Mode' : 'Song Mode',
              style: GoogleFonts.sourceSans3(
                color: AppColors.sequencerAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 