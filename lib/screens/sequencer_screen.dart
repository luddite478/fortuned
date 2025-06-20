import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/sequencer/top_multitask_panel_widget.dart';
import '../widgets/sequencer/sample_banks_widget.dart';
import '../widgets/sequencer/sound_grid_widget.dart';
import '../widgets/sequencer/edit_buttons_widget.dart';
import '../state/patterns_state.dart';
import '../state/sequencer_state.dart';
import 'contacts_screen.dart';

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
    return Consumer<PatternsState>(
      builder: (context, patternsState, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: const Color(0xFF111827),
            elevation: 0,
            title: Text(
              patternsState.currentPattern?.name ?? 'NIYYA SEQUENCER',
              style: const TextStyle(
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
                      builder: (context) => const ContactsScreen(),
                    ),
                  );
                },
                tooltip: 'Contacts',
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
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: const Column(
                children: [
                  // Multitask panel (25% of available space)
                  Expanded(
                    flex: 25,
                    child: MultitaskPanelWidget(),
                  ),
                  // Sample banks panel
                  SampleBanksWidget(),
                  // Sample grid (starts around 50% and takes remaining space)
                  Expanded(
                    flex: 50,
                    child: SampleGridWidget(),
                  ),
                  // Edit buttons panel (smaller, fixed size)
                  EditButtonsWidget(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _sharePattern(BuildContext context) async {
    final patternsState = context.read<PatternsState>();
    final sequencerState = context.read<SequencerState>();
    
    try {
      final shareData = await sequencerState.generateShareData(patternsState.currentPattern);
      
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