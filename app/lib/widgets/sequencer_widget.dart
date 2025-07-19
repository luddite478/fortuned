import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sequencer/v1/top_multitask_panel_widget.dart';
import 'sequencer/v1/sample_banks_widget.dart'; // Legacy - commented out
import 'sequencer/v1/sound_grid_widget.dart';
import 'sequencer/v1/edit_buttons_widget.dart';
import '../state/sequencer_state.dart';

class SequencerWidget extends StatelessWidget {
  final bool isCompact;
  final VoidCallback? onToggleSize;
  final double? height;
  final double? width;

  const SequencerWidget({
    super.key,
    this.isCompact = false,
    this.onToggleSize,
    this.height,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return _buildCompactView(context);
    } else {
      return _buildFullView(context);
    }
  }

  Widget _buildCompactView(BuildContext context) {
    return Container(
      height: height ?? 120,
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggleSize,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.music_note,
                      color: Colors.orangeAccent,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'SEQUENCER',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    if (onToggleSize != null)
                      Icon(
                        Icons.fullscreen,
                        color: Colors.white.withOpacity(0.7),
                        size: 16,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    children: [
                      // Mini grid representation
                      Expanded(
                        flex: 3,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Consumer<SequencerState>(
                            builder: (context, sequencer, child) {
                              return _buildMiniGrid(sequencer);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Controls preview
                      Expanded(
                        flex: 1,
                        child: Column(
                          children: [
                            Consumer<SequencerState>(
                              builder: (context, sequencer, child) {
                                return Container(
                                  width: double.infinity,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: sequencer.isSequencerPlaying 
                                        ? Colors.greenAccent.withOpacity(0.3)
                                        : Colors.grey.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Icon(
                                    sequencer.isSequencerPlaying 
                                        ? Icons.pause 
                                        : Icons.play_arrow,
                                    color: Colors.white.withOpacity(0.8),
                                    size: 12,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 4),
                            Consumer<SequencerState>(
                              builder: (context, sequencer, child) {
                                return Container(
                                  width: double.infinity,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: sequencer.isRecording 
                                        ? Colors.red.withOpacity(0.3)
                                        : Colors.grey.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Center(
                                    child: Text(
                                      sequencer.isRecording ? 'REC' : 'STOP',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniGrid(SequencerState sequencer) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 1,
          crossAxisSpacing: 1,
          mainAxisSpacing: 1,
        ),
        itemCount: 16, // 4x4 mini grid
        itemBuilder: (context, index) {
          final row = index ~/ 4;
          final col = index % 4;
          final cellIndex = row * sequencer.gridColumns + col;
          
          // Check if this cell has a sample
          final hasSample = sequencer.gridSamples.length > cellIndex && 
                           sequencer.gridSamples[cellIndex] != null;
          
          // Check if this is the current step
          final isCurrentStep = sequencer.isSequencerPlaying && 
                               sequencer.currentStep == col;
          
          return Container(
            decoration: BoxDecoration(
              color: isCurrentStep 
                  ? Colors.orangeAccent.withOpacity(0.8)
                  : hasSample 
                      ? Colors.blue.withOpacity(0.6)
                      : Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(1),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFullView(BuildContext context) {
    return Container(
      height: height,
      width: width,
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenHeight = constraints.maxHeight;
          
          const double multitaskPanelPercent = 20.0;
          const double sampleBanksPercent = 8.0;
          const double sampleGridPercent = 63.0;
          const double editButtonsPercent = 9.0;
          
          final totalContentPercent = multitaskPanelPercent + sampleBanksPercent + 
                                    sampleGridPercent + editButtonsPercent;
          final remainingPercent = 100.0 - totalContentPercent;
          final singleSpacingPercent = remainingPercent / 5;
          
          final multitaskPanelHeight = screenHeight * (multitaskPanelPercent / 100);
          final sampleBanksHeight = screenHeight * (sampleBanksPercent / 100);
          final sampleGridHeight = screenHeight * (sampleGridPercent / 100);
          final editButtonsHeight = screenHeight * (editButtonsPercent / 100);
          final spacingHeight = screenHeight * (singleSpacingPercent / 100);
          
          return Column(
            children: [
              SizedBox(height: spacingHeight),
              SizedBox(
                height: multitaskPanelHeight,
                child: const MultitaskPanelWidget(),
              ),
              SizedBox(height: spacingHeight),
              SizedBox(
                height: sampleBanksHeight,
                child: const SampleBanksWidget(),
              ),
              SizedBox(height: spacingHeight),
              SizedBox(
                height: sampleGridHeight,
                child: const SampleGridWidget(),
              ),
              SizedBox(height: spacingHeight),
              SizedBox(
                height: editButtonsHeight,
                child: const EditButtonsWidget(),
              ),
              SizedBox(height: spacingHeight),
            ],
          );
        },
      ),
    );
  }
} 