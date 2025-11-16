import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../widgets/sequencer/v1/sample_banks_widget.dart' as v1;
import '../widgets/sequencer/v1/edit_buttons_widget.dart' as v1;
import '../widgets/sequencer/v1/top_multitask_panel_widget.dart' as v1;
import '../widgets/sequencer/v1/message_bar_widget.dart';
import '../widgets/sequencer/v1/sequencer_body.dart';
import '../widgets/sequencer/v1/value_control_overlay.dart';
import '../widgets/app_header_widget.dart';
import '../state/threads_state.dart';
import '../services/threads_service.dart';
import '../services/snapshot/snapshot_service.dart';
import '../utils/app_colors.dart';
import '../utils/thread_name_generator.dart';
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
import '../state/sequencer/ui_selection.dart';

class SequencerScreenV1 extends StatefulWidget {
  final Map<String, dynamic>? initialSnapshot;

  const SequencerScreenV1({super.key, this.initialSnapshot});

  @override
  State<SequencerScreenV1> createState() => _SequencerScreenV1State();
}

class _SequencerScreenV1State extends State<SequencerScreenV1> with WidgetsBindingObserver {
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
  late final UiSelectionState _uiSelectionState;
  late final SectionSettingsState _sectionSettingsState;
  late final SliderOverlayState _sliderOverlayState;
  late final UndoRedoState _undoRedoState;
  
  bool _isInitialLoading = false;
  
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize new state system (reuse Provider-managed states)
    debugPrint('🎵 [SEQUENCER_V1] Initializing new state system');
    _undoRedoState = UndoRedoState();
    _tableState = Provider.of<TableState>(context, listen: false);
    _playbackState = Provider.of<PlaybackState>(context, listen: false);
    _sampleBankState = Provider.of<SampleBankState>(context, listen: false);
    _sampleBrowserState = SampleBrowserState();
    _multitaskPanelState = MultitaskPanelState();
    _soundSettingsState = SoundSettingsState();
    _uiSelectionState = UiSelectionState();
    _recordingState = RecordingState();
    _recordingState.setOnRecordingComplete(() => _onRecordingComplete());
    _editState = EditState(_tableState, _uiSelectionState);
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
    
    // Attach RecordingState to ThreadsState for audio upload functionality
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    threadsState.attachRecordingState(_recordingState);
    
    // Start new state system and ensure active thread
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapInitialLoad();
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

  Future<void> _importInitialSnapshotIfAny() async {
    final snapshot = widget.initialSnapshot;
    if (snapshot == null) return;
    try {
      final service = SnapshotService(
        tableState: _tableState,
        playbackState: _playbackState,
        sampleBankState: _sampleBankState,
      );
      await service.importFromJson(json.encode(snapshot));
      debugPrint('✅ Imported initial snapshot into Sequencer V1');
    } catch (e) {
      debugPrint('❌ Failed to import initial snapshot: $e');
    }
  }

  Future<void> _ensureActiveThread() async {
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    
    // If there's no active thread, create one (no collaboration logic)
    if (threadsState.activeThread == null) {
      try {
        debugPrint('📝 No active thread found, creating new unpublished thread for sequencer V1');
        
        final currentUserId = threadsState.currentUserId;
        final currentUserName = threadsState.currentUserName;
        
        if (currentUserId != null) {
          // Create an unpublished thread for this new project
          // Generate name using timestamp as seed for uniqueness
          final threadName = ThreadNameGenerator.generate(DateTime.now().microsecondsSinceEpoch.toString());
          final threadId = await threadsState.createThread(
            users: [
              ThreadUser(id: currentUserId, name: currentUserName ?? 'User', joinedAt: DateTime.now()),
            ],
            name: threadName,
            metadata: {
              'project_type': 'solo',
              'is_public': false,
              'created_from': 'sequencer_v1',
              'layout_version': 'v1',
            },
          );
          
          debugPrint('✅ Created new unpublished thread: $threadId with name: $threadName');
        } else {
          debugPrint('❌ Cannot create thread: No current user ID');
        }
      } catch (e) {
        debugPrint('❌ Failed to create initial thread: $e');
        // Not critical - user can still work and publish later
      }
    }
    
    // Preload recent messages in background for instant thread screen navigation
    final activeThread = threadsState.activeThread;
    if (activeThread != null) {
      // Preload only recent 30 messages (not all) for faster loading and instant thread UI
      threadsState.preloadRecentMessages(activeThread.id, limit: 30).catchError((e) {
        debugPrint('⚠️ Background message preload failed (non-critical): $e');
      });
    }
  }

  Future<void> _bootstrapInitialLoad() async {
    if (mounted) {
      setState(() {
        _isInitialLoading = true;
      });
    }
    try {
      _timerState.start();
      _sampleBrowserState.initialize();
      await _ensureActiveThread();
      await _importInitialSnapshotIfAny();
    } catch (e) {
      debugPrint('❌ Initial sequencer bootstrap failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    }
  }

  void _onRecordingComplete() {
    debugPrint('🎵 [SEQUENCER_V1] Recording complete, auto-saving as message...');
    final threadsState = context.read<ThreadsState>();
    final activeThread = threadsState.activeThread;
    
    if (activeThread != null) {
      threadsState.sendMessageFromSequencer(threadId: activeThread.id).then((_) {
        debugPrint('✅ [SEQUENCER_V1] Recording auto-saved successfully');
      }).catchError((e) {
        debugPrint('❌ [SEQUENCER_V1] Failed to auto-save recording: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to save recording'),
              backgroundColor: AppColors.sequencerAccent,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    debugPrint('🧹 [SEQUENCER_V1] Disposing new state system');
    
    _timerState.dispose();
    // Do not dispose Provider-managed states here
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
        ChangeNotifierProvider.value(value: _uiSelectionState),
      ],
      child: Scaffold(
        backgroundColor: AppColors.sequencerPageBackground,
        appBar: AppHeaderWidget(
          mode: HeaderMode.sequencer,
          onBack: () {
            if (_playbackState.isPlaying) {
              _playbackState.stop();
            }
            Navigator.of(context).pop();
          },
          threadsService: _threadsService,
        ),
        body: Stack(
          children: [
            SafeArea(
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
                  // 🎯 PERFORMANCE: Multitask panel only rebuilds when panel mode changes
                  Expanded(
                    flex: 15, // Reduced from 18 to make space for message bar
                    child: RepaintBoundary(
                      child: const v1.MultitaskPanelWidget(),
                    ),
                  ),

                  // V1 Specific: Message bar at the bottom
                  const SizedBox(
                    height: 44, // Smaller height for message bar
                    child: MessageBarWidget(),
                  ),
                ],
              ),
            ),
            // Value overlay covers SequencerBody (flex 50) + EditButtons (flex 8), excludes SampleBanks, Multitask, and MessageBar
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final h = constraints.maxHeight;
                  const double messageBar = 44.0;
                  // Column flex breakdown: 7 (SampleBanks), 50 (Body), 8 (EditButtons), 15 (Multitask), then 44 px (MessageBar)
                  const int flexTotal = 7 + 50 + 8 + 15; // = 80
                  final double flexRegion = h - messageBar;
                  final double topInset = flexRegion * (7.0 / flexTotal);
                  final double bottomInset = (flexRegion * (15.0 / flexTotal)) + messageBar; // multitask + message bar
                  return Padding(
                    padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
                    child: const ValueControlOverlay(),
                  );
                },
              ),
            ),
            if (_isInitialLoading)
              Positioned.fill(
                child: Container
                (
                  color: AppColors.sequencerPageBackground.withOpacity(0.8),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.menuPrimaryButton),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
