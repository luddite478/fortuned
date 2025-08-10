import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';
import '../../../state/sequencer_state.dart';

class SectionCreationOverlay extends StatefulWidget {
  const SectionCreationOverlay({super.key});

  @override
  State<SectionCreationOverlay> createState() => _SectionCreationOverlayState();
}

class _SectionCreationOverlayState extends State<SectionCreationOverlay> {

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
            children: [
              // Header
              _buildHeader(context, sequencerState),
              
              // Content
              Expanded(
                child: _buildContent(context, sequencerState),
              ),
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
                'Create New Section',
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
                sequencerState.closeSectionCreationOverlay();
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

  Widget _buildContent(BuildContext context, SequencerState sequencerState) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width * 0.04,
          vertical: MediaQuery.of(context).size.height * 0.02,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Create Blank Button
            _buildSimpleButton(
              context,
              text: 'Create Blank',
              onPressed: () {
                sequencerState.createEmptySection();
              },
            ),
            
            SizedBox(height: MediaQuery.of(context).size.height * 0.02),
            
            // Create From Label
            Text(
              'Create From:',
              style: GoogleFonts.sourceSans3(
                color: AppColors.sequencerLightText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            
            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
            
            // Scrollable list of sections
            Expanded(
              child: ListView.builder(
                itemCount: sequencerState.numSections,
                itemBuilder: (context, index) {
                  return _buildSectionCopyButton(context, sequencerState, index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleButton(
    BuildContext context, {
    required String text,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          vertical: MediaQuery.of(context).size.height * 0.02,
        ),
        decoration: BoxDecoration(
          color: AppColors.sequencerAccent,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Center(
          child: Text(
            text,
            style: GoogleFonts.sourceSans3(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCopyButton(BuildContext context, SequencerState sequencerState, int sectionIndex) {
    return Container(
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.01),
      child: GestureDetector(
        onTap: () {
          sequencerState.createSectionCopyFrom(sectionIndex);
        },
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            vertical: MediaQuery.of(context).size.height * 0.015,
            horizontal: MediaQuery.of(context).size.width * 0.03,
          ),
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfacePressed,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 1,
            ),
          ),
          child: Text(
            'Section ${sectionIndex + 1}',
            style: GoogleFonts.sourceSans3(
              color: AppColors.sequencerLightText,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
} 