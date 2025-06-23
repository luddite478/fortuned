import 'package:flutter/material.dart';
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
        ],
      ),
      body: SafeArea(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
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
                      // Simple pattern button
                      Expanded(
                        child: _buildSimplePatternButton(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimplePatternButton() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.cyanAccent, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _openSequencer(),
          child: const Center(
            child: Text(
              'OPEN SEQUENCER',
              style: TextStyle(
                color: Colors.cyanAccent,
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openSequencer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PatternScreen(),
      ),
    );
  }
} 