import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'table.dart';
import 'playback.dart';
import 'sample_bank.dart';
import 'undo_redo.dart';

/// Ticker-based timer for efficient native state synchronization
/// 
/// This state handles frame-by-frame updates from native layer using Flutter's
/// Ticker system. It queries changed cells from native and updates ValueNotifiers
/// to trigger minimal UI refreshes.
class TimerState {
  Ticker? _ticker;
  final TableState tableState;
  final PlaybackState playbackState;
  final SampleBankState sampleBankState;
  final UndoRedoState undoRedoState;
  
  bool _isRunning = false;
  int _frameCount = 0;
  
  TimerState({
    required this.tableState,
    required this.playbackState,
    required this.sampleBankState,
    required this.undoRedoState,
  });
  
  void start() {
    if (_isRunning) return;
    
    _ticker = Ticker(_onTick);
    _ticker!.start();
    _isRunning = true;
    
    debugPrint('⏰ [TIMER_STATE] Started timer system');
  }
  
  void stop() {
    if (!_isRunning) return;
    
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _isRunning = false;
    
    debugPrint('⏹️ [TIMER_STATE] Stopped timer system');
  }
  
  /// Called every frame by Flutter's Ticker
  void _onTick(Duration elapsed) {
    _frameCount++;
    
    try {
      tableState.syncTableState();
      playbackState.syncPlaybackState();
      sampleBankState.syncSampleBankState();
      undoRedoState.syncFromNative();
      
      // Debug logging every 60 frames (~1 second at 60fps)
      if (_frameCount % 60 == 0) {
        debugPrint('⏰ [TIMER_STATE] Frame $_frameCount');
      }
    } catch (e) {
      debugPrint('❌ [TIMER_STATE] Error in tick: $e');
    }
  }
  
  void dispose() {
    stop();
    debugPrint('🧹 [TIMER_STATE] Disposed timer state');
  }
  
  bool get isRunning => _isRunning;
  int get frameCount => _frameCount;
}
