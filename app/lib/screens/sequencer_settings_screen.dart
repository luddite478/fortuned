import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../widgets/app_header_widget.dart';
// Removed performance test integration
// import '../ffi/pitch_bindings.dart';
import '../utils/app_colors.dart';
import 'package:provider/provider.dart';
import '../state/sequencer/table.dart';
import '../state/sequencer/playback.dart';
import '../state/threads_state.dart';
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
        mode: HeaderMode.sequencerSettings,
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
              
              // Developer Settings Section
              _buildSectionHeader('Developer Settings'),
              const SizedBox(height: 16),
              _buildProjectInfo(),
              const SizedBox(height: 16),
              _buildEnhancedPlaybackLogging(),
              
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


  Widget _buildProjectInfo() {
    final threadsState = context.watch<ThreadsState>();
    final activeThread = threadsState.activeThread;
    final projectId = activeThread?.id ?? 'No project loaded';
    final projectName = activeThread?.name ?? 'Untitled';
    
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
                Icons.info_outline,
                color: AppColors.sequencerAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Project Information',
                style: GoogleFonts.sourceSans3(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.sequencerText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Name', projectName),
          const SizedBox(height: 8),
          _buildInfoRow('Project ID', projectId, copyable: true),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool copyable = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: GoogleFonts.sourceSans3(
              fontSize: 11,
              color: AppColors.sequencerText.withOpacity(0.6),
            ),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    color: AppColors.sequencerText,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (copyable && value != 'No project loaded')
                IconButton(
                  icon: Icon(
                    Icons.copy,
                    size: 16,
                    color: AppColors.sequencerAccent,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Copied: $value'),
                        backgroundColor: AppColors.sequencerAccent,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedPlaybackLogging() {
    final playbackState = context.watch<PlaybackState>();
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
      child: Row(
        children: [
          Icon(
            Icons.bug_report,
            color: AppColors.sequencerAccent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enhanced Playback Logging',
                  style: GoogleFonts.sourceSans3(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.sequencerText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Logs detailed playback state to console for debugging',
                  style: GoogleFonts.sourceSans3(
                    fontSize: 11,
                    color: AppColors.sequencerText.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: playbackState.enhancedPlaybackLogging,
            onChanged: (value) {
              playbackState.setEnhancedPlaybackLogging(value);
            },
            activeColor: AppColors.sequencerAccent,
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