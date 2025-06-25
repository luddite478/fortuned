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
          
          // Horizontal scrollable sample list
          Expanded(
            child: sequencerState.currentSampleItems.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open,
                          color: Colors.grey,
                          size: 32,
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
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: sequencerState.currentSampleItems.map((item) {
                        return GestureDetector(
                          onTap: () => sequencerState.selectSampleItem(item),
                          child: Container(
                            width: 100,
                            height: double.infinity,
                            margin: const EdgeInsets.only(right: 8),
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
                                ? // Folder layout - keep simple centered design
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.folder,
                                            color: Colors.blue,
                                            size: 24,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            item.name,
                                            style: const TextStyle(
                                              color: Colors.lightBlue,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : // File layout - independent positioning
                                  Stack(
                                    children: [
                                      // Play button - positioned independently
                                      Positioned(
                                        top: 20, // Adjust this value to move play button up/down
                                        left: 0,
                                        right: 0,
                                        child: Center(
                                          child: GestureDetector(
                                            onTap: () => sequencerState.previewSample(item.path),
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.withOpacity(0.3),
                                                borderRadius: BorderRadius.circular(16),
                                              ),
                                              child: Icon(
                                                Icons.play_arrow,
                                                color: Colors.green.withOpacity(0.7),
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // File name - positioned independently
                                      Positioned(
                                        bottom: 8, // Adjust this value to move text up/down
                                        left: 8,
                                        right: 8,
                                        child: Text(
                                          item.name,
                                          style: const TextStyle(
                                            color: Colors.lightGreen,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
} 