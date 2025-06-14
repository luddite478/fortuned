import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/tracker/future_panel_widget.dart';
import '../widgets/tracker/sample_banks_widget.dart';
import '../widgets/tracker/sound_grid_widget.dart';
import '../widgets/tracker/edit_buttons_widget.dart';
import '../state/patterns_state.dart';
import '../state/tracker_state.dart';
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
              patternsState.currentPattern?.name ?? 'NIYYA TRACKER',
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
                  // Clear current pattern to return to pattern selection
                  context.read<PatternsState>().clearCurrentPattern();
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
              Consumer<TrackerState>(
                builder: (context, tracker, child) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tracker.isRecording) ...[
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
                                tracker.formattedRecordingDuration,
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
                          onPressed: () => tracker.stopRecording(),
                          tooltip: 'Stop Recording',
                        ),
                      ] else ...[
                        // Start recording button
                        IconButton(
                          icon: const Icon(Icons.fiber_manual_record, color: Colors.red),
                          onPressed: () => tracker.startRecording(),
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
                  context.read<TrackerState>().startSequencer();
                },
                tooltip: 'Start Sequencer',
              ),
              IconButton(
                icon: const Icon(Icons.stop_circle, color: Colors.redAccent),
                onPressed: () {
                  context.read<TrackerState>().stopSequencer();
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
                  // Blank panel for future use (25% of available space)
                  Expanded(
                    flex: 25,
                    child: FuturePanelWidget(),
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
    final trackerState = context.read<TrackerState>();
    
    try {
      final shareData = await trackerState.generateShareData(patternsState.currentPattern);
      
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