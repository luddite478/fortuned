# Audio Render Upload System

## Overview

The audio render upload system allows users to record audio in the sequencer and automatically attach it to thread messages. Recordings are converted to MP3 format, uploaded to Digital Ocean Spaces (S3-compatible storage), and attached to messages for playback and sharing.

## Architecture

### Components

```
┌─────────────────┐
│   Flutter App   │
│  (Sequencer)    │
└────────┬────────┘
         │ 1. Record Audio
         │ 2. Convert to MP3
         │ 3. Send Message
         ▼
┌─────────────────┐
│  FastAPI Server │
│  (Message API)  │
└────────┬────────┘
         │ 4. Create Message (without render)
         │ 5. Return Message ID
         ▼
┌─────────────────┐
│   Flutter App   │
│ (Upload Service)│
└────────┬────────┘
         │ 6. Upload MP3 to Server
         ▼
┌─────────────────┐
│  FastAPI Server │
│  (Upload API)   │
└────────┬────────┘
         │ 7. Upload to S3
         ▼
┌─────────────────┐
│ Digital Ocean   │
│    Spaces       │
└────────┬────────┘
         │ 8. Return Public URL
         ▼
┌─────────────────┐
│  FastAPI Server │
│  (Attach Render)│
└────────┬────────┘
         │ 9. Update Message with Render
         ▼
┌─────────────────┐
│    MongoDB      │
│   (messages)    │
└─────────────────┘
```

## Data Flow

### 1. Recording and Message Creation

```dart
// User records audio in sequencer
RecordingState.startRecording()
RecordingState.stopRecording()
  → Converts WAV to MP3
  → Stores at: convertedMp3Path

// User presses send
ThreadsState.sendMessageFromSequencer()
  → Creates message with snapshot (no renders)
  → Server returns message with ID
  → Starts background upload with message ID
```

### 2. Background Upload

```dart
ThreadsState._uploadRecordingInBackground(messageId, mp3Path)
  → UploadService.uploadAudio()
    → Multipart HTTP POST to /api/v1/upload/audio
    → Server receives file
    → S3Service.upload_file()
      → boto3.put_object() to Digital Ocean Spaces
      → Returns public URL
    → Returns Render object
  → ThreadsState._attachRenderToMessage(messageId, render)
    → ThreadsApi.attachRenderToMessage()
      → Server updates message in MongoDB
    → Updates local message state
```

### 3. Playback

```dart
// User clicks play button
AudioPlayerState.playRender()
  → Check if local file exists (recorded by current user)
  → If not, check cache via AudioCacheService
  → If not cached, download from S3 URL
  → Play using just_audio (Flutter audio player)
  → Stream position updates for seek bar
  → Support pause/resume and seeking
```

## S3 Configuration

### Environment Variables

```bash
# .env or .prod.env
S3_ENDPOINT_URL=https://{region}.digitaloceanspaces.com  # e.g., fra1, nyc3, sgp1
S3_REGION=us-east-1                                      # Always use us-east-1 for DO Spaces
S3_ACCESS_KEY=YOUR_ACCESS_KEY_HERE
S3_SECRET_KEY=YOUR_SECRET_KEY_HERE
S3_BUCKET_NAME=your-bucket-name
ENV=prod                                                 # or 'stage' for staging
```

### File Storage Structure

```
{BUCKET_NAME}/                         # Your S3 bucket name
├── prod/                              # Environment prefix
│   └── renders/
│       ├── {uuid}.mp3                # Audio render files
│       ├── {uuid}.mp3
│       └── ...
└── stage/                             # Staging environment
    └── renders/
        └── ...
```

### Public URLs

Format: `https://{BUCKET_NAME}.{REGION}.digitaloceanspaces.com/{ENV}/renders/{UUID}.mp3`

Example: `https://your-bucket.fra1.digitaloceanspaces.com/prod/renders/a1b2c3d4-1234-5678-abcd-ef0123456789.mp3`

## API Endpoints

### 1. Upload Audio File

**Endpoint:** `POST /api/v1/upload/audio`

**Request:**
- Method: `multipart/form-data`
- Fields:
  - `token` (string, required): API authentication token
  - `file` (file, required): Audio file (MP3)
  - `format` (string, optional): Audio format (default: "mp3")
  - `bitrate` (integer, optional): Audio bitrate in kbps
  - `duration` (float, optional): Duration in seconds

**Response:**
```json
{
  "id": "a1b2c3d4-1234-5678-abcd-ef0123456789",
  "url": "https://APP_NAME.REGION.digitaloceanspaces.com/prod/renders/a1b2c3d4-1234-5678-abcd-ef0123456789.mp3",
  "format": "mp3",
  "bitrate": 320,
  "duration": 45.5,
  "size_bytes": 1834560,
  "created_at": "2025-10-05T18:30:00Z"
}
```

**Example (Dart):**
```dart
final render = await UploadService.uploadAudio(
  filePath: '/path/to/recording.mp3',
  format: 'mp3',
  bitrate: 320,
  duration: 45.5,
);
```

### 2. Attach Render to Message

**Endpoint:** `POST /api/v1/messages/{message_id}/renders`

**Request:**
```json
{
  "token": "api_token_here",
  "render": {
  "id": "a1b2c3d4-1234-5678-abcd-ef0123456789",
  "url": "https://your-bucket.{region}.digitaloceanspaces.com/prod/renders/a1b2c3d4-1234-5678-abcd-ef0123456789.mp3",
  "format": "mp3",
    "bitrate": 320,
    "duration": 45.5,
    "size_bytes": 1834560,
    "created_at": "2025-10-05T18:30:00Z"
  }
}
```

**Response:**
```json
{
  "status": "render_attached",
  "message_id": "67890abcdef12345"
}
```

## Data Models

### Render Schema

**File:** `schemas/0.0.1/thread/message.json`

```json
{
  "renders": {
    "type": "array",
    "items": {
      "type": "object",
      "properties": {
        "id": { "type": "string" },
        "url": { "type": "string" },
        "format": { "type": "string" },
        "bitrate": { "type": "integer" },
        "duration": { "type": "number" },
        "size_bytes": { "type": "integer" },
        "created_at": { "type": "string" }
      }
    }
  }
}
```

### Dart Model

**File:** `app/lib/models/thread/message.dart`

```dart
class Render {
  final String id;
  final String url;
  final String format;
  final int? bitrate;
  final double? duration;
  final int? sizeBytes;
  final DateTime createdAt;

  // Client-only field (not stored in database)
  final String? uploadStatus;  // 'uploading', 'completed', 'failed'
}

class Message {
  final String id;
  final DateTime createdAt;
  final DateTime timestamp;
  final String userId;
  final String parentThread;
  final Map<String, dynamic> snapshot;
  final Map<String, dynamic>? snapshotMetadata;
  final List<Render> renders;  // Audio renders attached to this message
}
```

## Server Implementation

### S3 Service

**File:** `server/app/storage/s3_service.py`

```python
class S3Service:
    def __init__(self):
        self.endpoint_url = os.getenv("S3_ENDPOINT_URL")
        self.region = os.getenv("S3_REGION")
        self.access_key = os.getenv("S3_ACCESS_KEY")
        self.secret_key = os.getenv("S3_SECRET_KEY")
        self.bucket_name = os.getenv("S3_BUCKET_NAME")
        
        self.client = boto3.client(
            's3',
            endpoint_url=self.endpoint_url,
            aws_access_key_id=self.access_key,
            aws_secret_access_key=self.secret_key,
            region_name=self.region
        )
    
    def upload_file(self, file_data: bytes, file_key: str, 
                   content_type: str = "audio/mpeg") -> Optional[str]:
        """Upload a file to S3 and return the public URL"""
        self.client.put_object(
            Bucket=self.bucket_name,
            Key=file_key,
            Body=file_data,
            ContentType=content_type,
            ACL='public-read'
        )
        
        # Construct public URL
        # Format: https://{bucket}.{region}.digitaloceanspaces.com/{file_key}
        public_url = f"https://{self.bucket_name}.{self.endpoint_url.replace('https://', '')}/{file_key}"
        return public_url
```

### Upload Handler

**File:** `server/app/http_api/files.py`

```python
async def upload_audio_handler(
    request: Request,
    file: UploadFile = File(...),
    token: str = Form(...),
    format: str = Form("mp3"),
    bitrate: Optional[int] = Form(None),
    duration: Optional[float] = Form(None),
):
    """Upload an audio file to S3 storage"""
    verify_token(token)
    
    # Read file data
    file_data = await file.read()
    file_size = len(file_data)
    
    # Generate unique file key with environment prefix
    env = os.getenv("ENV", "dev")
    file_id = str(uuid.uuid4())
    file_key = f"{env}/renders/{file_id}.{format}"
    
    # Upload to S3
    s3_service = get_s3_service()
    public_url = s3_service.upload_file(file_data, file_key, "audio/mpeg")
    
    if not public_url:
        raise HTTPException(status_code=500, detail="Failed to upload file to storage")
    
    # Return render object
    render = {
        "id": file_id,
        "url": public_url,
        "format": format,
        "size_bytes": file_size,
        "created_at": datetime.utcnow().isoformat() + "Z"
    }
    
    if bitrate:
        render["bitrate"] = bitrate
    if duration:
        render["duration"] = duration
    
    return render
```

## Client Implementation

### Audio Player State

**File:** `app/lib/state/audio_player_state.dart`

```dart
class AudioPlayerState extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // State tracking
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _isLoading = false;
  
  // Play/pause render with seeking support
  Future<void> playRender({
    required String messageId,
    required Render render,
    String? localPathIfRecorded,
  }) async {
    // Load from local file or cache
    final playablePath = await AudioCacheService.getPlayablePath(render, ...);
    
    // Load and play using just_audio
    await _audioPlayer.setFilePath(playablePath);
    await _audioPlayer.play();
  }
  
  // Seek to specific position
  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }
  
  // Streams: position, duration, playing state
  // Updated automatically via just_audio listeners
}
```

**Features:**
- Full seeking support with draggable slider
- Real-time position updates during playback
- Pause/resume functionality
- Automatic completion handling
- Progress indicator during download

### Render UI Component

**File:** `app/lib/screens/thread_screen.dart`

```dart
Widget _buildRenderButton(...) {
  return Consumer<AudioPlayerState>(
    builder: (context, audioPlayer, _) {
      return Container(
        child: Row(
          children: [
            // Play/Pause button (28x28 circular)
            GestureDetector(
              onTap: () => audioPlayer.playRender(...),
              child: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            
            // Seek bar with knob
            Expanded(
              child: Slider(
                value: audioPlayer.position.inMilliseconds.toDouble(),
                max: audioPlayer.duration.inMilliseconds.toDouble(),
                onChanged: (value) => audioPlayer.seek(Duration(milliseconds: value.toInt())),
              ),
            ),
          ],
        ),
      );
    },
  );
}
```

**UI Design:**
- Minimal, clean design with no text labels
- Play/pause button (circular, 28px)
- Draggable seek bar with knob (2px track height, 6px thumb radius)
- Active track color matches app theme (`menuOnlineIndicator`)
- Smooth real-time position updates during playback
- Only shows seek bar when audio is loaded

### Upload Service

**File:** `app/lib/services/upload_service.dart`

```dart
class UploadService {
  static Future<Render?> uploadAudio({
    required String filePath,
    String format = 'mp3',
    int? bitrate,
    double? duration,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ [UPLOAD] File does not exist: $filePath');
        return null;
      }

      final fields = <String, String>{
        'format': format,
      };
      if (bitrate != null) fields['bitrate'] = bitrate.toString();
      if (duration != null) fields['duration'] = duration.toString();

      debugPrint('🔄 [UPLOAD] Uploading audio file: $filePath');
      final response = await ApiHttpClient.uploadFile(
        '/upload/audio',
        filePath,
        fields: fields,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final render = Render.fromJson(json);
        debugPrint('✅ [UPLOAD] Upload successful: ${render.url}');
        return render;
      } else {
        debugPrint('❌ [UPLOAD] Upload failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ [UPLOAD] Upload error: $e');
      return null;
    }
  }
}
```

### State Management

**File:** `app/lib/state/threads_state.dart`

```dart
Future<void> sendMessageFromSequencer({required String threadId}) async {
  // Create message first
  final saved = await ThreadsApi.createMessage(
    threadId: threadId,
    userId: _currentUserId ?? 'unknown',
    snapshot: snapshotMap,
    snapshotMetadata: snapshotMetadata,
    renders: [],  // Empty initially
    timestamp: pending.timestamp,
  );
  
  // Start background upload AFTER we have the message ID
  if (_recordingState != null && _recordingState!.convertedMp3Path != null) {
    _recordingState!.setUploading(true);
    unawaited(_uploadRecordingInBackground(saved.id, _recordingState!.convertedMp3Path!));
  }
}

Future<void> _uploadRecordingInBackground(String messageId, String mp3Path) async {
  final render = await UploadService.uploadAudio(
    filePath: mp3Path,
    format: 'mp3',
    bitrate: 320,
  );
  
  if (render != null) {
    _recordingState?.setUploadedRenderUrl(render.url);
    _recordingState?.setUploading(false);
    await _attachRenderToMessage(messageId, render);
  }
}

Future<void> _attachRenderToMessage(String messageId, Render render) async {
  // Update on server
  await ThreadsApi.attachRenderToMessage(messageId, render);
  
  // Update local state
  for (final entry in _messagesByThread.entries) {
    final list = entry.value;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      final message = list[idx];
      list[idx] = message.copyWith(renders: [...message.renders, render]);
      _messagesByThread[entry.key] = List<Message>.from(list);
      notifyListeners();
      break;
    }
  }
}
```

## UI/UX Behavior

### Message Send Flow

1. **User records audio** → Recording indicator appears
2. **User presses send** → Message appears immediately with snapshot
3. **Upload starts** → "Uploading audio..." indicator shows below message
4. **Upload completes** (3-5 seconds) → Play button appears
5. **User can play** → Audio streams from S3 or plays from local file

### Visual States

```
┌─────────────────────────────────────┐
│ John • 14:30                        │
│ [Snapshot Preview]                  │
│ 🔄 Uploading audio...               │  ← While uploading
│ [Load]                              │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ John • 14:30                        │
│ [Snapshot Preview]                  │
│ ▶ ───────●──────────────────────    │  ← Audio player with seek bar
│ [Load]                              │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ John • 14:30                        │
│ [Snapshot Preview]                  │
│ ⏸ ───────────────●──────────────    │  ← Playing (pause icon + animated position)
│ [Load]                              │
└─────────────────────────────────────┘
```

### Uploading Indicator

- Only shows for the **latest message** from the current user
- Shows spinner + "Uploading audio..." text
- Automatically disappears when upload completes
- If user sends another message before upload completes, indicator disappears but upload continues

## Audio Caching

### Cache Strategy

1. **Local Recording**: If current user recorded it, play from local file path
2. **Already Downloaded**: Check cache via `AudioCacheService.isCached()`
3. **Not Cached**: Download from S3, show progress, cache for future playback

### Cache Location

```dart
// iOS: /Library/Caches/audio_cache/
// Android: /data/data/com.yourapp.package/cache/audio_cache/
final cacheDir = await getTemporaryDirectory();
final audioCacheDir = Directory('${cacheDir.path}/audio_cache');
```

### File Names

Cached files use render ID: `{render_id}.mp3`

## Error Handling

### Upload Errors

```dart
// Network error
if (response.statusCode != 200) {
  _recordingState?.setUploadError('Upload failed');
  // User can retry by sending message again
}

// S3 error
if (!public_url) {
  raise HTTPException(status_code=500, detail="Failed to upload file to storage")
  // Client receives 500 error
}
```

### Server-Side Logging

```python
logger.info(f"📤 Uploading file: {file_key}")
logger.info(f"✅ Upload successful! Public URL: {public_url}")
logger.error(f"❌ S3 Error: {e}")
logger.error(f"   Error Code: {e.response.get('Error', {}).get('Code', 'Unknown')}")
```

### Client-Side Logging

```dart
debugPrint('🔄 [UPLOAD] Uploading audio file: $filePath');
debugPrint('✅ [UPLOAD] Upload successful: ${render.url}');
debugPrint('❌ [UPLOAD] Upload error: $e');
```

## Testing

### Test Script

**File:** `server/test_s3_upload.py`

```bash
cd server
python test_s3_upload.py
```

**Output:**
```
============================================================
🧪 Digital Ocean Spaces S3 Upload Test
============================================================

📋 Configuration:
   Endpoint: https://{region}.digitaloceanspaces.com
   Region: us-east-1
   Bucket: your-bucket-name
   Access Key: YOUR_KEY...
   Environment: prod

🔧 Initializing boto3 client...
✅ Client initialized

📤 Uploading test file: prod/renders/test_upload_123.mp3
✅ Upload successful!
📍 Public URL: https://your-bucket.{region}.digitaloceanspaces.com/prod/renders/test_upload_123.mp3

🔍 Verifying upload...
✅ File exists! Size: 50 bytes
   Content-Type: audio/mpeg

============================================================
✅ Test PASSED - S3 upload is working!
============================================================
```

## Troubleshooting

### Common Issues

#### 1. SignatureDoesNotMatch Error

**Problem:** S3 credentials don't match

**Solution:**
- Verify `S3_ACCESS_KEY` and `S3_SECRET_KEY`
- Ensure `S3_REGION` is set to `us-east-1` (not the actual region code)
- Verify `S3_ENDPOINT_URL` doesn't include bucket name

#### 2. Upload Never Completes

**Problem:** Upload starts but render never appears

**Solution:**
- Check server logs for errors
- Verify message ID is being passed correctly
- Ensure `attachRenderToMessage` API is being called

#### 3. Audio Won't Play

**Problem:** Render button appears but audio doesn't play

**Solution:**
- Verify S3 file is accessible (check URL in browser)
- Check `ACL='public-read'` is set on upload
- Verify audio format is supported (MP3)

## Performance Considerations

### File Size Optimization

- MP3 encoding at 320kbps (high quality)
- Average file size: ~2.5MB per minute of audio
- Upload time: 3-5 seconds for typical recording

### Background Processing

- Upload runs in background using `unawaited()`
- Message appears immediately (optimistic UI)
- User can continue working while upload completes

### Caching Benefits

- First playback: Download from S3 (streaming)
- Subsequent playbacks: Instant from cache
- Reduces bandwidth and improves UX

## Security

### Authentication

- All API requests require `API_TOKEN`
- Token passed in multipart form field
- Token verified before S3 operations

### Access Control

- Files uploaded with `ACL='public-read'`
- Anyone with URL can access
- Consider implementing signed URLs for private threads (future enhancement)

### File Validation

- Content-Type validation
- File size limits (implement if needed)
- Format validation (MP3 only)

## Cleanup and Deletion

### Automatic S3 Cleanup

When a message is deleted, all associated render files are automatically deleted from S3 storage.

**Implementation:** `server/app/http_api/threads.py` - `delete_message_handler()`

```python
async def delete_message_handler(request: Request, message_id: str, token: str = Query(...)):
    # Find message with renders
    message = db.messages.find_one({"id": message_id})
    
    # Delete associated render files from S3
    renders = message.get("renders", [])
    if renders:
        s3_service = get_s3_service()
        for render in renders:
            render_url = render.get("url", "")
            # Extract file key from URL
            # URL: https://bucket.region.digitaloceanspaces.com/prod/renders/uuid.mp3
            # Key: prod/renders/uuid.mp3
            match = re.search(r'\.com/(.+)$', render_url)
            if match:
                file_key = match.group(1)
                s3_service.delete_file(file_key)
    
    # Delete message from database
    db.messages.delete_one({"id": message_id})
    
    return {"status": "deleted", "id": message_id, "renders_deleted": len(renders)}
```

### Cleanup Flow

1. User long-presses message and selects "Delete"
2. Client calls `DELETE /api/v1/messages/{message_id}`
3. Server retrieves message and extracts render URLs
4. For each render:
   - Extract S3 file key from URL
   - Call `s3_service.delete_file(file_key)`
   - Log success/failure
5. Delete message from MongoDB
6. Remove message reference from thread
7. Return success response with count of deleted renders

### Error Handling

- S3 deletion failures are logged but don't prevent message deletion
- If S3 file is already deleted, the operation continues
- Partial failures are logged for debugging

### Logging

```
🗑️  Deleted render from S3: {env}/renders/{uuid}.mp3
⚠️  Failed to delete render from S3: {env}/renders/{uuid}.mp3 (file not found)
```

## Future Enhancements

1. **Progressive Upload**: Show upload progress percentage
2. **Retry Logic**: Auto-retry failed uploads
3. **Compression**: Optional lower bitrate for mobile data
4. **Waveform Preview**: Visual audio waveform in message
5. **Multiple Formats**: Support WAV, OGG for different use cases
6. **Signed URLs**: Private audio for private threads
7. **CDN Optimization**: Leverage Digital Ocean CDN for faster delivery
8. **Bulk Cleanup**: Periodic job to remove orphaned S3 files

## References

- [Digital Ocean Spaces Documentation](https://docs.digitalocean.com/products/spaces/)
- [Boto3 S3 Documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3.html)
- [FastAPI File Uploads](https://fastapi.tiangolo.com/tutorial/request-files/)
- [Flutter HTTP Multipart](https://pub.dev/packages/http#multipart-requests)

