# Offline-First Caching System Implementation Plan

## Executive Summary

This document outlines the plan to transform the application into an offline-first system with intelligent caching, deduplication, and seamless synchronization. The goal is to make the app work independently of internet connectivity while efficiently utilizing device storage and syncing changes when connectivity is available.

## Current State Analysis

### Problems Identified

1. **No Persistence**: Messages and library items exist only in memory, lost on app restart
2. **Redundant Audio Storage**: Same audio files cached multiple times when referenced in both library and thread renders
3. **Snapshots Not Cached**: Heavy snapshot data requires network calls when applying checkpoints
4. **No Offline Sync**: Changes fail silently when offline
5. **No Cache Management**: No limits, eviction, or cleanup strategy

### Current Caching Behavior

| Component | Storage | Persistence | Deduplication |
|-----------|---------|-------------|---------------|
| Messages | Memory (`_messagesByThread`) | ❌ Lost on restart | N/A |
| Snapshots | Memory (when loaded) | ❌ Not cached by default | N/A |
| Audio Files | Filesystem (`AudioCacheService`) | ✅ Persistent | ❌ Multiple copies |
| Library Items | Memory (`LibraryState`) | ❌ Lost on restart | N/A |

## Goals

1. **Offline Independence**: App works fully offline after initial sync
2. **Storage Efficiency**: Single copy of each audio file, regardless of references
3. **Fast Loading**: Instant UI with cached data, background sync
4. **Smart Caching**: Automatic eviction, size limits, LRU policies
5. **Seamless Sync**: Queue offline changes, sync when online

## Architecture Overview

### Backend Changes

#### 1. New MongoDB Collection: `audio_files`

**Purpose**: Centralized storage for audio file metadata, referenced by both messages and playlists.

```javascript
// Schema
{
  _id: ObjectId,
  url: String,              // S3 URL (unique index)
  s3_key: String,           // S3 object key
  format: String,           // 'mp3'
  bitrate: Number,         // 320
  duration: Number,         // seconds
  size_bytes: Number,
  created_at: Date,
  hash: String,            // Optional: file hash for deduplication
  reference_count: Number  // Track references (for cleanup)
}

// Indexes
- url: unique
- created_at: descending
```

**API Endpoints**:
- `GET /api/v1/audio/{audio_file_id}` - Get audio metadata
- `POST /api/v1/audio` - Create audio file record (on upload)
- `GET /api/v1/audio/by-url?url={url}` - Lookup by URL

#### 2. Updated Collections

**Messages Collection**:
```javascript
{
  ...
  renders: [{
    audio_file_id: ObjectId,  // NEW: Reference to audio_files
    url: String,                // KEEP: For backward compatibility
    // ... other fields
  }]
}
```

**User Playlist Collection**:
```javascript
{
  ...
  items: [{
    audio_file_id: ObjectId,  // NEW: Reference to audio_files
    url: String,                // KEEP: For backward compatibility
    // ... other fields
  }]
}
```

### Client Changes

#### 1. Local Database (Hive/Isar)

**Why Hive/Isar over SQLite**:
- No schema migrations needed
- Type-safe with code generation
- Faster for simple queries
- Built-in encryption support
- Better for nested JSON (snapshots)

**Database Models**:

```dart
// CachedMessage - Persist messages with snapshots
@collection
class CachedMessage {
  @Id()
  String id;
  
  String threadId;
  DateTime timestamp;
  String userId;
  Map<String, dynamic> snapshot;        // Full snapshot cached
  Map<String, dynamic>? snapshotMetadata;
  List<String> renderIds;              // References to CachedRender
  DateTime cachedAt;
  DateTime? syncedAt;                   // For offline changes
  bool isPendingDelete;                 // For offline deletions
}

// CachedRender - Unified audio cache with deduplication
@collection
class CachedRender {
  @Id()
  String id;
  
  String url;                           // Unique index
  String? audioFileId;                   // MongoDB reference
  String format;
  int? bitrate;
  double? duration;
  int? sizeBytes;
  DateTime createdAt;
  String? localPath;                    // Cached file path
  DateTime cachedAt;
  DateTime lastAccessedAt;              // For LRU eviction
  int referenceCount;                   // How many messages/library items reference this
}

// CachedPlaylistItem - Persist library items
@collection
class CachedPlaylistItem {
  @Id()
  String id;
  
  String userId;
  String name;
  String renderId;                      // Reference to CachedRender
  DateTime createdAt;
  DateTime? syncedAt;                   // For offline changes
  bool isPendingDelete;                 // For offline deletions
}

// SyncQueue - Queue operations for offline sync
@collection
class SyncQueueItem {
  @Id()
  int id;
  
  String operation;                    // 'add_playlist', 'remove_playlist', 'create_message'
  Map<String, dynamic> data;
  DateTime queuedAt;
  int retryCount;
  DateTime? lastRetryAt;
}
```

#### 2. Service Layer

**OfflineMessageCache**:
- Load from local DB first (instant)
- Sync from server in background
- Cache snapshots when loaded
- Implement LRU eviction

**UnifiedAudioCache**:
- Single cache entry per URL
- Reference counting
- Automatic deduplication
- Size-based eviction

**OfflineSyncQueue**:
- Queue operations when offline
- Process queue when online
- Exponential backoff for retries
- Conflict resolution

## Implementation Phases

### Phase 1: Backend Audio Deduplication (Week 1-2)

**Goal**: Create centralized audio file storage

**Tasks**:
1. Create `audio_files` MongoDB collection
2. Add indexes (url unique, created_at)
3. Create migration script:
   - Extract unique audio files from messages
   - Extract unique audio files from playlists
   - Create `audio_files` records
   - Update references (keep `url` for backward compatibility)
4. Add API endpoints:
   - `GET /api/v1/audio/{audio_file_id}`
   - `GET /api/v1/audio/by-url?url={url}`
   - `POST /api/v1/audio` (on upload)
5. Update message/playlist APIs to return `audio_file_id`
6. Update upload flow to create `audio_files` record

**Deliverables**:
- `audio_files` collection with data
- Migration script
- Updated API endpoints
- API documentation

**Testing**:
- Migration script on test data
- API endpoint tests
- Backward compatibility (old clients still work)

---

### Phase 2: Local Database Setup (Week 2-3)

**Goal**: Add local persistence layer

**Tasks**:
1. Add Hive/Isar dependency to `pubspec.yaml`
2. Create database models (CachedMessage, CachedRender, etc.)
3. Set up database initialization:
   - Create boxes/collections
   - Set up encryption (optional)
   - Handle migrations
4. Create `LocalDatabaseService`:
   - CRUD operations for all models
   - Query helpers
   - Transaction support
5. Add database initialization in app startup

**Deliverables**:
- Database models with code generation
- `LocalDatabaseService` implementation
- Database initialization in app startup
- Unit tests for database operations

**Testing**:
- Database CRUD operations
- Query performance
- Data integrity

---

### Phase 3: Message Caching (Week 3-4)

**Goal**: Persist messages with snapshots

**Tasks**:
1. Create `OfflineMessageCache` service:
   - Load from local DB first
   - Sync from server in background
   - Cache snapshots when loaded
2. Update `ThreadsState`:
   - Use `OfflineMessageCache` instead of memory-only storage
   - Load from local DB on init
   - Background sync on view
3. Update `loadProjectSnapshot`:
   - Check local DB first
   - Fallback to API if not cached
   - Cache result in local DB
4. Implement LRU eviction:
   - Keep last 50 messages per thread with snapshots
   - Clear snapshots from older messages
   - Keep metadata for all messages

**Deliverables**:
- `OfflineMessageCache` service
- Updated `ThreadsState`
- LRU eviction logic
- Integration tests

**Testing**:
- Offline message loading
- Snapshot caching
- Eviction behavior
- Background sync

---

### Phase 4: Unified Audio Cache (Week 4-5)

**Goal**: Deduplicate audio storage

**Tasks**:
1. Create `UnifiedAudioCache` service:
   - Single cache entry per URL
   - Reference counting
   - Increment count on cache
   - Decrement count on release
2. Update `AudioCacheService`:
   - Use `UnifiedAudioCache` for metadata
   - Store file path in `CachedRender`
   - Track last accessed time
3. Update `AudioPlayerState`:
   - Use unified cache
   - Update reference counts
4. Update library and thread views:
   - Share same cache entries
   - Release references on delete
5. Implement size-based eviction:
   - Max cache size (500MB default)
   - Evict least recently used files
   - Only evict files with ref count = 0

**Deliverables**:
- `UnifiedAudioCache` service
- Updated `AudioCacheService`
- Reference counting logic
- Size-based eviction
- Integration tests

**Testing**:
- Deduplication (same file cached once)
- Reference counting
- Eviction behavior
- File cleanup

---

### Phase 5: Library Persistence (Week 5)

**Goal**: Persist library items locally

**Tasks**:
1. Update `LibraryState`:
   - Load from local DB on init
   - Save to local DB on changes
   - Background sync to server
2. Implement offline add/remove:
   - Queue operations when offline
   - Process queue when online
3. Add conflict resolution:
   - Server wins on conflicts
   - Merge local changes

**Deliverables**:
- Updated `LibraryState`
- Offline library operations
- Conflict resolution
- Integration tests

**Testing**:
- Offline library operations
- Sync on reconnect
- Conflict resolution

---

### Phase 6: Offline Sync Queue (Week 6)

**Goal**: Queue and sync offline changes

**Tasks**:
1. Create `OfflineSyncQueue` service:
   - Queue operations when offline
   - Process queue when online
   - Exponential backoff for retries
2. Add connectivity monitoring:
   - Detect online/offline state
   - Trigger sync on reconnect
3. Implement sync handlers:
   - `add_playlist` sync
   - `remove_playlist` sync
   - `create_message` sync (if needed)
4. Add sync status UI:
   - Show pending sync count
   - Show sync errors
   - Manual retry option

**Deliverables**:
- `OfflineSyncQueue` service
- Connectivity monitoring
- Sync handlers
- Sync status UI
- Integration tests

**Testing**:
- Queue operations offline
- Process queue online
- Retry logic
- Error handling

---

### Phase 7: Cache Management (Week 7)

**Goal**: Smart cache eviction and monitoring

**Tasks**:
1. Implement cache eviction policies:
   - LRU for snapshots (keep last 50 per thread)
   - Size-based for audio (max 500MB)
   - Time-based for old data (optional)
2. Add cache monitoring:
   - Track cache size
   - Track hit/miss rates
   - Log eviction events
3. Add cache management UI:
   - Show cache size
   - Manual clear option
   - Clear by type (messages, audio, library)
4. Add cache settings:
   - Max cache size setting
   - Auto-eviction toggle
   - Cache location (if applicable)

**Deliverables**:
- Eviction policies
- Cache monitoring
- Cache management UI
- Settings integration
- Unit tests

**Testing**:
- Eviction behavior
- Cache size limits
- Manual clear
- Settings persistence

---

### Phase 8: Migration & Rollout (Week 8)

**Goal**: Migrate existing data and roll out

**Tasks**:
1. Create migration script:
   - Migrate existing audio cache to database
   - Migrate library items to database
   - Migrate recent messages (if any)
2. Add migration UI:
   - Show migration progress
   - Handle errors gracefully
3. Update app startup:
   - Check migration status
   - Run migration if needed
4. Add feature flags:
   - Toggle offline-first mode
   - Rollback if issues
5. Monitor and optimize:
   - Track performance metrics
   - Optimize queries
   - Fix issues

**Deliverables**:
- Migration script
- Migration UI
- Feature flags
- Monitoring dashboard
- Rollback plan

**Testing**:
- Migration on test devices
- Performance testing
- Edge case handling
- Rollback testing

## Technical Details

### Database Choice: Hive vs Isar

**Recommendation: Isar**

**Reasons**:
- Better performance for complex queries
- Built-in full-text search
- Better type safety
- Active development

**Alternative: Hive**
- Simpler API
- Smaller bundle size
- Good for simple use cases

### Cache Size Limits

**Default Limits**:
- Total cache: 500MB
- Snapshots: Last 50 messages per thread
- Audio: Unlimited (within total limit)
- Library: Unlimited (within total limit)

**Configurable**:
- User can adjust in settings
- Auto-eviction when limit reached
- Manual clear option

### Sync Strategy

**Priority Order**:
1. User actions (add/remove playlist)
2. Message creation (if offline)
3. Background sync (messages, library)

**Conflict Resolution**:
- Server wins for collaborative data
- Last write wins for user-owned data
- Merge strategy for playlists

### Eviction Policies

**Snapshots (LRU)**:
- Keep last 50 messages per thread with snapshots
- Clear snapshots from older messages
- Keep metadata for all messages

**Audio (Size-based + LRU)**:
- Max total size: 500MB
- Evict least recently used files first
- Only evict files with ref count = 0
- Keep files referenced by library items

**Library**:
- No eviction (user-owned data)
- Clear on logout

## Migration Strategy

### Backward Compatibility

**During Migration**:
- Keep `url` field in messages/playlists
- Support both `audio_file_id` and `url`
- Gradually migrate clients

**After Migration**:
- Remove `url` field (optional)
- Require `audio_file_id` (optional)

### Data Migration

**Backend**:
1. Extract unique audio files
2. Create `audio_files` records
3. Update references (keep `url`)
4. Verify data integrity

**Client**:
1. Migrate existing cache to database
2. Update references
3. Verify data integrity
4. Clear old cache files

## Testing Strategy

### Unit Tests

- Database operations
- Cache eviction logic
- Sync queue processing
- Reference counting

### Integration Tests

- Offline message loading
- Audio deduplication
- Library persistence
- Sync on reconnect

### E2E Tests

- Full offline workflow
- Sync after reconnect
- Cache eviction
- Migration process

### Performance Tests

- Database query performance
- Cache hit rates
- Sync speed
- Memory usage

## Rollout Plan

### Phase 1: Internal Testing (Week 8)
- Test on internal devices
- Fix critical issues
- Performance optimization

### Phase 2: Beta Testing (Week 9)
- Release to beta users
- Collect feedback
- Monitor metrics

### Phase 3: Gradual Rollout (Week 10+)
- 10% of users
- Monitor crash rates
- Monitor performance
- Increase to 50%, then 100%

### Rollback Plan

- Feature flag to disable offline-first
- Fallback to current behavior
- Data migration rollback script
- Clear local database if needed

## Success Metrics

### Performance
- App startup time: < 2s (with cache)
- Message load time: < 100ms (from cache)
- Audio play time: < 500ms (from cache)
- Cache hit rate: > 80%

### Storage
- Audio deduplication: 50%+ reduction
- Cache size: < 500MB average
- Storage efficiency: > 90%

### User Experience
- Offline functionality: 100% core features
- Sync success rate: > 95%
- Error rate: < 1%

## Risks & Mitigations

### Risk 1: Database Corruption
**Mitigation**: 
- Regular backups
- Data validation
- Corruption detection
- Recovery mechanisms

### Risk 2: Storage Overflow
**Mitigation**:
- Size limits
- Automatic eviction
- User warnings
- Manual clear option

### Risk 3: Sync Conflicts
**Mitigation**:
- Clear conflict resolution
- Server wins strategy
- User notification
- Manual resolution option

### Risk 4: Migration Failures
**Mitigation**:
- Gradual migration
- Rollback capability
- Data validation
- Error recovery

## Future Enhancements

1. **Incremental Sync**: Only sync changes, not full data
2. **Compression**: Compress snapshots before caching
3. **Encryption**: Encrypt sensitive cached data
4. **Cloud Backup**: Backup cache to cloud (optional)
5. **Multi-Device Sync**: Sync cache across devices
6. **Analytics**: Track cache performance and usage

## Questions & Decisions Needed

1. **Storage Limits**: What's the target max cache size? (Recommend: 500MB)
2. **Snapshot Caching**: Cache all snapshots or only recent ones? (Recommend: Last 50 per thread)
3. **Audio Retention**: Delete audio files when ref count = 0, or keep for potential reuse? (Recommend: Keep, evict by LRU)
4. **Sync Priority**: Which operations should sync first? (Recommend: User actions > Background sync)
5. **Migration**: Gradual migration or one-time migration? (Recommend: Gradual)
6. **Database**: Hive or Isar? (Recommend: Isar)
7. **Encryption**: Encrypt cached data? (Recommend: Optional, for sensitive data)

## Timeline Summary

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Backend Audio Deduplication | 2 weeks | None |
| Phase 2: Local Database Setup | 1 week | Phase 1 |
| Phase 3: Message Caching | 1 week | Phase 2 |
| Phase 4: Unified Audio Cache | 1 week | Phase 2, Phase 3 |
| Phase 5: Library Persistence | 1 week | Phase 2 |
| Phase 6: Offline Sync Queue | 1 week | Phase 5 |
| Phase 7: Cache Management | 1 week | Phase 3, Phase 4 |
| Phase 8: Migration & Rollout | 1 week | All phases |
| **Total** | **9 weeks** | |

## Conclusion

This plan provides a comprehensive roadmap for implementing an offline-first caching system that will significantly improve user experience, reduce storage usage, and enable seamless offline functionality. The phased approach allows for incremental development and testing, reducing risk and ensuring quality.


