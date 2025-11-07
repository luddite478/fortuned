import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../state/threads_state.dart';
import '../../../state/audio_player_state.dart';
import '../../../services/audio_cache_service.dart';
import '../../../models/thread/thread.dart';
import '../../../models/thread/message.dart';
import '../../../models/thread/thread_user.dart';
import '../../../utils/app_colors.dart';
import '../../sequencer/v2/message_sections_chain.dart';

typedef MessageContextMenuCallback = void Function(BuildContext context, Message message, Offset globalPosition);
typedef ApplyMessageCallback = void Function(BuildContext context, Message message);
typedef AddToLibraryCallback = void Function(BuildContext context, Render render);
typedef ShareRenderCallback = void Function(BuildContext context, Render render);

class ThreadViewWidget extends StatefulWidget {
  final ScrollController scrollController;
  final bool isLoadingOlderMessages;
  final MessageContextMenuCallback onShowMessageContextMenu;
  final ApplyMessageCallback onApplyMessage;
  final AddToLibraryCallback onAddToLibrary;
  final ShareRenderCallback onShareRender;

  const ThreadViewWidget({
    super.key,
    required this.scrollController,
    required this.isLoadingOlderMessages,
    required this.onShowMessageContextMenu,
    required this.onApplyMessage,
    required this.onAddToLibrary,
    required this.onShareRender,
  });

  @override
  State<ThreadViewWidget> createState() => _ThreadViewWidgetState();
}

class _ThreadViewWidgetState extends State<ThreadViewWidget> {
  final GlobalKey<AnimatedListState> _animatedListKey = GlobalKey<AnimatedListState>();
  List<Message> _displayedMessages = [];
  bool _hasPerformedInitialLoad = false;
  String? _optimisticRenderKey;
  String? _downloadingShareRenderKey;
  
  // Configurable chat alignment percentages
  static const double singleUserLeftMarginPercent = 0.02; // 2% left margin for single user
  static const double currentUserLeftMarginPercent = 0.02; // 2% left margin for current user (multi-user)
  static const double otherUserRightMarginPercent = 0.02; // 2% right margin for other users
  static const double layer3WidthPercent = 0.95; // Layer 3 (sections + buttons) is 95% of message width

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.sequencerSurfaceRaised,
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
                });
              }
            });
          }

          // Detect new messages and animate them in
          _updateDisplayedMessages(messages, threadsState);

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final allMessagesToday = _displayedMessages.isEmpty || _displayedMessages.every((msg) {
            final msgDate = DateTime(msg.timestamp.year, msg.timestamp.month, msg.timestamp.day);
            return msgDate == today;
          });

          return Stack(
            children: [
              AnimatedList(
                key: _animatedListKey,
                controller: widget.scrollController,
                reverse: true,
                padding: const EdgeInsets.only(
                  top: 8,
                  left: 12,
                  right: 12,
                  bottom: 52,
                ),
                initialItemCount: _displayedMessages.length + (widget.isLoadingOlderMessages ? 1 : 0),
                itemBuilder: (context, index, animation) {
                  if (index == _displayedMessages.length) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: AppColors.sequencerAccent),
                      ),
                    );
                  }

                  final reversedIndex = _displayedMessages.length - 1 - index;
                  final message = _displayedMessages[reversedIndex];
                  final isCurrentUser = message.userId == threadsState.currentUserId;

                  bool needsDivider = false;
                  if (!allMessagesToday) {
                    if (reversedIndex == _displayedMessages.length - 1) {
                      needsDivider = true;
                    } else if (reversedIndex == 0) {
                      needsDivider = true;
                    } else if (reversedIndex > 0) {
                      final olderMessage = _displayedMessages[reversedIndex - 1];
                      needsDivider = _needsDayDivider(olderMessage.timestamp, message.timestamp);
                    }
                  }

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

                  return _buildMessageAnimation(bubble, animation, isNewMessage: index == 0);
                },
              ),
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

  void _updateDisplayedMessages(List<Message> newMessages, ThreadsState threadsState) {
    if (_displayedMessages.isEmpty && newMessages.isNotEmpty && !_hasPerformedInitialLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _displayedMessages = List.from(newMessages);
            _hasPerformedInitialLoad = true;
          });
        }
      });
    } else if (_displayedMessages.length < newMessages.length) {
      final animatedList = _animatedListKey.currentState;
      
      if (animatedList != null) {
        final List<Message> newlyAdded = newMessages.sublist(_displayedMessages.length);
        
        for (int i = 0; i < newlyAdded.length; i++) {
          final message = newlyAdded[i];
          _displayedMessages.add(message);
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              animatedList.insertItem(0, duration: const Duration(milliseconds: 350));
            }
          });
        }
      } else {
        _displayedMessages = List.from(newMessages);
      }
    } else if (_displayedMessages.length > newMessages.length) {
      final animatedList = _animatedListKey.currentState;
      
      if (animatedList != null) {
        final thread = threadsState.activeThread;
        final currentUserId = threadsState.currentUserId;
        
        if (thread != null) {
          final removedIndices = <int>[];
          for (int i = 0; i < _displayedMessages.length; i++) {
            final msg = _displayedMessages[i];
            if (!newMessages.any((m) => m.id == msg.id)) {
              removedIndices.add(i);
            }
          }
          
          for (int i = removedIndices.length - 1; i >= 0; i--) {
            final removedIndex = removedIndices[i];
            final removedMessage = _displayedMessages[removedIndex];
            final isCurrentUser = removedMessage.userId == currentUserId;
            
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
        
        _displayedMessages = List.from(newMessages);
      } else {
        _displayedMessages = List.from(newMessages);
      }
    } else {
      bool isDifferent = false;
      for (int i = 0; i < newMessages.length; i++) {
        final oldMsg = _displayedMessages[i];
        final newMsg = newMessages[i];
        
        if (oldMsg.id != newMsg.id) {
          isDifferent = true;
          break;
        }
        
        if (oldMsg.renders.length != newMsg.renders.length) {
          isDifferent = true;
          break;
        }
        
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

  Widget _buildMessageAnimation(Widget child, Animation<double> animation, {bool isNewMessage = false}) {
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
        name: '',
        joinedAt: DateTime.now(),
      ),
    ).name;

    final shouldShowUsername = userName.isNotEmpty && thread.users.length > 1;
    final isMultiUser = thread.users.length > 1;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => widget.onShowMessageContextMenu(context, message, details.globalPosition),
      onLongPressStart: (details) => widget.onShowMessageContextMenu(context, message, details.globalPosition),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate margins based on chat type and user
          final double leftMargin;
          final double rightMargin;
          
          if (!isMultiUser) {
            // Single user: small left margin for all messages
            leftMargin = constraints.maxWidth * singleUserLeftMarginPercent;
            rightMargin = 0;
          } else if (isCurrentUser) {
            // Multi-user, current user: small left margin, align right
            leftMargin = constraints.maxWidth * currentUserLeftMarginPercent;
            rightMargin = 0;
          } else {
            // Multi-user, other user: small right margin, align left
            leftMargin = 0;
            rightMargin = constraints.maxWidth * otherUserRightMarginPercent;
          }

          return Container(
            margin: EdgeInsets.only(
              left: leftMargin,
              right: rightMargin,
              bottom: 8,
            ),
            child: Column(
              crossAxisAlignment: isMultiUser && !isCurrentUser 
                  ? CrossAxisAlignment.start 
                  : CrossAxisAlignment.start,
              children: [
                // Solid message container with all 3 layers
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.sequencerSurfaceBase,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Layer 1: Header (username + timestamp)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        child: Row(
                          children: [
                            if (shouldShowUsername) ...[
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
                            ] else
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
                      ),
                      
                      // Layer 2: Optional render audio bar (directly under header, no gap)
                      if (message.renders.isNotEmpty)
                        for (final render in message.renders)
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            child: _buildRenderButton(context, message, render),
                          ),
                      
                      // Layer 3: Sections chain + buttons (slightly narrower)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: LayoutBuilder(
                          builder: (context, innerConstraints) {
                            final layer3Width = innerConstraints.maxWidth * layer3WidthPercent;
                            final layer3LeftMargin = (innerConstraints.maxWidth - layer3Width) / 2;
                            
                            return Container(
                              margin: EdgeInsets.only(left: layer3LeftMargin, right: layer3LeftMargin),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildMessagePreviewFromMetadata(message),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: null,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF2A2D30),
                                            foregroundColor: AppColors.sequencerLightText.withOpacity(0.5),
                                            disabledBackgroundColor: const Color(0xFF2A2D30),
                                            disabledForegroundColor: AppColors.sequencerLightText.withOpacity(0.5),
                                            elevation: 0,
                                            shadowColor: Colors.black.withOpacity(0.1),
                                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                            minimumSize: const Size(0, 40),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                          child: const Text(
                                            'Comment',
                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: () => widget.onApplyMessage(context, message),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF2A2D30),
                                            foregroundColor: AppColors.sequencerText,
                                            elevation: 0,
                                            shadowColor: Colors.black.withOpacity(0.1),
                                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                            minimumSize: const Size(0, 40),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                          child: const Text(
                                            'Load',
                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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

    final stepsPerSectionTrimmed = () {
      if (stepsPerSectionMeta.isEmpty) return List<int>.filled(sectionsCount, 16);
      if (stepsPerSectionMeta.length >= sectionsCount) {
        return stepsPerSectionMeta.take(sectionsCount).toList();
      }
      final list = List<int>.from(stepsPerSectionMeta);
      list.addAll(List<int>.filled(sectionsCount - stepsPerSectionMeta.length, stepsPerSectionMeta.last));
      return list;
    }();

    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: MessageSectionsChain(
          sectionsCount: sectionsCount,
          stepsPerSection: stepsPerSectionTrimmed,
          loopsPerSection: loopsTrimmed,
          layersPerSection: layersTrimmed,
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
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: isFailed ? BoxDecoration(
                color: AppColors.sequencerAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.sequencerAccent,
                  width: 0.5,
                ),
              ) : null,
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
                                  Expanded(
                                    child: Container(
                                      height: 2,
                                      decoration: BoxDecoration(
                                        color: AppColors.sequencerBorder.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(1),
                                      ),
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
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: (isUploading || isFailed) ? null : () => widget.onAddToLibrary(context, render),
                    child: Icon(
                      Icons.playlist_add,
                      color: (isUploading || isFailed) 
                          ? AppColors.sequencerLightText.withOpacity(0.3)
                          : AppColors.sequencerText,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildShareButton(context, message, render, isUploading, isFailed),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildShareButton(
    BuildContext context,
    Message message,
    Render render,
    bool isUploading,
    bool isFailed,
  ) {
    final renderKey = '${message.id}::${render.id}';
    final isDownloadingForShare = _downloadingShareRenderKey == renderKey;

    if (isDownloadingForShare) {
      // Show loading indicator while downloading
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.sequencerText,
        ),
      );
    }

    return GestureDetector(
      onTap: (isUploading || isFailed)
          ? null
          : () async {
              // Check if file is cached
              final isCached = await AudioCacheService.isCached(render.url);
              
              if (!isCached) {
                // Download the file first
                setState(() {
                  _downloadingShareRenderKey = renderKey;
                });

                try {
                  // Use AudioPlayerState to download the file (it handles caching)
                  final audioPlayer = context.read<AudioPlayerState>();
                  await audioPlayer.playRender(
                    messageId: message.id,
                    render: render,
                  );
                  // Stop playback immediately after download completes
                  await audioPlayer.stop();
                } catch (e) {
                  debugPrint('Error downloading render for share: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Failed to download audio for sharing'),
                        backgroundColor: AppColors.sequencerAccent,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                  setState(() {
                    _downloadingShareRenderKey = null;
                  });
                  return;
                }

                setState(() {
                  _downloadingShareRenderKey = null;
                });
              }

              // Now share the cached file
              widget.onShareRender(context, render);
            },
      child: Icon(
        Icons.link,
        color: (isUploading || isFailed)
            ? AppColors.sequencerLightText.withOpacity(0.3)
            : AppColors.sequencerText,
        size: 22,
      ),
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
}

