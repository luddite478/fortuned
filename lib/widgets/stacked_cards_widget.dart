import 'package:flutter/material.dart';

class StackedCardsWidget extends StatelessWidget {
  final int numCards;
  final List<Color> cardColors;
  final double cardWidthFactor;
  final double cardHeightFactor;
  final Offset offsetPerDepth;
  final double scaleFactorPerDepth;
  final double borderRadius;
  final List<Widget>? cardContents;
  final double shadowBlurRadius;
  final Offset shadowOffset;
  final double shadowOpacity;
  final Widget Function(int index, double width, double height, int depth)? cardBuilder;
  final int? activeCardIndex;

  const StackedCardsWidget({
    super.key,
    this.numCards = 3,
    this.cardColors = const [
      Colors.red,
      Colors.orange,
      Colors.green,
      Colors.teal,
      Colors.indigo,
    ],
    this.cardWidthFactor = 0.99,
    this.cardHeightFactor = 0.5,
    this.offsetPerDepth = const Offset(5, -5),
    this.scaleFactorPerDepth = 0.001,
    this.borderRadius = 12.0,
    this.cardContents,
    this.shadowBlurRadius = 4.0,
    this.shadowOffset = const Offset(0, 2),
    this.shadowOpacity = 0.2,
    this.cardBuilder,
    this.activeCardIndex,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;
        final cardWidth = availableWidth * cardWidthFactor;
        final cardHeight = availableHeight * cardHeightFactor;

    List<Widget> cards = [];

    for (int i = 0; i < numCards; i++) {
      final depth = numCards - i - 1;
      final scale = 1.0 - (scaleFactorPerDepth * depth);

      final offsetX = offsetPerDepth.dx * depth;
      final offsetY = offsetPerDepth.dy * depth;

      final scaledWidth = cardWidth * scale;
      final scaledHeight = cardHeight * scale;

      final left = (availableWidth - scaledWidth) / 2.0 + offsetX;
      final top = (availableHeight - scaledHeight) / 2.0 + offsetY;

      final isActiveCard = activeCardIndex == i;
      
      cards.add(
        Positioned(
          left: left,
          top: top,
          child: cardBuilder != null
              ? cardBuilder!(i, scaledWidth, scaledHeight, depth)
              : Container(
                  width: scaledWidth,
                  height: scaledHeight,
                  decoration: BoxDecoration(
                    color: cardColors[i % cardColors.length].withOpacity(1.0 - 0.1 * depth),
                    borderRadius: BorderRadius.circular(borderRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(shadowOpacity),
                        blurRadius: shadowBlurRadius,
                        offset: shadowOffset,
                      ),
                    ],
                  ),
                  child: cardContents != null && i < cardContents!.length
                      ? cardContents![i]
                      : Center(
                          child: Text(
                            'Card ${i + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 24),
                          ),
                        ),
                ),
        ),
      );
    }

        return Stack(children: cards);
      },
    );
  }
} 