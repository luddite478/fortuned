import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/threads_state.dart';
import '../state/sequencer_state.dart';

class CheckpointsScreen extends StatefulWidget {
  final String threadId;
  
  const CheckpointsScreen({
    super.key,
    required this.threadId,
  });

  @override
  State<CheckpointsScreen> createState() => _CheckpointsScreenState();
}

class _CheckpointsScreenState extends State<CheckpointsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
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
      appBar: AppBar(
        title: Consumer<ThreadsState>(
          builder: (context, threadsState, child) {
            final thread = threadsState.currentThread;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thread?.title ?? 'Project Checkpoints',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${thread?.users.length ?? 0} collaborators',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[300],
                  ),
                ),
              ],
            );
          },
        ),
        backgroundColor: const Color(0xFF1f2937),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showProjectInfo(context),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: Consumer2<ThreadsState, SequencerState>(
        builder: (context, threadsState, sequencerState, child) {
          final thread = threadsState.currentThread;
          
          if (thread == null) {
            return const Center(
              child: Text(
                'Project not found',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          if (thread.checkpoints.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No checkpoints yet',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 18,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Save your progress to create checkpoints',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: thread.checkpoints.length,
                  itemBuilder: (context, index) {
                    final checkpoint = thread.checkpoints[index];
                    final isCurrentUser = checkpoint.userId == threadsState.currentUserId;
                    
                    return _buildCheckpointMessage(
                      context,
                      checkpoint,
                      isCurrentUser,
                      sequencerState,
                      threadsState,
                    );
                  },
                ),
              ),
              _buildNewCheckpointButton(context, threadsState, sequencerState),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCheckpointMessage(
    BuildContext context,
    ThreadCheckpoint checkpoint,
    bool isCurrentUser,
    SequencerState sequencerState,
    ThreadsState threadsState,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isCurrentUser) ...[
            _buildUserAvatar(checkpoint.userName),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              child: Column(
                crossAxisAlignment: isCurrentUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isCurrentUser)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 4),
                      child: Text(
                        checkpoint.userName,
                        style: TextStyle(
                          color: _getUserColor(checkpoint.userName),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: () => _applyCheckpoint(context, checkpoint, sequencerState),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isCurrentUser 
                            ? const Color(0xFF0084ff) 
                            : const Color(0xFF374151),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Comment text
                          if (checkpoint.comment.isNotEmpty)
                            Text(
                              checkpoint.comment,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          
                          const SizedBox(height: 8),
                          
                          // Sound grid preview
                          _buildSoundGridPreview(checkpoint.snapshot),
                          
                          const SizedBox(height: 8),
                          
                          // Project info
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.audiotrack,
                                      size: 16,
                                      color: Colors.white70,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        checkpoint.snapshot.name,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.schedule,
                                      size: 14,
                                      color: Colors.white60,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatDuration(checkpoint.snapshot.audio.duration),
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Icon(
                                      Icons.layers,
                                      size: 14,
                                      color: Colors.white60,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${checkpoint.snapshot.audio.sources.isNotEmpty ? checkpoint.snapshot.audio.sources.first.scenes.length : 0} scenes',
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Timestamp
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _formatTimestamp(checkpoint.timestamp),
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isCurrentUser) ...[
            const SizedBox(width: 8),
            _buildUserAvatar(checkpoint.userName),
          ],
        ],
      ),
    );
  }

  Widget _buildUserAvatar(String userName) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _getUserColor(userName),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          userName.isNotEmpty ? userName[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildSoundGridPreview(SequencerSnapshot snapshot) {
    if (snapshot.audio.sources.isEmpty || 
        snapshot.audio.sources.first.scenes.isEmpty ||
        snapshot.audio.sources.first.scenes.first.layers.isEmpty) {
      return Container(
        height: 80,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'Empty Project',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    final scene = snapshot.audio.sources.first.scenes.first;
    final layers = scene.layers;
    
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Text(
              'Sound Grid Preview',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Row(
                children: List.generate(
                  layers.length.clamp(0, 4), // Show max 4 layers
                  (layerIndex) {
                    final layer = layers[layerIndex];
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: _getLayerColor(layerIndex),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Column(
                          children: List.generate(
                            layer.rows.length.clamp(0, 8), // Show max 8 rows
                            (rowIndex) {
                              final row = layer.rows[rowIndex];
                              final hasSample = row.cells.any(
                                (cell) => cell.sample?.hasSample == true,
                              );
                              return Expanded(
                                child: Container(
                                  margin: const EdgeInsets.all(0.5),
                                  decoration: BoxDecoration(
                                    color: hasSample 
                                        ? Colors.white.withOpacity(0.8)
                                        : Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewCheckpointButton(
    BuildContext context,
    ThreadsState threadsState,
    SequencerState sequencerState,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _createNewCheckpoint(context, threadsState, sequencerState),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Save Current State'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10b981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            onPressed: () => Navigator.of(context).pop(),
            backgroundColor: const Color(0xFF374151),
            child: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Color _getUserColor(String userName) {
    final colors = [
      const Color(0xFF10b981), // Green
      const Color(0xFF3b82f6), // Blue
      const Color(0xFFf59e0b), // Orange
      const Color(0xFFef4444), // Red
      const Color(0xFF8b5cf6), // Purple
      const Color(0xFF06b6d4), // Cyan
      const Color(0xFFf97316), // Orange
      const Color(0xFFec4899), // Pink
    ];
    
    final hash = userName.hashCode;
    return colors[hash.abs() % colors.length];
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

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  String _formatDuration(double duration) {
    final minutes = (duration / 60).floor();
    final seconds = (duration % 60).floor();
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  void _applyCheckpoint(
    BuildContext context,
    ThreadCheckpoint checkpoint,
    SequencerState sequencerState,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF374151),
        title: const Text(
          'Apply Checkpoint',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will replace your current project with:\n"${checkpoint.comment}"\n\nYour current work will be lost unless saved.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              sequencerState.applySnapshot(checkpoint.snapshot);
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Go back to sequencer
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Applied checkpoint: ${checkpoint.comment}'),
                  backgroundColor: const Color(0xFF10b981),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10b981),
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _createNewCheckpoint(
    BuildContext context,
    ThreadsState threadsState,
    SequencerState sequencerState,
  ) {
    final commentController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF374151),
        title: const Text(
          'Save Checkpoint',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add a comment to describe your changes:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: commentController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'e.g., Added bassline and drums',
                hintStyle: TextStyle(color: Colors.white54),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF10b981)),
                ),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final comment = commentController.text.trim();
              if (comment.isEmpty) return;
              
              try {
                await threadsState.addCheckpointFromSequencer(
                  widget.threadId,
                  comment,
                  sequencerState,
                );
                
                Navigator.of(context).pop();
                
                // Scroll to bottom to show new checkpoint
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Checkpoint saved successfully!'),
                    backgroundColor: Color(0xFF10b981),
                  ),
                );
              } catch (e) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to save checkpoint: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10b981),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showProjectInfo(BuildContext context) {
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    final thread = threadsState.currentThread;
    
    if (thread == null) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF374151),
        title: const Text(
          'Project Info',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Title: ${thread.title}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              'Status: ${thread.status.name}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              'Collaborators (${thread.users.length}):',
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            ...thread.users.map((user) => Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Text(
                '• ${user.name}${thread.users.indexOf(user) == 0 ? ' (Author)' : ''}',
                style: const TextStyle(color: Colors.white60),
              ),
            )),
            const SizedBox(height: 8),
            Text(
              'Checkpoints: ${thread.checkpoints.length}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              'Created: ${_formatDate(thread.createdAt)}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
} 