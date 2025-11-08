import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/thread/message.dart';
import '../services/audio_cache_service.dart';
// import '../sequencer_library.dart';

enum LoopMode {
  off,        // No looping
  single,     // Loop single track
  playlist,   // Loop whole playlist
}

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
  String? _lastLoadedFilePath;
  
  // Loop modes: off, single track, or playlist
  LoopMode _loopMode = LoopMode.off;
  
  // Shuffle mode
  bool _shuffleEnabled = false;
  
  // Callbacks for track navigation
  VoidCallback? _onTrackCompleted;
  VoidCallback? _onNextTrack;
  VoidCallback? _onPreviousTrack;

  AudioPlayerState() {
    _setupListeners();
  }

  void _setupListeners() {
    _audioPlayer.playingStream.listen((playing) {
      _isPlaying = playing;
      notifyListeners();
    });

    _audioPlayer.durationStream.listen((duration) {
      _duration = duration ?? Duration.zero;
      notifyListeners();
    });

    _audioPlayer.positionStream.listen((position) {
      _position = position;
      notifyListeners();
    });

    _audioPlayer.playerStateStream.listen((state) {
      _isLoading = state.processingState == ProcessingState.loading ||
                   state.processingState == ProcessingState.buffering;
      notifyListeners();
    });

    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _isPlaying = false;
        notifyListeners();
        _handleTrackCompletion();
      }
    });
  }
  
  void _handleTrackCompletion() {
    if (_loopMode == LoopMode.single) {
      // Replay current track
      _reloadAndPlay();
    } else if (_loopMode == LoopMode.playlist) {
      // Advance to next track (or loop to start)
      _onTrackCompleted?.call();
    } else {
      // No loop - just advance to next or stop
      _onTrackCompleted?.call();
    }
  }

  // void _ensureAudioSession() {}

  // Getters
  String? get currentlyPlayingMessageId => _currentlyPlayingMessageId;
  String? get currentlyPlayingRenderId => _currentlyPlayingRenderId;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  double get downloadProgress => _downloadProgress;
  String? get error => _error;
  Duration get duration => _duration;
  Duration get position => _position;
  LoopMode get loopMode => _loopMode;
  bool get shuffleEnabled => _shuffleEnabled;
  
  // Set callbacks for track navigation
  void setTrackCompletionCallback(VoidCallback? callback) {
    _onTrackCompleted = callback;
  }
  
  void setNextTrackCallback(VoidCallback? callback) {
    _onNextTrack = callback;
  }
  
  void setPreviousTrackCallback(VoidCallback? callback) {
    _onPreviousTrack = callback;
  }
  
  // Cycle through loop modes: off -> single -> playlist -> off
  void toggleLoopMode() {
    switch (_loopMode) {
      case LoopMode.off:
        _loopMode = LoopMode.single;
        break;
      case LoopMode.single:
        _loopMode = LoopMode.playlist;
        break;
      case LoopMode.playlist:
        _loopMode = LoopMode.off;
        break;
    }
    notifyListeners();
  }
  
  // Toggle shuffle mode
  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    debugPrint('🔀 Shuffle ${_shuffleEnabled ? "enabled" : "disabled"}');
    notifyListeners();
  }
  
  // Trigger next track
  void playNext() {
    _onNextTrack?.call();
  }
  
  // Trigger previous track
  void playPrevious() {
    _onPreviousTrack?.call();
  }

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

  // Check if track is at end or completed
  bool get _isTrackAtEnd {
    return _audioPlayer.processingState == ProcessingState.completed ||
           (_duration.inMilliseconds > 0 && 
            _position.inMilliseconds >= _duration.inMilliseconds - 100);
  }

  // Reload a completed track from cached file path
  Future<void> _reloadAndPlay() async {
    _isPlaying = true;
    _position = Duration.zero;
    notifyListeners();
    
    if (_lastLoadedFilePath != null) {
      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(_lastLoadedFilePath!);
    }
    
    await _audioPlayer.play();
  }

  /// Play a render from a message (library, thread, or profile)
  Future<void> playRender({
    required String messageId,
    required Render render,
    String? localPathIfRecorded,
  }) async {
    try {
      // Pause if already playing this render
      if (isPlayingRender(messageId, render.id)) {
        await _audioPlayer.pause();
        return;
      }

      // Resume or reload if same render is loaded but not playing
      if (_currentlyPlayingMessageId == messageId && 
          _currentlyPlayingRenderId == render.id && 
          !_isPlaying) {
        if (_isTrackAtEnd) {
          await _reloadAndPlay();
        } else {
          await _audioPlayer.play();
        }
        return;
      }

      // Load new render
      final wasPlaying = _isPlaying;
      _currentlyPlayingMessageId = messageId;
      _currentlyPlayingRenderId = render.id;
      _isLoading = true;
      _isPlaying = false;
      _downloadProgress = 0.0;
      _error = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      notifyListeners();

      if (wasPlaying) {
        await _audioPlayer.stop();
      }

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
        return;
      }

      _lastLoadedFilePath = playablePath;
      await _audioPlayer.setFilePath(playablePath);
      
      // Optimistically set playing state
      _isLoading = false;
      _isPlaying = true;
      notifyListeners();
      
      await _audioPlayer.play();
      
    } catch (e) {
      _error = 'Error: $e';
      _isLoading = false;
      _isPlaying = false;
      notifyListeners();
    }
  }

  /// Seek to a specific position
  Future<void> seek(Duration position) async {
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      // Silently handle seek errors
    }
  }

  /// Pause playback
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
    } catch (e) {
      // Silently handle pause errors
    }
  }

  /// Resume playback (used by bottom audio player)
  Future<void> resume() async {
    try {
      if (_isTrackAtEnd) {
        await _reloadAndPlay();
      } else {
        await _audioPlayer.play();
      }
    } catch (e) {
      // Silently handle resume errors
    }
  }

  /// Stop playback
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _isPlaying = false;
      _currentlyPlayingMessageId = null;
      _currentlyPlayingRenderId = null;
      _lastLoadedFilePath = null;
      _position = Duration.zero;
      notifyListeners();
    } catch (e) {
      // Silently handle stop errors
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
