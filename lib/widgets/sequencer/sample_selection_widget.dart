import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sequencer_state.dart';

class SampleSelectionWidget extends StatelessWidget {
  const SampleSelectionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencerState, child) {
        return Container(
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 0, 0, 0),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.cyanAccent.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: _buildSampleBrowser(context, sequencerState),
        );
      },
    );
  }

  Widget _buildSampleBrowser(BuildContext context, SequencerState sequencerState) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with sample selection info
          Row(
            children: [
              if (sequencerState.currentSamplePath.isNotEmpty) ...[
                GestureDetector(
                  onTap: () => sequencerState.navigateBackInSamples(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, color: Colors.grey, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'BACK',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  sequencerState.currentSamplePath.isEmpty 
                      ? 'samples/' 
                      : 'samples/${sequencerState.currentSamplePath.join('/')}/',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => sequencerState.cancelSampleSelection(),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.red,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Horizontal scrollable sample list showing 3 full items + partial 4th
          Expanded(
            child: sequencerState.currentSampleItems.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open,
                          color: Colors.grey,
                          size: 24,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Loading samples...',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Calculate item width: show 3 full items + 40% of 4th item
                      final itemWidth = (constraints.maxWidth - 24) / 3.4; // 3 items + 0.4 of next + margins
                      
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: sequencerState.currentSampleItems.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            
                            return Container(
                              width: itemWidth,
                              height: constraints.maxHeight,
                              margin: EdgeInsets.only(right: index < sequencerState.currentSampleItems.length - 1 ? 8 : 0),
                              child: GestureDetector(
                                onTap: () => sequencerState.selectSampleItem(item),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: item.isFolder 
                                        ? Colors.blue.withOpacity(0.2)
                                        : Colors.green.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: item.isFolder 
                                          ? Colors.blue.withOpacity(0.4)
                                          : Colors.green.withOpacity(0.5),
                                      width: 1,
                                    ),
                                  ),
                                  child: item.isFolder 
                                      ? // Folder layout
                                        LayoutBuilder(
                                          builder: (context, itemConstraints) {
                                            final iconSize = itemConstraints.maxHeight * 0.3; // 30% of height
                                            final fontSize = itemConstraints.maxHeight * 0.12; // 12% of height
                                            
                                            return Center(
                                              child: Padding(
                                                padding: EdgeInsets.all(itemConstraints.maxHeight * 0.08), // 8% padding
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.folder,
                                                      color: Colors.blue,
                                                      size: iconSize.clamp(16.0, 32.0), // min 16, max 32
                                                    ),
                                                    SizedBox(height: itemConstraints.maxHeight * 0.08),
                                                    Flexible(
                                                      child: Text(
                                                        item.name,
                                                        style: TextStyle(
                                                          color: Colors.lightBlue,
                                                          fontSize: fontSize.clamp(8.0, 14.0), // min 8, max 14
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                        textAlign: TextAlign.center,
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        )
                                      : // File layout
                                        LayoutBuilder(
                                          builder: (context, itemConstraints) {
                                            final iconSize = itemConstraints.maxHeight * 0.2; // 20% of height for icon
                                            final fontSize = itemConstraints.maxHeight * 0.15; // 15% of height for bigger text
                                            final topSectionHeight = itemConstraints.maxHeight * 0.5; // Top 35% for play button
                                            final bottomSectionHeight = itemConstraints.maxHeight * 0.5; // Bottom 65% for text
                                            
                                            return Column(
                                              children: [
                                                // Top section - Play button area (easily controllable)
                                                Container(
                                                  height: topSectionHeight,
                                                  decoration: BoxDecoration(
                                                    color: Colors.purple.withOpacity(0.2), // Colored background to see the section
                                                    borderRadius: BorderRadius.only(
                                                      topLeft: Radius.circular(8),
                                                      topRight: Radius.circular(8),
                                                    ),
                                                  ),
                                                  child: Center(
                                                    child: GestureDetector(
                                                      onTap: () => sequencerState.previewSample(item.path),
                                                      child: Container(
                                                        padding: EdgeInsets.all(iconSize * 0.3),
                                                        decoration: BoxDecoration(
                                                          color: const Color.fromARGB(66, 33, 99, 51).withOpacity(0.6),
                                                          borderRadius: BorderRadius.circular(iconSize * 0.6),
                                                        ),
                                                        child: Icon(
                                                          Icons.play_arrow,
                                                          color: Colors.white,
                                                          size: iconSize.clamp(12.0, 20.0), // min 12, max 20
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                // Bottom section - Text/pick surface (easily controllable)
                                                Container(
                                                  height: bottomSectionHeight,
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withOpacity(0.2), // Colored background to see the section
                                                    borderRadius: BorderRadius.only(
                                                      bottomLeft: Radius.circular(8),
                                                      bottomRight: Radius.circular(8),
                                                    ),
                                                  ),
                                                  padding: EdgeInsets.symmetric(horizontal: itemConstraints.maxHeight * 0.08),
                                                  child: Center(
                                                    child: Text(
                                                      item.name,
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: fontSize.clamp(6.0, 18.0), // min 6, max 12
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                      textAlign: TextAlign.center,
                                                      maxLines: 3,
                                                      overflow: TextOverflow.ellipsis,
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
                          }).toList(),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
} 