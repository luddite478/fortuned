import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/tracker/future_panel_widget.dart';
import '../widgets/tracker/sample_banks_widget.dart';
import '../widgets/tracker/sound_grid_widget.dart';
import '../widgets/tracker/edit_buttons_widget.dart';
import '../state/patterns_state.dart';
import '../state/tracker_state.dart';
import 'pattern_selection_screen.dart';
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
} 