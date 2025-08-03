import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/sequencer/v1/top_multitask_panel_widget.dart' as v1;
import '../widgets/sequencer/v1/sample_banks_widget.dart' as v1;
import '../widgets/sequencer/v1/sound_grid_widget.dart' as v1;
import '../widgets/sequencer/v1/edit_buttons_widget.dart' as v1;
import '../widgets/app_header_widget.dart';
import '../state/sequencer_state.dart';
import '../state/threads_state.dart';
import '../services/threads_service.dart';
import 'checkpoints_screen.dart';
import '../utils/app_colors.dart';

class SequencerScreenV1 extends StatefulWidget {
  const SequencerScreenV1({super.key});

  @override
  State<SequencerScreenV1> createState() => _SequencerScreenV1State();
}

class _SequencerScreenV1State extends State<SequencerScreenV1> with WidgetsBindingObserver {
  late ThreadsService _threadsService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Use the global ThreadsService from Provider instead of creating a new one
    _threadsService = Provider.of<ThreadsService>(context, listen: false);
    _setupThreadsServiceListeners();
    
    // Ensure there's an active thread for saving work
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureActiveThread();
    });
  }

  void _setupThreadsServiceListeners() async {
    // Setup connection status listener
    _threadsService.connectionStream.listen((connected) {
      debugPrint('📡 ThreadsService connection status changed: $connected');
      if (connected) {
        debugPrint('📡 ✅ WebSocket connected and ready for notifications');
      } else {
        debugPrint('📡 ❌ WebSocket disconnected');
      }
    });
    
    // Setup error listener
    _threadsService.errorStream.listen((error) {
      debugPrint('📡 ❌ ThreadsService error: $error');
    });
    
    // No need to connect here - it's already connected globally
    debugPrint('📡 Using global ThreadsService connection in sequencer V1');
  }

  void _ensureActiveThread() async {
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    final sequencerState = Provider.of<SequencerState>(context, listen: false);
    
    // If there's no active thread and we're not in collaboration mode, create one
    if (threadsState.activeThread == null && !sequencerState.isCollaborating) {
      try {
        debugPrint('📝 No active thread found, creating new unpublished thread for sequencer V1');
        
        final currentUserId = threadsState.currentUserId;
        final currentUserName = threadsState.currentUserName;
        
        if (currentUserId != null) {
          // Create an unpublished thread for this new project
          final threadId = await threadsState.createThread(
            title: 'Untitled ${DateTime.now().toString().substring(5, 16)}', // e.g. "Untitled Project 12-25 14:30"
            authorId: currentUserId,
            authorName: currentUserName ?? 'User',
            metadata: {
              'project_type': 'solo',
              'is_public': false, // Unpublished initially
              'created_from': 'sequencer_v1',
              'layout_version': 'v1',
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
      backgroundColor: AppColors.sequencerPageBackground,
      appBar: AppHeaderWidget(
        mode: HeaderMode.sequencer,
        onBack: () => Navigator.of(context).pop(),
        threadsService: _threadsService,
      ),
      body: SafeArea(
        child: Column(
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
                    return const v1.SampleGridWidget();
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
                    return const v1.EditButtonsWidget();
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
                    return const v1.SampleBanksWidget();
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
                    return const v1.MultitaskPanelWidget();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 