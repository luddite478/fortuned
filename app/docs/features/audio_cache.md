# Audio Caching & Playback System

## Overview

Intelligent audio caching system that minimizes bandwidth usage and provides instant playback for recorded and cached audio.

## How It Works

### 1. **Local-First Strategy**
- If user recorded the audio: plays from local filesystem instantly
- If audio was downloaded before: plays from cache instantly  
- Otherwise: downloads from S3 CDN and caches for future use

### 2. **Smart State Management**

#### For the Uploader (Current User):
- ✅ **While uploading**: Shows "Uploading audio..." with spinner
- ✅ **After upload**: Plays from local MP3 file (no download needed)
- ✅ **Cached indicator**: Shows offline pin icon

#### For Other Users:
- ⏳ **Not downloaded yet**: Shows "Tap to play • MP3"
- 🔄 **While downloading**: Shows progress indicator with "Downloading..."
- ✅ **After download**: Shows "Cached • MP3" with offline pin icon
- ▶️ **Playback**: Tap to play, tap again to stop

### 3. **S3 CDN Streaming**
- Uses Digital Ocean Spaces URLs directly (CDN-enabled by default)
- No additional CDN configuration needed
- Fast delivery worldwide

## Architecture

### Components

1. **`AudioCacheService`** (`app/lib/services/audio_cache_service.dart`)
   - Manages local cache directory
   - Downloads and caches audio from S3
   - Checks if audio is already cached
   - Provides cache management (clear cache, get size)

2. **`AudioPlayerState`** (`app/lib/state/audio_player_state.dart`)
   - Manages audio playback
   - Tracks currently playing audio
   - Shows download progress
   - Uses native FFI playback bindings

3. **Thread UI** (`app/lib/screens/thread_screen.dart`)
   - Displays render buttons with appropriate states
   - Shows upload progress for sender
   - Shows download progress for receivers
   - Cached indicator for all cached audio

## User Experience

### Scenario 1: User Records and Sends Audio
```
1. Record audio → Convert to MP3 → Press send
2. Message sent immediately with snapshot
3. Audio upload starts in background
4. UI shows "Uploading audio..." with spinner
5. Upload completes → Audio attached to message
6. User can play instantly from local file
```

### Scenario 2: Another User Wants to Play Audio
```
1. See message with "Tap to play • MP3"
2. Tap audio button
3. Download starts (shows progress)
4. "Downloading..." with circular progress
5. Download completes → Cached
6. Audio plays automatically
7. Future plays are instant (from cache)
```

### Scenario 3: Trying to Play While Still Uploading
```
1. Another user sees the message
2. No renders available yet (still uploading)
3. UI shows snapshot preview only
4. Once upload completes, render appears
5. Can then download and play
```

## Cache Management

### Cache Location
- **Android**: `/storage/emulated/0/Download/{APP_NAME}_data/audio_cache/`
- **iOS**: `{temp}/APP_NAME/audio_cache/`
- **macOS**: `~/Documents/APP_NAME/audio_cache/`
- **Windows**: `{USERPROFILE}\Documents\APP_NAME\audio_cache\`

### Cache Operations

```dart
// Check if audio is cached
final isCached = await AudioCacheService.isCached(url);

// Get cache size
final sizeBytes = await AudioCacheService.getCacheSize();
final sizeStr = AudioCacheService.formatCacheSize(sizeBytes); // "2.3 MB"

// Clear cache
await AudioCacheService.clearCache();
```

## Benefits

1. **Bandwidth Savings**: Downloads once, plays forever
2. **Instant Playback**: Local recordings play immediately
3. **Offline Capable**: Cached audio works without internet
4. **Smart UX**: Different indicators for different states
5. **CDN Performance**: Fast delivery via Digital Ocean CDN

## Performance

- **Upload**: Background upload, non-blocking UI
- **Download**: Progress indicator, ~1-2 seconds for typical audio
- **Playback**: Instant for cached/local, native performance
- **Storage**: Efficient - only downloads what's played

## Technical Details

### Upload Flow
1. Recording converted to MP3 (320kbps)
2. Message sent with snapshot (no blocking)
3. Upload starts in background via `UploadService`
4. S3 receives file → Returns public CDN URL
5. Render attached to message in database
6. UI updates with render button

### Download & Cache Flow
1. User taps render button
2. Check local cache first
3. If not cached: download from S3 URL
4. Stream to local file with progress updates
5. Cache URL → local path mapping
6. Play from local file

### S3 CDN
- Digital Ocean Spaces includes CDN by default
- No additional configuration needed
- URLs like: `https://nyc3.digitaloceanspaces.com/bucket/renders/...`
- Automatic global distribution

## Future Enhancements

- [ ] Auto-cleanup of old cache (LRU)
- [ ] Cache size limits
- [ ] Prefetching for next messages
- [ ] Waveform visualization
- [ ] Audio trimming/editing

