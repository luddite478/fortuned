import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../widgets/sequencer/v2/sample_banks_widget.dart' as v2;
import '../widgets/sequencer/v2/edit_buttons_widget.dart' as v2;
import '../widgets/sequencer/v2/top_multitask_panel_widget.dart' as v2;
import '../widgets/sequencer/v2/sequencer_body.dart';
import '../widgets/sequencer/v2/value_control_overlay.dart';
import '../widgets/sections_chain_squares.dart';
import '../state/threads_state.dart';
import '../state/audio_player_state.dart';
import '../state/library_state.dart';
import '../state/user_state.dart';
import '../services/threads_service.dart';
import '../services/snapshot/snapshot_service.dart';
import '../services/audio_cache_service.dart';
import '../services/http_client.dart';
import '../utils/app_colors.dart';
import '../utils/thread_name_generator.dart';
import '../models/thread/thread_user.dart';
import '../models/thread/message.dart';
import '../models/thread/thread.dart';
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
import '../services/thread_draft_service.dart';
import 'sequencer_settings_screen.dart';

enum _SequencerView { sequencer, thread }

class SequencerScreenV2 extends StatefulWidget {
  final Map<String, dynamic>? initialSnapshot;

  const SequencerScreenV2({super.key, this.initialSnapshot});

  @override
  State<SequencerScreenV2> createState() => _SequencerScreenV2State();
}

class _SequencerScreenV2State extends State<SequencerScreenV2> with TickerProviderStateMixin, WidgetsBindingObserver {
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
  late final ThreadDraftService _draftService;
  
  bool _isInitialLoading = false;
  
  // View switching state
  _SequencerView _currentView = _SequencerView.sequencer;
  late PageController _pageController;
  
  // Thread screen state
  final ScrollController _threadScrollController = ScrollController();
  bool _isLoadingOlderMessages = false;
  bool _hasMoreMessages = true;
  String? _optimisticRenderKey;
  static const int _initialMessageCount = 30;
  final GlobalKey<AnimatedListState> _animatedListKey = GlobalKey<AnimatedListState>();
  List<Message> _displayedMessages = [];
  bool _hasPerformedInitialLoad = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize page controller
    _pageController = PageController(initialPage: 0);
    
    // Initialize thread scroll listener
    _threadScrollController.addListener(_onThreadScroll);
    
    // Initialize new state system (reuse Provider-managed states)
    debugPrint('🎵 [SEQUENCER_V2] Initializing new state system');
    _undoRedoState = UndoRedoState();
    _tableState = Provider.of<TableState>(context, listen: false);
    _playbackState = Provider.of<PlaybackState>(context, listen: false);
    _sampleBankState = Provider.of<SampleBankState>(context, listen: false);
    _sampleBrowserState = SampleBrowserState();
    _multitaskPanelState = MultitaskPanelState();
    _soundSettingsState = SoundSettingsState();
    _uiSelectionState = UiSelectionState();
    _recordingState = RecordingState();
    _recordingState.attachPanelState(_multitaskPanelState);
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
    
    // Initialize draft service for thread-specific draft saving
    _draftService = ThreadDraftService(
      tableState: _tableState,
      playbackState: _playbackState,
      sampleBankState: _sampleBankState,
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
    debugPrint('📡 Using global ThreadsService connection in sequencer V2');
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
      debugPrint('✅ Imported initial snapshot into Sequencer V2');
    } catch (e) {
      debugPrint('❌ Failed to import initial snapshot: $e');
    }
  }

  Future<void> _ensureActiveThread() async {
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    
    // If there's no active thread, create one (no collaboration logic)
    if (threadsState.activeThread == null) {
      try {
        debugPrint('📝 No active thread found, creating new unpublished thread for sequencer V2');
        
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
              'created_from': 'sequencer_v2',
              'layout_version': 'v2',
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
      
      // Draft functionality disabled - only manual checkpoints are saved
      // Start tracking draft for active thread
      // final threadsState = Provider.of<ThreadsState>(context, listen: false);
      // final activeThread = threadsState.activeThread;
      // if (activeThread != null) {
      //   _draftService.startTracking(activeThread.id);
      // }
      
      // Load server snapshot first (if provided), then draft if no snapshot
      // Draft is only used when there are no saved messages
      await _importInitialSnapshotIfAny();
      // Draft loading disabled
      // if (widget.initialSnapshot == null) {
      //   await _loadDraftIfAny();
      // }
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
  
  // Draft loading disabled - only manual checkpoints are saved
  // Future<void> _loadDraftIfAny() async {
  //   final threadsState = Provider.of<ThreadsState>(context, listen: false);
  //   final activeThread = threadsState.activeThread;
  //   
  //   if (activeThread == null) return;
  //   
  //   try {
  //     final draft = await _draftService.loadDraft(activeThread.id);
  //     if (draft != null) {
  //       final service = SnapshotService(
  //         tableState: _tableState,
  //         playbackState: _playbackState,
  //         sampleBankState: _sampleBankState,
  //       );
  //       await service.importFromJson(json.encode(draft));
  //       debugPrint('✅ Loaded draft for thread: ${activeThread.id}');
  //     }
  //   } catch (e) {
  //     debugPrint('❌ Failed to load draft: $e');
  //   }
  // }

  void _switchView(_SequencerView newView) {
    if (_currentView == newView) return;
    
    // Stop audio playback when switching FROM thread view (audio is only played in thread view)
    if (_currentView == _SequencerView.thread) {
      try {
        context.read<AudioPlayerState>().stop();
      } catch (_) {}
    }
    
    setState(() {
      _currentView = newView;
    });
    
    final targetPage = newView == _SequencerView.sequencer ? 0 : 1;
    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    
    // Load thread messages when switching to thread view
    if (newView == _SequencerView.thread) {
      // Mark initial load as complete on first switch to thread view
      // This prevents existing messages from animating, but allows new ones to animate
      if (!_hasPerformedInitialLoad) {
        _hasPerformedInitialLoad = true;
      }
      _loadThreadMessages();
    }
  }

  Future<void> _loadThreadMessages() async {
    final threadsState = context.read<ThreadsState>();
    final activeThread = threadsState.activeThread;
    
    if (activeThread == null) return;
    
    threadsState.enterThreadView(activeThread.id);
    
    try {
      await threadsState.ensureThreadSummary(activeThread.id);
    } catch (_) {}
    
    // Load only recent messages if not already loaded
    final alreadyLoaded = threadsState.hasMessagesLoaded(activeThread.id);
    
    if (!alreadyLoaded) {
      await threadsState.loadMessages(
        activeThread.id,
        includeSnapshot: false,
        order: 'desc',
        limit: _initialMessageCount,
      );
    }
    
    final loadedCount = threadsState.activeThreadMessages.length;
    if (mounted) {
      setState(() {
        _hasMoreMessages = loadedCount >= _initialMessageCount;
      });
    }
  }

  void _onThreadScroll() {
    final maxScroll = _threadScrollController.position.maxScrollExtent;
    final currentScroll = _threadScrollController.position.pixels;
    
    if (maxScroll - currentScroll <= 100 && !_isLoadingOlderMessages && _hasMoreMessages) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingOlderMessages || !_hasMoreMessages) return;
    
    setState(() {
      _isLoadingOlderMessages = true;
    });
    
    try {
      final threadsState = context.read<ThreadsState>();
      final currentMessages = threadsState.activeThreadMessages;
      
      if (currentMessages.isEmpty) {
        setState(() {
          _isLoadingOlderMessages = false;
        });
        return;
      }
      
      debugPrint('📜 Would load older messages');
      
      setState(() {
        _hasMoreMessages = false;
        _isLoadingOlderMessages = false;
      });
    } catch (e) {
      debugPrint('❌ Failed to load older messages: $e');
      setState(() {
        _isLoadingOlderMessages = false;
      });
    }
  }

  @override
  void dispose() {
    debugPrint('🧹 [SEQUENCER_V2] Disposing new state system');
    
    try {
      final threadsState = context.read<ThreadsState>();
      threadsState.exitThreadView();
      final audioPlayer = context.read<AudioPlayerState>();
      audioPlayer.stop();
    } catch (_) {}
    
    // Draft saving disabled - only manual checkpoints are saved
    // _draftService.saveDraft();
    _draftService.stopTracking();
    
    _timerState.dispose();
    _sampleBrowserState.dispose();
    _multitaskPanelState.dispose();
    _soundSettingsState.dispose();
    _recordingState.dispose();
    _editState.dispose();
    _sectionSettingsState.dispose();
    _undoRedoState.dispose();
    _pageController.dispose();
    _threadScrollController.dispose();
    
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 App resumed - reconfiguring Bluetooth audio session');
    }
  }

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
        backgroundColor: _currentView == _SequencerView.sequencer 
            ? AppColors.sequencerPageBackground 
            : AppColors.sequencerPageBackground, // Dark gray background for thread view
        appBar: _buildCommonHeader(context),
        body: Stack(
          children: [
            // Main content with page view
            PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), // Disable swipe, only button controls
              children: [
                _buildSequencerView(),
                _buildThreadView(),
              ],
            ),
            
            // Floating playback bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildFloatingPlaybackBar(),
            ),
            
            if (_isInitialLoading)
              Positioned.fill(
                child: Container(
                  color: AppColors.sequencerPageBackground.withOpacity(0.8),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.sequencerAccent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildCommonHeader(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.sequencerSurfaceBase,
      foregroundColor: AppColors.sequencerText,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: AppColors.sequencerText),
        onPressed: () {
            if (_playbackState.isPlaying) {
              _playbackState.stop();
            }
            // Stop audio player (for render playback from thread view)
            try {
              context.read<AudioPlayerState>().stop();
            } catch (_) {}
            // Draft saving disabled - only manual checkpoints are saved
            // _draftService.saveDraft();
            Navigator.of(context).pop();
          },
        iconSize: 20,
      ),
      title: const SizedBox.shrink(),
      actions: [
        // Settings button (always visible)
        IconButton(
          icon: Icon(Icons.settings, color: AppColors.sequencerAccent),
          onPressed: () => _navigateToSettings(context),
          iconSize: 18,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        ),
        const SizedBox(width: 4),
        
        // Invite button (always visible)
        IconButton(
          icon: Icon(Icons.ios_share , color: AppColors.sequencerAccent),
          onPressed: () => _showInviteCollaboratorsModal(context),
          iconSize: 18,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        ),
        const SizedBox(width: 4),
        
        // View toggle buttons (always visible)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: ToggleButtons(
            isSelected: [
              _currentView == _SequencerView.thread,
              _currentView == _SequencerView.sequencer,
            ],
            onPressed: (index) {
              if (index == 0) {
                _switchView(_SequencerView.thread);
              } else {
                _switchView(_SequencerView.sequencer);
              }
            },
            borderRadius: BorderRadius.circular(3),
            constraints: const BoxConstraints(minHeight: 36, minWidth: 55),
            fillColor: AppColors.sequencerPrimaryButton,
            selectedColor: Colors.white,
            color: AppColors.sequencerLightText,
            borderColor: AppColors.sequencerBorder,
            selectedBorderColor: AppColors.sequencerBorder,
            borderWidth: 0.5,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.reorder, size: 18),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.my_library_music_rounded, size: 18),
              ),
            ],
                               ),
          ),
      ],
    );
  }

  Widget _buildSequencerView() {
    return Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    flex: 7,
                    child: RepaintBoundary(
                      child: const v2.SampleBanksWidget(),
                    ),
                  ),
                  Expanded(
                flex: 50,
                    child: const SequencerBody(),
                  ),
                  Expanded(
                    flex: 8,
                    child: RepaintBoundary(
                      child: const v2.EditButtonsWidget(),
                    ),
                  ),
                  Expanded(
                flex: 15,
                    child: RepaintBoundary(
                      child: const v2.MultitaskPanelWidget(),
                    ),
                  ),
              const SizedBox(height: 44), // Space for floating playback bar
                ],
              ),
            ),
        // Value overlay
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final h = constraints.maxHeight;
                  const double playbackControl = 44.0;
              const int flexTotal = 7 + 50 + 8 + 15;
                  final double flexRegion = h - playbackControl;
                  final double topInset = flexRegion * (7.0 / flexTotal);
              final double bottomInset = (flexRegion * (15.0 / flexTotal)) + playbackControl;
                  return Padding(
                    padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
                    child: const ValueControlOverlay(),
                  );
                },
              ),
            ),
      ],
    );
  }

  Widget _buildThreadView() {
    return Container(
      color: AppColors.sequencerSurfaceRaised, // Match sound settings background for floating effect
      child: Consumer<ThreadsState>(
        builder: (context, threadsState, child) {
          final thread = threadsState.activeThread;
          final messages = threadsState.activeThreadMessages;

          if (thread == null) {
            return Center(
              child: Text(
                'No active thread',
                style: GoogleFonts.sourceSans3(
                  color: AppColors.sequencerText,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }

          if (messages.isEmpty && threadsState.isLoadingMessages(thread.id)) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.sequencerAccent),
            );
          }

          // Reset displayed messages when empty
          if (messages.isEmpty && _displayedMessages.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _displayedMessages = [];
                  // Don't reset _hasPerformedInitialLoad - we want new messages to animate
                });
              }
            });
          }

          // Detect new messages and animate them in
          _updateDisplayedMessages(messages);

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final allMessagesToday = _displayedMessages.isEmpty || _displayedMessages.every((msg) {
            final msgDate = DateTime(msg.timestamp.year, msg.timestamp.month, msg.timestamp.day);
            return msgDate == today;
          });

          return Stack(
            children: [
              // Always render AnimatedList, even when empty
              AnimatedList(
            key: _animatedListKey,
            controller: _threadScrollController,
            reverse: true,
            padding: EdgeInsets.only(
              top: 8,
              left: 12,
              right: 12,
              bottom: 52, // Extra space for floating bar
            ),
            initialItemCount: _displayedMessages.length + (_isLoadingOlderMessages ? 1 : 0),
            itemBuilder: (context, index, animation) {
              if (index == _displayedMessages.length) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: AppColors.sequencerAccent),
                  ),
                );
              }

              // In a reversed list, index 0 is at bottom (newest)
              // Our _displayedMessages is in normal order (oldest first), so we need to reverse
              final reversedIndex = _displayedMessages.length - 1 - index;
              final message = _displayedMessages[reversedIndex];
              final isCurrentUser = message.userId == threadsState.currentUserId;

              final bool needsDivider = !allMessagesToday && (
                reversedIndex == 0 ||
                _needsDayDivider(
                  _displayedMessages[reversedIndex - 1].timestamp,
                  message.timestamp,
                )
              );

              Widget bubble = _buildMessageBubble(context, thread, message, isCurrentUser);

              if (needsDivider) {
                bubble = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDayDivider(message.timestamp),
                    const SizedBox(height: 8),
                    bubble,
                  ],
                );
              }

              // Animate new messages sliding up from bottom
              // Only animate for messages at the bottom (index close to 0)
              return _buildMessageAnimation(bubble, animation, isNewMessage: index == 0);
            },
          ),
              // Show "No checkpoints yet" overlay when empty
              if (_displayedMessages.isEmpty)
                Positioned.fill(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'No checkpoints yet',
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.sequencerText,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMessageAnimation(Widget child, Animation<double> animation, {bool isNewMessage = false}) {
    // Only apply slide animation to new messages at the bottom
    if (!isNewMessage) {
      return child;
    }
    
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      )),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeIn,
        ),
        child: child,
      ),
    );
  }

  void _updateDisplayedMessages(List<Message> newMessages) {
    // Detect new messages that need to be animated
    if (_displayedMessages.isEmpty && newMessages.isNotEmpty && !_hasPerformedInitialLoad) {
      // Initial load when first opening thread view - no animation
      _displayedMessages = List.from(newMessages);
      _hasPerformedInitialLoad = true;
    } else if (_displayedMessages.length < newMessages.length) {
      // New messages added - animate them
      final animatedList = _animatedListKey.currentState;
      
      if (animatedList != null && _currentView == _SequencerView.thread) {
        // Get the new messages that were added (they're at the end of newMessages list)
        final List<Message> newlyAdded = newMessages.sublist(_displayedMessages.length);
        
        // Add new messages one by one with animation
        // Since list is reversed, new messages (at end of data) appear at bottom (index 0)
        for (int i = 0; i < newlyAdded.length; i++) {
          final message = newlyAdded[i];
          _displayedMessages.add(message); // Add to end of data list
          
          // In reversed AnimatedList, index 0 is the visual bottom (where new messages appear)
          // The itemBuilder will use reversedIndex to get the last item from _displayedMessages
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              // Insert at index 0 which is the visual bottom in a reversed list
              animatedList.insertItem(0, duration: const Duration(milliseconds: 350));
            }
          });
        }
      } else {
        // AnimatedList not ready yet or not in thread view, just update the list
        _displayedMessages = List.from(newMessages);
      }
    } else if (_displayedMessages.length > newMessages.length) {
      // Messages removed (e.g., deleted) - need to properly remove from AnimatedList
      final animatedList = _animatedListKey.currentState;
      
      if (animatedList != null && _currentView == _SequencerView.thread) {
        // Get thread info before removal
        final threadsState = Provider.of<ThreadsState>(context, listen: false);
        final thread = threadsState.activeThread;
        final currentUserId = threadsState.currentUserId;
        
        if (thread != null) {
          // Find which message(s) were removed
          final removedIndices = <int>[];
          for (int i = 0; i < _displayedMessages.length; i++) {
            final msg = _displayedMessages[i];
            if (!newMessages.any((m) => m.id == msg.id)) {
              removedIndices.add(i);
            }
          }
          
          // Remove items from AnimatedList (in reverse order to maintain indices)
          for (int i = removedIndices.length - 1; i >= 0; i--) {
            final removedIndex = removedIndices[i];
            final removedMessage = _displayedMessages[removedIndex];
            final isCurrentUser = removedMessage.userId == currentUserId;
            
            // Remove from AnimatedList with animation
            animatedList.removeItem(
              removedIndex,
              (context, animation) => SizeTransition(
                sizeFactor: animation,
                child: FadeTransition(
                  opacity: animation,
                  child: _buildMessageBubble(
                    context,
                    thread,
                    removedMessage,
                    isCurrentUser,
                  ),
                ),
              ),
              duration: const Duration(milliseconds: 250),
            );
          }
        }
        
        // Update our displayed messages list
        _displayedMessages = List.from(newMessages);
      } else {
        // AnimatedList not ready or not in thread view, just update the list
        _displayedMessages = List.from(newMessages);
      }
    } else {
      // Check if messages are different (e.g., updated renders, changed content)
      bool isDifferent = false;
      for (int i = 0; i < newMessages.length; i++) {
        final oldMsg = _displayedMessages[i];
        final newMsg = newMessages[i];
        
        // Check if message ID changed
        if (oldMsg.id != newMsg.id) {
          isDifferent = true;
          break;
        }
        
        // Check if renders changed (count or content)
        if (oldMsg.renders.length != newMsg.renders.length) {
          isDifferent = true;
          break;
        }
        
        // Check if any render uploadStatus changed
        for (int j = 0; j < oldMsg.renders.length; j++) {
          if (oldMsg.renders[j].uploadStatus != newMsg.renders[j].uploadStatus ||
              oldMsg.renders[j].id != newMsg.renders[j].id ||
              oldMsg.renders[j].url != newMsg.renders[j].url) {
            isDifferent = true;
            break;
          }
        }
        if (isDifferent) break;
      }
      
      if (isDifferent) {
        _displayedMessages = List.from(newMessages);
      }
    }
  }

  Widget _buildFloatingPlaybackBar() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        border: Border(
          top: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Consumer4<TableState, PlaybackState, RecordingState, MultitaskPanelState>(
          builder: (context, tableState, playbackState, recordingState, multitaskPanelState, child) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final barHeight = constraints.maxHeight;
                final double innerVerticalMargin = 6;
                final double innerHorizontalMargin = 8;
                final double innerHeight = (barHeight - innerVerticalMargin * 2).clamp(0, double.infinity);

                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: innerHorizontalMargin,
                    vertical: innerVerticalMargin,
                  ),
                  child: Container(
                    height: innerHeight,
                    decoration: BoxDecoration(
                      color: AppColors.sequencerSurfaceRaised,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
                    ),
                    child: LayoutBuilder(
                      builder: (context, rowConstraints) {
                        final totalWidth = rowConstraints.maxWidth;
                        const gap = 8.0;
                        final double chainFraction = _currentView == _SequencerView.thread ? 0.8 : 0.4;
                        final double buttonsFraction = 1 - chainFraction;
                        final double chainWidth = (totalWidth - gap) * chainFraction;
                        final double buttonsWidth = (totalWidth - gap) * buttonsFraction;
                        return Row(
                          children: [
                            // Left side: Section chain (animated width)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              width: chainWidth,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Center(
                                  child: SizedBox(
                                    height: innerHeight - 8,
                                    child: ValueListenableBuilder<bool>(
                                      valueListenable: recordingState.isRecordingNotifier,
                                      builder: (context, isRecording, _) {
                                        return Stack(
                                          children: [
                                            Container(
                                              decoration: BoxDecoration(
                                                color: isRecording ? AppColors.sequencerShadow : AppColors.sequencerSurfaceBase,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
                                              ),
                                              clipBehavior: Clip.hardEdge,
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: Center(
                                                child: _buildSectionChain(
                                                  tableState.sectionsCount,
                                                  playbackState,
                                                  allActive: _currentView == _SequencerView.thread,
                                                ),
                                              ),
                                            ),
                                            if (isRecording)
                                              Positioned.fill(
                                                child: Center(
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.transparent,
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(color: AppColors.sequencerLightText, width: 1),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        _RecordingIndicatorDot(color: AppColors.sequencerLightText),
                                                        const SizedBox(width: 4),
                                                        ValueListenableBuilder<Duration>(
                                                          valueListenable: recordingState.recordingDurationNotifier,
                                                          builder: (context, duration, __) {
                                                            final minutes = duration.inMinutes;
                                                            final seconds = duration.inSeconds % 60;
                                                            final text = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
                                                            return Text(
                                                              text,
                                                              style: TextStyle(
                                                                color: AppColors.sequencerLightText,
                                                                fontSize: 11,
                                                                fontWeight: FontWeight.w600,
                                                                fontFamily: 'monospace',
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: gap),
                            // Right side: Buttons or Save (animated width)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              width: buttonsWidth,
                              child: SizedBox(
                                height: innerHeight - 8,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.sequencerSurfaceBase,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  clipBehavior: Clip.hardEdge,
                                  child: _currentView == _SequencerView.sequencer
                                      ? ValueListenableBuilder<bool>(
                                          valueListenable: recordingState.isRecordingNotifier,
                                          builder: (context, isRecording, _) {
                                            return ValueListenableBuilder<bool>(
                                              valueListenable: playbackState.isPlayingNotifier,
                                              builder: (context, isPlaying, __) {
                                                return LayoutBuilder(
                                                  builder: (context, box) {
                                                    final double perButtonWidth = box.maxWidth / 3;
                                                    final double perButtonHeight = box.maxHeight;
                                                    return ToggleButtons(
                                                      isSelected: [
                                                        false, // Never show background selection for master button
                                                        isRecording,
                                                        isPlaying,
                                                      ],
                                                      onPressed: (index) async {
                                                        if (index == 0) {
                                                          // Master settings button - toggle
                                                          debugPrint('🎛️ Master settings button pressed');
                                                          if (multitaskPanelState.currentMode == MultitaskPanelMode.masterSettings) {
                                                            multitaskPanelState.showPlaceholder();
                                                          } else {
                                                            multitaskPanelState.showMasterSettings();
                                                          }
                                                        } else if (index == 1) {
                                                          if (isRecording) {
                                                            await recordingState.stopRecording();
                                                          } else {
                                                            await recordingState.startRecording();
                                                          }
                                                        } else if (index == 2) {
                                                          if (isPlaying) {
                                                            playbackState.stop();
                                                          } else {
                                                            playbackState.start();
                                                          }
                                                        }
                                                      },
                                                      borderRadius: BorderRadius.circular(4),
                                                      constraints: BoxConstraints.tightFor(width: perButtonWidth, height: perButtonHeight),
                                                      fillColor: AppColors.sequencerPrimaryButton,
                                                      selectedColor: Colors.white,
                                                      color: AppColors.sequencerLightText,
                                                      renderBorder: false,
                                                      splashColor: Colors.transparent,
                                                      highlightColor: Colors.transparent,
                                                      children: [
                                                        Transform.rotate(
                                                          angle: 1.5708, // 90 degrees in radians (π/2)
                                                          child: Icon(
                                                            Icons.tune, 
                                                            size: 18,
                                                            color: multitaskPanelState.currentMode == MultitaskPanelMode.masterSettings
                                                                ? Colors.white // Brighter when active
                                                                : AppColors.sequencerLightText, // Normal color
                                                          ),
                                                        ),
                                                        const Icon(Icons.fiber_manual_record, size: 18),
                                                        Icon(isPlaying ? Icons.stop : Icons.play_arrow, size: 18),
                                                      ],
                                                    );
                                                  },
                                                );
                                              },
                                            );
                                          },
                                        )
                                      : _buildSaveButton(),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionChain(int numSections, PlaybackState playbackState, {bool allActive = false}) {
    return ValueListenableBuilder<int>(
      valueListenable: playbackState.currentSectionNotifier,
      builder: (context, currentSection, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            const double squareWidth = 15.0;
            const double horizontalMargin = 4.0;
            const double totalSquareWidth = squareWidth + horizontalMargin;
            
            final double availableWidth = constraints.maxWidth;
            final int rawVisible = (availableWidth / totalSquareWidth).floor();
            final int visibleCount = rawVisible > 0 ? rawVisible : 1;
            final int centerIndexWithinView = visibleCount ~/ 2;
            
            final int startIndex = currentSection - centerIndexWithinView;
            
            return ClipRect(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(visibleCount, (visibleIndex) {
                  final actualIndex = startIndex + visibleIndex;
                  if (actualIndex < 0 || actualIndex >= numSections) {
                    // Placeholder to keep current section centered
                    return Container(
                      width: squareWidth,
                      height: 15,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }
                  final bool isCurrentSection = allActive || actualIndex == currentSection;
                  return Container(
                    width: squareWidth,
                    height: 15,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isCurrentSection
                          ? AppColors.sequencerLightText // match buttons icon color
                          : const Color.fromARGB(255, 114, 114, 110), // match inactive section settings button bg
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              ),
            );
          },
        );
      },
    );
  }

  

  Widget _buildSaveButton() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final vPad = (h * 0.18).clamp(6.0, 14.0);
        final borderRadius = 4.0;
        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 0),
          child: SizedBox.expand(
            child: ElevatedButton(
              onPressed: () => _saveCheckpoint(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.sequencerAccent,
                foregroundColor: AppColors.sequencerText,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: vPad),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
              ),
              child: Icon(
                Icons.add,
                size: h * 0.7,
                color: AppColors.sequencerText,
                weight: 900,
              ),
            ),
          ),
        );
      },
    );
  }

  void _saveCheckpoint(BuildContext context) {
    if (_playbackState.isPlaying) {
      _playbackState.stop();
    }

    final threadsState = context.read<ThreadsState>();
    final activeThread = threadsState.activeThread;
    
    if (activeThread != null) {
      threadsState.sendMessageFromSequencer(threadId: activeThread.id).then((_) {
        // Clear draft when message is successfully saved
        _draftService.clearDraft(activeThread.id);
        // Success: no popup per request
      }).catchError((e) {
        debugPrint('Error sending message: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save checkpoint'),
            backgroundColor: AppColors.sequencerAccent,
            duration: const Duration(seconds: 2),
          ),
          );
        }
      });
    }
  }

  void _navigateToSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SequencerSettingsScreen(),
      ),
    );
  }

  // Thread message building methods
  Widget _buildMessageBubble(
    BuildContext context,
    Thread thread,
    Message message,
    bool isCurrentUser,
  ) {
    final userName = thread.users.firstWhere(
      (u) => u.id == message.userId,
      orElse: () => ThreadUser(
        id: message.userId,
        name: 'User ${message.userId.substring(0, 6)}',
        joinedAt: DateTime.now(),
      ),
    ).name;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showMessageContextMenu(context, message, details.globalPosition),
      onLongPressStart: (details) => _showMessageContextMenu(context, message, details.globalPosition),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceBase, // Dark gray background for message tiles
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    userName,
                    style: GoogleFonts.sourceSans3(
                      color: AppColors.sequencerText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  if (message.sendStatus == SendStatus.failed && isCurrentUser) ...[
                    Icon(Icons.error, color: AppColors.sequencerAccent, size: 16),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    _formatTimestamp(message.timestamp),
                    style: GoogleFonts.sourceSans3(
                      color: AppColors.sequencerLightText,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMessagePreviewFromMetadata(message),
                  const SizedBox(height: 8),
                  if (message.renders.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final render in message.renders)
                          _buildRenderButton(context, message, render),
                        const SizedBox(height: 4),
                      ],
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (message.renders.isNotEmpty) ...[
                        OutlinedButton.icon(
                          onPressed: () => _addToPlaylist(context, message.renders.first),
                          icon: const Icon(Icons.playlist_add, size: 16),
                          label: const Text('Add to playlist'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.sequencerText,
                            side: BorderSide(color: AppColors.sequencerBorder),
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                            minimumSize: const Size(0, 28),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      OutlinedButton(
                        onPressed: () => _applyMessage(context, message),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.sequencerText,
                          side: BorderSide(color: AppColors.sequencerBorder),
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                          minimumSize: const Size(0, 28),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text('Load'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagePreviewFromMetadata(Message message) {
    final meta = message.snapshotMetadata ?? const {};
    final sectionsCount = (meta['sections_count'] as num?)?.toInt() ?? 0;
    final stepsPerSectionMeta = (meta['sections_steps'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const <int>[];
    final loopsMeta = (meta['sections_loops_num'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const <int>[];
    final layersMeta = (meta['layers'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const <int>[];

    final loopsTrimmed = loopsMeta.length >= sectionsCount
        ? loopsMeta.take(sectionsCount).toList()
        : List<int>.from(loopsMeta)..addAll(List<int>.filled(sectionsCount - loopsMeta.length, loopsMeta.isNotEmpty ? loopsMeta.last : 4));

    final int defaultLayersPerSection = (layersMeta.isNotEmpty ? layersMeta.first : 4);
    final layersTrimmed = layersMeta.length >= sectionsCount
        ? layersMeta.take(sectionsCount).toList()
        : List<int>.from(layersMeta)..addAll(List<int>.filled(sectionsCount - layersMeta.length, defaultLayersPerSection));

    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised, // Dark gray background for preview
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SectionsChainSquares(
          loopsPerSection: loopsTrimmed,
          layersPerSection: layersTrimmed,
          stepsPerSection: () {
            if (stepsPerSectionMeta.isEmpty) return null;
            if (stepsPerSectionMeta.length >= sectionsCount) {
              return stepsPerSectionMeta.take(sectionsCount).toList();
            }
            final list = List<int>.from(stepsPerSectionMeta);
            list.addAll(List<int>.filled(sectionsCount - stepsPerSectionMeta.length, stepsPerSectionMeta.last));
            return list;
          }(),
        ),
      ),
    );
  }

  Widget _buildRenderButton(BuildContext context, Message message, Render render) {
    final isUploading = render.uploadStatus == RenderUploadStatus.uploading;
    final isFailed = render.uploadStatus == RenderUploadStatus.failed;
    
    return Consumer<AudioPlayerState>(
      builder: (context, audioPlayer, _) {
        final isPlaying = audioPlayer.isPlayingRender(message.id, render.id);
        final isLoadingFromNetwork = audioPlayer.isLoadingRender(message.id, render.id);
        final isThisRender = audioPlayer.currentlyPlayingMessageId == message.id && 
                             audioPlayer.currentlyPlayingRenderId == render.id;
        
        return FutureBuilder<bool>(
          future: (isUploading || isFailed) ? Future.value(false) : AudioCacheService.isCached(render.url),
          builder: (context, snapshot) {
            final renderKey = '${message.id}::${render.id}';
            final bool isOptimistic = _optimisticRenderKey == renderKey;
            
            if (isOptimistic) {
              final shouldClear = (isThisRender && isPlaying) || (!isThisRender && !isLoadingFromNetwork);
              if (shouldClear) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() { _optimisticRenderKey = null; });
                  }
                });
              }
            }
            
            final bool showLoading = isUploading || (isLoadingFromNetwork && !isThisRender && !isOptimistic);

            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isFailed ? AppColors.sequencerAccent.withOpacity(0.1) : AppColors.sequencerSurfaceRaised, // Dark gray for render buttons
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isFailed ? AppColors.sequencerAccent : AppColors.sequencerBorder,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: (isUploading || isFailed) ? null : () async {
                      final player = context.read<AudioPlayerState>();
                      if (isThisRender && isPlaying) {
                        setState(() { _optimisticRenderKey = null; });
                        await player.playRender(
                          messageId: message.id,
                          render: render,
                        );
                      } else {
                        setState(() { _optimisticRenderKey = renderKey; });
                        await player.playRender(
                          messageId: message.id,
                          render: render,
                        );
                      }
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isFailed
                            ? AppColors.sequencerAccent
                            : showLoading
                                ? AppColors.sequencerBorder.withOpacity(0.5)
                                : AppColors.sequencerText.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: isFailed
                          ? Icon(Icons.error, color: AppColors.sequencerText, size: 16)
                          : showLoading
                              ? Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.sequencerLightText,
                                    value: isLoadingFromNetwork && audioPlayer.downloadProgress > 0 
                                        ? audioPlayer.downloadProgress 
                                        : null,
                                  ),
                                )
                              : Icon(
                                  (isPlaying || (isOptimistic && isThisRender)) ? Icons.pause : Icons.play_arrow,
                                  color: AppColors.sequencerPageBackground,
                                  size: 16,
                                ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: isFailed
                        ? Text(
                            'Upload failed - file too large or network error',
                            style: GoogleFonts.sourceSans3(
                              color: AppColors.sequencerAccent,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        : isUploading
                            ? Row(
                                children: [
                                  Text(
                                    'Uploading...',
                                    style: GoogleFonts.sourceSans3(
                                      color: AppColors.sequencerLightText,
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    height: 2,
                                    decoration: BoxDecoration(
                                      color: AppColors.sequencerBorder.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  ),
                                ],
                              )
                            : isThisRender
                                ? SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 2,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                      activeTrackColor: AppColors.sequencerText.withOpacity(0.6),
                                      inactiveTrackColor: AppColors.sequencerBorder.withOpacity(0.3),
                                      thumbColor: AppColors.sequencerText,
                                      overlayColor: AppColors.sequencerText.withOpacity(0.1),
                                    ),
                                    child: Slider(
                                      value: audioPlayer.duration.inMilliseconds > 0
                                          ? audioPlayer.position.inMilliseconds.toDouble()
                                          : 0.0,
                                      min: 0.0,
                                      max: audioPlayer.duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
                                      onChanged: (value) async {
                                        final player = context.read<AudioPlayerState>();
                                        await player.seek(Duration(milliseconds: value.toInt()));
                                      },
                                    ),
                                  )
                                : Container(
                                    height: 2,
                                    decoration: BoxDecoration(
                                      color: AppColors.sequencerBorder.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    
    if (messageDate == today) {
      return timeStr;
    } else if (messageDate == yesterday) {
      return 'Yesterday at $timeStr';
    } else {
      return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}/${timestamp.year}, $timeStr';
    }
  }

  bool _needsDayDivider(DateTime previous, DateTime current) {
    final prevDate = DateTime(previous.year, previous.month, previous.day);
    final currDate = DateTime(current.year, current.month, current.day);
    return prevDate != currDate;
  }

  Widget _buildDayDivider(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    String dateLabel;
    if (messageDate == today) {
      dateLabel = 'Today';
    } else if (messageDate == yesterday) {
      dateLabel = 'Yesterday';
    } else {
      final months = ['January', 'February', 'March', 'April', 'May', 'June', 
                     'July', 'August', 'September', 'October', 'November', 'December'];
      dateLabel = '${timestamp.day} ${months[timestamp.month - 1]} ${timestamp.year}';
    }
    
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.sequencerBorder.withOpacity(0.5),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            dateLabel,
            style: GoogleFonts.sourceSans3(
              color: AppColors.sequencerLightText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.sequencerBorder.withOpacity(0.5),
          ),
        ),
      ],
    );
  }

  void _showMessageContextMenu(BuildContext context, Message message, Offset globalPos) async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
      ],
    );
    if (selected == 'delete') {
      final threadsState = context.read<ThreadsState>();
      final ok = await threadsState.deleteMessage(message.parentThread ?? '', message.id);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to delete message'),
            backgroundColor: AppColors.sequencerAccent,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _addToPlaylist(BuildContext context, Render render) async {
    final userState = context.read<UserState>();
    final userId = userState.currentUser?.id;
    
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please log in to add to playlist'),
          backgroundColor: AppColors.menuErrorColor,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    
    final libraryState = context.read<LibraryState>();
    final success = await libraryState.addToPlaylist(
      userId: userId,
      render: render,
    );
    
    if (!mounted) return;
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Added to playlist'),
          backgroundColor: AppColors.menuOnlineIndicator,
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to add to playlist'),
          backgroundColor: AppColors.menuErrorColor,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _applyMessage(BuildContext context, Message message) async {
    final threadsState = context.read<ThreadsState>();
    final thread = threadsState.activeThread;
    
    if (thread == null) {
      debugPrint('❌ [SEQUENCER] Cannot apply message - no active thread');
      return;
    }
    
    // Use unified loader (handles initialization, caching, and import)
    // Pass the message's snapshot as override to avoid refetching
    final ok = await threadsState.loadProjectIntoSequencer(
      thread.id,
      snapshotOverride: message.snapshot.isNotEmpty ? message.snapshot : null,
    );
    
    if (!mounted) return;
    if (ok) {
      // Switch back to sequencer view after loading
      _switchView(_SequencerView.sequencer);
    } else {
      debugPrint('❌ [SEQUENCER] Failed to load checkpoint');
    }
  }

  void _showInviteCollaboratorsModal(BuildContext context) {
    final thread = context.read<ThreadsState>().activeThread;
    if (thread == null) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.sequencerPageBackground.withOpacity(0.8),
      builder: (context) => _InviteLinkDialog(threadId: thread.id),
    );
  }
}

class _InviteLinkDialog extends StatelessWidget {
  final String threadId;

  const _InviteLinkDialog({required this.threadId});

  @override
  Widget build(BuildContext context) {
    final inviteLink = '${ApiHttpClient.publicBaseUrl}/join/$threadId';

    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.8).clamp(280.0, size.width);
    final dialogHeight = (size.height * 0.42).clamp(240.0, size.height);

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints.tightFor(width: dialogWidth, height: dialogHeight),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.sequencerSurfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
            ),
            clipBehavior: Clip.hardEdge,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Share',
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.sequencerText,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close, color: AppColors.sequencerLightText, size: 28),
                          splashRadius: 22,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Anyone with this link can join',
                      textAlign: TextAlign.left,
                      style: GoogleFonts.sourceSans3(
                        color: AppColors.sequencerLightText,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.sequencerSurfaceBase,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
                      ),
                      child: SelectableText(
                        inviteLink,
                        textAlign: TextAlign.left,
                        style: GoogleFonts.sourceCodePro(
                          color: AppColors.sequencerText,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Copy Link'),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: inviteLink));
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.sequencerText,
                              side: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              minimumSize: const Size(0, 44),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Helper widget for pulsing recording indicator
class _RecordingIndicatorDot extends StatefulWidget {
  final Color? color;
  const _RecordingIndicatorDot({this.color});
  @override
  _RecordingIndicatorDotState createState() => _RecordingIndicatorDotState();
}

class _RecordingIndicatorDotState extends State<_RecordingIndicatorDot>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    // Start repeating animation
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: (widget.color ?? AppColors.sequencerAccent).withOpacity(_animation.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

