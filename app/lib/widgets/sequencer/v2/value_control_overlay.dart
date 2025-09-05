import 'package:flutter/material.dart';
// duplicate import removed
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../state/sequencer/slider_overlay.dart';
import '../../../utils/app_colors.dart';

class ValueControlOverlay extends StatelessWidget {
  const ValueControlOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SliderOverlayState>(
      builder: (context, sliderOverlay, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: sliderOverlay.isInteractingNotifier,
          builder: (context, isInteracting, child) {
            if (!isInteracting) {
              return const SizedBox.shrink();
            }

            return Stack(
              children: [
                // Dark overlay background
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.6),
                  ),
                ),
                
                // Value display overlay
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40.0,
                        vertical: 30.0,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.sequencerSurfaceBase.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.sequencerBorder,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.sequencerShadow.withOpacity(0.8),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: AppColors.sequencerSurfaceRaised.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Setting name
                          ValueListenableBuilder<String>(
                            valueListenable: sliderOverlay.settingNameNotifier,
                            builder: (context, setting, child) {
                              return Text(
                                setting,
                                style: GoogleFonts.sourceSans3(
                                  color: AppColors.sequencerLightText,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 1.0,
                                ),
                              );
                            },
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Value display
                          ValueListenableBuilder<String>(
                            valueListenable: sliderOverlay.valueNotifier,
                            builder: (context, value, child) {
                              return Text(
                                value,
                                style: GoogleFonts.sourceSans3(
                                  color: AppColors.sequencerAccent,
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2.0,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
} 