import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state/sequencer_state.dart';

// Copy exact color scheme from sound_settings.dart
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

class SimpleMasterSettingsWidget extends StatefulWidget {
  final VoidCallback closeAction;

  const SimpleMasterSettingsWidget({
    super.key,
    required this.closeAction,
  });

  @override
  State<SimpleMasterSettingsWidget> createState() => _SimpleMasterSettingsWidgetState();
}

class _SimpleMasterSettingsWidgetState extends State<SimpleMasterSettingsWidget> {
  String _selectedControl = 'BPM'; // Default to BPM
  
  // Simple variables for main layout areas
  double _headerButtonsHeight = 0.45;     // 25% for header buttons area
  double _sliderTileHeightPercent = 0.50; // 60% for slider tile area
  double _spacingHeight = 0.02;           // 2% for spacing between areas
  
  // Simple variables for slider components heights (within the slider tile)
  double _sliderTextAreaHeight = 0.5;     // 30% of tile for text area
  double _sliderControlHeight = 0.5;      // 70% of tile for slider control

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive sizes based on available space - INHERIT from parent
            final panelHeight = constraints.maxHeight;
            
            // Padding & ratios (same as sound_settings.dart)
            final padding = panelHeight * 0.03;

            final innerHeight = panelHeight - padding * 2;
            final borderThickness = 1.0;
            final innerHeightAdj = innerHeight - borderThickness * 2;

            // Use the simple variables for layout calculations
            final headerHeight = innerHeightAdj * _headerButtonsHeight;
            final spacingHeight = innerHeightAdj * _spacingHeight;
            final contentHeight = innerHeightAdj * _sliderTileHeightPercent;

            final labelFontSize = (headerHeight * 0.25).clamp(8.0, 11.0);
            
            return Container(
              padding: EdgeInsets.all(padding),
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
              child: Column(
                children: [
                  // Header buttons area - controllable via _headerButtonsHeight
                  Expanded(
                    flex: (_headerButtonsHeight * 100).round(),
                    child: _buildScrollableHeader(headerHeight, labelFontSize),
                  ),
                  
                  // Top spacer - controllable via _spacingHeight
                  Spacer(flex: (_spacingHeight * 100).round()),
                  
                  // Slider tile area - controllable via _sliderTileHeightPercent
                  Expanded(
                    flex: (_sliderTileHeightPercent * 100).round(),
                    child: _buildActiveControl(sequencer, contentHeight, padding, labelFontSize),
                  ),
                  
                  // Bottom spacer - controllable via _spacingHeight
                  Spacer(flex: (_spacingHeight * 100).round()),
                  
                  // Remaining space (auto-adjusts based on other areas)
                  Spacer(flex: ((1.0 - _headerButtonsHeight - _spacingHeight - _sliderTileHeightPercent - _spacingHeight) * 100).round().clamp(0, 100)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildScrollableHeader(double headerHeight, double labelFontSize) {
    final buttons = [
      'BPM', 'TILE', 'MASTER', 'COMP', 'EQ', 'RVB', 'DLY', 'FILTER', 'DISTORT'
    ];
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: buttons.map((buttonName) {
          return Padding(
            padding: const EdgeInsets.only(right: 8.0), // Spacing between buttons
            child: SizedBox(
              width: 80, // Fixed width for each button
              child: _buildSettingsButton(
                buttonName, 
                _selectedControl == buttonName, 
                headerHeight * 0.7, 
                labelFontSize, 
                () {
                  setState(() {
                    _selectedControl = buttonName;
                  });
                }
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActiveControl(SequencerState sequencer, double height, double padding, double fontSize) {
    switch (_selectedControl) {
      case 'BPM':
        return _buildBPMControl(sequencer, height, padding, fontSize);
      case 'MASTER':
        return _buildMasterControl(height, padding, fontSize);
      case 'COMP':
        return _buildCompControl(height, padding, fontSize);
      case 'EQ':
        return _buildEQControl(height, padding, fontSize);
      case 'RVB':
        return _buildRVBControl(height, padding, fontSize);
      case 'DLY':
        return _buildDLYControl(height, padding, fontSize);
      case 'FILTER':
        return _buildFilterControl(height, padding, fontSize);
      case 'DISTORT':
        return _buildDistortControl(height, padding, fontSize);
      default:
        return _buildBPMControl(sequencer, height, padding, fontSize);
    }
  }

  Widget _buildBPMControl(SequencerState sequencer, double height, double padding, double fontSize) {
    // The height parameter already reflects the _sliderTileHeightPercent from the flex layout
    // Use the simple variables to control text and slider heights
    final textAreaHeight = height * _sliderTextAreaHeight;
    final sliderAreaHeight = height * _sliderControlHeight;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding * 0.5, 
        vertical: padding * 0.3
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
        children: [
          // BPM info row - fixed proportion of text area
          SizedBox(
            height: textAreaHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left: BPM label
                Text(
                  'BPM',
                  style: GoogleFonts.sourceSans3(
                    color: SequencerPhoneBookColors.lightText,
                    fontSize: (textAreaHeight * 0.4).clamp(8.0, 16.0),
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
                    fontSize: (textAreaHeight * 0.6).clamp(12.0, 24.0),
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
                    fontSize: (textAreaHeight * 0.35).clamp(7.0, 14.0),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          
          // Slider area - takes remaining space and scales with tile height
          Expanded(
            child: Center(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: SequencerPhoneBookColors.accent,
                  inactiveTrackColor: SequencerPhoneBookColors.border,
                  thumbColor: SequencerPhoneBookColors.accent,
                  trackHeight: (sliderAreaHeight * 0.05).clamp(2.0, 8.0), // Scales with slider area
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: (sliderAreaHeight * 0.08).clamp(8.0, 20.0), // Scales with slider area
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
            ),
          ),
        ],
      ),
    );
  }

  // Placeholder controls for other buttons
  Widget _buildMasterControl(double height, double padding, double fontSize) {
    return _buildPlaceholderControl('MASTER', 'Master volume and effects', height, padding, fontSize);
  }

  Widget _buildCompControl(double height, double padding, double fontSize) {
    return _buildPlaceholderControl('COMP', 'Compression settings', height, padding, fontSize);
  }

  Widget _buildEQControl(double height, double padding, double fontSize) {
    return _buildPlaceholderControl('EQ', 'Equalizer settings', height, padding, fontSize);
  }

  Widget _buildRVBControl(double height, double padding, double fontSize) {
    return _buildPlaceholderControl('RVB', 'Reverb settings', height, padding, fontSize);
  }

  Widget _buildDLYControl(double height, double padding, double fontSize) {
    return _buildPlaceholderControl('DLY', 'Delay settings', height, padding, fontSize);
  }

  Widget _buildFilterControl(double height, double padding, double fontSize) {
    return _buildPlaceholderControl('FILTER', 'Filter settings', height, padding, fontSize);
  }

  Widget _buildDistortControl(double height, double padding, double fontSize) {
    return _buildPlaceholderControl('DISTORT', 'Distortion settings', height, padding, fontSize);
  }

  Widget _buildPlaceholderControl(String title, String description, double height, double padding, double fontSize) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding * 0.5, 
        vertical: padding * 0.3
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
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: GoogleFonts.sourceSans3(
                color: SequencerPhoneBookColors.accent,
                fontSize: fontSize * 1.8,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: height * 0.05),
            Text(
              description,
              textAlign: TextAlign.center,
              style: GoogleFonts.sourceSans3(
                color: SequencerPhoneBookColors.lightText,
                fontSize: fontSize * 1.1,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsButton(String label, bool isSelected, double height, double fontSize, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
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
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
} 