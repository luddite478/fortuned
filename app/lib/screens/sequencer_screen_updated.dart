import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/sequencer/table.dart';
import '../state/sequencer/playback.dart';
import '../state/sequencer/sample_bank.dart';
import '../state/sequencer/timer.dart';
import '../state/sequencer/sample_browser.dart';
import '../widgets/sequencer_updated/simplified_sound_grid.dart';
import '../widgets/sequencer_updated/simplified_sample_bank.dart';
import '../widgets/sequencer_updated/playback_controls.dart';
import '../utils/app_colors.dart';

/// Simplified sequencer screen for testing new native backend
/// 
/// This screen contains only the essential elements:
/// - Sample bank widget (top)
/// - Sound grid widget (middle)  
/// - Playback controls (bottom)
/// 
/// Features:
/// - 1 section with 4 layers (sound grids)
/// - Direct native state access via FFI pointers
/// - Efficient UI updates using ValueNotifiers
/// - A/B node switching for smooth audio playback
class SequencerScreenUpdated extends StatefulWidget {
  const SequencerScreenUpdated({super.key});

  @override
  State<SequencerScreenUpdated> createState() => _SequencerScreenUpdatedState();
}

class _SequencerScreenUpdatedState extends State<SequencerScreenUpdated> {
  late final TableState _tableState;
  late final PlaybackState _playbackState;
  late final SampleBankState _sampleBankState;
  late final SampleBrowserState _sampleBrowserState;
  late final TimerState _timerState;

  @override
  void initState() {
    super.initState();
    
    debugPrint('🎵 [SEQUENCER_UPDATED] Initializing sequencer screen');
    
    // Initialize states in dependency order
    _tableState = TableState();
    _playbackState = PlaybackState(_tableState);
    _sampleBankState = SampleBankState();
    _sampleBrowserState = SampleBrowserState();
    
    // Initialize timer with dependencies
    _timerState = TimerState(
      tableState: _tableState,
      playbackState: _playbackState,
    );
    
    // Start the timer system for change tracking and sample browser
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _timerState.start();
      _sampleBrowserState.initialize();
    });
  }

  @override
  void dispose() {
    debugPrint('🧹 [SEQUENCER_UPDATED] Disposing sequencer screen');
    
    _timerState.dispose();
    _tableState.dispose();
    _playbackState.dispose();
    _sampleBankState.dispose();
    _sampleBrowserState.dispose();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _tableState),
        ChangeNotifierProvider.value(value: _playbackState),
        ChangeNotifierProvider.value(value: _sampleBankState),
        ChangeNotifierProvider.value(value: _sampleBrowserState),
      ],
      child: Scaffold(
        backgroundColor: AppColors.sequencerPageBackground,
        appBar: AppBar(
          title: const Text('Sequencer Updated'),
          backgroundColor: AppColors.sequencerPageBackground,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            // Section loops controls
            Consumer<PlaybackState>(
              builder: (context, playbackState, child) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Loops: ',
                      style: const TextStyle(fontSize: 12),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove, size: 16),
                      onPressed: () {
                        final currentLoops = playbackState.currentSectionLoopsNum;
                        if (currentLoops > PlaybackState.minLoopsPerSection) {
                          playbackState.setSectionLoopsNum(
                            playbackState.currentSection, 
                            currentLoops - 1
                          );
                        }
                      },
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      padding: EdgeInsets.zero,
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: playbackState.currentSectionLoopsNumNotifier,
                      builder: (context, loops, child) {
                        return Container(
                          width: 32,
                          child: Text(
                            '$loops',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 16),
                      onPressed: () {
                        final currentLoops = playbackState.currentSectionLoopsNum;
                        if (currentLoops < PlaybackState.maxLoopsPerSection) {
                          playbackState.setSectionLoopsNum(
                            playbackState.currentSection, 
                            currentLoops + 1
                          );
                        }
                      },
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                );
              },
            ),
            // Debug info
            Consumer2<TableState, PlaybackState>(
              builder: (context, tableState, playbackState, child) {
                return Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Center(
                    child: Text(
                      'S${tableState.uiSelectedSection + 1}/${tableState.sectionsCount} | ${playbackState.currentSectionLoop + 1}/${playbackState.currentSectionLoopsNum}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Sample Bank (top section)
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: const SimplifiedSampleBank(),
              ),
              
              // Sound Grid (main content)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: const SimplifiedSoundGrid(),
                ),
              ),
              
              // Playback Controls (bottom section)
              Container(
                height: 96,
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: AppColors.sequencerSurfaceBase,
                  border: Border(
                    top: BorderSide(
                      color: AppColors.sequencerBorder,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Section switcher (previous/next) at bottom
                    Consumer2<TableState, PlaybackState>(
                      builder: (context, tableState, playbackState, child) {
                        final currentSection = tableState.uiSelectedSection;
                        final sectionsCount = tableState.sectionsCount;
                        final hasPrev = currentSection > 0;
                        final hasNext = currentSection < (sectionsCount - 1);
                        void switchToPrev() {
                          playbackState.switchToPreviousSection();
                          tableState.setUiSelectedSection(playbackState.currentSection);
                        }
                        void switchToNext() {
                          playbackState.switchToNextSection();
                          tableState.setUiSelectedSection(playbackState.currentSection);
                        }
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (hasPrev) switchToPrev();
                              },
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.chevron_left,
                                  size: 18,
                                  color: hasPrev ? AppColors.sequencerLightText : AppColors.sequencerLightText.withOpacity(0.3),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                // Delegate logic to PlaybackState wrappers only
                                switchToNext();
                              },
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: hasNext || sectionsCount == 1
                                      ? AppColors.sequencerLightText
                                      : AppColors.sequencerLightText.withOpacity(0.3),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Transform.scale(
                          scale: 0.88,
                          alignment: Alignment.centerLeft,
                          child: const PlaybackControls(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
