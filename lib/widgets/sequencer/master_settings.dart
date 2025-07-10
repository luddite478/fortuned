import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state/sequencer_state.dart';

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

class MasterSettingsPanel extends StatefulWidget {
  final VoidCallback closeAction;

  const MasterSettingsPanel({
    super.key,
    required this.closeAction,
  });

  @override
  State<MasterSettingsPanel> createState() => _MasterSettingsPanelState();
}

class _MasterSettingsPanelState extends State<MasterSettingsPanel> {
  String _selectedControl = 'BPM'; // 'BPM', 'MASTER', 'COMPRESSOR', etc.

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        return Container(
          decoration: BoxDecoration(
            color: SequencerPhoneBookColors.surfaceBase,
            borderRadius: BorderRadius.circular(2),
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
              BoxShadow(
                color: SequencerPhoneBookColors.surfaceRaised,
                blurRadius: 1,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with 2 rows of buttons
                Row(
                  children: [
                    // BPM button
                    Expanded(
                      child: _buildSettingsButton('BPM', _selectedControl == 'BPM', 32, 10, () {
                        setState(() {
                          _selectedControl = 'BPM';
                        });
                      }),
                    ),
                    
                    const SizedBox(width: 4),
                    
                    // MASTER button
                    Expanded(
                      child: _buildSettingsButton('MASTER', _selectedControl == 'MASTER', 32, 10, () {
                        setState(() {
                          _selectedControl = 'MASTER';
                        });
                      }),
                    ),
                    
                    const SizedBox(width: 4),
                    
                    // COMP button
                    Expanded(
                      child: _buildSettingsButton('COMP', _selectedControl == 'COMP', 32, 10, null),
                    ),
                    
                    const SizedBox(width: 4),
                    
                    // EQ button
                    Expanded(
                      child: _buildSettingsButton('EQ', _selectedControl == 'EQ', 32, 10, null),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // Close button
                    GestureDetector(
                      onTap: widget.closeAction,
                      child: Container(
                        width: 32,
                        height: 32,
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
                        child: const Center(
                          child: Icon(
                            Icons.close,
                            color: SequencerPhoneBookColors.lightText,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 4),
                
                // Second row of buttons
                Row(
                  children: [
                    // RVB button
                    Expanded(
                      flex: 1,
                      child: _buildSettingsButton('RVB', _selectedControl == 'RVB', 32, 10, null),
                    ),
                    
                    const SizedBox(width: 4),
                    
                    // DLY button
                    Expanded(
                      flex: 2,
                      child: _buildSettingsButton('DLY', _selectedControl == 'DLY', 32, 10, null),
                    ),
                    
                    const SizedBox(width: 4),
                    
                    // FILTER button
                    Expanded(
                      flex: 3,
                      child: _buildSettingsButton('FILTER', _selectedControl == 'FILTER', 32, 10, null),
                    ),
                    
                    const SizedBox(width: 4),
                    
                    // DISTORT button
                    Expanded(
                      flex: 3,
                      child: _buildSettingsButton('DISTORT', _selectedControl == 'DISTORT', 32, 10, null),
                    ),
                    
                    // Right spacer to balance close button
                    const SizedBox(width: 40),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Control area - takes remaining space
                Expanded(
                  child: _buildActiveControl(sequencer, 0, 12, 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildActiveControl(SequencerState sequencer, double height, double padding, double fontSize) {
    switch (_selectedControl) {
      case 'BPM':
        return _buildBpmControl(sequencer, height, padding, fontSize);
      case 'MASTER':
        return _buildMasterVolumeControl(sequencer, height, padding, fontSize);
      default:
        return _buildComingSoonMessage(height, fontSize);
    }
  }

  Widget _buildBpmControl(SequencerState sequencer, double height, double padding, double fontSize) {
    final currentBpm = sequencer.bpm;
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding * 0.3, vertical: padding * 0.01),
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
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // BPM info row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left: BPM label
              Expanded(
                flex: 30,
                child: Text(
                  'BPM',
                  style: GoogleFonts.sourceSans3(
                    color: SequencerPhoneBookColors.lightText,
                    fontSize: (fontSize * 0.9).clamp(10.0, 14.0),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              
              // Center: Current BPM value
              Expanded(
                flex: 40,
                child: Text(
                  '$currentBpm',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.sourceSans3(
                    color: SequencerPhoneBookColors.accent,
                    fontSize: (fontSize * 1.4).clamp(14.0, 20.0),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              
              // Right: BPM text
              Expanded(
                flex: 30,
                child: Text(
                  'Beats/Min',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.sourceSans3(
                    color: SequencerPhoneBookColors.lightText,
                    fontSize: (fontSize * 0.8).clamp(8.0, 12.0),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: padding * 0.01),
          
          // BPM slider (60 to 200 BPM)
          Builder(
            builder: (context) => SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: SequencerPhoneBookColors.accent,
                inactiveTrackColor: SequencerPhoneBookColors.border,
                thumbColor: SequencerPhoneBookColors.accent,
                trackHeight: 2.0, // Fixed small track height
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8.0), // Fixed small thumb
              ),
              child: Slider(
                value: currentBpm.toDouble(),
                onChanged: (value) {
                  sequencer.setBpm(value.round());
                },
                min: 60.0,
                max: 200.0,
                divisions: 140, // 1 BPM increments
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterVolumeControl(SequencerState sequencer, double height, double padding, double fontSize) {
    // For now, just a placeholder - could control overall output volume
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding * 0.3, vertical: padding * 0.01),
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
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Master volume info row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left: Master label
              Expanded(
                flex: 30,
                child: Text(
                  'MASTER',
                  style: GoogleFonts.sourceSans3(
                    color: SequencerPhoneBookColors.lightText,
                    fontSize: (fontSize * 0.9).clamp(10.0, 14.0),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              
              // Center: Volume level
              Expanded(
                flex: 40,
                child: Text(
                  '100%',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.sourceSans3(
                    color: SequencerPhoneBookColors.accent,
                    fontSize: (fontSize * 1.4).clamp(14.0, 20.0),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              
              // Right: Volume text
              Expanded(
                flex: 30,
                child: Text(
                  'Volume',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.sourceSans3(
                    color: SequencerPhoneBookColors.lightText,
                    fontSize: (fontSize * 0.8).clamp(8.0, 12.0),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: padding * 0.01),
          
          // Volume slider (0 to 100%)
          Builder(
            builder: (context) => SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: SequencerPhoneBookColors.accent,
                inactiveTrackColor: SequencerPhoneBookColors.border,
                thumbColor: SequencerPhoneBookColors.accent,
                trackHeight: 2.0, // Fixed small track height
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8.0), // Fixed small thumb
              ),
              child: Slider(
                value: 100.0, // Placeholder value
                onChanged: (value) {
                  // TODO: Implement master volume control
                },
                min: 0.0,
                max: 100.0,
                divisions: 100,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildComingSoonMessage(double height, double fontSize) {
    return Container(
      decoration: BoxDecoration(
        color: SequencerPhoneBookColors.surfacePressed,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: SequencerPhoneBookColors.border,
          width: 1,
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.build,
              color: SequencerPhoneBookColors.lightText,
              size: height * 0.3,
            ),
            SizedBox(height: height * 0.1),
            Text(
              'Coming Soon',
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
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: SequencerPhoneBookColors.border,
            width: 0.5,
          ),
          boxShadow: isEnabled
              ? [
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