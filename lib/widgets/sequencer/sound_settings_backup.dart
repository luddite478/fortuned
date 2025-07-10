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

enum SettingsType { cell, sample }

class CellOrSampleSettingsWidget extends StatefulWidget {
  final SettingsType type;
  final String title;
  final String Function(SequencerState sequencer) infoTextBuilder;
  final bool Function(SequencerState sequencer) hasDataChecker;
  final int? Function(SequencerState sequencer) indexProvider;
  final double Function(SequencerState sequencer, int index) volumeGetter;
  final void Function(SequencerState sequencer, int index, double volume) volumeSetter;
  final double Function(SequencerState sequencer, int index) pitchGetter;
  final void Function(SequencerState sequencer, int index, double pitch) pitchSetter;
  final VoidCallback? Function(SequencerState sequencer, int? index) deleteActionProvider;
  final VoidCallback closeAction;
  final String noDataMessage;
  final IconData noDataIcon;

  const CellOrSampleSettingsWidget({
    super.key,
    required this.type,
    required this.title,
    required this.infoTextBuilder,
    required this.hasDataChecker,
    required this.indexProvider,
    required this.volumeGetter,
    required this.volumeSetter,
    required this.pitchGetter,
    required this.pitchSetter,
    required this.deleteActionProvider,
    required this.closeAction,
    required this.noDataMessage,
    required this.noDataIcon,
  });

  // Factory constructors for common use cases
  factory CellOrSampleSettingsWidget.forCell() {
    return CellOrSampleSettingsWidget(
      type: SettingsType.cell,
      title: 'Cell Settings',
      infoTextBuilder: (sequencer) {
        final selectedCell = sequencer.selectedCellForSettings;
        final hasCellSelected = selectedCell != null;
        final cellSample = hasCellSelected ? sequencer.gridSamples[selectedCell] : null;
        final cellHasSample = cellSample != null;
        
        if (hasCellSelected) {
          if (cellHasSample) {
            final row = selectedCell ~/ sequencer.gridColumns;
            final col = selectedCell % sequencer.gridColumns;
            return 'Cell ${row + 1}:${col + 1} - Sample ${String.fromCharCode(65 + cellSample!)}';
          } else {
            final row = selectedCell ~/ sequencer.gridColumns;
            final col = selectedCell % sequencer.gridColumns;
            return 'Cell ${row + 1}:${col + 1} - Empty';
          }
        } else {
          return 'No cell selected';
        }
      },
      hasDataChecker: (sequencer) {
        final selectedCell = sequencer.selectedCellForSettings;
        final hasCellSelected = selectedCell != null;
        final cellSample = hasCellSelected ? sequencer.gridSamples[selectedCell] : null;
        return cellSample != null;
      },
      indexProvider: (sequencer) => sequencer.selectedCellForSettings,
      volumeGetter: (sequencer, index) => sequencer.getCellVolume(index),
      volumeSetter: (sequencer, index, volume) => sequencer.setCellVolume(index, volume),
      pitchGetter: (sequencer, index) => sequencer.getCellPitch(index),
      pitchSetter: (sequencer, index, pitch) => sequencer.setCellPitch(index, pitch),
      deleteActionProvider: (sequencer, index) => (index != null && 
          sequencer.selectedCellForSettings != null && 
          sequencer.gridSamples[sequencer.selectedCellForSettings!] != null) 
        ? () {
            sequencer.clearCell(index);
            sequencer.setShowCellSettings(false);
          }
        : null,
      closeAction: () {}, // Will be set by consumer
      noDataMessage: 'Tap a cell with a sample to configure',
      noDataIcon: Icons.grid_off,
    );
  }

  factory CellOrSampleSettingsWidget.forSample() {
    return CellOrSampleSettingsWidget(
      type: SettingsType.sample,
      title: 'Sample Settings',
      infoTextBuilder: (sequencer) {
        final currentSample = sequencer.activeBank;
        final sampleName = sequencer.fileNames[currentSample];
        final hasActiveSample = sampleName != null;
        
        return hasActiveSample
            ? 'Sample ${String.fromCharCode(65 + currentSample)}: ${sampleName!.split('/').last}'
            : 'No sample selected';
      },
      hasDataChecker: (sequencer) => sequencer.fileNames[sequencer.activeBank] != null,
      indexProvider: (sequencer) => sequencer.activeBank,
      volumeGetter: (sequencer, index) => sequencer.getSampleVolume(index),
      volumeSetter: (sequencer, index, volume) => sequencer.setSampleVolume(index, volume),
      pitchGetter: (sequencer, index) => sequencer.getSamplePitch(index),
      pitchSetter: (sequencer, index, pitch) => sequencer.setSamplePitch(index, pitch),
      deleteActionProvider: (sequencer, index) => (index != null && 
          sequencer.fileNames[index] != null) 
        ? () {
            sequencer.removeSample(index);
            sequencer.setShowSampleSettings(false);
          }
        : null,
      closeAction: () {}, // Will be set by consumer
      noDataMessage: 'Select a sample to configure',
      noDataIcon: Icons.music_off,
    );
  }

  @override
  State<CellOrSampleSettingsWidget> createState() => _CellOrSampleSettingsWidgetState();
}

class _CellOrSampleSettingsWidgetState extends State<CellOrSampleSettingsWidget> {
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
            const double spacerPercent = 1.0;        // Minimal left spacer
            const double volButtonPercent = 14;    // VOL button
            const double keyButtonPercent = 14;    // KEY button
            const double eqButtonPercent = 14;     // EQ button
            const double rvbButtonPercent = 14;    // RVB button
            const double dlyButtonPercent = 14;    // DLY button
            const double spacingPercent = 2.0;       // Spacing before DEL
            const double delButtonPercent = 14;    // DEL button
            const double spacing2Percent = 2.0;      // Spacing before close
            const double closeButtonPercent = 10.0;  // Close button
            
            // Get current data info
            final hasData = widget.hasDataChecker(sequencer);
            final currentIndex = widget.indexProvider(sequencer);
            
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
                            // Left spacer (no text)
                            SizedBox(
                              width: headerWidth * (spacerPercent / 100),
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
                            
                            // Spacing before DEL
                            SizedBox(width: headerWidth * (spacingPercent / 100)),
                            
                            // DEL button
                            SizedBox(
                              width: headerWidth * (delButtonPercent / 100),
                              child: _buildSettingsButton('DEL', false, headerHeight * 0.7, labelFontSize, widget.deleteActionProvider(sequencer, currentIndex)),
                            ),
                            
                            // Spacing before close
                            SizedBox(width: headerWidth * (spacing2Percent / 100)),
                            
                            // Close button
                            SizedBox(
                              width: headerWidth * (closeButtonPercent / 100),
                              child: GestureDetector(
                                onTap: widget.closeAction,
                                child: Container(
                                  height: headerHeight * 0.7,
                                  decoration: BoxDecoration(
                                    color: SequencerPhoneBookColors.surfacePressed,
                                    borderRadius: BorderRadius.circular(2), // Sharp corners
                                    border: Border.all(
                                      color: SequencerPhoneBookColors.border,
                                      width: 0.5,
                                    ),
                                    boxShadow: [
                                      // Recessed effect for close button
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
                        final controlHeight = innerConstraints.maxHeight;
                        return (hasData && currentIndex != null)
                            ? _buildActiveControl(sequencer, currentIndex, controlHeight, padding, labelFontSize)
                            : _buildNoDataMessage(controlHeight, labelFontSize);
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
  
  Widget _buildActiveControl(SequencerState sequencer, int index, double height, double padding, double fontSize) {
    switch (_selectedControl) {
      case 'VOL':
        return _buildVolumeControl(sequencer, index, height, padding, fontSize);
      case 'KEY':
        return _buildPitchControl(sequencer, index, height, padding, fontSize);
      default:
        return _buildVolumeControl(sequencer, index, height, padding, fontSize);
    }
  }

  Widget _buildVolumeControl(SequencerState sequencer, int index, double height, double padding, double fontSize) {
    // Get info text based on type
    String leftInfo = '';
    String centerInfo = '';
    
    if (widget.type == SettingsType.cell) {
      final selectedCell = sequencer.selectedCellForSettings;
      if (selectedCell != null) {
        final row = selectedCell ~/ sequencer.gridColumns;
        final col = selectedCell % sequencer.gridColumns;
        final cellSample = sequencer.gridSamples[selectedCell];
        final sampleLetter = cellSample != null ? String.fromCharCode(65 + cellSample) : '-';
        leftInfo = 'L1-${row + 1}-${col + 1}-$sampleLetter';
        
        // Get sample name
        if (cellSample != null) {
          final sampleName = sequencer.fileNames[cellSample];
          centerInfo = sampleName?.split('/').last ?? 'Unknown';
        }
      }
    } else {
      // Sample mode
      leftInfo = String.fromCharCode(65 + index);
      final sampleName = sequencer.fileNames[index];
      centerInfo = sampleName?.split('/').last ?? 'Unknown';
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding * 0.3, vertical: padding * 0.05),
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
          // Info row - left info, center sample name, right percentage
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left: Layer-Row-Col-Sample or Sample letter
              Expanded(
                flex: 25,
                child: Text(
                  leftInfo,
                  style: GoogleFonts.sourceSans3(
                    color: SequencerPhoneBookColors.lightText,
                    fontSize: (fontSize * 0.9).clamp(10.0, 14.0),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              
              // Center: Sample name
              Expanded(
                flex: 50,
                child: Text(
                  centerInfo,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.sourceSans3(
                    color: SequencerPhoneBookColors.text,
                    fontSize: (fontSize * 0.85).clamp(9.0, 13.0),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              // Right: Percentage (bigger)
              Expanded(
                flex: 25,
                child: Text(
                  '${(widget.volumeGetter(sequencer, index) * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.sourceSans3(
                    color: SequencerPhoneBookColors.accent,
                    fontSize: (fontSize * 1.1).clamp(11.0, 16.0),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: padding * 0.08),
          
          // Volume slider
          Builder(
            builder: (context) => SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: SequencerPhoneBookColors.accent,
                inactiveTrackColor: SequencerPhoneBookColors.border,
                thumbColor: SequencerPhoneBookColors.accent,
                trackHeight: (height * 0.04).clamp(1.5, 3.0),
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: (height * 0.03).clamp(6.0, 10.0)),
              ),
              child: Slider(
                value: widget.volumeGetter(sequencer, index),
                onChanged: (value) => widget.volumeSetter(sequencer, index, value),
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

  Widget _buildPitchControl(SequencerState sequencer, int index, double height, double padding, double fontSize) {
    final currentPitch = widget.pitchGetter(sequencer, index);
    final currentPosition = pitchMultiplierToSliderPosition(currentPitch);
    final noteName = sliderPositionToNoteName(currentPosition);

    // Get info text based on type
    String leftInfo = '';
    String centerInfo = '';
    
    if (widget.type == SettingsType.cell) {
      final selectedCell = sequencer.selectedCellForSettings;
      if (selectedCell != null) {
        final row = selectedCell ~/ sequencer.gridColumns;
        final col = selectedCell % sequencer.gridColumns;
        final cellSample = sequencer.gridSamples[selectedCell];
        final sampleLetter = cellSample != null ? String.fromCharCode(65 + cellSample) : '-';
        leftInfo = 'L1-${row + 1}-${col + 1}-$sampleLetter';
        
        // Get sample name
        if (cellSample != null) {
          final sampleName = sequencer.fileNames[cellSample];
          centerInfo = sampleName?.split('/').last ?? 'Unknown';
        }
      }
    } else {
      // Sample mode
      leftInfo = String.fromCharCode(65 + index);
      final sampleName = sequencer.fileNames[index];
      centerInfo = sampleName?.split('/').last ?? 'Unknown';
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding * 0.3, vertical: padding * 0.05),
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
          // Info row - left info, center sample name, right note name
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left: Layer-Row-Col-Sample or Sample letter
              Expanded(
                flex: 25,
                child: Text(
                  leftInfo,
                  style: GoogleFonts.sourceSans3(
                    color: SequencerPhoneBookColors.lightText,
                    fontSize: (fontSize * 0.9).clamp(10.0, 14.0),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              
              // Center: Sample name
              Expanded(
                flex: 50,
                child: Text(
                  centerInfo,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.sourceSans3(
                    color: SequencerPhoneBookColors.text,
                    fontSize: (fontSize * 0.85).clamp(9.0, 13.0),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              // Right: Note name (bigger)
              Expanded(
                flex: 25,
                child: Text(
                  noteName,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.sourceSans3(
                    color: SequencerPhoneBookColors.accent,
                    fontSize: (fontSize * 1.1).clamp(11.0, 16.0),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: padding * 0.08),
          
          // Pitch slider (C0 to C10)
          Builder(
            builder: (context) => SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: SequencerPhoneBookColors.accent,
                inactiveTrackColor: SequencerPhoneBookColors.border,
                thumbColor: SequencerPhoneBookColors.accent,
                trackHeight: (height * 0.04).clamp(1.5, 3.0),
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: (height * 0.03).clamp(6.0, 10.0)),
              ),
              child: Slider(
                value: currentPosition.toDouble(),
                onChanged: (value) {
                  final position = value.round();
                  final pitch = sliderPositionToPitchMultiplier(position);
                  widget.pitchSetter(sequencer, index, pitch);
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
  
  Widget _buildNoDataMessage(double height, double fontSize) {
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
              widget.noDataIcon,
              color: SequencerPhoneBookColors.lightText,
              size: height * 0.3,
            ),
            SizedBox(height: height * 0.1),
            Text(
              widget.noDataMessage,
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