import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/sequencer/top_multitask_panel_widget.dart';
import '../widgets/sequencer/sample_banks_widget.dart';
import '../widgets/sequencer/sound_grid_widget.dart';
import '../widgets/sequencer/edit_buttons_widget.dart';
import '../state/sequencer_state.dart';
import 'users_screen.dart';

class PatternScreen extends StatefulWidget {
  const PatternScreen({super.key});

  @override
  State<PatternScreen> createState() => _PatternScreenState();
}

class _PatternScreenState extends State<PatternScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Re-configure Bluetooth audio session when app becomes active
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 App resumed - reconfiguring Bluetooth audio session');
      // This will be handled by the AudioService later
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: const Text(
          'NIYYA SEQUENCER',
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.orangeAccent),
            onPressed: () {
              // Navigate back to pattern selection screen
              Navigator.of(context).pop();
            },
            tooltip: 'Back to Patterns',
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.purpleAccent),
            onPressed: () => _sharePattern(context),
            tooltip: 'Share Pattern',
          ),
          IconButton(
            icon: const Icon(Icons.people, color: Colors.cyanAccent),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const UsersScreen(),
                ),
              );
            },
            tooltip: 'Users',
          ),
          // Recording controls
          Consumer<SequencerState>(
            builder: (context, sequencer, child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (sequencer.isRecording) ...[
                    // Recording indicator and duration
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            sequencer.formattedRecordingDuration,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Stop recording button
                    IconButton(
                      icon: const Icon(Icons.stop, color: Colors.red),
                      onPressed: () => sequencer.stopRecording(),
                      tooltip: 'Stop Recording',
                    ),
                  ] else ...[
                    // Start recording button
                    IconButton(
                      icon: const Icon(Icons.fiber_manual_record, color: Colors.red),
                      onPressed: () => sequencer.startRecording(),
                      tooltip: 'Start Recording',
                    ),
                  ],
                ],
              );
            },
          ),
          // Sequencer controls
          IconButton(
            icon: const Icon(Icons.play_circle, color: Colors.greenAccent),
            onPressed: () {
              // 🚀 Using sample-accurate sequencer for perfect timing
              context.read<SequencerState>().startSequencer();
            },
            tooltip: 'Start Sequencer',
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle, color: Colors.redAccent),
            onPressed: () {
              // 🚀 Using sample-accurate sequencer
              context.read<SequencerState>().stopSequencer();
            },
            tooltip: 'Stop Sequencer',
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = constraints.maxHeight;
            final screenWidth = constraints.maxWidth;
            
            return Container(
              constraints: BoxConstraints(maxWidth: screenWidth > 400 ? 400 : screenWidth),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Top spacing from SafeArea
                  SizedBox(height: screenHeight * 0.01), // 1% top margin
                  
                  // Multitask panel (15% of screen height)
                  SizedBox(
                    height: screenHeight * 0.2,
                    child: const MultitaskPanelWidget(),
                  ),
                  
                  // Spacing between top panel and sample banks
                  SizedBox(height: screenHeight * 0.005), // 0.5% spacing
                  
                  // Sample banks panel (8% of screen height, fixed to prevent size changes)
                  SizedBox(
                    height: screenHeight * 0.08,
                    child: const SampleBanksWidget(),
                  ),
                  
                  // Spacing between sample banks and grid
                  SizedBox(height: screenHeight * 0.005), // 0.5% spacing
                  
                  // Sample grid (61% of screen height, adjusted for new spacing)
                  SizedBox(
                    height: screenHeight * 0.55,
                    child: const SampleGridWidget(),
                  ),
                  
                  // Spacing between grid and edit buttons
                  SizedBox(height: screenHeight * 0.005), // 0.5% spacing
                  
                  // Edit buttons panel (9% of screen height)
                  SizedBox(
                    height: screenHeight * 0.09,
                    child: const EditButtonsWidget(),
                  ),
                  
                  // Bottom spacing
                  SizedBox(height: screenHeight * 0.005), // 0.5% bottom margin
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _sharePattern(BuildContext context) async {
    final sequencerState = context.read<SequencerState>();
    
    try {
      final shareData = await sequencerState.generateShareData(null);
      
      await Share.share(
        shareData['text'] as String,
        subject: shareData['subject'] as String,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share pattern: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
} 