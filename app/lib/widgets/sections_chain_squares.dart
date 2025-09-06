import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';

class SectionsChainSquares extends StatelessWidget {
  final List<int> loopsPerSection;
  final List<int> layersPerSection;
  final double? squareSize;
  final double? connectorWidth;

  const SectionsChainSquares({
    super.key,
    required this.loopsPerSection,
    required this.layersPerSection,
    this.squareSize,
    this.connectorWidth,
  });

  @override
  Widget build(BuildContext context) {
    final count = loopsPerSection.length;
    if (count == 0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight <= 0 ? 24.0 : constraints.maxHeight;
        final s = squareSize ?? (h * 0.65).clamp(18.0, 28.0);
        final c = connectorWidth ?? (s * 0.6).clamp(8.0, 16.0);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(count * 2 - 1, (i) {
              if (i.isEven) {
                final idx = i ~/ 2;
                final loops = loopsPerSection[idx];
                final layers = idx < layersPerSection.length ? layersPerSection[idx] : 0;
                return _buildSquare(context, loops, layers, s);
              } else {
                return _buildConnector(c);
              }
            }),
          ),
        );
      },
    );
  }

  Widget _buildSquare(BuildContext context, int loops, int layers, double s) {
    return Container(
      width: s,
      height: s,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF5A6F72),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.menuBorder, width: 1),
      ),
      child: Center(
        child: Text(
          '${layers}\n${loops}',
          textAlign: TextAlign.center,
          style: GoogleFonts.sourceSans3(
            color: Colors.white,
            fontSize: (s * 0.35).clamp(7, 12),
            fontWeight: FontWeight.w700,
            height: 0.9,
          ),
        ),
      ),
    );
  }

  Widget _buildConnector(double c) {
    return Container(
      width: c,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: AppColors.menuLightText,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}


