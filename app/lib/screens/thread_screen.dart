import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/threads_state.dart';
import '../models/thread/message.dart';
import '../models/thread/thread.dart';
import '../utils/app_colors.dart';
import '../models/thread/thread_user.dart';
import '../services/users_service.dart';
import '../widgets/sections_chain_squares.dart';

class ThreadScreen extends StatefulWidget {
  final String threadId;
  final bool highlightNewest;

  const ThreadScreen({
    super.key,
    required this.threadId,
    this.highlightNewest = false,
  });

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
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
      await threadsState.loadThread(widget.threadId);
      _scrollToBottom();
    });

    // Periodically refresh timestamps like "Just now" / "2m ago"
    _timestampRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
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

              return shouldHighlight
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
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: () => _applyMessage(context, message),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.menuText,
                      side: BorderSide(color: AppColors.menuText),
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      minimumSize: const Size(0, 28),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: const Text('Load'),
                  ),
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
    final difference = now.difference(timestamp);
    if (difference.inDays > 0) return '${difference.inDays}d ago';
    if (difference.inHours > 0) return '${difference.inHours}h ago';
    if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
    return 'Just now';
  }

  String _formatDuration(double duration) {
    final minutes = (duration / 60).floor();
    final seconds = (duration % 60).floor();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _playMessageRender(Message message) {
    final renders = (message.snapshot['audio']?['renders'] as List?) ?? const [];
    if (renders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No audio renders available for this message'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final last = renders.last as Map<String, dynamic>;
    final url = last['url'] as String?;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playing render: ${url ?? 'Latest render'}'),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
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
    _scrollController.dispose();
    _colorAnimationController?.dispose();
    _timestampRefreshTimer?.cancel();
    super.dispose();
  }
}

class _InviteCollaboratorsModalBottomSheet extends StatefulWidget {
  const _InviteCollaboratorsModalBottomSheet();

  @override
  State<_InviteCollaboratorsModalBottomSheet> createState() => _InviteCollaboratorsModalBottomSheetState();
}

class _InviteCollaboratorsModalBottomSheetState extends State<_InviteCollaboratorsModalBottomSheet> {
  final Set<String> _selectedContacts = {};
  List<UserProfile> _userProfiles = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserProfiles();
  }

  Future<void> _loadUserProfiles() async {
    try {
      final response = await UsersService.getUserProfiles(limit: 50);
      final threadsState = Provider.of<ThreadsState>(context, listen: false);
      final currentUserId = threadsState.currentUserId;

      setState(() {
        _userProfiles = response.profiles.where((u) => u.id != currentUserId).toList();
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load users: $e';
        _isLoading = false;
      });
    }
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
                  const SizedBox(height: 8),
                  Text(
                    'Select users to invite to this thread',
                    style: GoogleFonts.sourceSans3(
                      color: AppColors.menuLightText,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
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
                                onPressed: _loadUserProfiles,
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
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _userProfiles.length,
                          itemBuilder: (context, index) {
                            final user = _userProfiles[index];
                            final isSelected = _selectedContacts.contains(user.id);
                            final isOnline = user.isOnline;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedContacts.remove(user.id);
                                    } else {
                                      _selectedContacts.add(user.id);
                                    }
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppColors.menuCurrentUserCheckpoint : AppColors.menuCheckpointBackground,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected ? AppColors.menuOnlineIndicator : AppColors.menuBorder,
                                      width: isSelected ? 2 : 1,
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
                                      Icon(
                                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                                        color: isSelected ? AppColors.menuOnlineIndicator : AppColors.menuLightText,
                                        size: 20,
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
                    '${_selectedContacts.length} selected',
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
                    onPressed: _selectedContacts.isNotEmpty ? () => _inviteSelectedContacts() : null,
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
    if (_selectedContacts.isEmpty) return;

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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sending ${_selectedContacts.length} invitation(s)...', style: GoogleFonts.sourceSans3(fontWeight: FontWeight.w500)),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );

    int successCount = 0;
    int failureCount = 0;

    for (final contactId in _selectedContacts) {
      try {
        final userProfile = _userProfiles.where((p) => p.id == contactId).firstOrNull;
        final userName = userProfile?.username ?? 'Unknown User';
        await threadsState.sendInvite(
          threadId: currentThread.id,
          userId: contactId,
          userName: userName,
        );
        successCount++;
      } catch (_) {
        failureCount++;
      }
    }

    if (!mounted) return;
    String message;
    Color backgroundColor;
    if (failureCount == 0) {
      message = 'Successfully invited $successCount user(s)!';
      backgroundColor = Colors.green;
    } else if (successCount == 0) {
      message = 'Failed to send all invitations';
      backgroundColor = Colors.red;
    } else {
      message = 'Invited $successCount user(s), $failureCount failed';
      backgroundColor = Colors.orange;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.sourceSans3(fontWeight: FontWeight.w500)),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}


