import 'package:flutter/material.dart';
// duplicate import removed
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../state/sequencer/edit.dart';
import '../../../state/sequencer/multitask_panel.dart';
import '../../../utils/app_colors.dart';

class StepInsertSettingsWidget extends StatelessWidget {
  const StepInsertSettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<EditState, MultitaskPanelState>(
      builder: (context, editState, panelState, child) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceBase,
            borderRadius: BorderRadius.circular(2), // Sharp corners
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 0.5,
            ),
            boxShadow: [
              // Protruding effect
              BoxShadow(
                color: AppColors.sequencerShadow,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: AppColors.sequencerSurfaceRaised,
                blurRadius: 1,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final panelHeight = constraints.maxHeight;
              final sliderHeight = panelHeight * 0.7;
              final textHeight = panelHeight * 0.3;
              
              return Column(
                children: [
                  // Title and close button
                  Container(
                    height: textHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Jump Insert: ${editState.stepInsertSize} cells',
                            style: GoogleFonts.sourceSans3(
                              color: AppColors.sequencerText,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => panelState.showPlaceholder(),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              color: AppColors.sequencerLightText,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Slider
                  Container(
                    height: sliderHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          '1',
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.sequencerLightText,
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: AppColors.sequencerAccent,
                              inactiveTrackColor: AppColors.sequencerBorder,
                              thumbColor: AppColors.sequencerAccent,
                              overlayColor: AppColors.sequencerAccent.withOpacity(0.3),
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: editState.stepInsertSize.toDouble(),
                              min: 1,
                              max: 16,
                              divisions: 15,
                              onChanged: (value) {
                                editState.setStepInsertSize(value.round());
                              },
                            ),
                          ),
                        ),
                        Text(
                          '16',
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.sequencerLightText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
} 