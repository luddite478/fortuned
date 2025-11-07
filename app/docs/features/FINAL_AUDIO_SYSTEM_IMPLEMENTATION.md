# Final Audio System Implementation Guide

## Executive Summary

**Goal**: Unified audio storage system with deduplication, aggressive deletion, and multi-user cache support

**Key Features**:
- ✅ Content-based S3 keys (SHA-256 hash) - prevents duplicates
- ✅ Unified `audio_files` collection - tracks all audio
- ✅ Aggressive deletion - delete from S3 when `reference_count = 0`
- ✅ Local cache grace period - ~30 days via LRU
- ✅ Multi-user safe - automatic re-upload coordination
- ✅ Generic path structure - `prod/audio/` for all audio types

---

## Architecture Overview

### Data Flow

```
┌─────────────────────────────────────────────────────────┐
│                    S3 Storage                            │
│  prod/audio/                                             │
│    ├─ a1b2c3d4e5f6...sha256.mp3 (content-based key)    │
│    ├─ f7e8d9c1b2a3...sha256.mp3                         │
│    └─ ...                                                │
└─────────────────────────────────────────────────────────┘
                           ▲
                           │ (hash-based upload)
                           │
┌─────────────────────────────────────────────────────────┐
│              audio_files Collection                      │
│  ┌────────────────────────────────────────────────┐     │
│  │ id: "audio_abc"                                │     │
│  │ url: "https://s3.../prod/audio/a1b2c3...mp3"  │     │
│  │ s3_key: "prod/audio/a1b2c3d4e5f6.mp3"        │     │
│  │ content_hash: "a1b2c3d4e5f6..."              │     │
│  │ reference_count: 2                             │     │
│  └────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────┘
                    ▲               ▲
                    │               │
          ┌─────────┴──────┐       │
          │                │       │
┌─────────────────┐  ┌────────────────┐
│   messages      │  │    users       │
│  renders: [{    │  │  playlist: [{  │
│   audio_file_id │  │   audio_file_id│
│  }]             │  │  }]            │
└─────────────────┘  └────────────────┘
```

### Key Principle: Content-Based Addressing

```
Same audio content → Same hash → Same S3 key → One file

User A uploads: SHA-256 = a1b2c3d4 → s3.../prod/audio/a1b2c3d4.mp3
User B uploads: SHA-256 = a1b2c3d4 → s3.../prod/audio/a1b2c3d4.mp3 (same!)

Result: Automatic deduplication, no coordination needed
```

---

## Complete Schema Changes

### 1. MongoDB Schema: audio_files Collection

**File**: `schemas/0.0.1/audio/audio.json`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Audio File Schema",
  "type": "object",
  "properties": {
    "schema_version": {
      "type": "integer",
      "enum": [1]
    },
    "id": {
      "type": "string",
      "pattern": "^[a-fA-F0-9]{24}$",
      "minLength": 24,
      "maxLength": 24,
      "description": "MongoDB ObjectId"
    },
    "url": {
      "type": "string",
      "description": "S3 URL: https://s3.../prod/audio/{hash}.mp3"
    },
    "s3_key": {
      "type": "string",
      "description": "S3 object key: prod/audio/{hash}.mp3"
    },
    "content_hash": {
      "type": "string",
      "pattern": "^[a-f0-9]{64}$",
      "description": "SHA-256 hash of file content (used as S3 key)"
    },
    "name": {
      "type": "string",
      "description": "Optional: Name for library items (not used for message renders)"
    },
    "format": {
      "type": "string",
      "enum": ["mp3", "wav", "m4a"],
      "description": "Audio file format"
    },
    "bitrate": {
      "type": "integer",
      "description": "Audio bitrate in kbps"
    },
    "duration": {
      "type": "number",
      "description": "Duration in seconds"
    },
    "size_bytes": {
      "type": "integer",
      "description": "File size in bytes"
    },
    "created_at": {
      "type": "string",
      "format": "date-time",
      "description": "ISO timestamp of creation"
    },
    "reference_count": {
      "type": "integer",
      "description": "Number of references (messages + playlists)",
      "minimum": 0
    },
    "pending_deletion": {
      "type": "boolean",
      "description": "True if S3 deletion failed, needs retry"
    }
  },
  "required": [
    "schema_version",
    "id",
    "url",
    "s3_key",
    "content_hash",
    "format",
    "created_at",
    "reference_count"
  ],
  "additionalProperties": false
}
```

### 2. Database Indexes

```python
# server/app/db/init_collections.py

"audio_files": {
    "indexes": [
        {"fields": "id", "unique": True},
        {"fields": "url", "unique": True},
        {"fields": "content_hash", "unique": True},  # NEW: Deduplication
        {"fields": "s3_key", "unique": False},
        {"fields": "created_at", "unique": False},
        {"fields": "reference_count", "unique": False}
    ]
}
```

---

## Implementation Changes

### 1. Server: Upload Handler with Content Hashing

**File**: `server/app/http_api/files.py`

```python
import hashlib
import os
from datetime import datetime
from fastapi import UploadFile, File, Form, HTTPException
from bson import ObjectId
from storage.s3_service import get_s3_service
from db.connection import get_database

async def upload_audio_handler(
    request: Request,
    file: UploadFile = File(...),
    token: str = Form(...),
    format: str = Form("mp3"),
    bitrate: Optional[int] = Form(None),
    duration: Optional[float] = Form(None),
):
    """
    Upload audio file with content-based addressing
    
    Flow:
    1. Read file content
    2. Calculate SHA-256 hash
    3. Use hash as S3 key: prod/audio/{hash}.{format}
    4. Check if already exists in S3
    5. If exists: return existing URL (deduplication!)
    6. If not: upload to S3
    """
    verify_token(token)
    
    try:
        # Read file content
        file_content = await file.read()
        
        # Calculate content hash (SHA-256)
        content_hash = hashlib.sha256(file_content).hexdigest()
        
        # Construct S3 key using hash
        env = os.getenv("ENVIRONMENT", "prod")  # prod or stage
        s3_key = f"{env}/audio/{content_hash}.{format}"
        
        # Get S3 service
        s3_service = get_s3_service()
        s3_url = s3_service.get_public_url(s3_key)
        
        # Check if file already exists in S3
        if s3_service.file_exists(s3_key):
            logger.info(f"♻️  Audio already exists in S3: {s3_key}")
            
            # Check if audio_files record exists
            db = get_database()
            audio = db.audio_files.find_one({"content_hash": content_hash})
            
            if audio:
                # Perfect - both S3 and DB exist
                logger.info(f"✅ Audio found in DB: {audio['id']}")
                return {
                    "url": s3_url,
                    "s3_key": s3_key,
                    "content_hash": content_hash,
                    "audio_file_id": audio["id"],
                    "status": "existing",
                    "message": "File already exists (content-based deduplication)"
                }
            else:
                # S3 exists but no DB record - create it
                # (This can happen if previous upload succeeded but DB insert failed)
                audio_id = str(ObjectId())
                audio_file = {
                    "schema_version": 1,
                    "id": audio_id,
                    "url": s3_url,
                    "s3_key": s3_key,
                    "content_hash": content_hash,
                    "format": format,
                    "reference_count": 0,
                    "size_bytes": len(file_content),
                    "created_at": datetime.utcnow().isoformat() + "Z"
                }
                
                if bitrate:
                    audio_file["bitrate"] = bitrate
                if duration:
                    audio_file["duration"] = duration
                
                db.audio_files.insert_one(audio_file)
                
                logger.info(f"🔧 Created missing DB record: {audio_id}")
                return {
                    "url": s3_url,
                    "s3_key": s3_key,
                    "content_hash": content_hash,
                    "audio_file_id": audio_id,
                    "status": "restored",
                    "message": "File existed in S3, DB record created"
                }
        
        # File doesn't exist - upload to S3
        uploaded_url = s3_service.upload_file(
            file_content=file_content,
            s3_key=s3_key,
            content_type=f"audio/{format}"
        )
        
        logger.info(f"✅ Uploaded to S3: {s3_key}")
        
        return {
            "url": uploaded_url,
            "s3_key": s3_key,
            "content_hash": content_hash,
            "size_bytes": len(file_content),
            "status": "uploaded",
            "message": "File uploaded successfully"
        }
        
    except Exception as e:
        logger.error(f"❌ Upload failed: {e}")
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")
```

### 2. Server: Audio API with Hash Lookup

**File**: `server/app/http_api/audio.py`

```python
async def get_or_create_audio_handler(request: Request, audio_data: Dict[str, Any] = Body(...)):
    """
    Get existing audio by URL/hash, or create new one
    
    Lookup priority:
    1. By content_hash (most reliable)
    2. By URL (backward compatibility)
    3. Create new if not found
    """
    verify_token(audio_data.get("token", ""))
    try:
        db = get_db()
        url = audio_data.get("url")
        content_hash = audio_data.get("content_hash")
        
        if not url:
            raise HTTPException(status_code=400, detail="url is required")
        
        # Try to find by content_hash first (most reliable)
        audio = None
        if content_hash:
            audio = db.audio_files.find_one({"content_hash": content_hash}, {"_id": 0})
            if audio:
                logger.info(f"✅ Found audio by hash: {audio['id']}")
        
        # Fallback to URL lookup (backward compatibility)
        if not audio:
            audio = db.audio_files.find_one({"url": url}, {"_id": 0})
            if audio:
                logger.info(f"✅ Found audio by URL: {audio['id']}")
        
        if audio:
            # Increment reference count
            db.audio_files.update_one(
                {"id": audio["id"]},
                {"$inc": {"reference_count": 1}}
            )
            
            # Update name if provided and not already set
            name = audio_data.get("name")
            if name and not audio.get("name"):
                db.audio_files.update_one(
                    {"id": audio["id"]},
                    {"$set": {"name": name}}
                )
                audio["name"] = name
            
            # Get updated document
            updated = db.audio_files.find_one({"id": audio["id"]}, {"_id": 0})
            
            return {
                "id": audio["id"],
                "status": "existing",
                "audio": updated or audio
            }
        
        # Create new audio file record
        audio_id = str(ObjectId())
        audio_file = {
            "schema_version": 1,
            "id": audio_id,
            "url": url,
            "s3_key": audio_data.get("s3_key", ""),
            "content_hash": content_hash or "",
            "format": audio_data.get("format", "mp3"),
            "reference_count": 1,
            "created_at": datetime.utcnow().isoformat() + "Z"
        }
        
        # Add optional fields
        if audio_data.get("name"):
            audio_file["name"] = audio_data["name"]
        if audio_data.get("bitrate"):
            audio_file["bitrate"] = audio_data["bitrate"]
        if audio_data.get("duration"):
            audio_file["duration"] = audio_data["duration"]
        if audio_data.get("size_bytes"):
            audio_file["size_bytes"] = audio_data["size_bytes"]
        
        db.audio_files.insert_one(audio_file)
        audio_file.pop("_id", None)
        
        logger.info(f"✅ Created new audio record: {audio_id}")
        
        return {
            "id": audio_id,
            "status": "created",
            "audio": audio_file
        }
        
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
```

### 3. Client: Upload with Hash Calculation ✅ IMPLEMENTED

**File**: `app/lib/services/upload_service.dart`

The Flutter client now calculates SHA-256 hash before upload and includes it in the request:

```dart
import 'dart:io';
import 'package:crypto/crypto.dart';

// Calculate SHA-256 hash
final bytes = await file.readAsBytes();
final hash = sha256.convert(bytes);
final contentHash = hash.toString(); // hex string

// Upload with hash
final fields = {
  'format': format,
  'content_hash': contentHash, // Server uses this as S3 key
};

final response = await ApiHttpClient.uploadFile(
  '/upload/audio',
  filePath,
  fields: fields,
);
```

**How it works:**
1. Read file bytes
2. Calculate SHA-256 hash
3. Include hash in upload request
4. Server checks if file exists by hash
5. If exists: returns existing URL (deduplicated!)
6. If not: uploads to `prod/audio/{hash}.mp3`

**Dependencies added:**
- `crypto: ^3.0.5` in `pubspec.yaml`

---

## Path Structure Changes

### Old Structure (Renders-Specific)
```
s3://bucket/
├── prod/
│   └── renders/
│       ├── 550e8400-e29b-41d4-a716-446655440000.mp3
│       ├── 6ba7b810-9dad-11d1-80b4-00c04fd430c8.mp3
│       └── ...
└── stage/
    └── renders/
        └── ...
```

### New Structure (Generic Audio) ✅
```
s3://bucket/
├── prod/
│   └── audio/
│       ├── a1b2c3d4e5f6789...{sha256}.mp3  (content-based)
│       ├── f7e8d9c1b2a3456...{sha256}.mp3  (content-based)
│       └── ...
└── stage/
    └── audio/
        └── ...
```

### Benefits of New Structure

1. **Generic naming**: `audio` covers both renders and library items
2. **Content-based**: Same content = same path
3. **No confusion**: Clear that it's audio storage, not just renders
4. **Scalable**: Can add other audio types later (samples, effects, etc.)

### Migration Plan

**NOT NEEDED** ✅

Database will be reinitialized, old audio files can be discarded.

If you need to migrate existing data in the future:
1. Calculate content_hash for each existing audio file
2. Copy from old S3 path to new hash-based path
3. Update database records
4. Delete old files

(Migration script can be created if needed, but not required for initial deployment)

---

## Complete Reference Flow

### Flow 1: Upload New Audio

```
Client:
1. Record/select audio file
2. Calculate SHA-256: a1b2c3d4e5f6...
3. POST /upload/audio (includes hash)

Server:
4. Receives file + hash
5. S3 key = prod/audio/a1b2c3d4e5f6.mp3
6. Check if exists in S3
   - Exists? Return existing URL ✅
   - Not exists? Upload to S3
7. Return: {url, s3_key, content_hash}

Client:
8. POST /audio {url, s3_key, content_hash}
9. Server creates audio_files record
10. Return: {audio_file_id}
11. Create message with audio_file_id
```

### Flow 2: Multi-User Re-upload

```
Initial State:
- Audio in S3: prod/audio/a1b2c3d4.mp3
- reference_count = 0
- S3 file DELETED (aggressive)
- User A has cached file (hash: a1b2c3d4)
- User B has cached file (hash: a1b2c3d4)

User A Re-uploads:
1. Calculates hash: a1b2c3d4
2. POST /upload/audio
3. Server: s3_key = prod/audio/a1b2c3d4.mp3
4. File doesn't exist → uploads
5. POST /audio {content_hash: a1b2c3d4}
6. Creates audio_files record
7. Success ✅

User B Re-uploads (1 second later):
1. Calculates hash: a1b2c3d4 (SAME!)
2. POST /upload/audio
3. Server: s3_key = prod/audio/a1b2c3d4.mp3
4. File EXISTS! → returns existing URL
5. POST /audio {content_hash: a1b2c3d4}
6. Finds existing audio_files by hash
7. Increments reference_count
8. Success ✅ No duplicate!
```

---

## Challenges & Solutions

### Challenge 1: Hash Collisions

**Risk**: Two different files produce same SHA-256 hash (extremely unlikely)

**Probability**: 2^-256 ≈ 0 (practically impossible)

**Solution**: SHA-256 is cryptographically secure
- Bitcoin uses it (billions at stake)
- Git uses it (millions of repos)
- No known collisions in real-world use

**Mitigation**: If paranoid, also store file size and check on collision

```python
# Enhanced collision detection
if existing_audio and existing_audio.get("size_bytes") != len(file_content):
    # Hash collision detected! (would be historic event)
    logger.critical(f"SHA-256 COLLISION DETECTED: {content_hash}")
    # Fallback to UUID-based key
    s3_key = f"{env}/audio/{uuid.v4()}.{format}"
```

### Challenge 2: S3 Eventual Consistency

**Risk**: File uploaded but S3 GET returns 404 briefly

**Solution**: S3 is now strongly consistent (as of Dec 2020)

**Mitigation**: Retry logic in client
```dart
int retries = 3;
while (retries > 0) {
  if (await s3FileExists(url)) break;
  await Future.delayed(Duration(seconds: 1));
  retries--;
}
```

### Challenge 3: Orphaned S3 Files

**Risk**: Upload succeeds but DB insert fails → file in S3, no DB record

**Solution**: Upload handler checks for this and creates missing record

```python
# In upload_audio_handler
if s3_service.file_exists(s3_key):
    audio = db.audio_files.find_one({"content_hash": content_hash})
    if not audio:
        # Create missing DB record
        audio = create_audio_record(...)
```

### Challenge 4: Concurrent Uploads (Race Condition)

**Risk**: Two users upload same file simultaneously

**Scenario**:
```
T0: User A starts upload (hash: a1b2c3)
T0: User B starts upload (hash: a1b2c3)
T1: Both check: file doesn't exist
T2: Both upload to prod/audio/a1b2c3.mp3
T3: Both create DB record
```

**Solution**: Unique index on content_hash

```python
# In MongoDB
db.audio_files.create_index("content_hash", unique=True)

# Second insert fails with duplicate key error
try:
    db.audio_files.insert_one(audio_file)
except DuplicateKeyError:
    # Another user beat us to it, find their record
    audio = db.audio_files.find_one({"content_hash": content_hash})
    return {"id": audio["id"], "status": "existing"}
```

### Challenge 5: Migration of Existing Files

**Risk**: Existing files have UUID-based keys, not hash-based

**Solution**: Gradual migration

```
Phase 1: Support both formats
- Old files: prod/renders/uuid.mp3
- New files: prod/audio/hash.mp3
- Both work fine

Phase 2: Background migration (optional)
- Calculate hash for old files
- Copy to new location
- Update DB records
- Delete old files

Phase 3: Eventually all files use hash-based keys
```

### Challenge 6: Hash Calculation Performance

**Risk**: Hashing large files is slow

**Reality**: SHA-256 is very fast
- 5MB file: ~50ms on mobile
- 10MB file: ~100ms on mobile
- Acceptable for audio files

**Optimization**: Hash while uploading
```dart
// Stream file and calculate hash simultaneously
final digest = AccumulatorSink<Digest>();
final hashSink = sha256.startChunkedConversion(digest);

await for (final chunk in file.openRead()) {
  hashSink.add(chunk);
  uploadStream.add(chunk); // Upload simultaneously
}

hashSink.close();
final hash = digest.events.single.toString();
```

---

## Complete Implementation Checklist

### Server Changes ✅ COMPLETED

- [x] **Schema**
  - [x] Update `schemas/0.0.1/audio/audio.json` (add `content_hash`, `pending_deletion`)
  - [x] Run `python -m app.db.init_collections`

- [x] **Audio API** (`server/app/http_api/audio.py`) **[MERGED]**
  - [x] Merged `files.py` into `audio.py` (single module for all audio operations)
  - [x] Add `import hashlib`
  - [x] Calculate SHA-256 hash of file content in upload handler
  - [x] Change S3 key format: `{env}/audio/{hash}.{format}`
  - [x] Check if file exists in S3 before uploading
  - [x] Check if audio_files record exists, create if missing
  - [x] Update `get_or_create_audio_handler` to lookup by `content_hash` first
  - [x] Fallback to URL lookup for backward compatibility
  - [x] Aggressive deletion already implemented

- [x] **Database Indexes**
  - [x] Add unique index on `content_hash`
  - [x] Keep existing indexes (url, s3_key, etc.)

- [x] **S3 Service** (`server/app/storage/s3_service.py`)
  - [x] Add `file_exists(s3_key)` method
  - [x] Add `get_public_url(s3_key)` method

### Client Changes ✅ COMPLETED

- [x] **Dependencies**
  - [x] Add `crypto: ^3.0.5` to `pubspec.yaml`

- [x] **Upload Service** (`app/lib/services/upload_service.dart`)
  - [x] Calculate SHA-256 hash before upload
  - [x] Include `content_hash` in upload request
  - [x] Log deduplication status (existing vs new)

- [ ] **Message Creation** (ALREADY WORKS)
  - Message creation already uses `UploadService.uploadAudio()`
  - No changes needed - hash calculation happens automatically

- [ ] **Library Management** (FUTURE)
  - Not yet implemented in the app
  - When implemented, will use same `UploadService.uploadAudio()`

### Migration Tasks

**NOT NEEDED** - Database will be reinitialized

- [x] **Database Reinitialization**
  - Run `python -m app.db.init_collections` to create fresh schema
  - Old data will be discarded (acceptable per requirements)

- [ ] **Future Migration** (if needed later)
  - Script to calculate hashes for existing files
  - Move files to new path structure
  - Update database records

---

## Testing Strategy

### Unit Tests

```python
def test_content_based_upload():
    # Same file uploaded twice
    file_content = b"test audio content"
    
    # First upload
    result1 = upload_audio(file_content)
    hash1 = hashlib.sha256(file_content).hexdigest()
    assert result1['s3_key'] == f"prod/audio/{hash1}.mp3"
    
    # Second upload (same content)
    result2 = upload_audio(file_content)
    assert result2['s3_key'] == result1['s3_key']  # Same key!
    assert result2['status'] == 'existing'  # Not re-uploaded

def test_multi_user_reupload():
    # Simulate: audio deleted, two users re-upload
    content_hash = "a1b2c3d4e5f6..."
    
    # User A uploads
    audio_a = create_audio(content_hash=content_hash)
    
    # User B uploads (same hash)
    audio_b = get_or_create_audio(content_hash=content_hash)
    
    # Should be same audio_file_id
    assert audio_a['id'] == audio_b['id']
    assert audio_b['status'] == 'existing'
```

### Integration Tests

```dart
test('re-upload from cache creates no duplicates', () async {
  // 1. Upload audio
  final file = File('test.mp3');
  final hash = calculateHash(await file.readAsBytes());
  
  final uploadResult = await AudioUploadService.uploadAudio(file);
  
  // 2. Delete from S3 (simulate reference_count = 0)
  await deleteFromS3(uploadResult['s3_key']);
  
  // 3. Re-upload from cache
  final reuploadResult = await AudioUploadService.uploadAudio(file);
  
  // Should have same hash-based key
  expect(reuploadResult['s3_key'], equals(uploadResult['s3_key']));
  expect(reuploadResult['content_hash'], equals(hash));
});
```

---

## Monitoring & Metrics

### Key Metrics to Track

```python
# Deduplication effectiveness
deduplication_ratio = total_references / total_files
# Target: > 1.5 (50% of audio files are reused)

# Re-upload frequency
reupload_rate = reuploads / total_uploads
# Target: < 1% (rare event)

# Hash-based hits
hash_hit_rate = hash_lookups_found / total_hash_lookups
# Target: > 90% (most hash lookups succeed)

# Storage savings
storage_saved = (total_references - total_files) * avg_file_size
# Track in GB and $
```

### Dashboard Queries

```python
# Get deduplication stats
stats = await get_audio_stats()
print(f"Total files: {stats['total_files']}")
print(f"Total references: {stats['total_references']}")
print(f"Deduplication ratio: {stats['deduplication_ratio']}")
print(f"Storage saved: {stats['storage_saved_gb']} GB")

# Find most referenced audio
popular = db.audio_files.find().sort("reference_count", -1).limit(10)
```

---

## Summary

### What Changes

| Component | Old Behavior | New Behavior |
|-----------|--------------|--------------|
| **S3 Path** | `prod/renders/{uuid}.mp3` | `prod/audio/{hash}.mp3` |
| **Deduplication** | By URL matching | By content hash |
| **Multi-user re-upload** | Creates duplicates | Automatic dedup |
| **Lookup** | URL only | Hash first, URL fallback |
| **Deletion** | Conservative (30 days) | Aggressive (immediate) |

### Key Benefits

1. ✅ **True deduplication**: Same content = one file, always
2. ✅ **Multi-user safe**: No coordination needed
3. ✅ **Generic naming**: `audio` instead of `renders`
4. ✅ **Idempotent uploads**: Upload same file 1000x = 1 S3 file
5. ✅ **Storage savings**: Immediate, not delayed
6. ✅ **Future-proof**: Can add other audio types easily

### Implementation Effort

- **Server**: ~4 hours (upload handler, audio API, migration)
- **Client**: ~2 hours (hash calculation, upload integration)
- **Testing**: ~2 hours (unit + integration tests)
- **Migration**: ~1 hour (existing data, optional)
- **Total**: ~1 day of focused work

### Risk Level

**Low** - Content-based addressing is proven technology:
- Git uses SHA-1 (we're using SHA-256, even stronger)
- Bitcoin uses SHA-256 ($1T+ secured by it)
- Dropbox uses content-based addressing
- No breaking changes (backward compatible)

---

## Deployment Steps

```bash
# 1. Update code
cd /Users/romansmirnov/projects/fortuned
git pull

# 2. Reinitialize database (drops existing data)
cd server
python -m app.db.init_collections --drop

# 3. Install Flutter dependencies
cd ../app
flutter pub get

# 4. Restart server
sudo systemctl restart fortuned-api

# 5. Rebuild Flutter app
flutter run  # or flutter build

# 6. Verify server
curl "http://your-server/api/v1/audio/stats?token=TOKEN"

# 7. Test upload
# Upload same audio twice from app, verify deduplication in logs:
# First upload: "Upload successful (new file)"
# Second upload: "File already exists on server (deduplicated)"

# 8. Monitor
# Check deduplication ratio after 1 week
```

---

## Conclusion

This unified implementation provides:
- Content-based S3 addressing (prevents duplicates)
- Aggressive deletion (immediate storage savings)
- Multi-user cache support (automatic coordination)
- Generic audio path structure (`prod/audio/`)
- Backward compatibility (old URLs still work)

**Ready to implement!** Start with server changes, then client, then optional migration.

Total storage savings expected: **50%+** with deduplication ratio of **1.5x-2x**.

