import 'package:flutter/foundation.dart';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import '../ffi/playback_bindings.dart';
import '../models/thread/message.dart';
import '../services/audio_cache_service.dart';

/// State for playing audio from messages (renders)
/// Uses the same native playback system as recording preview
class AudioPlayerState extends ChangeNotifier {
  final PlaybackBindings _playback = PlaybackBindings();
  
  String? _currentlyPlayingMessageId;
  String? _currentlyPlayingRenderId;
  bool _isPlaying = false;
  bool _isLoading = false;
  double _downloadProgress = 0.0;
  String? _error;

  // Getters
  String? get currentlyPlayingMessageId => _currentlyPlayingMessageId;
  String? get currentlyPlayingRenderId => _currentlyPlayingRenderId;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  double get downloadProgress => _downloadProgress;
  String? get error => _error;

  bool isPlayingRender(String messageId, String renderId) {
    return _currentlyPlayingMessageId == messageId && 
           _currentlyPlayingRenderId == renderId && 
           _isPlaying;
  }

  bool isLoadingRender(String messageId, String renderId) {
    return _currentlyPlayingMessageId == messageId && 
           _currentlyPlayingRenderId == renderId && 
           _isLoading;
  }

  /// Play a render from a message
  Future<void> playRender({
    required String messageId,
    required Render render,
    String? localPathIfRecorded,
  }) async {
    try {
      // If already playing this render, stop it
      if (isPlayingRender(messageId, render.id)) {
        stop();
        return;
      }

      // Stop any currently playing audio
      if (_isPlaying) {
        stop();
      }

      _currentlyPlayingMessageId = messageId;
      _currentlyPlayingRenderId = render.id;
      _isLoading = true;
      _downloadProgress = 0.0;
      _error = null;
      notifyListeners();

      debugPrint('🎵 [AUDIO_PLAYER] Loading render: ${render.url}');

      // Get playable path (local file or download and cache)
      final playablePath = await AudioCacheService.getPlayablePath(
        render,
        localPathIfRecorded: localPathIfRecorded,
        onProgress: (progress) {
          _downloadProgress = progress;
          notifyListeners();
        },
      );

      if (playablePath == null) {
        _error = 'Failed to load audio';
        _isLoading = false;
        notifyListeners();
        debugPrint('❌ [AUDIO_PLAYER] Failed to get playable path');
        return;
      }

      _isLoading = false;
      notifyListeners();

      // Play using native playback (volume 1.0, pitch 1.0)
      final pathPtr = playablePath.toNativeUtf8();
      final result = _playback.previewSamplePath(pathPtr, 1.0, 1.0);
      malloc.free(pathPtr);

      if (result == 0) {
        _isPlaying = true;
        notifyListeners();
        debugPrint('▶️ [AUDIO_PLAYER] Playing: $playablePath');
        
        // Note: In production, you'd want to listen for playback completion
        // and automatically stop. For now, user can tap again to stop.
      } else {
        _error = 'Playback failed';
        debugPrint('❌ [AUDIO_PLAYER] Native playback failed: $result');
        notifyListeners();
      }
    } catch (e) {
      _error = 'Error: $e';
      _isLoading = false;
      _isPlaying = false;
      debugPrint('❌ [AUDIO_PLAYER] Error: $e');
      notifyListeners();
    }
  }

  /// Stop playback
  void stop() {
    if (_isPlaying) {
      _playback.previewStopSample();
      _isPlaying = false;
      _currentlyPlayingMessageId = null;
      _currentlyPlayingRenderId = null;
      notifyListeners();
      debugPrint('⏹️ [AUDIO_PLAYER] Stopped playback');
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

