import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../state/sequencer_state.dart';

// Darker Gray-Beige Telephone Book Color Scheme for Sequencer
class SequencerPhoneBookColors {
  static const Color pageBackground = Color(0xFF3A3A3A); // Dark gray background
  static const Color surfaceBase = Color(0xFF4A4A47); // Gray-beige base surface
  static const Color surfaceRaised = Color(0xFF525250); // Protruding surface color
  static const Color surfacePressed = Color(0xFF424240); // Pressed/active surface
  static const Color text = Color(0xFFE8E6E0); // Light text for contrast
  static const Color lightText = Color(0xFFB8B6B0); // Muted light text
  static const Color accent = Color(0xFF8B7355); // Brown accent for highlights
  static const Color border = Color(0xFF5A5A57); // Subtle borders
  static const Color shadow = Color(0xFF2A2A2A); // Dark shadows for depth
}

// Main sizing control variables for easy adjustment
class SampleBrowserSizing {
  // Tile dimensions
  static const double tileAspectRatio = 2.0; // Width:Height ratio (makes tiles shorter)
  static const double tileSpacing = 2.0; // Spacing between tiles in percent of screen width
  static const double tilePadding = 1.5; // Internal padding in percent of tile size
  
  // File tile split ratios
  static const double playButtonAreaRatio = 0.5; // Top 50% for play button
  static const double pickAreaRatio = 0.5; // Bottom 50% for file info
  
  // Button sizes
  static const double headerButtonHeight = 12.0; // Header buttons height in percent of header
  static const double closeButtonSize = 8.0; // Close button size in percent of screen width
  static const double backButtonHeight = 8.0; // Back button height in percent of header
}

class SampleSelectionWidget extends StatelessWidget {
  const SampleSelectionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencerState, child) {
        return Container(
          decoration: BoxDecoration(
            color: SequencerPhoneBookColors.surfaceBase,
            borderRadius: BorderRadius.circular(2), // Sharp corners
            border: Border.all(
              color: SequencerPhoneBookColors.border,
              width: 1,
            ),
            boxShadow: [
              // Protruding effect
              BoxShadow(
                color: SequencerPhoneBookColors.shadow,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: SequencerPhoneBookColors.surfaceRaised,
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
          // Header with sample selection info - using responsive sizing
          LayoutBuilder(
            builder: (context, headerConstraints) {
              final screenWidth = headerConstraints.maxWidth;
              final backButtonHeight = screenWidth * (SampleBrowserSizing.backButtonHeight / 100);
              final closeButtonSize = screenWidth * (SampleBrowserSizing.closeButtonSize / 100);
              final headerFontSize = screenWidth * 0.035;
              final pathFontSize = screenWidth * 0.025;
              
              return Row(
                children: [
                  if (sequencerState.currentSamplePath.isNotEmpty) ...[
                                          GestureDetector(
                        onTap: () {
                          // Navigation works the same for both browsers
                          sequencerState.navigateBackInSamples();
                        },
                      child: Container(
                        height: backButtonHeight.clamp(32.0, 50.0),
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.03,
                          vertical: screenWidth * 0.01,
                        ),
                        decoration: BoxDecoration(
                          color: SequencerPhoneBookColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: SequencerPhoneBookColors.border,
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: SequencerPhoneBookColors.shadow,
                              blurRadius: 3,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_back, 
                              color: SequencerPhoneBookColors.text, 
                              size: (headerFontSize * 1.2).clamp(14.0, 20.0),
                            ),
                            SizedBox(width: screenWidth * 0.015),
                            Text(
                              'BACK',
                              style: GoogleFonts.sourceSans3(
                                color: SequencerPhoneBookColors.text,
                                fontSize: headerFontSize.clamp(12.0, 16.0),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: screenWidth * 0.02),
                  ],
                  Expanded(
                    child: Text(
                      sequencerState.currentSamplePath.isEmpty 
                          ? 'samples/' 
                          : 'samples/${sequencerState.currentSamplePath.join('/')}/',
                      style: GoogleFonts.sourceSans3(
                        color: SequencerPhoneBookColors.lightText,
                        fontSize: pathFontSize.clamp(10.0, 14.0),
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      // Use appropriate close method based on usage context
                      if (sequencerState.isBodyElementSampleBrowserOpen) {
                        sequencerState.closeBodyElementSampleBrowser();
                      } else {
                        sequencerState.cancelSampleSelection();
                      }
                    },
                    child: Container(
                      width: closeButtonSize.clamp(40.0, 60.0),
                      height: closeButtonSize.clamp(40.0, 60.0),
                      decoration: BoxDecoration(
                        color: SequencerPhoneBookColors.surfacePressed,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: SequencerPhoneBookColors.accent.withOpacity(0.8),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: SequencerPhoneBookColors.shadow,
                            blurRadius: 3,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.close,
                        color: SequencerPhoneBookColors.accent,
                        size: (closeButtonSize * 0.5).clamp(18.0, 28.0),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          
          // Vertical scrolling 2-column grid as requested
          Expanded(
            child: sequencerState.currentSampleItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open,
                          color: SequencerPhoneBookColors.lightText,
                          size: 24,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Loading samples...',
                          style: GoogleFonts.sourceSans3(
                            color: SequencerPhoneBookColors.lightText,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final screenWidth = constraints.maxWidth;
                      final spacing = screenWidth * (SampleBrowserSizing.tileSpacing / 100);
                      
                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, // 2 columns as requested
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: spacing,
                          childAspectRatio: SampleBrowserSizing.tileAspectRatio, // Controlled aspect ratio
                        ),
                        itemCount: sequencerState.currentSampleItems.length,
                        padding: EdgeInsets.all(spacing),
                    itemBuilder: (context, index) {
                      final item = sequencerState.currentSampleItems[index];
                            
                      return GestureDetector(
                        onTap: () => sequencerState.selectSampleItem(item),
                        child: Container(
                          decoration: BoxDecoration(
                            color: item.isFolder 
                                ? SequencerPhoneBookColors.surfaceRaised
                                : SequencerPhoneBookColors.accent.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: item.isFolder 
                                  ? SequencerPhoneBookColors.border
                                  : SequencerPhoneBookColors.accent.withOpacity(0.6),
                              width: 1,
                            ),
                            boxShadow: [
                              // Protruding effect for all items
                              BoxShadow(
                                color: SequencerPhoneBookColors.shadow,
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                              BoxShadow(
                                color: SequencerPhoneBookColors.surfaceRaised,
                                blurRadius: 1,
                                offset: const Offset(0, -0.5),
                              ),
                            ],
                          ),
                          child: LayoutBuilder(
                            builder: (context, tileConstraints) {
                              final tilePadding = tileConstraints.maxWidth * (SampleBrowserSizing.tilePadding / 100);
                              final iconSize = tileConstraints.maxHeight * 0.4;
                              final fontSize = tileConstraints.maxWidth * 0.08;
                              
                              return item.isFolder 
                                  ? // Folder layout
                                    Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(tilePadding),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.folder,
                                              color: SequencerPhoneBookColors.accent,
                                              size: iconSize.clamp(20.0, 40.0),
                                            ),
                                            SizedBox(height: tilePadding * 0.5),
                                            Flexible(
                                              child: Text(
                                                item.name,
                                                style: GoogleFonts.sourceSans3(
                                                  color: SequencerPhoneBookColors.text,
                                                  fontSize: fontSize.clamp(8.0, 14.0),
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
                                    )
                                  : // File layout with 50/50 split
                                    Column(
                                      children: [
                                        // Top 50% - Play button area
                                        Expanded(
                                          flex: (SampleBrowserSizing.playButtonAreaRatio * 100).round(),
                                          child: GestureDetector(
                                            onTap: () => sequencerState.previewSample(item.path),
                                            child: Container(
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                color: SequencerPhoneBookColors.surfacePressed,
                                                borderRadius: const BorderRadius.only(
                                                  topLeft: Radius.circular(4),
                                                  topRight: Radius.circular(4),
                                                ),
                                                border: const Border(
                                                  bottom: BorderSide(
                                                    color: SequencerPhoneBookColors.border,
                                                    width: 1,
                                                  ),
                                                ),
                                              ),
                                              child: Center(
                                                child: Container(
                                                  width: tileConstraints.maxHeight * 0.25,
                                                  height: tileConstraints.maxHeight * 0.25,
                                                  decoration: BoxDecoration(
                                                    color: SequencerPhoneBookColors.accent.withOpacity(0.9),
                                                    borderRadius: BorderRadius.circular(tileConstraints.maxHeight * 0.125),
                                                    border: Border.all(
                                                      color: SequencerPhoneBookColors.border,
                                                      width: 1,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: SequencerPhoneBookColors.shadow,
                                                        blurRadius: 2,
                                                        offset: const Offset(0, 1),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Icon(
                                                    Icons.play_arrow,
                                                    color: SequencerPhoneBookColors.pageBackground,
                                                    size: (tileConstraints.maxHeight * 0.15).clamp(12.0, 20.0),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Bottom 50% - Pick/Select area
                                        Expanded(
                                          flex: (SampleBrowserSizing.pickAreaRatio * 100).round(),
                                          child: GestureDetector(
                                            onTap: () => sequencerState.selectSampleItem(item),
                                            child: Container(
                                              width: double.infinity,
                                              padding: EdgeInsets.all(tilePadding),
                                              decoration: const BoxDecoration(
                                                color: SequencerPhoneBookColors.accent,
                                                borderRadius: BorderRadius.only(
                                                  bottomLeft: Radius.circular(4),
                                                  bottomRight: Radius.circular(4),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  // File name
                                                  Expanded(
                                                    child: Text(
                                                      item.name,
                                                      style: GoogleFonts.sourceSans3(
                                                        color: SequencerPhoneBookColors.pageBackground,
                                                        fontSize: (fontSize * 0.8).clamp(6.0, 12.0),
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  // File type and tap hint
                                                  Text(
                                                    item.name.toLowerCase().endsWith('.wav') ? 'WAV' :
                                                    item.name.toLowerCase().endsWith('.mp3') ? 'MP3' :
                                                    item.name.toLowerCase().endsWith('.m4a') ? 'M4A' : 'AUDIO',
                                                    style: GoogleFonts.sourceSans3(
                                                      color: SequencerPhoneBookColors.pageBackground.withOpacity(0.8),
                                                      fontSize: (fontSize * 0.6).clamp(5.0, 10.0),
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  Text(
                                                    'TAP TO SELECT',
                                                    style: GoogleFonts.sourceSans3(
                                                      color: SequencerPhoneBookColors.pageBackground.withOpacity(0.9),
                                                      fontSize: (fontSize * 0.5).clamp(4.0, 8.0),
                                                      fontWeight: FontWeight.w700,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                            },
                          ),
                        ),
                        );
                      },
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
} 