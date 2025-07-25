import 'package:flutter/material.dart';

// Custom ScrollPhysics to retain position when content changes
class PositionRetainedScrollPhysics extends ScrollPhysics {
  final bool shouldRetain;
  const PositionRetainedScrollPhysics({super.parent, this.shouldRetain = true});

  @override
  PositionRetainedScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return PositionRetainedScrollPhysics(
      parent: buildParent(ancestor),
      shouldRetain: shouldRetain,
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final position = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );

    final diff = newPosition.maxScrollExtent - oldPosition.maxScrollExtent;

    // Always retain position when content is added (diff > 0), regardless of scroll position
    if (diff > 0 && shouldRetain) {
      return position + diff;
    } else {
      return position;
    }
  }
}

class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  int _itemCount = 5; // Starting number of items
  static const int _minItems = 1;
  static const int _maxItems = 20;
  static const double _itemHeight = 80.0;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _increaseSize() {
    if (_itemCount < _maxItems) {
      setState(() {
        _itemCount++;
      });
    }
  }

  void _decreaseSize() {
    if (_itemCount > _minItems) {
      setState(() {
        _itemCount--;
      });
    }
  }

  Widget _buildItem(int index) {
    return Container(
      height: _itemHeight,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue[100 + (index * 100) % 500],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[300]!, width: 1),
      ),
      child: Center(
        child: Text(
          'Item ${index + 1}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F2937),
      appBar: AppBar(
        title: const Text('Growing Element with Scroll'),
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Info panel
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF374151),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Current items: $_itemCount (scroll to see buttons move with content)',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          // Scrollable growing element with attached buttons
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              physics: const PositionRetainedScrollPhysics(), // Prevents jumping when content changes
              itemCount: _itemCount + 1, // +1 for the buttons container
              itemBuilder: (context, index) {
                if (index < _itemCount) {
                  // Regular items - they represent the growing element
                  return _buildItem(index);
                } else {
                  // Buttons container - attached to the bottom of the growing element
                  return Container(
                    padding: const EdgeInsets.all(24),
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF374151),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey, width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Decrease size button
                        ElevatedButton.icon(
                          onPressed: _itemCount > _minItems ? _decreaseSize : null,
                          icon: const Icon(Icons.remove),
                          label: const Text('Remove'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        // Increase size button
                        ElevatedButton.icon(
                          onPressed: _itemCount < _maxItems ? _increaseSize : null,
                          icon: const Icon(Icons.add),
                          label: const Text('Add'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
} 