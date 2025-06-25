import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/threads_state.dart';
import '../state/sequencer_state.dart';
import '../widgets/sequencer_widget.dart';
import '../widgets/checkpoint_message_widget.dart';
import '../widgets/app_header_widget.dart';
import '../widgets/sequencer/top_multitask_panel_widget.dart';
import '../widgets/sequencer/sample_banks_widget.dart';
import '../widgets/sequencer/sound_grid_widget.dart';
import '../widgets/sequencer/edit_buttons_widget.dart';

class ThreadScreen extends StatefulWidget {
  final String threadId;
  
  const ThreadScreen({
    super.key,
    required this.threadId,
  });

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _slideAnimationController;
  late AnimationController _headerAnimationController;
  
  late Animation<Offset> _slideAnimation;
  
  String? _expandedCheckpointId;
  bool _isCurrentSequencerExpanded = false;
  bool _isInSequencerMode = false;

  @override
  void initState() {
    super.initState();
    
    // Slide animation controller for sequencer
    _slideAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    // Header animation controller (faster transition)
    _headerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    
    // Simple slide animation from right to left
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0), // Start from right (off-screen)
      end: Offset.zero, // End at normal position
    ).animate(CurvedAnimation(
      parent: _slideAnimationController,
      curve: Curves.easeOutCubic,
    ));
    
    // Auto-scroll to bottom when new checkpoints are added
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _slideAnimationController.dispose();
    _headerAnimationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _expandCheckpoint(String checkpointId) {
    setState(() {
      if (_expandedCheckpointId == checkpointId && _isInSequencerMode) {
        // Collapse if already expanded
        _expandedCheckpointId = null;
        _isCurrentSequencerExpanded = false;
        _isInSequencerMode = false;
      } else {
        // Expand new checkpoint
        _expandedCheckpointId = checkpointId;
        _isCurrentSequencerExpanded = false;
        _isInSequencerMode = true;
        
        // Apply the checkpoint to sequencer state
        final threadsState = context.read<ThreadsState>();
        final sequencerState = context.read<SequencerState>();
        final thread = threadsState.currentThread;
        
        if (thread != null) {
          final checkpoint = thread.checkpoints.firstWhere(
            (cp) => cp.id == checkpointId,
            orElse: () => thread.checkpoints.last,
          );
          
          // Apply snapshot to sequencer
          sequencerState.applySnapshot(checkpoint.snapshot);
        }
      }
    });
    
    if (_isInSequencerMode) {
      // Change header and slide in sequencer
      _headerAnimationController.forward();
      _slideAnimationController.forward();
    } else {
      // Slide out sequencer and change header back
      _slideAnimationController.reverse();
      _headerAnimationController.reverse();
    }
  }

  void _expandCurrentSequencer() {
    setState(() {
      if (_isCurrentSequencerExpanded && _isInSequencerMode) {
        _isCurrentSequencerExpanded = false;
        _isInSequencerMode = false;
      } else {
        _expandedCheckpointId = null; // Collapse any checkpoint
        _isCurrentSequencerExpanded = true;
        _isInSequencerMode = true;
      }
    });
    
    if (_isInSequencerMode) {
      _headerAnimationController.forward();
      _slideAnimationController.forward();
    } else {
      _slideAnimationController.reverse();
      _headerAnimationController.reverse();
    }
  }

  void _exitSequencerMode() {
    setState(() {
      _expandedCheckpointId = null;
      _isCurrentSequencerExpanded = false;
      _isInSequencerMode = false;
    });
    
    _slideAnimationController.reverse();
    _headerAnimationController.reverse();
  }

  Future<void> _saveCheckpoint() async {
    final threadsState = context.read<ThreadsState>();
    final sequencerState = context.read<SequencerState>();
    
    try {
      // Show dialog to get checkpoint comment
      final comment = await _showCheckpointDialog();
      if (comment == null) return;
      
      await threadsState.addCheckpointFromSequencer(
        widget.threadId,
        comment,
        sequencerState,
      );
      
      // Exit sequencer mode and scroll to show new checkpoint
      _exitSequencerMode();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Checkpoint saved!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving checkpoint: $e')),
        );
      }
    }
  }

  Future<String?> _showCheckpointDialog() async {
    final TextEditingController controller = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Checkpoint'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Describe your changes...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showProjectInfo() {
    // Implementation for project info dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Project Info'),
        content: const Text('Project information dialog'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeaderWidget(
        mode: _isInSequencerMode ? HeaderMode.sequencer : HeaderMode.thread,
        onBack: _isInSequencerMode ? _exitSequencerMode : null,
        onSave: _isInSequencerMode ? _saveCheckpoint : null,
        onInfo: _showProjectInfo,
        showProjectInfo: !_isInSequencerMode,
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: Consumer2<ThreadsState, SequencerState>(
        builder: (context, threadsState, sequencerState, child) {
          final thread = threadsState.currentThread;
          
          if (thread == null) {
            return const Center(
              child: Text(
                'Thread not found',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return Stack(
            children: [
              // Main checkpoint chat view
              _buildCheckpointChatView(thread, threadsState, sequencerState),
              
              // Sliding sequencer overlay
              SlideTransition(
                position: _slideAnimation,
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.black,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final screenHeight = constraints.maxHeight;
                      
                      // Use same calculations as sequencer_screen.dart
                      const double footerPadding = 7.0;
                      const double multitaskPanelPercent = 20.0;
                      const double sampleBanksPercent = 8.0;
                      const double sampleGridPercent = 63.0;
                      const double editButtonsPercent = 9.0;
                      
                      final totalContentPercent = multitaskPanelPercent + sampleBanksPercent + 
                                                sampleGridPercent + editButtonsPercent;
                      final remainingPercent = 100.0 - totalContentPercent;
                      final singleSpacingPercent = remainingPercent / 5;
                      
                      final availableHeight = screenHeight - footerPadding;
                      final multitaskPanelHeight = availableHeight * (multitaskPanelPercent / 100);
                      final sampleBanksHeight = availableHeight * (sampleBanksPercent / 100);
                      final sampleGridHeight = availableHeight * (sampleGridPercent / 100);
                      final editButtonsHeight = availableHeight * (editButtonsPercent / 100);
                      final spacingHeight = availableHeight * (singleSpacingPercent / 100);
                      
                      return Column(
                        children: [
                          SizedBox(height: spacingHeight),
                          SizedBox(
                            height: multitaskPanelHeight,
                            child: const MultitaskPanelWidget(),
                          ),
                          SizedBox(height: spacingHeight),
                          SizedBox(
                            height: sampleBanksHeight,
                            child: const SampleBanksWidget(),
                          ),
                          SizedBox(height: spacingHeight),
                          SizedBox(
                            height: sampleGridHeight,
                            child: const SampleGridWidget(),
                          ),
                          SizedBox(height: spacingHeight),
                          SizedBox(
                            height: editButtonsHeight,
                            child: const EditButtonsWidget(),
                          ),
                          SizedBox(height: spacingHeight),
                          Container(
                            height: footerPadding,
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 244, 244, 244),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCheckpointChatView(Thread thread, ThreadsState threadsState, SequencerState sequencerState) {
    // Create mock checkpoints for testing different positions
    final mockCheckpoints = [
      ThreadCheckpoint(
        id: 'mock_1',
        userId: 'other_user',
        userName: 'Alice',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        comment: 'Added some drums',
        snapshot: SequencerSnapshot(
          id: 'snap_1',
          name: 'Mock 1',
          createdAt: DateTime.now(),
          version: '1.0',
          audio: ProjectAudio(
            format: 'wav',
            duration: 120.0,
            sampleRate: 44100,
            channels: 2,
            url: '',
            renders: [],
            sources: [],
          ),
        ),
      ),
      ThreadCheckpoint(
        id: 'mock_2',
        userId: threadsState.currentUserId ?? 'current_user',
        userName: 'You',
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        comment: 'Mixed the levels',
        snapshot: SequencerSnapshot(
          id: 'snap_2',
          name: 'Mock 2',
          createdAt: DateTime.now(),
          version: '1.0',
          audio: ProjectAudio(
            format: 'wav',
            duration: 120.0,
            sampleRate: 44100,
            channels: 2,
            url: '',
            renders: [],
            sources: [],
          ),
        ),
      ),
      ThreadCheckpoint(
        id: 'mock_3',
        userId: 'other_user_2',
        userName: 'Bob',
        timestamp: DateTime.now().subtract(const Duration(minutes: 30)),
        comment: 'Added bassline',
        snapshot: SequencerSnapshot(
          id: 'snap_3',
          name: 'Mock 3',
          createdAt: DateTime.now(),
          version: '1.0',
          audio: ProjectAudio(
            format: 'wav',
            duration: 120.0,
            sampleRate: 44100,
            channels: 2,
            url: '',
            renders: [],
            sources: [],
          ),
        ),
      ),
      ThreadCheckpoint(
        id: 'mock_4',
        userId: threadsState.currentUserId ?? 'current_user',
        userName: 'You',
        timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
        comment: 'Final tweaks',
        snapshot: SequencerSnapshot(
          id: 'snap_4',
          name: 'Mock 4',
          createdAt: DateTime.now(),
          version: '1.0',
          audio: ProjectAudio(
            format: 'wav',
            duration: 120.0,
            sampleRate: 44100,
            channels: 2,
            url: '',
            renders: [],
            sources: [],
          ),
        ),
      ),
    ];

    // Combine real and mock checkpoints
    final allCheckpoints = [...thread.checkpoints, ...mockCheckpoints];

    return Container(
      color: const Color(0xFF0f172a),
      child: Column(
        children: [
          // Chat messages area
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: allCheckpoints.length + 1, // +1 for current sequencer
              itemBuilder: (context, index) {
                if (index == allCheckpoints.length) {
                  // Current sequencer widget at the bottom
                  return Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: _expandCurrentSequencer,
                          child: Consumer<SequencerState>(
                            builder: (context, sequencer, child) {
                                                             return SequencerWidget(
                                 height: 120,
                                 width: MediaQuery.of(context).size.width * 0.75,
                                 isCompact: true,
                                 onToggleSize: _expandCurrentSequencer,
                               );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final checkpoint = allCheckpoints[index];
                final isCurrentUser = checkpoint.userId == (threadsState.currentUserId ?? 'current_user');

                                 return Padding(
                   padding: const EdgeInsets.only(bottom: 12),
                   child: Align(
                     alignment: isCurrentUser 
                         ? Alignment.centerRight 
                         : Alignment.centerLeft,
                     child: GestureDetector(
                       onTap: () => _expandCheckpoint(checkpoint.id),
                       child: CheckpointMessageWidget(
                         checkpoint: checkpoint,
                         isCurrentUser: isCurrentUser,
                         isExpanded: _expandedCheckpointId == checkpoint.id,
                       ),
                     ),
                   ),
                 );
              },
            ),
          ),
        ],
      ),
    );
  }
} 