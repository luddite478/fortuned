import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';

/// Custom sections chain widget for message tiles
/// Shows sections as rectangles with layer divisions in the header
/// and steps/loops counters in the bottom
/// Horizontally scrollable like the old chain
class MessageSectionsChain extends StatelessWidget {
  final int sectionsCount;
  final List<int> stepsPerSection;
  final List<int> loopsPerSection;
  final List<int> layersPerSection;
  
  // Sizing constants similar to old widget
  static const double rectangleSizePercentOfHeight = 0.85; // ~85% of container height (bigger)
  static const double rectangleHorizontalMarginPercent = 0.06; // 6% margin on each side (less margin = bigger)
  static const double rectangleMinWidth = 40.0; // Minimum width for rectangle (increased)
  static const double layerColumnMinWidth = 14.0; // Minimum width per layer column (increased)

  const MessageSectionsChain({
    super.key,
    required this.sectionsCount,
    required this.stepsPerSection,
    required this.loopsPerSection,
    required this.layersPerSection,
  });

  @override
  Widget build(BuildContext context) {
    if (sectionsCount == 0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight <= 0 ? 24.0 : constraints.maxHeight;
        final normalizedPercent = rectangleSizePercentOfHeight > 1.0
            ? (rectangleSizePercentOfHeight > 100.0 ? 1.0 : rectangleSizePercentOfHeight / 100.0)
            : rectangleSizePercentOfHeight;
        final double baseHeight = (h * normalizedPercent).clamp(12.0, h);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(sectionsCount, (sectionIndex) {
              final layers = layersPerSection[sectionIndex];
              final steps = stepsPerSection[sectionIndex];
              final loops = loopsPerSection[sectionIndex];

              return _buildSectionRectangle(
                context,
                layersCount: layers,
                stepsCount: steps,
                loopsCount: loops,
                baseHeight: baseHeight,
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildSectionRectangle(
    BuildContext context, {
    required int layersCount,
    required int stepsCount,
    required int loopsCount,
    required double baseHeight,
  }) {
    final int clampedLayers = layersCount.clamp(1, 12);
    
    // Width grows with number of layers
    final double minLayerWidth = layerColumnMinWidth;
    final double baseWidth = (clampedLayers * minLayerWidth).clamp(rectangleMinWidth, double.infinity);
    final double horizontalMargin = baseWidth * rectangleHorizontalMarginPercent;

    return Container(
      width: baseWidth,
      height: baseHeight,
      margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
      child: _SectionRectangle(
        height: baseHeight,
        layersCount: clampedLayers,
        stepsCount: stepsCount,
        loopsCount: loopsCount,
      ),
    );
  }
}

class _SectionRectangle extends StatelessWidget {
  final double height;
  final int layersCount;
  final int stepsCount;
  final int loopsCount;

  const _SectionRectangle({
    required this.height,
    required this.layersCount,
    required this.stepsCount,
    required this.loopsCount,
  });

  @override
  Widget build(BuildContext context) {
    // Split height: 30% for layers header, 70% for counters (via Expanded)
    final double headerHeight = height * 0.30;

    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 102, 102, 102),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // Top part: Layers header with indices (1, 2, 3, 4...)
            Container(
              height: headerHeight,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: List.generate(layersCount, (layerIndex) {
                  return Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: layerIndex < layersCount - 1
                              ? BorderSide(
                                  color: AppColors.sequencerBorder,
                                  width: 0.5,
                                )
                              : BorderSide.none,
                        ),
                      ),
                      clipBehavior: Clip.hardEdge,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(1),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${layerIndex + 1}',
                          style: GoogleFonts.sourceSans3(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            height: 1.0,
                            letterSpacing: 0,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Bottom part: Loops and steps on one line (loops steps)
            Expanded(
              child: Container(
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(),
                padding: const EdgeInsets.all(2),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Text(
                      '$loopsCount $stepsCount',
                      style: GoogleFonts.sourceSans3(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                        letterSpacing: 0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

