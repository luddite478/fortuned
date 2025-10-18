import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/app_header_widget.dart';
// Removed performance test integration
// import '../ffi/pitch_bindings.dart';
import '../utils/app_colors.dart';
import 'package:provider/provider.dart';
import '../state/sequencer/table.dart';
class SequencerSettingsScreen extends StatefulWidget {
  const SequencerSettingsScreen({super.key});

  @override
  State<SequencerSettingsScreen> createState() => _SequencerSettingsScreenState();
}

class _SequencerSettingsScreenState extends State<SequencerSettingsScreen> {
  @override
  void initState() {
    super.initState();
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


  Widget _buildResetButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Settings reset to defaults'),
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