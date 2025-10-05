import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/thread/message.dart';
import '../services/audio_cache_service.dart';

/// State for playing audio from messages (renders)
/// Uses just_audio for full playback control with seeking
class AudioPlayerState extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  String? _currentlyPlayingMessageId;
  String? _currentlyPlayingRenderId;
  bool _isPlaying = false;
  bool _isLoading = false;
  double _downloadProgress = 0.0;
  String? _error;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  AudioPlayerState() {
    _setupListeners();
  }

  void _setupListeners() {
    // Listen to playing state
    _audioPlayer.playingStream.listen((playing) {
      _isPlaying = playing;
      notifyListeners();
    });

    // Listen to duration changes
    _audioPlayer.durationStream.listen((duration) {
      _duration = duration ?? Duration.zero;
      notifyListeners();
    });

    // Listen to position changes
    _audioPlayer.positionStream.listen((position) {
      _position = position;
      notifyListeners();
    });

    // Listen to player state for loading
    _audioPlayer.playerStateStream.listen((state) {
      _isLoading = state.processingState == ProcessingState.loading ||
                   state.processingState == ProcessingState.buffering;
      notifyListeners();
    });

    // Listen to completion
    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _isPlaying = false;
        _position = Duration.zero;
        notifyListeners();
      }
    });
  }

  // Getters
  String? get currentlyPlayingMessageId => _currentlyPlayingMessageId;
  String? get currentlyPlayingRenderId => _currentlyPlayingRenderId;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  double get downloadProgress => _downloadProgress;
  String? get error => _error;
  Duration get duration => _duration;
  Duration get position => _position;

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
      // If already playing this render, pause it
      if (isPlayingRender(messageId, render.id)) {
        await _audioPlayer.pause();
        return;
      }

      // If it's loaded but paused, resume
      if (_currentlyPlayingMessageId == messageId && 
          _currentlyPlayingRenderId == render.id && 
          !_isPlaying) {
        await _audioPlayer.play();
        return;
      }

      // Set loading state BEFORE stopping to prevent flicker
      final wasPlaying = _isPlaying;
      _currentlyPlayingMessageId = messageId;
      _currentlyPlayingRenderId = render.id;
      _isLoading = true;
      _isPlaying = false; // Prevent flicker by setting this immediately
      _downloadProgress = 0.0;
      _error = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      notifyListeners(); // Update UI immediately with loading state

      debugPrint('🎵 [AUDIO_PLAYER] Loading render: ${render.url}');

      // Stop any currently playing audio
      if (wasPlaying) {
        await _audioPlayer.stop();
      }

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

      // Load audio file
      await _audioPlayer.setFilePath(playablePath);
      
      // Start playing
      await _audioPlayer.play();
      
      debugPrint('▶️ [AUDIO_PLAYER] Playing: $playablePath');
      
    } catch (e) {
      _error = 'Error: $e';
      _isLoading = false;
      _isPlaying = false;
      debugPrint('❌ [AUDIO_PLAYER] Error: $e');
      notifyListeners();
    }
  }

  /// Seek to a specific position
  Future<void> seek(Duration position) async {
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      debugPrint('❌ [AUDIO_PLAYER] Seek error: $e');
    }
  }

  /// Stop playback
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _isPlaying = false;
      _currentlyPlayingMessageId = null;
      _currentlyPlayingRenderId = null;
      _position = Duration.zero;
      notifyListeners();
      debugPrint('⏹️ [AUDIO_PLAYER] Stopped playback');
    } catch (e) {
      debugPrint('❌ [AUDIO_PLAYER] Stop error: $e');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
