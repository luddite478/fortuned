import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/app_header_widget.dart';
// Removed performance test integration
import '../ffi/pitch_bindings.dart';
import '../utils/app_colors.dart';
import 'package:provider/provider.dart';
import '../state/sequencer/table.dart';
class SequencerSettingsScreen extends StatefulWidget {
  const SequencerSettingsScreen({super.key});

  @override
  State<SequencerSettingsScreen> createState() => _SequencerSettingsScreenState();
}

class _SequencerSettingsScreenState extends State<SequencerSettingsScreen> {
  final _pitchFFI = PitchBindings();
  int _pitchQuality = 2; // 0..4 (best..worst) — default to Middle

  @override
  void initState() {
    super.initState();
    try {
      final q = _pitchFFI.pitchGetQuality();
      if (q >= 0 && q <= 4) {
        _pitchQuality = q;
      } else {
        _pitchQuality = 2;
        try { _pitchFFI.pitchSetQuality(2); } catch (_) {}
      }
    } catch (_) {
      try { _pitchFFI.pitchSetQuality(_pitchQuality); } catch (_) {}
    }
  }

  // Removed performance test utilities



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.sequencerPageBackground,
      appBar: AppHeaderWidget(
        mode: HeaderMode.sequencer,
        title: 'Sequencer Settings',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // General Settings Section
              const SizedBox(height: 24),
              
              // Layout Settings Section
              _buildSectionHeader('Layout Settings'),
              const SizedBox(height: 16),
              _buildLayoutSelection(),
              
              const SizedBox(height: 24),

              // Edit Buttons Layout Section
              _buildSectionHeader('Edit Buttons Layout'),
              const SizedBox(height: 16),
              _buildEditButtonsLayoutSelection(),
              
              const SizedBox(height: 24),
              
              // Pitch Quality
              _buildSectionHeader('Pitch Quality'),
              const SizedBox(height: 16),
              _buildPitchQualitySection(),
              
              const SizedBox(height: 16),
              
              const SizedBox(height: 32),
              
              // Reset to Defaults Button
              _buildResetButton(),
              
              // Bottom padding for scrolling
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.sourceSans3(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.sequencerText,
      ),
    );
  }

  // Setting item helper removed (unused)

  Widget _buildLayoutSelection() {
    final tableState = context.watch<TableState>();
    final current = tableState.uiSoundGridViewMode;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceBase,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.view_column,
                color: AppColors.sequencerAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Table view',
                style: GoogleFonts.sourceSans3(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.sequencerText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RadioListTile<SoundGridViewMode>(
            value: SoundGridViewMode.stack,
            groupValue: current,
            onChanged: (v) {
              if (v == null) return;
              context.read<TableState>().setUiSoundGridViewMode(v);
            },
            activeColor: AppColors.sequencerAccent,
            dense: true,
            title: Text(
              'Stack',
              style: GoogleFonts.sourceSans3(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.sequencerText,
              ),
            ),
          ),
          RadioListTile<SoundGridViewMode>(
            value: SoundGridViewMode.flat,
            groupValue: current,
            onChanged: (v) {
              if (v == null) return;
              context.read<TableState>().setUiSoundGridViewMode(v);
            },
            activeColor: AppColors.sequencerAccent,
            dense: true,
            title: Text(
              'Flat',
              style: GoogleFonts.sourceSans3(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.sequencerText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditButtonsLayoutSelection() {
    final tableState = context.watch<TableState>();
    final current = tableState.uiEditButtonsLayoutMode;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceBase,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune,
                color: AppColors.sequencerAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Buttons layout',
                style: GoogleFonts.sourceSans3(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.sequencerText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RadioListTile<EditButtonsLayoutMode>(
            value: EditButtonsLayoutMode.v1,
            groupValue: current,
            onChanged: (v) {
              if (v == null) return;
              context.read<TableState>().setUiEditButtonsLayoutMode(v);
            },
            activeColor: AppColors.sequencerAccent,
            dense: true,
            title: Text(
              'V1 (classic icons, centered)',
              style: GoogleFonts.sourceSans3(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.sequencerText,
              ),
            ),
          ),
          RadioListTile<EditButtonsLayoutMode>(
            value: EditButtonsLayoutMode.v2,
            groupValue: current,
            onChanged: (v) {
              if (v == null) return;
              context.read<TableState>().setUiEditButtonsLayoutMode(v);
            },
            activeColor: AppColors.sequencerAccent,
            dense: true,
            title: Text(
              'V2 (text, bigger, right-aligned)',
              style: GoogleFonts.sourceSans3(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.sequencerText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPitchQualitySection() {
    final options = [
      (0, 'Best'),
      (1, 'High'),
      (2, 'Medium'),
      (3, 'Low'),
      (4, 'Lowest'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceBase,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: options.map((opt) {
          final (value, title) = opt;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: RadioListTile<int>(
              value: value,
              groupValue: _pitchQuality,
              onChanged: (v) {
                if (v == null) return;
                setState(() { _pitchQuality = v; });
                try {
                  _pitchFFI.pitchSetQuality(v);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Pitch quality set to $title'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                } catch (e) {
                  debugPrint('❌ Failed to set pitch quality: $e');
                }
              },
              title: Text(
                title,
                style: GoogleFonts.sourceSans3(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.sequencerText,
                ),
              ),
              activeColor: AppColors.sequencerAccent,
              dense: true,
            ),
          );
        }).toList(),
      ),
    );
  }

  // Removed advanced/debug settings section entirely

  Widget _buildResetButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          setState(() { _pitchQuality = 2; });
          try { _pitchFFI.pitchSetQuality(2); } catch (_) {}
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Settings reset to defaults (Pitch: Medium)'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.sequencerSurfaceRaised,
          foregroundColor: AppColors.sequencerText,
          side: BorderSide(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          'Reset to Defaults',
          style: GoogleFonts.sourceSans3(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // Removed not-implemented dialog helper (unused)
} 