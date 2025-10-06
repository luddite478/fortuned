import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/threads_state.dart';
import '../state/audio_player_state.dart';
import '../state/library_state.dart';
import '../state/sequencer/recording.dart';
import '../models/thread/message.dart';
import '../models/thread/thread.dart';
import '../utils/app_colors.dart';
import '../utils/thread_name_generator.dart';
import '../models/thread/thread_user.dart';
import '../services/users_service.dart';
import '../services/audio_cache_service.dart';
import '../widgets/sections_chain_squares.dart';
import '../services/auth_service.dart';

class ThreadScreen extends StatefulWidget {
  final String threadId;
  final bool highlightNewest;
  final String? targetMessageId;

  const ThreadScreen({
    super.key,
    required this.threadId,
    this.highlightNewest = false,
    this.targetMessageId,
  });

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};
  AnimationController? _colorAnimationController;
  Animation<Color?>? _colorAnimation;
  Timer? _timestampRefreshTimer;

  @override
  void initState() {
    super.initState();

    if (widget.highlightNewest) {
      _colorAnimationController = AnimationController(
        duration: const Duration(seconds: 1),
        vsync: this,
      );
      final Color originalColor = AppColors.menuCheckpointBackground;
      final Color highlightColor = Colors.lightBlue.withOpacity(0.3);
      _colorAnimation = ColorTween(
        begin: originalColor,
        end: highlightColor,
      ).animate(CurvedAnimation(
        parent: _colorAnimationController!,
        curve: Curves.easeInOut,
      ));
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _colorAnimationController?.forward().then((_) {
            if (mounted) {
              _colorAnimationController?.reverse();
            }
          });
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final threadsState = context.read<ThreadsState>();
      threadsState.enterThreadView(widget.threadId);
      try {
        await threadsState.ensureThreadSummary(widget.threadId);
      } catch (_) {}
      threadsState.setActiveThread(
        threadsState.threads.firstWhere(
          (t) => t.id == widget.threadId,
          orElse: () => Thread(id: widget.threadId, name: ThreadNameGenerator.generate(widget.threadId), createdAt: DateTime.now(), updatedAt: DateTime.now(), users: const [], messageIds: const [], invites: const []),
        ),
      );
      await threadsState.loadMessages(widget.threadId, includeSnapshot: false, order: 'asc');
      if (widget.targetMessageId != null) {
        _scrollToMessageIfNeeded(widget.targetMessageId!);
      } else {
        _scrollToBottom();
      }
    });

    // No need to refresh timestamps anymore since we show fixed dates
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

  void _scrollToMessageIfNeeded(String messageId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _messageKeys[messageId];
      if (key != null && key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 350),
          alignment: 0.2,
          curve: Curves.easeOut,
        );
      } else {
        _scrollToBottom();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildHeader(context),
      backgroundColor: AppColors.menuPageBackground,
      body: Consumer<ThreadsState>(
        builder: (context, threadsState, child) {
        final thread = threadsState.activeThread;
        final messages = threadsState.activeThreadMessages;

          if (thread == null) {
            return Center(
              child: Text(
                'Thread not found',
                style: GoogleFonts.sourceSans3(
                  color: AppColors.menuLightText,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }

          if (messages.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: AppColors.menuLightText,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No checkpoints yet',
                    style: GoogleFonts.sourceSans3(
                      color: AppColors.menuText,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Press send button in the bottom right of sequencer\nto save checkpoint',
                    style: GoogleFonts.sourceSans3(
                      color: AppColors.menuLightText,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final isCurrentUser = message.userId == threadsState.currentUserId;
              final isNewest = index == messages.length - 1;
              final shouldHighlight = widget.highlightNewest && isNewest && _colorAnimation != null;
              final isTarget = widget.targetMessageId != null && widget.targetMessageId == message.id;
              final key = _messageKeys.putIfAbsent(message.id, () => GlobalKey());

              // Check if we need a day divider before this message
              final bool needsDivider = index == 0 || _needsDayDivider(
                messages[index - 1].timestamp,
                message.timestamp,
              );

              Widget bubble = shouldHighlight
                  ? AnimatedBuilder(
                      animation: _colorAnimation!,
                      builder: (context, child) {
                        return _buildMessageBubble(
                          context,
                          thread,
                          message,
                          isCurrentUser,
                          highlightColor: _colorAnimation!.value,
                        );
                      },
                    )
                  : _buildMessageBubble(
                      context,
                      thread,
                      message,
                      isCurrentUser,
                    );
              if (isTarget) {
                bubble = Container(
                  key: key,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.lightBlueAccent.withOpacity(0.6), width: 1),
                  ),
                  child: bubble,
                );
              } else {
                bubble = Container(key: key, child: bubble);
              }

              // Add day divider if needed
              if (needsDivider) {
                return Column(
                  children: [
                    if (index > 0) const SizedBox(height: 8),
                    _buildDayDivider(message.timestamp),
                    const SizedBox(height: 8),
                    bubble,
                  ],
                );
              }

              return bubble;
            },
          );
        },
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    Thread thread,
    Message message,
    bool isCurrentUser, {
    Color? highlightColor,
  }) {
    final userName = thread.users.firstWhere(
      (u) => u.id == message.userId,
      orElse: () => ThreadUser(id: message.userId, name: 'User ${message.userId.substring(0, 6)}', joinedAt: DateTime.now()),
    ).name;

    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: highlightColor ?? AppColors.menuEntryBackground,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: AppColors.menuBorder,
            width: 0.5,
          ),
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
                    color: AppColors.menuText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatTimestamp(message.timestamp),
                  style: GoogleFonts.sourceSans3(
                    color: AppColors.menuLightText,
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
                // Show upload indicator if message has no renders but recording might be uploading
                if (message.renders.isEmpty && message.sendStatus == SendStatus.sent && isCurrentUser)
                  Consumer<ThreadsState>(
                    builder: (context, threadsState, _) {
                      // Try to get RecordingState if available
                      final recordingState = context.read<RecordingState?>();
                      
                      // Check if recording is currently uploading (only for latest message from current user)
                      final messages = threadsState.activeThreadMessages;
                      final isLatestMessage = messages.isNotEmpty && messages.last.id == message.id;
                      final isUploading = isLatestMessage && recordingState != null && recordingState.isUploading;
                      
                      if (!isUploading) return const SizedBox.shrink();
                      
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppColors.menuBorder.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.menuLightText,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Uploading audio...',
                              style: GoogleFonts.sourceSans3(
                                color: AppColors.menuLightText,
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                // Show renders if they exist
                if (message.renders.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final render in message.renders)
                        _buildRenderButton(context, message, render, threadsState: context.read<ThreadsState>()),
                      const SizedBox(height: 4),
                    ],
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Add to playlist button (only if renders exist)
                    if (message.renders.isNotEmpty) ...[
                      OutlinedButton.icon(
                        onPressed: () => _addToPlaylist(context, message.renders.first),
                        icon: Icon(Icons.playlist_add, size: 16),
                        label: const Text('Add to playlist'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.menuText,
                          side: BorderSide(color: AppColors.menuBorder),
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                          minimumSize: const Size(0, 28),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Load button
                    OutlinedButton(
                      onPressed: () => _applyMessage(context, message),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.menuText,
                        side: BorderSide(color: AppColors.menuBorder),
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
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showMessageContextMenu(context, message, details.globalPosition),
      onLongPressStart: (details) => _showMessageContextMenu(context, message, details.globalPosition),
      child: bubble,
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
          const SnackBar(content: Text('Failed to delete message'), backgroundColor: Colors.red, duration: Duration(seconds: 2)),
        );
      }
    }
  }

  Widget _buildMediaBar(Message message) {
    final renders = (message.snapshot['audio']?['renders'] as List?) ?? const [];
    final hasRenders = renders.isNotEmpty;
    final durationSec = (message.snapshot['audio']?['duration'] ?? 0.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.menuButtonBackground,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppColors.menuBorder,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _playMessageRender(message),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.menuOnlineIndicator,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.schedule, size: 14, color: AppColors.menuLightText),
          const SizedBox(width: 4),
          Text(
            _formatDuration(durationSec),
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuLightText,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          const Spacer(),
          if (hasRenders) ...[
            Icon(Icons.audiotrack, size: 14, color: AppColors.menuLightText),
            const SizedBox(width: 4),
            Text(
              '${renders.length}',
              style: GoogleFonts.sourceSans3(
                color: AppColors.menuLightText,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSoundGridPreview(Map<String, dynamic> snapshot) {
    final audio = snapshot['audio'] as Map<String, dynamic>?;
    final sources = (audio?['sources'] as List?) ?? const [];
    final firstSource = sources.isNotEmpty ? sources.first as Map<String, dynamic>? : null;
    final sections = (firstSource?['sections'] as List?) ?? const [];
    final firstSection = sections.isNotEmpty ? sections.first as Map<String, dynamic>? : null;
    final layers = (firstSection?['layers'] as List?) ?? const [];

    if (sources.isEmpty || sections.isEmpty || layers.isEmpty) {
      return Container(
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.menuBorder.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: AppColors.menuBorder,
            width: 0.5,
          ),
        ),
        child: Center(
          child: Text(
            'Empty Project',
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuLightText,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: AppColors.menuBorder.withOpacity(0.3),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppColors.menuBorder,
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Text(
              'Sound Grid Preview',
              style: GoogleFonts.sourceSans3(
                color: AppColors.menuLightText,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Row(
                children: List.generate(layers.length.clamp(0, 4), (layerIndex) {
                  final layer = layers[layerIndex] as Map<String, dynamic>;
                  final rows = (layer['rows'] as List?) ?? const [];
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: _getLayerColor(layerIndex),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Column(
                        children: List.generate(rows.length.clamp(0, 8), (rowIndex) {
                          final row = rows[rowIndex] as Map<String, dynamic>;
                          final cells = (row['cells'] as List?) ?? const [];
                          final hasSample = cells.any((c) {
                            final cell = c as Map<String, dynamic>;
                            final sample = cell['sample'];
                            return sample != null && (sample['sample_id'] != null && (sample['sample_id'] as String).isNotEmpty);
                          });
                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.all(0.5),
                              decoration: BoxDecoration(
                                color: hasSample ? Colors.white.withOpacity(0.8) : Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getLayerColor(int layerIndex) {
    final colors = [
      const Color(0xFF3b82f6),
      const Color(0xFF10b981),
      const Color(0xFFf59e0b),
      const Color(0xFFef4444),
    ];
    return colors[layerIndex % colors.length];
  }

  Widget _buildMessagePreviewFromMetadata(Message message) {
    // Simplified: rely only on snapshotMetadata
    final meta = message.snapshotMetadata ?? const {};
    final sectionsCount = (meta['sections_count'] as num?)?.toInt() ?? 0;
    final stepsPerSectionMeta = (meta['sections_steps'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const <int>[];
    final loopsMeta = (meta['sections_loops_num'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const <int>[];
    final layersMeta = (meta['layers'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const <int>[];

    // Normalize lengths to exactly sectionsCount
    final loopsTrimmed = loopsMeta.length >= sectionsCount
        ? loopsMeta.take(sectionsCount).toList()
        : List<int>.from(loopsMeta)..addAll(List<int>.filled(sectionsCount - loopsMeta.length, loopsMeta.isNotEmpty ? loopsMeta.last : 4));

    final int defaultLayersPerSection = (layersMeta.isNotEmpty ? layersMeta.first : 4);
    final layersTrimmed = layersMeta.length >= sectionsCount
        ? layersMeta.take(sectionsCount).toList()
        : List<int>.from(layersMeta)..addAll(List<int>.filled(sectionsCount - layersMeta.length, defaultLayersPerSection));

    // (Optional) We could later show steps per section under each stack using stepsPerSectionMeta.take(sectionsCount)

    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.menuBorder.withOpacity(0.3),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppColors.menuBorder,
          width: 0.5,
        ),
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

  PreferredSizeWidget _buildHeader(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.menuEntryBackground,
      foregroundColor: AppColors.menuText,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: AppColors.menuText),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        _ParticipantsIndicator(threadId: widget.threadId),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(Icons.person_add, color: AppColors.menuText),
          onPressed: () => _showInviteCollaboratorsModal(context),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    // Format time as HH:mm
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    
    if (messageDate == today) {
      // Today: just show time
      return timeStr;
    } else if (messageDate == yesterday) {
      // Yesterday: show "Yesterday at HH:mm"
      return 'Yesterday at $timeStr';
    } else {
      // Older: show "DD/MM/YYYY, HH:mm"
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
      // Format as "2 October 2025"
      final months = ['January', 'February', 'March', 'April', 'May', 'June', 
                     'July', 'August', 'September', 'October', 'November', 'December'];
      dateLabel = '${timestamp.day} ${months[timestamp.month - 1]} ${timestamp.year}';
    }
    
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.menuBorder.withOpacity(0.5),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            dateLabel,
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuLightText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.menuBorder.withOpacity(0.5),
          ),
        ),
      ],
    );
  }

  String _formatDuration(double duration) {
    final minutes = (duration / 60).floor();
    final seconds = (duration % 60).floor();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildRenderButton(BuildContext context, Message message, Render render, {required ThreadsState threadsState}) {
    final isCurrentUser = message.userId == threadsState.currentUserId;
    
    return Consumer<AudioPlayerState>(
      builder: (context, audioPlayer, _) {
        final isPlaying = audioPlayer.isPlayingRender(message.id, render.id);
        final isLoading = audioPlayer.isLoadingRender(message.id, render.id);
        final isThisRender = audioPlayer.currentlyPlayingMessageId == message.id && 
                             audioPlayer.currentlyPlayingRenderId == render.id;
        
        // Try to get RecordingState if available (might not be if not coming from sequencer)
        final recordingState = context.read<RecordingState?>();
        
        // Check if audio is cached
        return FutureBuilder<bool>(
          future: AudioCacheService.isCached(render.url),
          builder: (context, snapshot) {
            final isCached = snapshot.data ?? false;
            
            // For current user, check if they have local file
            String? localPath;
            if (isCurrentUser && recordingState != null && recordingState.convertedMp3Path != null) {
              // Check if this render URL matches the recently uploaded one
              if (render.url == recordingState.uploadedRenderUrl) {
                localPath = recordingState.convertedMp3Path;
              }
            }
            
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.menuButtonBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.menuBorder,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  // Play/Pause/Loading button
                  GestureDetector(
                    onTap: () async {
                      if (isLoading) return;
                      
                      final player = context.read<AudioPlayerState>();
                      await player.playRender(
                        messageId: message.id,
                        render: render,
                        localPathIfRecorded: localPath,
                      );
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isLoading 
                            ? AppColors.menuBorder.withOpacity(0.5)
                            : AppColors.menuText.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: isLoading
                          ? Padding(
                              padding: const EdgeInsets.all(6),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.menuLightText,
                                value: audioPlayer.downloadProgress > 0 
                                    ? audioPlayer.downloadProgress 
                                    : null,
                              ),
                            )
                          : Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: AppColors.menuPageBackground,
                              size: 16,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Seek bar
                  Expanded(
                    child: isThisRender
                        ? SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              activeTrackColor: AppColors.menuText.withOpacity(0.6),
                              inactiveTrackColor: AppColors.menuBorder.withOpacity(0.3),
                              thumbColor: AppColors.menuText,
                              overlayColor: AppColors.menuText.withOpacity(0.1),
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
                              color: AppColors.menuBorder.withOpacity(0.3),
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

  void _playMessageRender(Message message) {
    // Legacy method - now handled by _buildRenderButton
    if (message.renders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No audio renders available for this message'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
  }

  Future<void> _addToPlaylist(BuildContext context, Render render) async {
    final auth = context.read<AuthService>();
    final userId = auth.currentUser?.id;
    
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to add to playlist'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // Use LibraryState which handles optimistic update + background sync
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
        const SnackBar(
          content: Text('Failed to add to playlist'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _applyMessage(BuildContext context, Message message) async {
    final threadsState = context.read<ThreadsState>();
    final ok = await threadsState.applyMessage(message);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    }
  }

  void _showInviteCollaboratorsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: const _InviteCollaboratorsModalBottomSheet(),
      ),
    );
  }

  @override
  void dispose() {
    try {
      final threadsState = context.read<ThreadsState>();
      threadsState.exitThreadView();
      // Stop audio playback when leaving thread screen
      final audioPlayer = context.read<AudioPlayerState>();
      audioPlayer.stop();
    } catch (_) {}
    _scrollController.dispose();
    _colorAnimationController?.dispose();
    _timestampRefreshTimer?.cancel();
    super.dispose();
  }
}

class _ParticipantsIndicator extends StatelessWidget {
  final String threadId;
  const _ParticipantsIndicator({required this.threadId});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ThreadsState, AuthService>(
      builder: (context, threadsState, auth, _) {
        final thread = threadsState.threads.firstWhere(
          (t) => t.id == threadId,
          orElse: () => threadsState.activeThread ?? Thread(id: threadId, name: ThreadNameGenerator.generate(threadId), createdAt: DateTime.now(), updatedAt: DateTime.now(), users: const [], messageIds: const [], invites: const []),
        );
        final me = auth.currentUser?.id;
        final others = thread.users.where((u) => u.id != me).map((u) => u.name).toList();
        if (others.isEmpty) {
          return const SizedBox.shrink();
        }
        final text = others.take(3).join(', ');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.menuBorder.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.group, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                text,
                style: GoogleFonts.sourceSans3(color: AppColors.menuLightText, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InviteCollaboratorsModalBottomSheet extends StatefulWidget {
  const _InviteCollaboratorsModalBottomSheet();

  @override
  State<_InviteCollaboratorsModalBottomSheet> createState() => _InviteCollaboratorsModalBottomSheetState();
}

class _InviteCollaboratorsModalBottomSheetState extends State<_InviteCollaboratorsModalBottomSheet> {
  final List<UserProfile> _selectedUsers = [];
  final TextEditingController _searchController = TextEditingController();
  List<UserProfile> _filteredUserProfiles = [];
  List<UserProfile> _followedUsers = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setupSearchListener();
    _loadFollowedUsers();
  }

  void _setupSearchListener() {
    _searchController.addListener(() {
      _handleSearch(_searchController.text);
    });
  }

  void _handleSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _filteredUserProfiles = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoading = false;
    });

    // First, check followed users for immediate matches
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    final currentUserId = threadsState.currentUserId;
    
    final followedMatches = _followedUsers
        .where((user) => user.username.toLowerCase().contains(query.toLowerCase()))
        .where((user) => user.id != currentUserId)
        .where((user) => !_selectedUsers.any((selected) => selected.id == user.id))
        .toList();

    setState(() {
      _filteredUserProfiles = followedMatches;
    });

    // If query is 4+ characters, also search all users
    if (query.length >= 4) {
      setState(() {
        _isLoading = true;
      });

      try {
        final searchResults = await UsersService.searchUsers(query, limit: 50);
        
        // Combine followed matches with search results, avoiding duplicates
        final allResults = <UserProfile>[...followedMatches];
        for (final user in searchResults.users) {
          if (user.id != currentUserId && 
              !allResults.any((existing) => existing.id == user.id) &&
              !_selectedUsers.any((selected) => selected.id == user.id)) {
            allResults.add(user);
          }
        }

        setState(() {
          _filteredUserProfiles = allResults;
          _isLoading = false;
        });
      } catch (e) {
        setState(() {
          _error = 'Search failed: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFollowedUsers() async {
    try {
      final threadsState = Provider.of<ThreadsState>(context, listen: false);
      final currentUserId = threadsState.currentUserId;
      
      if (currentUserId == null) {
        setState(() {
          _error = 'Please log in to view followed users';
          _isLoading = false;
        });
        return;
      }

      final response = await UsersService.getFollowedUsers(currentUserId);
      setState(() {
        _followedUsers = response.users;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      // If loading followed users fails, show empty state but don't show error
      setState(() {
        _followedUsers = [];
        _isLoading = false;
        _error = null;
      });
      print('Failed to load followed users: $e');
    }
  }

  List<UserProfile> get _displayedUsers {
    return _isSearching ? _filteredUserProfiles : _followedUsers;
  }

  Widget _buildSearchBarWithChips() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.menuPageBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.menuBorder),
      ),
      child: Column(
        children: [
          // Selected users chips
          if (_selectedUsers.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectedUsers.map((user) => _buildUserChip(user)).toList(),
              ),
            ),
          
          // Search input
          Row(
            children: [
              if (_isSearching)
                IconButton(
                  icon: Icon(Icons.arrow_back, color: AppColors.menuText, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _isSearching = false;
                      _filteredUserProfiles = [];
                    });
                    // Dismiss keyboard
                    FocusScope.of(context).unfocus();
                  },
                ),
              
              if (!_isSearching)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Icon(Icons.search, color: AppColors.menuLightText, size: 20),
                ),
              
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: GoogleFonts.sourceSans3(
                    color: AppColors.menuText,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    hintStyle: GoogleFonts.sourceSans3(
                      color: AppColors.menuLightText,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserChip(UserProfile user) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.menuEntryBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.menuBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 12),
          Text(
            user.username,
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuText,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedUsers.removeWhere((selected) => selected.id == user.id);
              });
              // Refresh search results to show the user again
              _handleSearch(_searchController.text);
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.close,
                size: 16,
                color: AppColors.menuLightText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.menuEntryBackground,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.menuBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Invite Collaborators',
                    style: GoogleFonts.sourceSans3(
                      color: AppColors.menuText,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Search bar with selected user chips
                  _buildSearchBarWithChips(),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            'Loading users...',
                            style: GoogleFonts.sourceSans3(
                              color: AppColors.menuLightText,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, color: AppColors.menuLightText, size: 48),
                              const SizedBox(height: 16),
                              Text(
                                _error!,
                                style: GoogleFonts.sourceSans3(
                                  color: AppColors.menuLightText,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadFollowedUsers,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.menuButtonBackground,
                                  side: BorderSide(color: AppColors.menuButtonBorder),
                                ),
                                child: Text(
                                  'Retry',
                                  style: GoogleFonts.sourceSans3(
                                    color: AppColors.menuText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : _displayedUsers.isEmpty
                          ? const SizedBox.shrink()
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              itemCount: _displayedUsers.length,
                              itemBuilder: (context, index) {
                                final user = _displayedUsers[index];
                                final isOnline = user.isOnline;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: GestureDetector(
                                    onTap: () {
                                      // Add user to selected chips
                                      setState(() {
                                        if (!_selectedUsers.any((selected) => selected.id == user.id)) {
                                          _selectedUsers.add(user);
                                        }
                                      });
                                      // Clear search and refresh results to hide selected user
                                      _searchController.clear();
                                      _handleSearch('');
                                      // Dismiss keyboard
                                      FocusScope.of(context).unfocus();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: AppColors.menuCheckpointBackground,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppColors.menuBorder,
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: isOnline ? AppColors.menuOnlineIndicator : AppColors.menuLightText,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              user.username,
                                              style: GoogleFonts.sourceSans3(
                                                color: AppColors.menuText,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Text(
                    '${_selectedUsers.length} selected',
                    style: GoogleFonts.sourceSans3(
                      color: AppColors.menuLightText,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.sourceSans3(
                        color: AppColors.menuLightText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _selectedUsers.isNotEmpty ? () => _inviteSelectedContacts() : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.menuButtonBackground,
                      foregroundColor: AppColors.menuText,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      side: BorderSide(color: AppColors.menuButtonBorder),
                    ),
                    child: Text(
                      'Invite',
                      style: GoogleFonts.sourceSans3(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _inviteSelectedContacts() async {
    Navigator.of(context).pop();
    if (_selectedUsers.isEmpty) return;

    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    final currentThread = threadsState.activeThread;
    final currentUserId = threadsState.currentUserId;

    if (currentThread == null || currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to send invitations at this time'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }


    int successCount = 0;
    int failureCount = 0;

    for (final user in _selectedUsers) {
      try {
        await threadsState.sendInvite(
          threadId: currentThread.id,
          userId: user.id,
          userName: user.username,
        );
        successCount++;
      } catch (_) {
        failureCount++;
      }
    }

  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}


