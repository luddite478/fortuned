import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';import '../../../state/sequencer_state.dart';
import '../../../utils/app_colors.dart';import '../../../utils/musical_notes.dart';
import '../../../utils/app_colors.dart';import 'generic_slider.dart';
import '../../../utils/app_colors.dart';


// Pitch conversion utilities
class PitchConversion {
  /// Convert UI slider value (0.0-1.0) to pitch ratio (0.03125-32.0)
  /// UI: 0.0 = -12 semitones, 0.5 = 0 semitones, 1.0 = +12 semitones
  static double uiValueToPitchRatio(double uiValue) {
    if (uiValue < 0.0 || uiValue > 1.0) return 1.0; // Fallback to original pitch
    
    // Convert: UI 0.0→-12 semitones, 0.5→0 semitones, 1.0→+12 semitones
    final semitones = uiValue * 24.0 - 12.0;
    return math.pow(2.0, semitones / 12.0).toDouble();
  }
  
  /// Convert pitch ratio (0.03125-32.0) to UI slider value (0.0-1.0)
  static double pitchRatioToUiValue(double ratio) {
    if (ratio <= 0.0) return 0.5; // Fallback to center
    
    // Convert: ratio → semitones → UI value
    final semitones = 12.0 * (math.log(ratio) / math.ln2);
    return (semitones + 12.0) / 24.0;
  }
}


enum SettingsType { cell, sample, master }

class SoundSettingsWidget extends StatefulWidget {
  final SettingsType type;
  final String title;
  final List<String> headerButtons;
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
  final bool showDeleteButton;
  final bool showCloseButton;

  const SoundSettingsWidget({
    super.key,
    required this.type,
    required this.title,
    required this.headerButtons,
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
    this.showDeleteButton = true,
    this.showCloseButton = true,
  });

  // Factory constructors for common use cases
  factory SoundSettingsWidget.forCell() {
    return SoundSettingsWidget(
      type: SettingsType.cell,
      title: 'Cell Settings',
      headerButtons: ['VOL', 'KEY'],
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
      pitchGetter: (sequencer, index) => PitchConversion.pitchRatioToUiValue(sequencer.getCellPitch(index)),
      pitchSetter: (sequencer, index, uiValue) => sequencer.setCellPitch(index, PitchConversion.uiValueToPitchRatio(uiValue)),
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

  factory SoundSettingsWidget.forSample() {
    return SoundSettingsWidget(
      type: SettingsType.sample,
      title: 'Sample Settings',
      headerButtons: ['VOL', 'KEY'],
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
      pitchGetter: (sequencer, index) => PitchConversion.pitchRatioToUiValue(sequencer.getSamplePitch(index)),
      pitchSetter: (sequencer, index, uiValue) => sequencer.setSamplePitch(index, PitchConversion.uiValueToPitchRatio(uiValue)),
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

  factory SoundSettingsWidget.forMaster() {
    return SoundSettingsWidget(
      type: SettingsType.master,
      title: 'Master Settings',
      headerButtons: ['BPM', 'MASTER'],
      infoTextBuilder: (sequencer) => 'Master Controls', // Always available
      hasDataChecker: (sequencer) => true, // Always has data for master
      indexProvider: (sequencer) => 0, // Default index for master
      volumeGetter: (sequencer, index) => 1.0, // Master volume placeholder
      volumeSetter: (sequencer, index, volume) {}, // Master volume setter placeholder
      pitchGetter: (sequencer, index) => 0.0, // Master pitch placeholder
      pitchSetter: (sequencer, index, pitch) {}, // Master pitch setter placeholder
      deleteActionProvider: (sequencer, index) => null, // No delete for master
      closeAction: () {}, // Will be set by consumer
      noDataMessage: 'Master controls not available',
      noDataIcon: Icons.settings,
      showDeleteButton: false, // No delete button for master
      showCloseButton: false,  // No close button for master
    );
  }

  @override
  State<SoundSettingsWidget> createState() => _SoundSettingsWidgetState();
}

class _SoundSettingsWidgetState extends State<SoundSettingsWidget> {
  String _selectedControl = 'VOL'; // Default to VOL for cell/sample, will be set to first button for master
  
  // Simple variables for main layout areas (same as master settings template)
  double _headerButtonsHeight = 0.45;     // 25% for header buttons area
  double _sliderTileHeightPercent = 0.50; // 60% for slider tile area
  double _spacingHeight = 0.02;           // 2% for spacing between areas
  
  // Simple variables for slider components heights (within the slider tile)
  double _sliderTextAreaHeight = 0.3;     // 30% of tile for text area
  double _sliderControlHeight = 0.7;      // 70% of tile for slider control

  @override
  void initState() {
    super.initState();
    // Set default control based on type
    if (widget.type == SettingsType.master) {
      _selectedControl = widget.headerButtons.isNotEmpty ? widget.headerButtons.first : 'BPM';
    } else {
      _selectedControl = 'VOL';
    }
  }

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

            // Use the simple variables for layout calculations
            final headerHeight = innerHeightAdj * _headerButtonsHeight;
            final spacingHeight = innerHeightAdj * _spacingHeight;
            final contentHeight = innerHeightAdj * _sliderTileHeightPercent;

            final labelFontSize = (headerHeight * 0.25).clamp(8.0, 11.0);
            
            // Get current data info
            final hasData = widget.hasDataChecker(sequencer);
            final currentIndex = widget.indexProvider(sequencer);
            
            return Container(
              padding: EdgeInsets.all(padding),
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
                  // Header buttons area - controllable via _headerButtonsHeight
                  Expanded(
                    flex: (_headerButtonsHeight * 100).round(),
                    child: _buildScrollableHeader(headerHeight, labelFontSize, sequencer, currentIndex),
                  ),
                  
                  // Top spacer - controllable via _spacingHeight
                  Spacer(flex: (_spacingHeight * 100).round()),
                  
                  // Slider tile area - controllable via _sliderTileHeightPercent
                  Expanded(
                    flex: (_sliderTileHeightPercent * 100).round(),
                    child: (hasData && currentIndex != null)
                        ? _buildActiveControl(sequencer, currentIndex, contentHeight, padding, labelFontSize)
                        : _buildNoDataMessage(contentHeight, labelFontSize),
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

  Widget _buildScrollableHeader(double headerHeight, double labelFontSize, SequencerState sequencer, int? currentIndex) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Header buttons from the configuration
          ...widget.headerButtons.map((buttonName) {
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
          
          // Optional spacing before action buttons
          if (widget.showDeleteButton || widget.showCloseButton)
            const SizedBox(width: 16.0),
          
          // DEL button (if enabled)
          if (widget.showDeleteButton)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: 80,
                child: _buildSettingsButton(
                  'DEL', 
                  false, 
                  headerHeight * 0.7, 
                  labelFontSize, 
                  widget.deleteActionProvider(sequencer, currentIndex)
                ),
              ),
            ),
          
          // Close button (if enabled)
          if (widget.showCloseButton)
            SizedBox(
              width: 60,
              child: GestureDetector(
                onTap: widget.closeAction,
                child: Container(
                  height: headerHeight * 0.7,
                  decoration: BoxDecoration(
                    color: AppColors.sequencerSurfacePressed,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: AppColors.sequencerBorder,
                      width: 0.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.sequencerShadow,
                        blurRadius: 1,
                        offset: const Offset(0, 0.5),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.close,
                      color: AppColors.sequencerLightText,
                      size: (headerHeight * 0.35).clamp(12.0, 18.0),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActiveControl(SequencerState sequencer, int index, double height, double padding, double fontSize) {
    // Handle different control types based on current selection and settings type
    if (widget.type == SettingsType.master) {
      return _buildMasterControl(sequencer, _selectedControl, height, padding, fontSize);
    } else {
      // Cell and Sample controls
      switch (_selectedControl) {
        case 'VOL':
          return _buildVolumeControl(sequencer, index, height, padding, fontSize);
        case 'KEY':
          return _buildPitchControl(sequencer, index, height, padding, fontSize);
        // case 'EQ':
        //   return _buildPlaceholderControl('EQ', 'Equalizer settings', height, padding, fontSize);
        // case 'RVB':
        //   return _buildPlaceholderControl('RVB', 'Reverb settings', height, padding, fontSize);
        // case 'DLY':
        //   return _buildPlaceholderControl('DLY', 'Delay settings', height, padding, fontSize);
        default:
          return _buildVolumeControl(sequencer, index, height, padding, fontSize);
      }
    }
  }

  Widget _buildMasterControl(SequencerState sequencer, String controlType, double height, double padding, double fontSize) {
    switch (controlType) {
      case 'BPM':
        return _buildBPMControl(sequencer, height, padding, fontSize);
      case 'MASTER':
        return _buildPlaceholderControl('MASTER', 'Master volume and effects', height, padding, fontSize);
      // case 'COMP':
      //   return _buildPlaceholderControl('COMP', 'Compression settings', height, padding, fontSize);
      // case 'EQ':
      //   return _buildPlaceholderControl('EQ', 'Equalizer settings', height, padding, fontSize);
      // case 'RVB':
      //   return _buildPlaceholderControl('RVB', 'Reverb settings', height, padding, fontSize);
      // case 'DLY':
      //   return _buildPlaceholderControl('DLY', 'Delay settings', height, padding, fontSize);
      // case 'FILTER':
      //   return _buildPlaceholderControl('FILTER', 'Filter settings', height, padding, fontSize);
      // case 'DIST':
      //   return _buildPlaceholderControl('DIST', 'Distortion settings', height, padding, fontSize);
      default:
        return _buildBPMControl(sequencer, height, padding, fontSize);
    }
  }

  Widget _buildBPMControl(SequencerState sequencer, double height, double padding, double fontSize) {
    // Use the simple variables to control text and slider heights
    final textAreaHeight = height * _sliderTextAreaHeight;
    final sliderAreaHeight = height * _sliderControlHeight;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding * 0.5, 
        vertical: padding * 0.3
      ),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 1,
        ),
        boxShadow: [
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
      child: ValueListenableBuilder<int>(
        valueListenable: sequencer.bpmNotifier,
        builder: (context, bpm, child) {
                    return Center(
            child: GenericSlider(
              value: bpm.toDouble(),
              min: SequencerState.minBpm.toDouble(),
              max: SequencerState.maxBpm.toDouble(),
              divisions: SequencerState.maxBpm - SequencerState.minBpm,
              type: SliderType.bpm,
              onChanged: (value) => sequencer.setBpm(value.round()),
              height: height,
              sequencer: sequencer,
            ),
          );
        },
      ),
    );
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
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 1,
        ),
        boxShadow: [
          // Protruding effect
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
      child: Center(
        child: GenericSlider(
          value: widget.volumeGetter(sequencer, index),
          min: 0.0,
          max: 1.0,
          divisions: 100,
          type: SliderType.volume,
          onChanged: (value) => widget.volumeSetter(sequencer, index, value),
          height: height,
          sequencer: sequencer,
        ),
      ),
    );
  }

  Widget _buildPitchControl(SequencerState sequencer, int index, double height, double padding, double fontSize) {
    // Get current pitch in semitones
    final currentPitch = widget.pitchGetter(sequencer, index);
    final semitones = (currentPitch * 24 - 12).round(); // Convert to semitones (-12 to +12)
    final noteInfo = MusicalNotes.getNoteInfo(semitones);
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding * 0.3, vertical: padding * 0.05),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 1,
        ),
        boxShadow: [
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
      child: Center(
        child: GenericSlider(
          value: currentPitch,
          min: 0.0,
          max: 1.0,
          divisions: 24,
          type: SliderType.pitch,
          onChanged: (value) => widget.pitchSetter(sequencer, index, value),
          height: height,
          sequencer: sequencer,
        ),
      ),
    );
  }

  Widget _buildPlaceholderControl(String title, String description, double height, double padding, double fontSize) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding * 0.5, 
        vertical: padding * 0.3
      ),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.sequencerShadow,
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
                color: AppColors.sequencerAccent,
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
                color: AppColors.sequencerLightText,
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

  Widget _buildNoDataMessage(double height, double fontSize) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 1,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.noDataIcon,
              color: AppColors.sequencerLightText,
              size: fontSize * 3,
            ),
            SizedBox(height: height * 0.05),
            Text(
              widget.noDataMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.sourceSans3(
                color: AppColors.sequencerLightText,
                fontSize: fontSize * 1.2,
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
              ? AppColors.sequencerAccent 
              : AppColors.sequencerSurfaceRaised,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: AppColors.sequencerBorder,
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.sequencerShadow,
              blurRadius: 1.5,
              offset: const Offset(0, 1),
            ),
            BoxShadow(
              color: AppColors.sequencerSurfaceRaised,
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
                  ? AppColors.sequencerPageBackground 
                  : AppColors.sequencerText,
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