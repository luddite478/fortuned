import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../widgets/app_header_widget.dart';
import '../state/sequencer_state.dart';
import '../state/threads_state.dart';
import '../sequencer_library.dart';
import 'checkpoints_screen.dart';

class SequencerSettingsScreen extends StatefulWidget {
  const SequencerSettingsScreen({super.key});

  @override
  State<SequencerSettingsScreen> createState() => _SequencerSettingsScreenState();
}

class _SequencerSettingsScreenState extends State<SequencerSettingsScreen> {
  int _currentPerfTestMode = 0;
  bool _showAdvancedSettings = false;

  @override
  void initState() {
    super.initState();
  }

  void _updatePerfTestMode(int mode) {
    setState(() {
      _currentPerfTestMode = mode;
    });
    
    try {
      // Use the existing SequencerLibrary instance
      SequencerLibrary.instance.setPerformanceTestMode(mode);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_getPerfTestModeDescription(mode)),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error setting performance test mode: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _getPerfTestModeDescription(int mode) {
    switch (mode) {
      case 0: return '🧪 Normal mode (all operations enabled)';
      case 1: return '🧪 Skip SoundTouch processing';
      case 2: return '🧪 Skip cell monitoring';
      case 3: return '🧪 Skip volume smoothing';
      case 4: return '🧪 Silence all nodes (test mixing overhead)';
      case 5: return '🧪 Skip mixing entirely';
      default: return '🧪 Unknown test mode';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SequencerPhoneBookColors.pageBackground,
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
              
              // Debug Settings Section
              _buildSectionHeader('Debug Settings'),
              const SizedBox(height: 16),
              
              // Performance Test Mode
              _buildPerformanceTestSection(),
              
              const SizedBox(height: 16),
              
              // Advanced Settings Toggle
              _buildSettingItem(
                'Advanced Settings',
                _showAdvancedSettings ? 'Hide' : 'Show',
                Icons.settings_applications,
                () {
                  setState(() {
                    _showAdvancedSettings = !_showAdvancedSettings;
                  });
                },
              ),
              
              // Advanced Settings (conditionally shown)
              if (_showAdvancedSettings) ...[
                const SizedBox(height: 16),
                _buildAdvancedSettings(),
              ],
              
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
        color: SequencerPhoneBookColors.text,
      ),
    );
  }

  Widget _buildSettingItem(String title, String subtitle, IconData icon, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: SequencerPhoneBookColors.surfaceBase,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: SequencerPhoneBookColors.border,
          width: 1,
        ),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: SequencerPhoneBookColors.accent,
          size: 20,
        ),
        title: Text(
          title,
          style: GoogleFonts.sourceSans3(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: SequencerPhoneBookColors.text,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.sourceSans3(
            fontSize: 12,
            color: SequencerPhoneBookColors.lightText,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: SequencerPhoneBookColors.lightText,
          size: 16,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildPerformanceTestSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SequencerPhoneBookColors.surfaceBase,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: SequencerPhoneBookColors.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.science,
                color: SequencerPhoneBookColors.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Performance Test Mode',
                style: GoogleFonts.sourceSans3(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SequencerPhoneBookColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          Text(
            'Use these modes to isolate audio performance bottlenecks:',
            style: GoogleFonts.sourceSans3(
              fontSize: 12,
              color: SequencerPhoneBookColors.lightText,
            ),
          ),
          const SizedBox(height: 12),
          
          // Performance test mode options
          ..._buildPerfTestModeOptions(),
        ],
      ),
    );
  }

  List<Widget> _buildPerfTestModeOptions() {
    final options = [
      (0, 'Normal', 'All operations enabled'),
      (1, 'Skip SoundTouch', 'Test without pitch processing'),
      (2, 'Skip Monitoring', 'Test without cell monitoring'),
      (3, 'Skip Smoothing', 'Test without volume smoothing'),
      (4, 'Silent Nodes', 'Test mixing overhead only'),
      (5, 'Skip Mixing', 'Test callback overhead only'),
    ];

    return options.map((option) {
      final (mode, title, description) = option;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: RadioListTile<int>(
          value: mode,
          groupValue: _currentPerfTestMode,
          onChanged: (value) {
            if (value != null) {
              _updatePerfTestMode(value);
            }
          },
          title: Text(
            title,
            style: GoogleFonts.sourceSans3(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SequencerPhoneBookColors.text,
            ),
          ),
          subtitle: Text(
            description,
            style: GoogleFonts.sourceSans3(
              fontSize: 11,
              color: SequencerPhoneBookColors.lightText,
            ),
          ),
          activeColor: SequencerPhoneBookColors.accent,
          dense: true,
        ),
      );
    }).toList();
  }

  Widget _buildAdvancedSettings() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SequencerPhoneBookColors.surfaceBase,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: SequencerPhoneBookColors.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Advanced Debug Options',
            style: GoogleFonts.sourceSans3(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SequencerPhoneBookColors.text,
            ),
          ),
          const SizedBox(height: 12),
          
          _buildAdvancedOption('Enable Systrace', 'Requires Android 6+', false),
          _buildAdvancedOption('Detailed Logging', 'Verbose performance logs', false),
          _buildAdvancedOption('Memory Profiling', 'Track memory usage', false),
        ],
      ),
    );
  }

  Widget _buildAdvancedOption(String title, String description, bool value) {
    return SwitchListTile(
      title: Text(
        title,
        style: GoogleFonts.sourceSans3(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: SequencerPhoneBookColors.text,
        ),
      ),
      subtitle: Text(
        description,
        style: GoogleFonts.sourceSans3(
          fontSize: 11,
          color: SequencerPhoneBookColors.lightText,
        ),
      ),
      value: value,
      onChanged: (newValue) {
        // TODO: Implement advanced options
        _showNotImplementedDialog(title);
      },
      activeColor: SequencerPhoneBookColors.accent,
      dense: true,
    );
  }

  Widget _buildResetButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          _updatePerfTestMode(0); // Reset to normal mode
          setState(() {
            _showAdvancedSettings = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Settings reset to defaults'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: SequencerPhoneBookColors.surfaceRaised,
          foregroundColor: SequencerPhoneBookColors.text,
          side: BorderSide(
            color: SequencerPhoneBookColors.border,
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

  void _showNotImplementedDialog(String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SequencerPhoneBookColors.surfaceBase,
        title: Text(
          'Coming Soon',
          style: GoogleFonts.sourceSans3(
            color: SequencerPhoneBookColors.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          '$feature is not implemented yet.',
          style: GoogleFonts.sourceSans3(
            color: SequencerPhoneBookColors.lightText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'OK',
              style: GoogleFonts.sourceSans3(
                color: SequencerPhoneBookColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
} 