import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state/sequencer_state.dart';
import '../../utils/musical_notes.dart';

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

class SampleSettingsWidget extends StatefulWidget {
  const SampleSettingsWidget({super.key});

  @override
  State<SampleSettingsWidget> createState() => _SampleSettingsWidgetState();
}

class _SampleSettingsWidgetState extends State<SampleSettingsWidget> {
  String _selectedControl = 'VOL'; // 'VOL' or 'KEY'

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive sizes based on available space - INHERIT from parent
            final panelHeight = constraints.maxHeight;
            
            // Padding & ratios
            final padding = panelHeight * 0.03;

            final innerHeight = panelHeight - padding * 2;
            final borderThickness = 1.0;
            final innerHeightAdj = innerHeight - borderThickness * 2;

            const headerRatio = 0.25;
            const footerRatio = 0.13;
            const spacingRatio = 0.02;

            final headerHeight = innerHeightAdj * headerRatio;
            final footerHeight = innerHeightAdj * footerRatio;
            final spacingHeight = innerHeightAdj * spacingRatio;
            final volumeControlHeight = innerHeightAdj - headerHeight - footerHeight - 2 * spacingHeight;

            final headerFontSize = (headerHeight * 0.35).clamp(10.0, 14.0);
            final labelFontSize = (headerHeight * 0.25).clamp(8.0, 11.0);
            final closeButtonSize = headerHeight * 0.8;
            final iconSize = (closeButtonSize * 0.5).clamp(12.0, 18.0);
            
            // Header element percentages (should add up to 100%)
            const double textAreaPercent = 25.0;     // Text area (Sample Settings + info)
            const double volButtonPercent = 11.0;    // VOL button
            const double keyButtonPercent = 11.0;    // KEY button
            const double eqButtonPercent = 11.0;     // EQ button
            const double rvbButtonPercent = 11.0;    // RVB button
            const double dlyButtonPercent = 11.0;    // DLY button
            const double delButtonPercent = 11.0;    // DEL button
            const double closeButtonPercent = 9.0;   // Close button
            
            // Get current sample info
            final currentSample = sequencer.activeBank;
            final sampleName = sequencer.fileNames[currentSample];
            final hasActiveSample = sampleName != null;
            
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
                  // Header – 25 %
                  Expanded(
                    flex: 25,
                    child: LayoutBuilder(
                      builder: (context, headerConstraints) {
                        final headerWidth = headerConstraints.maxWidth;
                        return Row(
                          children: [
                            // Sample info
                            SizedBox(
                              width: headerWidth * (textAreaPercent / 100),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Sample Settings',
                                    style: GoogleFonts.sourceSans3(
                                      color: SequencerPhoneBookColors.text,
                                      fontSize: headerFontSize,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  SizedBox(height: padding * 0.2),
                                  Text(
                                    hasActiveSample
                                        ? 'Sample ${String.fromCharCode(65 + currentSample)}: ${sampleName!.split('/').last}'
                                        : 'No sample selected',
                                    style: GoogleFonts.sourceSans3(
                                      color: SequencerPhoneBookColors.lightText,
                                      fontSize: labelFontSize,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 0.3,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            
                            // VOL button
                            SizedBox(
                              width: headerWidth * (volButtonPercent / 100),
                              child: _buildSettingsButton('VOL', _selectedControl == 'VOL', headerHeight * 0.7, labelFontSize, () {
                                setState(() {
                                  _selectedControl = 'VOL';
                                });
                              }),
                            ),
                            
                            // KEY button
                            SizedBox(
                              width: headerWidth * (keyButtonPercent / 100),
                              child: _buildSettingsButton('KEY', _selectedControl == 'KEY', headerHeight * 0.7, labelFontSize, () {
                                setState(() {
                                  _selectedControl = 'KEY';
                                });
                              }),
                            ),
                            
                            // EQ button
                            SizedBox(
                              width: headerWidth * (eqButtonPercent / 100),
                              child: _buildSettingsButton('EQ', false, headerHeight * 0.7, labelFontSize, null),
                            ),
                            
                            // RVB button
                            SizedBox(
                              width: headerWidth * (rvbButtonPercent / 100),
                              child: _buildSettingsButton('RVB', false, headerHeight * 0.7, labelFontSize, null),
                            ),
                            
                            // DLY button
                            SizedBox(
                              width: headerWidth * (dlyButtonPercent / 100),
                              child: _buildSettingsButton('DLY', false, headerHeight * 0.7, labelFontSize, null),
                            ),
                            
                            // DEL button
                            SizedBox(
                              width: headerWidth * (delButtonPercent / 100),
                              child: _buildSettingsButton('DEL', false, headerHeight * 0.7, labelFontSize, hasActiveSample ? () {
                                sequencer.removeSample(currentSample);
                                sequencer.setShowSampleSettings(false); // Close settings after deletion
                              } : null),
                            ),
                            
                            // Close button
                            SizedBox(
                              width: headerWidth * (closeButtonPercent / 100),
                              child: GestureDetector(
                                onTap: () => sequencer.setShowSampleSettings(false),
                                child: Container(
                                  height: headerHeight * 0.7,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(headerHeight * 0.7 * 0.15),
                                    border: Border.all(
                                      color: Colors.grey.withOpacity(0.4),
                                      width: 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.close,
                                      color: Colors.grey,
                                      size: iconSize,
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
                  
                  // Spacer 2 %
                  const Spacer(flex: 2),
                  
                  Expanded(
                    flex: 60,
                    child: LayoutBuilder(
                      builder: (context, innerConstraints) {
                        final volumeHeight = innerConstraints.maxHeight;
                        return hasActiveSample
                            ? _buildActiveControl(sequencer, currentSample, volumeHeight, padding, labelFontSize)
                            : _buildNoSampleMessage(volumeHeight, labelFontSize);
                      },
                    ),
                  ),
                  
                  // Spacer 2 %
                  const Spacer(flex: 2),
                  
                ],
              ),
            );
          },
        );
      },
    );
  }
  
  Widget _buildActiveControl(SequencerState sequencer, int sampleIndex, double height, double padding, double fontSize) {
    switch (_selectedControl) {
      case 'VOL':
        return _buildVolumeControl(sequencer, sampleIndex, height, padding, fontSize);
      case 'KEY':
        return _buildPitchControl(sequencer, sampleIndex, height, padding, fontSize);
      default:
        return _buildVolumeControl(sequencer, sampleIndex, height, padding, fontSize);
    }
  }

  Widget _buildVolumeControl(SequencerState sequencer, int sampleIndex, double height, double padding, double fontSize) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding * 0.4, vertical: padding * 0.2),
      decoration: BoxDecoration(
        color: SequencerPhoneBookColors.surfaceRaised,
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: SequencerPhoneBookColors.border,
          width: 1,
        ),
        boxShadow: [
          // Protruding effect
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
          // Volume label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Volume',
                style: GoogleFonts.sourceSans3(
                  color: SequencerPhoneBookColors.text,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                '${(sequencer.getSampleVolume(sampleIndex) * 100).round()}%',
                style: GoogleFonts.sourceSans3(
                  color: SequencerPhoneBookColors.accent,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          
          SizedBox(height: padding * 0.2),
          
          // Volume slider
          Builder(
            builder: (context) => SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: SequencerPhoneBookColors.accent,
                inactiveTrackColor: SequencerPhoneBookColors.border,
                thumbColor: SequencerPhoneBookColors.accent,
                trackHeight: (height * 0.06).clamp(2.0, 4.0),
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: (height * 0.04).clamp(8.0, 12.0)),
              ),
              child: Slider(
                value: sequencer.getSampleVolume(sampleIndex),
                onChanged: (value) => sequencer.setSampleVolume(sampleIndex, value),
                min: 0.0,
                max: 1.0,
                divisions: 100,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPitchControl(SequencerState sequencer, int sampleIndex, double height, double padding, double fontSize) {
    final currentPitch = sequencer.getSamplePitch(sampleIndex);
    final currentPosition = pitchMultiplierToSliderPosition(currentPitch);
    final noteName = sliderPositionToNoteName(currentPosition);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding * 0.4, vertical: padding * 0.2),
      decoration: BoxDecoration(
        color: SequencerPhoneBookColors.surfaceRaised,
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: SequencerPhoneBookColors.border,
          width: 1,
        ),
        boxShadow: [
          // Protruding effect
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
          // Pitch label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pitch',
                style: GoogleFonts.sourceSans3(
                  color: SequencerPhoneBookColors.text,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                noteName,
                style: GoogleFonts.sourceSans3(
                  color: SequencerPhoneBookColors.accent,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          
          SizedBox(height: padding * 0.2),
          
          // Pitch slider (C0 to C10)
          Builder(
            builder: (context) => SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: SequencerPhoneBookColors.accent,
                inactiveTrackColor: SequencerPhoneBookColors.border,
                thumbColor: SequencerPhoneBookColors.accent,
                trackHeight: (height * 0.06).clamp(2.0, 4.0),
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: (height * 0.04).clamp(8.0, 12.0)),
              ),
              child: Slider(
                value: currentPosition.toDouble(),
                onChanged: (value) {
                  final position = value.round();
                  final pitch = sliderPositionToPitchMultiplier(position);
                  sequencer.setSamplePitch(sampleIndex, pitch);
                },
                min: 0.0,
                max: (getTotalNotes() - 1).toDouble(),
                divisions: getTotalNotes() - 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNoSampleMessage(double height, double fontSize) {
    return Container(
      decoration: BoxDecoration(
        color: SequencerPhoneBookColors.surfacePressed,
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: SequencerPhoneBookColors.border,
          width: 1,
        ),
        boxShadow: [
          // Recessed effect for inactive state
          BoxShadow(
            color: SequencerPhoneBookColors.shadow,
            blurRadius: 1,
            offset: const Offset(0, 0.5),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_off,
              color: SequencerPhoneBookColors.lightText,
              size: height * 0.3,
            ),
            SizedBox(height: height * 0.1),
            Text(
              'Select a sample to configure',
              style: GoogleFonts.sourceSans3(
                color: SequencerPhoneBookColors.lightText,
                fontSize: fontSize,
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
    final isEnabled = onTap != null;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: isSelected 
              ? SequencerPhoneBookColors.accent 
              : isEnabled 
                  ? SequencerPhoneBookColors.surfaceRaised 
                  : SequencerPhoneBookColors.surfacePressed,
          borderRadius: BorderRadius.circular(2), // Sharp corners
          border: Border.all(
            color: SequencerPhoneBookColors.border,
            width: 0.5,
          ),
          boxShadow: isEnabled
              ? [
                  // Protruding effect for enabled buttons
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
                ]
              : [
                  // Recessed effect for disabled buttons
                  BoxShadow(
                    color: SequencerPhoneBookColors.shadow,
                    blurRadius: 1,
                    offset: const Offset(0, 0.5),
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