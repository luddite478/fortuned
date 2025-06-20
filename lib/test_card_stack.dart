import 'package:flutter/material.dart';
import 'widgets/stacked_cards_widget.dart';

class TestCardStackPage extends StatelessWidget {
  const TestCardStackPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Stacked Card Centered")),
      body: const StackedCardsWidget(
        numCards: 2,
        cardColors: [Colors.red, Colors.orange],
        cardWidthFactor: 0.99,
        cardHeightFactor: 0.5,
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  final int rows;
  final int columns;
  final Color color;
  final double strokeWidth;

  GridPainter({
    required this.rows,
    required this.columns,
    required this.color,
    this.strokeWidth = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;

    final rowHeight = size.height / rows;
    final colWidth = size.width / columns;

    for (int i = 1; i < rows; i++) {
      final dy = i * rowHeight;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
  }

    for (int i = 1; i < columns; i++) {
      final dx = i * colWidth;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
