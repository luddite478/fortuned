import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/patterns_state.dart';
import '../state/sequencer_state.dart';
import 'sequencer_screen.dart';
import '../test_card_stack.dart';

class PatternSelectionScreen extends StatefulWidget {
  const PatternSelectionScreen({super.key});

  @override
  State<PatternSelectionScreen> createState() => _PatternSelectionScreenState();
}

class _PatternSelectionScreenState extends State<PatternSelectionScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: const Text(
                        'NIYYA SEQUENCER',
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.layers, color: Colors.orangeAccent),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TestCardStackPage(),
                ),
              );
            },
            tooltip: 'Test Card Stack',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
            onPressed: () {
              context.read<PatternsState>().refresh();
            },
            tooltip: 'Refresh Patterns',
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Consumer<PatternsState>(
            builder: (context, patternsState, child) {
              if (patternsState.isLoading) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.cyanAccent),
                );
              }

              if (patternsState.error != null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error,
                        color: Colors.redAccent,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error: ${patternsState.error}',
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => patternsState.refresh(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  // Blank panel for future use (25% of available space)
                  Expanded(
                    flex: 25,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1f2937),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Text(
                          'Future Panel',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Patterns section (takes remaining space)
                  Expanded(
                    flex: 75,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1f2937),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          // Minimalistic title
                          const Text(
                            'PATTERNS',
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Patterns grid
                          Expanded(
                            child: _buildPatternsGrid(patternsState),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPatternsGrid(PatternsState patternsState) {
    // Create list with "NEW PATTERN" button first, then existing patterns
    final List<Widget> patternButtons = [];
    
    // Add "NEW PATTERN" button first
    patternButtons.add(_buildNewPatternButton(patternsState));
    
    // Add existing patterns
    for (final pattern in patternsState.patterns) {
      patternButtons.add(_buildPatternButton(pattern, patternsState));
    }

    return ListView.separated(
      itemCount: patternButtons.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) => patternButtons[index],
    );
  }

  Widget _buildNewPatternButton(PatternsState patternsState) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _createNewPattern(patternsState),
          child: const Center(
            child: Text(
              'NEW PATTERN',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPatternButton(Pattern pattern, PatternsState patternsState) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _selectPattern(pattern),
          onLongPress: () => _showPatternMenu(pattern, patternsState),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    pattern.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _formatDate(pattern.modifiedAt),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'now';
    }
  }

  Future<void> _createNewPattern(PatternsState patternsState) async {
    final pattern = await patternsState.createNewPattern();
    if (pattern != null && mounted) {
      _selectPattern(pattern);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to create pattern'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _selectPattern(Pattern pattern) async {
    final patternsState = context.read<PatternsState>();
    await patternsState.setCurrentPattern(pattern);
    if (mounted && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: patternsState),
                              ChangeNotifierProvider(create: (context) => SequencerState()),
            ],
            child: const PatternScreen(),
          ),
        ),
      );
    }
  }

  void _showPatternMenu(Pattern pattern, PatternsState patternsState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1f2937),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              pattern.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.open_in_new, color: Colors.white),
              title: const Text('Open', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _selectPattern(pattern);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.white),
              title: const Text('Duplicate', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _duplicatePattern(pattern, patternsState);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.redAccent),
              title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteDialog(pattern, patternsState);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _duplicatePattern(Pattern pattern, PatternsState patternsState) async {
    final newPattern = await patternsState.duplicatePattern(pattern.id);
    if (newPattern != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pattern duplicated successfully'),
          duration: Duration(seconds: 1),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to duplicate pattern'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDeleteDialog(Pattern pattern, PatternsState patternsState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1f2937),
        title: const Text('Delete Pattern', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete pattern "${pattern.name}"? This action cannot be undone.',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await patternsState.deletePattern(pattern.id);
              Navigator.pop(context);
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Pattern deleted successfully'),
                    duration: Duration(seconds: 1),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to delete pattern'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
} 