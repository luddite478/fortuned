import 'package:flutter/material.dart';
import '../state/threads_state.dart';

class CheckpointMessageWidget extends StatefulWidget {
  final ProjectCheckpoint checkpoint;
  final bool isCurrentUser;
  final bool isExpanded;
  final VoidCallback? onTap;
  final VoidCallback? onExpand;

  const CheckpointMessageWidget({
    super.key,
    required this.checkpoint,
    required this.isCurrentUser,
    this.isExpanded = false,
    this.onTap,
    this.onExpand,
  });

  @override
  State<CheckpointMessageWidget> createState() => _CheckpointMessageWidgetState();
}

class _CheckpointMessageWidgetState extends State<CheckpointMessageWidget> {
  bool _showAllRenders = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: widget.isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isCurrentUser) ...[
            _buildUserAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              child: Column(
                crossAxisAlignment: widget.isCurrentUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!widget.isCurrentUser)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 4),
                      child: Text(
                        widget.checkpoint.userName,
                        style: TextStyle(
                          color: _getUserColor(widget.checkpoint.userName),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onTap,
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: widget.isExpanded 
                              ? (widget.isCurrentUser ? const Color(0xFF0084ff).withOpacity(0.9) : const Color(0xFF374151).withOpacity(0.9))
                              : (widget.isCurrentUser ? const Color(0xFF0084ff) : const Color(0xFF374151)),
                          borderRadius: BorderRadius.circular(18),
                          border: widget.isExpanded 
                              ? Border.all(color: Colors.orangeAccent.withOpacity(0.5), width: 2)
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(widget.isExpanded ? 0.2 : 0.1),
                              blurRadius: widget.isExpanded ? 8 : 4,
                              offset: Offset(0, widget.isExpanded ? 4 : 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Renders section (no title)
                            _buildRendersSection(),
                            
                            // Timestamp
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatTimestamp(widget.checkpoint.timestamp),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (!widget.isExpanded)
                                    Text(
                                      'Tap to expand',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.5),
                                        fontSize: 10,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.isCurrentUser) ...[
            const SizedBox(width: 8),
            _buildUserAvatar(),
          ],
        ],
      ),
    );
  }

  Widget _buildRendersSection() {
    // Get renders from the checkpoint snapshot
    final renders = widget.checkpoint.snapshot.audio.renders;
    final latestRender = renders.isNotEmpty ? renders.last : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Latest render or "All renders" button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.music_note,
                color: Colors.white.withOpacity(0.9),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: latestRender != null && !_showAllRenders
                    ? _buildLatestRender(latestRender)
                    : Text(
                        widget.checkpoint.comment.isNotEmpty 
                            ? widget.checkpoint.comment 
                            : 'Sequencer checkpoint',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showAllRenders = !_showAllRenders;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _showAllRenders 
                        ? Colors.orangeAccent.withOpacity(0.2)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _showAllRenders ? 'Hide' : 'All renders',
                    style: TextStyle(
                      color: _showAllRenders ? Colors.orangeAccent : Colors.white.withOpacity(0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Horizontal render tiles (when showing all renders)
        if (_showAllRenders && renders.isNotEmpty)
          Container(
            height: 80,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: renders.length,
              itemBuilder: (context, index) {
                final render = renders[index];
                final isLatest = index == renders.length - 1;
                
                return Container(
                  width: 100,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isLatest 
                        ? Colors.orangeAccent.withOpacity(0.3)
                        : Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isLatest 
                          ? Colors.orangeAccent.withOpacity(0.5)
                          : Colors.grey.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Play button
                      Positioned(
                        top: 20,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () => _playRender(render),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.play_arrow,
                                color: isLatest ? Colors.orangeAccent : Colors.white.withOpacity(0.7),
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Render info
                      Positioned(
                        bottom: 8,
                        left: 4,
                        right: 4,
                        child: Column(
                          children: [
                            if (isLatest)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.orangeAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'LATEST',
                                  style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                                                         Text(
                               render.quality.toUpperCase(),
                               style: TextStyle(
                                 color: Colors.white.withOpacity(0.8),
                                 fontSize: 9,
                               ),
                               textAlign: TextAlign.center,
                             ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          
        // Mini sequencer preview (when not showing all renders)
        if (!_showAllRenders)
          Container(
            height: 60,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _buildSequencerPreview(),
          ),
      ],
    );
  }

  Widget _buildLatestRender(AudioRender render) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => _playRender(render),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.play_arrow,
              color: Colors.orangeAccent,
              size: 14,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Latest render',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
                             Text(
                 '${render.quality} • v${render.version}',
                 style: TextStyle(
                   color: Colors.white.withOpacity(0.7),
                   fontSize: 10,
                 ),
               ),
            ],
          ),
        ),
      ],
    );
  }

  void _playRender(AudioRender render) {
    // TODO: Implement render playback
    debugPrint('Playing render: ${render.url}');
  }

  Widget _buildUserAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _getUserColor(widget.checkpoint.userName),
        shape: BoxShape.circle,
        border: widget.isExpanded ? Border.all(color: Colors.orangeAccent.withOpacity(0.3), width: 2) : null,
      ),
      child: Center(
        child: Text(
          widget.checkpoint.userName.isNotEmpty 
              ? widget.checkpoint.userName[0].toUpperCase() 
              : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildSequencerPreview() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          // Mini grid
          Expanded(
            flex: 3,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 1,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: 16,
              itemBuilder: (context, index) {
                // Generate a pattern based on checkpoint data
                final hasContent = _generatePreviewPattern(index);
                
                return Container(
                  decoration: BoxDecoration(
                    color: hasContent 
                        ? (widget.isExpanded ? Colors.orangeAccent.withOpacity(0.8) : Colors.blue.withOpacity(0.6))
                        : Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Preview info
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.grid_view,
                  color: Colors.white.withOpacity(0.6),
                  size: 16,
                ),
                const SizedBox(height: 4),
                Text(
                  'Pattern',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _generatePreviewPattern(int index) {
    // Generate a consistent pattern based on checkpoint ID
    final hash = widget.checkpoint.id.hashCode;
    return (hash + index) % 3 == 0;
  }

  Color _getUserColor(String userName) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.orange,
      Colors.pink,
      Colors.cyan,
      Colors.amber,
      Colors.indigo,
    ];
    
    final hash = userName.hashCode;
    return colors[hash.abs() % colors.length];
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
} 