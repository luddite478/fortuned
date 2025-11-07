# Thread Draft Mechanism

## Overview

The thread draft mechanism provides automatic local persistence of sequencer state for each thread, allowing users to resume their work even if they haven't saved a checkpoint. Drafts are stored locally on the device and persist across app sessions.

## Purpose

- **Prevent data loss**: Automatically save unsaved work when navigating away from the sequencer
- **Seamless experience**: Users can continue working from where they left off without manually saving
- **Thread-specific**: Each thread has its own independent draft state
- **Non-intrusive**: Drafts are saved silently in the background without blocking UI

## How It Works

### Draft Storage

- Drafts are stored locally using `ReliableStorage` (cross-platform file-based storage)
- Each draft is keyed by thread ID: `thread_draft_{threadId}`
- Draft format is identical to server snapshots (JSON exported via `SnapshotService`)

### When Drafts Are Saved

1. **On Navigation Away**: When the user presses the back button to leave the sequencer screen
   - Save happens in the background (non-blocking)
   - Navigation proceeds immediately

2. **On Widget Disposal**: When the sequencer screen widget is disposed
   - Backup save in case navigation happened in an unexpected way
   - Also saves in background (no await)

### When Drafts Are Loaded

Drafts are loaded when opening a thread in the sequencer, but only if:
- **No server snapshot exists**: If the thread has no saved messages/checkpoints
- **Priority**: Server snapshots take precedence over drafts (drafts are for unsaved work)

### When Drafts Are Cleared

- **On Checkpoint Save**: When a user saves a checkpoint (message), the draft is cleared since the work is now committed
- **Manual cleanup**: Can be cleared programmatically if needed

## Technical Implementation

### ThreadDraftService

The `ThreadDraftService` class manages draft operations:

```dart
class ThreadDraftService {
  // Start tracking a thread (call when opening sequencer)
  void startTracking(String threadId);
  
  // Stop tracking (call when leaving sequencer)
  void stopTracking();
  
  // Save draft for currently tracked thread
  Future<void> saveDraft();
  
  // Load draft for a specific thread
  Future<Map<String, dynamic>?> loadDraft(String threadId);
  
  // Clear draft for a specific thread
  Future<void> clearDraft(String threadId);
}
```

### Integration Points

#### SequencerScreenV2

1. **Initialization**: Service is created in `initState()`
2. **Thread Tracking**: `startTracking()` is called when a thread is loaded
3. **Back Button**: `saveDraft()` is called (non-blocking) when user presses back
4. **Disposal**: `saveDraft()` is called in `dispose()` as backup

#### ProjectsScreen

- Drafts are loaded when opening a project if no server snapshot exists
- Draft is passed as `initialSnapshot` to the sequencer screen

## Data Flow

### Saving a Draft

```
User navigates away from sequencer
  ↓
Back button pressed
  ↓
ThreadDraftService.saveDraft() called (non-blocking)
  ↓
SnapshotService.exportToJson() creates snapshot
  ↓
ReliableStorage.setString() saves to local file
  ↓
Navigation proceeds (doesn't wait for save)
```

### Loading a Draft

```
User opens project in ProjectsScreen
  ↓
Check if server snapshot exists
  ↓
If no snapshot → load draft via ThreadDraftService.loadDraft()
  ↓
If draft exists → pass as initialSnapshot to sequencer
  ↓
SequencerScreenV2 imports draft via SnapshotService
```

## Benefits

1. **No UI Blocking**: Saves happen asynchronously without delaying navigation
2. **Simple Implementation**: No complex debouncing or throttling logic
3. **Reliable**: Multiple save points (back button + dispose) ensure data safety
4. **Transparent**: Users don't need to think about saving - it just works
5. **Efficient**: Only saves when navigating away, not on every state change

## Limitations

- **No auto-save during editing**: Drafts are only saved on navigation, not continuously
- **Local only**: Drafts are device-specific and don't sync across devices
- **No versioning**: Only the latest draft is kept (older drafts are overwritten)
- **Storage dependent**: Requires local storage to be available

## Future Enhancements

Potential improvements to consider:

1. **Periodic auto-save**: Save drafts periodically (e.g., every 30 seconds) while editing
2. **Cross-device sync**: Sync drafts via server (with appropriate privacy considerations)
3. **Draft versioning**: Keep multiple draft versions with timestamps
4. **Draft cleanup**: Automatically clean up old/unused drafts
5. **Draft indicators**: Show UI indicators when a draft exists for a thread

## Related Files

- `app/lib/services/thread_draft_service.dart` - Main draft service implementation
- `app/lib/screens/sequencer_screen_v2.dart` - Sequencer screen integration
- `app/lib/screens/projects_screen.dart` - Draft loading on project open
- `app/lib/services/reliable_storage.dart` - Underlying storage mechanism
- `app/lib/services/snapshot/snapshot_service.dart` - Snapshot export/import

## Example Usage

```dart
// Initialize service
final draftService = ThreadDraftService(
  tableState: tableState,
  playbackState: playbackState,
  sampleBankState: sampleBankState,
);

// Start tracking when opening sequencer
draftService.startTracking(threadId);

// Save draft when navigating away (non-blocking)
draftService.saveDraft(); // Don't await - navigate immediately

// Load draft when opening thread
final draft = await draftService.loadDraft(threadId);
if (draft != null) {
  // Import draft into sequencer
  snapshotService.importFromJson(json.encode(draft));
}

// Clear draft when checkpoint is saved
await draftService.clearDraft(threadId);
```






