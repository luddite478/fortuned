import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/sequencer/v2/sample_banks_widget.dart' as v1;
import '../widgets/sequencer/v2/edit_buttons_widget.dart' as v1;
import '../widgets/sequencer/v2/top_multitask_panel_widget.dart' as v1;
import '../widgets/sequencer/v2/message_bar_widget.dart';
import '../widgets/sequencer/v2/sequencer_body.dart';
import '../widgets/app_header_widget.dart';
import '../state/threads_state.dart';
import '../services/threads_service.dart';
import '../utils/app_colors.dart';
import '../models/thread/thread_user.dart';
// New state imports for migration
import '../state/sequencer/table.dart';
import '../state/sequencer/playback.dart';
import '../state/sequencer/sample_bank.dart';
import '../state/sequencer/sample_browser.dart';
import '../state/sequencer/timer.dart';
import '../state/sequencer/multitask_panel.dart';
import '../state/sequencer/sound_settings.dart';
import '../state/sequencer/recording.dart';
import '../state/sequencer/edit.dart';
import '../state/sequencer/section_settings.dart';
import '../state/sequencer/slider_overlay.dart';
import '../state/sequencer/undo_redo.dart';

class SequencerScreenV2 extends StatefulWidget {
  const SequencerScreenV2({super.key});

  @override
  State<SequencerScreenV2> createState() => _SequencerScreenV2State();
}

class _SequencerScreenV2State extends State<SequencerScreenV2> with WidgetsBindingObserver {
  late ThreadsService _threadsService;
  
  // New state instances for migration
  late final TableState _tableState;
  late final PlaybackState _playbackState;
  late final SampleBankState _sampleBankState;
  late final SampleBrowserState _sampleBrowserState;
  late final TimerState _timerState;
  late final MultitaskPanelState _multitaskPanelState;
  late final SoundSettingsState _soundSettingsState;
  late final RecordingState _recordingState;
  late final EditState _editState;
  late final SectionSettingsState _sectionSettingsState;
  late final SliderOverlayState _sliderOverlayState;
  late final UndoRedoState _undoRedoState;
  
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize new state system
    debugPrint('🎵 [SEQUENCER_V2] Initializing new state system');
    _undoRedoState = UndoRedoState();
    _tableState = TableState();
    _playbackState = PlaybackState(_tableState);
    _sampleBankState = SampleBankState();
    _sampleBrowserState = SampleBrowserState();
    _multitaskPanelState = MultitaskPanelState();
    _soundSettingsState = SoundSettingsState();
    _recordingState = RecordingState();
    _editState = EditState(_tableState);
    _sectionSettingsState = SectionSettingsState();
    _sliderOverlayState = SliderOverlayState();
    
    // Initialize timer with dependencies
    _timerState = TimerState(
      tableState: _tableState,
      playbackState: _playbackState,
      sampleBankState: _sampleBankState,
      undoRedoState: _undoRedoState,
    );
    
    // Use the global ThreadsService from Provider instead of creating a new one
    _threadsService = Provider.of<ThreadsService>(context, listen: false);
    _setupThreadsServiceListeners();
    
    // Start new state system and ensure active thread
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _timerState.start();
      _sampleBrowserState.initialize();
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
    debugPrint('📡 Using global ThreadsService connection in sequencer V2');
  }

  void _ensureActiveThread() async {
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    
    // If there's no active thread, create one (no collaboration logic)
    if (threadsState.activeThread == null) {
      try {
        debugPrint('📝 No active thread found, creating new unpublished thread for sequencer V2');
        
        final currentUserId = threadsState.currentUserId;
        final currentUserName = threadsState.currentUserName;
        
        if (currentUserId != null) {
          // Create an unpublished thread for this new project
          final threadId = await threadsState.createThread(
            users: [
              ThreadUser(id: currentUserId, name: currentUserName ?? 'User', joinedAt: DateTime.now()),
            ],
            metadata: {
              'project_type': 'solo',
              'is_public': false,
              'created_from': 'sequencer_v2',
              'layout_version': 'v2',
            },
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
    debugPrint('🧹 [SEQUENCER_V2] Disposing new state system');
    
    _timerState.dispose();
    _tableState.dispose();
    _playbackState.dispose();
    _sampleBankState.dispose();
    _sampleBrowserState.dispose();
    _multitaskPanelState.dispose();
    _soundSettingsState.dispose();
    _recordingState.dispose();
    _editState.dispose();
    _sectionSettingsState.dispose();
    _undoRedoState.dispose();
    
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

  // Note: navigation to checkpoints is handled in header

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _tableState),
        ChangeNotifierProvider.value(value: _playbackState),
        ChangeNotifierProvider.value(value: _sampleBankState),
        ChangeNotifierProvider.value(value: _sampleBrowserState),
        ChangeNotifierProvider.value(value: _multitaskPanelState),
        ChangeNotifierProvider.value(value: _soundSettingsState),
        ChangeNotifierProvider.value(value: _recordingState),
        ChangeNotifierProvider.value(value: _editState),
        ChangeNotifierProvider.value(value: _sectionSettingsState),
        ChangeNotifierProvider.value(value: _sliderOverlayState),
        ChangeNotifierProvider.value(value: _undoRedoState),
      ],
      child: Scaffold(
        backgroundColor: AppColors.sequencerPageBackground,
        appBar: AppHeaderWidget(
          mode: HeaderMode.sequencer,
          onBack: () => Navigator.of(context).pop(),
          threadsService: _threadsService,
        ),
        body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 7,
              child: RepaintBoundary(
                child: const v1.SampleBanksWidget(),
              ),
            ),
            // 🎯 PERFORMANCE: Body element with switching capability between sound grid and sample browser
            Expanded(
              flex: 50, // Reduced from 60 to make space for message bar
              child: const SequencerBody(),
            ),

            // 🎯 PERFORMANCE: Edit buttons only rebuild when selection or mode changes
            Expanded(
              flex: 8,
              child: RepaintBoundary(
                child: const v1.EditButtonsWidget(),
              ),
            ),

            // 🎯 PERFORMANCE: Sample banks only rebuild when file names or loading state changes


            // 🎯 PERFORMANCE: Multitask panel only rebuilds when panel mode changes
            Expanded(
              flex: 15, // Reduced from 18 to make space for message bar
              child: RepaintBoundary(
                child: const v1.MultitaskPanelWidget(),
              ),
            ),

            // V2 Specific: Message bar at the bottom
            const SizedBox(
              height: 44, // Smaller height for message bar
              child: MessageBarWidget(),
            ),
          ],
        ),
      ),
    ),
    );
  }
} 