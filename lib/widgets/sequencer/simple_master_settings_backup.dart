import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state/sequencer_state.dart';

// Copy exact color scheme from sample_selection_widget.dart
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

class SimpleMasterSettingsWidget extends StatelessWidget {
  final VoidCallback closeAction;

  const SimpleMasterSettingsWidget({
    super.key,
    required this.closeAction,
  });

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
          child: _buildSimpleMenu(context, sequencerState),
        );
      },
    );
  }

  Widget _buildSimpleMenu(BuildContext context, SequencerState sequencerState) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Inherit parent dimensions for percentage calculations
          final availableHeight = constraints.maxHeight - 24; // minus padding
          final availableWidth = constraints.maxWidth - 24; // minus padding
          
          // Calculate sizes as percentages of available space
          final buttonHeight = availableHeight * 0.30; // 8% of height (small buttons)
          final buttonSpacing = availableWidth * 0.01; // 1% of width
          final rowSpacing = availableHeight * 0.01; // 1% of height (minimal spacing)
          final beforeTilesSpacing = availableHeight * 0.02; // 2% of height
          final fontSize = buttonHeight * 0.35; // 35% of button height
          final closeButtonSize = buttonHeight; // Same as button height
          final iconSize = closeButtonSize * 0.5; // 50% of close button
          final rightSpacer = availableWidth * 0.08; // 8% of width
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Button area - natural sizing based on percentages
              Column(
                children: [
                  // Header with buttons - First row
                  Row(
                    children: [
                      // BPM button
                      Expanded(
                        child: _buildButton('BPM', true, buttonHeight, fontSize),
                      ),
                      
                      SizedBox(width: buttonSpacing),
                      
                      // MASTER button
                      Expanded(
                        child: _buildButton('MASTER', false, buttonHeight, fontSize),
                      ),
                      
                      SizedBox(width: buttonSpacing),
                      
                      // COMP button
                      Expanded(
                        child: _buildButton('COMP', false, buttonHeight, fontSize),
                      ),
                      
                      SizedBox(width: buttonSpacing),
                      
                      // EQ button
                      Expanded(
                        child: _buildButton('EQ', false, buttonHeight, fontSize),
                      ),
                      
                      SizedBox(width: buttonSpacing * 2), // Double spacing before close
                      
                      // Close button
                      GestureDetector(
                        onTap: closeAction,
                        child: Container(
                          width: closeButtonSize,
                          height: closeButtonSize,
                          decoration: BoxDecoration(
                            color: SequencerPhoneBookColors.surfacePressed,
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(
                              color: SequencerPhoneBookColors.border,
                              width: 0.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: SequencerPhoneBookColors.shadow,
                                blurRadius: 1,
                                offset: const Offset(0, 0.5),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              Icons.close,
                              color: SequencerPhoneBookColors.lightText,
                              size: iconSize,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  SizedBox(height: rowSpacing),
                  
                  // Second row of buttons
                  Row(
                    children: [
                      // RVB button
                      Expanded(
                        flex: 1,
                        child: _buildButton('RVB', false, buttonHeight, fontSize),
                      ),
                      
                      SizedBox(width: buttonSpacing),
                      
                      // DLY button
                      Expanded(
                        flex: 2,
                        child: _buildButton('DLY', false, buttonHeight, fontSize),
                      ),
                      
                      SizedBox(width: buttonSpacing),
                      
                      // FILTER button
                      Expanded(
                        flex: 3,
                        child: _buildButton('FILTER', false, buttonHeight, fontSize),
                      ),
                      
                      SizedBox(width: buttonSpacing),
                      
                      // DISTORT button
                      Expanded(
                        flex: 3,
                        child: _buildButton('DISTORT', false, buttonHeight, fontSize),
                      ),
                      
                      // Right spacer to balance close button
                      SizedBox(width: rightSpacer),
                    ],
                  ),
                ],
              ),
              
              SizedBox(height: beforeTilesSpacing),
              
              // Slider area - takes ALL remaining space
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: availableWidth * 0.05, // 5% padding on sides
                    vertical: availableHeight * 0.02, // 2% padding top/bottom
                  ),
                  decoration: BoxDecoration(
                    color: SequencerPhoneBookColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(2),
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
                      BoxShadow(
                        color: SequencerPhoneBookColors.surfaceRaised,
                        blurRadius: 1,
                        offset: const Offset(0, -0.5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // BPM info row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Left: BPM label
                          Text(
                            'BPM',
                            style: GoogleFonts.sourceSans3(
                              color: SequencerPhoneBookColors.lightText,
                              fontSize: fontSize * 0.9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          
                          // Center: Current BPM value
                          Text(
                            '120', // Default BPM value
                            textAlign: TextAlign.center,
                            style: GoogleFonts.sourceSans3(
                              color: SequencerPhoneBookColors.accent,
                              fontSize: fontSize * 1.4,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                          
                          // Right: BPM text
                          Text(
                            'Beats/Min',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.sourceSans3(
                              color: SequencerPhoneBookColors.lightText,
                              fontSize: fontSize * 0.8,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                      
                      SizedBox(height: availableHeight * 0.02),
                      
                      // BPM slider (60 to 200 BPM)
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: SequencerPhoneBookColors.accent,
                          inactiveTrackColor: SequencerPhoneBookColors.border,
                          thumbColor: SequencerPhoneBookColors.accent,
                          trackHeight: availableHeight * 0.008, // Track height as percentage
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: availableHeight * 0.015, // Thumb size as percentage
                          ),
                        ),
                        child: Slider(
                          value: 120.0, // Default BPM
                          onChanged: (value) {
                            // TODO: Implement BPM change
                          },
                          min: 60.0,
                          max: 200.0,
                          divisions: 140, // 1 BPM increments
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildButton(String label, bool isSelected, double height, double fontSize) {
    return Container(
      height: height, // Now percentage-based
      decoration: BoxDecoration(
        color: isSelected 
            ? SequencerPhoneBookColors.accent 
            : SequencerPhoneBookColors.surfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: SequencerPhoneBookColors.border,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: SequencerPhoneBookColors.shadow,
            blurRadius: 1.5,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: SequencerPhoneBookColors.surfaceRaised,
            blurRadius: 0.5,
            offset: const Offset(0, -0.5),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: GoogleFonts.sourceSans3(
            color: isSelected 
                ? SequencerPhoneBookColors.pageBackground 
                : SequencerPhoneBookColors.text,
            fontSize: fontSize, // Now percentage-based
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
} 