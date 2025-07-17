import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/sequencer/top_multitask_panel_widget.dart';
import '../widgets/sequencer/sample_banks_widget.dart';
import '../widgets/sequencer/sound_grid_widget.dart';
import '../widgets/sequencer/edit_buttons_widget.dart';
import '../widgets/app_header_widget.dart';
import '../state/sequencer_state.dart';
import '../state/threads_state.dart';
import '../services/chat_client.dart';

import 'checkpoints_screen.dart';

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

class PatternScreen extends StatefulWidget {
  const PatternScreen({super.key});

  @override
  State<PatternScreen> createState() => _PatternScreenState();
}

class _PatternScreenState extends State<PatternScreen> with WidgetsBindingObserver {
  late ChatClient _chatClient;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Use the global ChatClient from Provider instead of creating a new one
    _chatClient = Provider.of<ChatClient>(context, listen: false);
    _setupChatClientListeners();
    
    // Ensure there's an active thread for saving work
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureActiveThread();
    });
  }

  void _setupChatClientListeners() async {
    // Setup connection status listener
    _chatClient.connectionStream.listen((connected) {
      debugPrint('📡 ChatClient connection status changed: $connected');
      if (connected) {
        debugPrint('📡 ✅ WebSocket connected and ready for notifications');
      } else {
        debugPrint('📡 ❌ WebSocket disconnected');
      }
    });
    
    // Setup error listener
    _chatClient.errorStream.listen((error) {
      debugPrint('📡 ❌ ChatClient error: $error');
    });
    
    // No need to connect here - it's already connected globally
    debugPrint('📡 Using global ChatClient connection in sequencer');
  }

  void _ensureActiveThread() async {
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    final sequencerState = Provider.of<SequencerState>(context, listen: false);
    
    // If there's no active thread and we're not in collaboration mode, create one
    if (threadsState.activeThread == null && !sequencerState.isCollaborating) {
      try {
        debugPrint('📝 No active thread found, creating new unpublished thread for sequencer');
        
        final currentUserId = threadsState.currentUserId;
        final currentUserName = threadsState.currentUserName;
        
        if (currentUserId != null) {
          // Create an unpublished thread for this new project
          final threadId = await threadsState.createThread(
            title: 'Untitled Project ${DateTime.now().toString().substring(5, 16)}', // e.g. "Untitled Project 12-25 14:30"
            authorId: currentUserId,
            authorName: currentUserName ?? 'User',
            metadata: {
              'project_type': 'solo',
              'is_public': false, // Unpublished initially
              'created_from': 'sequencer',
            },
            createInitialCheckpoint: false, // Don't create checkpoint until user makes changes
          );
          
          debugPrint('✅ Created new unpublished thread: $threadId');
        } else {
          debugPrint('❌ Cannot create thread: No current user ID');
        }
      } catch (e) {
        debugPrint('❌ Failed to create initial thread: $e');
        // Not critical - user can still work and publish later
      }
    }
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

  void _navigateToCheckpoints() {
    final threadsState = context.read<ThreadsState>();
    final currentThread = threadsState.currentThread;
    
    if (currentThread != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckpointsScreen(
            threadId: currentThread.id,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SequencerPhoneBookColors.pageBackground,
      appBar: AppHeaderWidget(
        mode: HeaderMode.sequencer,
        onBack: () => Navigator.of(context).pop(),
        chatClient: _chatClient,
      ),
      body: const SafeArea(
        child: SequencerBody(),
      ),
    );
  }
}

// 🎯 PERFORMANCE: Sequencer body with selective rebuilding
class SequencerBody extends StatelessWidget {
  const SequencerBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 🎯 PERFORMANCE: Sample grid with cell-level step highlighting
        Expanded(
          flex: 60,
          child: RepaintBoundary(
            child: Selector<SequencerState, ({List<int?> currentGridSamples, Set<int> selectedCells})>(
              selector: (context, state) => (
                currentGridSamples: state.currentGridSamplesForSelector,
                selectedCells: state.selectedGridCellsForSelector,
                // Note: currentStep tracking moved to individual cells via ValueListenableBuilder
              ),
              builder: (context, data, child) {
                return const SampleGridWidget();
              },
            ),
          ),
        ),

        // 🎯 PERFORMANCE: Edit buttons only rebuild when selection or mode changes
        Expanded(
          flex: 8,
          child: RepaintBoundary(
            child: Selector<SequencerState, ({Set<int> selectedCells, bool isStepInsertMode, bool canUndo, bool canRedo})>(
              selector: (context, state) => (
                selectedCells: state.selectedGridCellsForSelector,
                isStepInsertMode: state.isStepInsertMode,
                canUndo: state.canUndo,
                canRedo: state.canRedo,
              ),
              builder: (context, data, child) {
                return const EditButtonsWidget();
              },
            ),
          ),
        ),

        // 🎯 PERFORMANCE: Sample banks only rebuild when file names or loading state changes
        Expanded(
          flex: 7,
          child: RepaintBoundary(
            child: Selector<SequencerState, ({List<String?> fileNames, List<bool> slotLoaded, int activeBank})>(
              selector: (context, state) => (
                fileNames: state.fileNamesForSelector,
                slotLoaded: state.slotLoadedForSelector, 
                activeBank: state.activeBank,
              ),
              builder: (context, data, child) {
                return const SampleBanksWidget();
              },
            ),
          ),
        ),

        // 🎯 PERFORMANCE: Multitask panel only rebuilds when panel mode changes
        Expanded(
          flex: 18,
          child: RepaintBoundary(
            child: Selector<SequencerState, MultitaskPanelMode>(
              selector: (context, state) => state.currentPanelModeForSelector,
                          builder: (context, panelMode, child) {
              return const MultitaskPanelWidget();
            },
            ),
          ),
        ),
      ],
    );
  }
} 