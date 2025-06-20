import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sequencer_state.dart';

class SampleBanksWidget extends StatelessWidget {
  const SampleBanksWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerState>(
      builder: (context, sequencer, child) {
        return Container(
          padding: const EdgeInsets.all(8),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1f2937),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(8, (bank) {
              final isActive = sequencer.activeBank == bank;
              final isSelected = sequencer.selectedSampleSlot == bank;
              final hasFile = sequencer.fileNames[bank] != null;
              final isPlaying = sequencer.slotPlaying[bank];
              
              Widget sampleButton = Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.yellowAccent.withOpacity(0.8) // Selected for placement
                      : isActive
                          ? Colors.white
                          : hasFile
                              ? sequencer.bankColors[bank].withOpacity(0.8)
                              : const Color(0xFF404040),
                  borderRadius: BorderRadius.circular(6),
                  border: isPlaying
                      ? Border.all(color: Colors.greenAccent, width: 2)
                      : isSelected
                          ? Border.all(color: Colors.yellowAccent, width: 2)
                          : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      String.fromCharCode(65 + bank), // A, B, C, etc.
                      style: TextStyle(
                        color: isSelected || isActive ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (hasFile) ...[
                      const SizedBox(height: 2),
                      Icon(
                        Icons.audiotrack,
                        size: 12,
                        color: isSelected || isActive ? Colors.black54 : Colors.white70,
                      ),
                    ],
                  ],
                ),
              );

              return Expanded(
                child: hasFile 
                    ? Draggable<int>(
                        data: bank,
                        feedback: Container(
                          width: 40,
                          height: 60,
                          decoration: BoxDecoration(
                            color: sequencer.bankColors[bank].withOpacity(0.9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                String.fromCharCode(65 + bank),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const Icon(
                                Icons.audiotrack,
                                size: 12,
                                color: Colors.white70,
                              ),
                            ],
                          ),
                        ),
                        childWhenDragging: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: sequencer.bankColors[bank].withOpacity(0.3),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey, width: 1),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                String.fromCharCode(65 + bank),
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Icon(
                                Icons.audiotrack,
                                size: 12,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                        child: GestureDetector(
                          onTap: () => sequencer.handleBankChange(bank, context),
                          onLongPress: () => sequencer.pickFileForSlot(bank, context),
                          child: sampleButton,
                        ),
                      )
                    : GestureDetector(
                        onTap: () => sequencer.handleBankChange(bank, context),
                        onLongPress: () => sequencer.pickFileForSlot(bank, context),
                        child: sampleButton,
                      ),
              );
            }),
          ),
        );
      },
    );
  }
} 