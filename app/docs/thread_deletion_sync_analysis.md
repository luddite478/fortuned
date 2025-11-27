# Thread Deletion Sync Analysis

## Current Implementation

### Delete Flow
1. **Optimistic removal**: `removeThreadOptimistically()` removes thread from `_threads` or `_unsyncedThreads`
2. **API call**: `ThreadsApi.deleteThread(threadId)` deletes on server
3. **Refresh**: `loadThreads()` refreshes from server
4. **Error recovery**: If API fails, refresh restores thread

## Critical Issues Found

### 🔴 **ISSUE 1: Cached Messages Not Cleaned Up**
**Problem**: When a thread is deleted, `_messagesByThread[threadId]` is never cleared.

**Impact**:
- Memory leak - messages accumulate for deleted threads
- If thread ID is reused (unlikely but possible), old messages could appear
- WebSocket handler `_onMessageCreated` checks `_messagesByThread.containsKey(threadId)` - deleted threads could still receive messages

**Location**: `removeThreadOptimistically()` doesn't clean `_messagesByThread`

**Fix Needed**: Clear messages cache when deleting thread

---

### 🔴 **ISSUE 2: Race Condition with syncOfflineThreads()**
**Problem**: `loadThreads()` calls `syncOfflineThreads()` which could restore a deleted thread.

**Scenario**:
1. User deletes thread A (optimistically removed)
2. API call completes successfully
3. `loadThreads()` is called
4. `syncOfflineThreads()` runs and processes `_unsyncedThreads`
5. If thread A was in `_unsyncedThreads` (unlikely but possible), it could be restored

**Impact**: Deleted thread could reappear if it was in unsynced state

**Location**: `loadThreads()` line 140 calls `syncOfflineThreads()`

**Fix Needed**: Filter out deleted thread IDs before syncing, or skip sync if thread was just deleted

---

### 🔴 **ISSUE 3: No WebSocket Handler for Thread Deletion**
**Problem**: If another user deletes a thread, current user won't know until manual refresh.

**Impact**:
- User might be viewing/editing a deleted thread
- UI shows thread that no longer exists
- `sendMessageFromSequencer()` could fail trying to send to deleted thread

**Location**: `_registerWsHandlers()` only registers `message_created`

**Fix Needed**: Add WebSocket handler for `thread_deleted` event

---

### 🟡 **ISSUE 4: Error Recovery Doesn't Restore Full State**
**Problem**: On API failure, refresh restores thread but not related state.

**Impact**:
- If thread had pending messages being sent, they're lost
- If thread was active and user was viewing it, state is inconsistent
- Cached messages might be out of sync

**Location**: `_deleteProject()` error handler only calls `loadThreads()`

**Fix Needed**: Better state restoration or prevent operations during delete

---

### 🟡 **ISSUE 5: Active Thread Navigation Issue**
**Problem**: If active thread is deleted, user might still be in sequencer viewing it.

**Impact**:
- User sees sequencer but thread no longer exists
- Subsequent operations (save, send message) will fail
- No navigation back to projects screen

**Location**: `removeThreadOptimistically()` clears `_activeThread` but doesn't navigate

**Fix Needed**: Navigate away from sequencer if active thread is deleted

---

### 🟡 **ISSUE 6: Double Deletion**
**Problem**: Rapid double-click on delete could cause issues.

**Scenario**:
1. First click: optimistic removal + API call starts
2. Second click: tries to delete already-removed thread (could fail or cause race)

**Impact**: 
- API might return 404 (thread already deleted)
- Error handler might restore thread incorrectly
- Race condition between two API calls

**Location**: `_deleteProject()` doesn't check if deletion is in progress

**Fix Needed**: Add deletion-in-progress flag or disable button during delete

---

### 🟡 **ISSUE 7: Offline Thread Deletion**
**Problem**: Deleting a thread from `_unsyncedThreads` that doesn't exist on server yet.

**Scenario**:
1. User creates thread offline (goes to `_unsyncedThreads`)
2. User deletes it before sync completes
3. API call fails (thread doesn't exist on server)
4. Thread is restored but will try to sync later

**Impact**:
- Delete operation fails unnecessarily
- Thread keeps reappearing when sync runs
- User confusion

**Location**: `removeThreadOptimistically()` handles unsynced threads, but API will fail

**Fix Needed**: Handle deletion of unsynced threads differently (just remove locally)

---

### 🟡 **ISSUE 8: Race Condition with Concurrent loadThreads()**
**Problem**: If `loadThreads()` is called during deletion, it could restore deleted thread.

**Scenario**:
1. Thread deleted optimistically
2. Background refresh (`refreshThreadsInBackground()`) runs
3. API delete completes
4. Refresh finishes and restores thread (if timing is wrong)

**Impact**: Deleted thread could reappear briefly

**Location**: `loadThreads()` replaces entire `_threads` list

**Fix Needed**: Track deleted thread IDs and filter them out during refresh

---

### 🟡 **ISSUE 9: Pending Invites Not Cleaned**
**Problem**: If thread is deleted but user has pending invite, invite might still show.

**Scenario**:
1. User A invites User B to thread
2. User A deletes thread
3. User B still sees invite in `pendingInvitesToThreads`
4. Accepting invite will fail

**Impact**: UI shows invalid invites, user confusion

**Location**: `_loadInvites()` loads invites without checking if thread exists

**Fix Needed**: Filter out invites for non-existent threads

---

### 🟡 **ISSUE 10: sendMessageFromSequencer to Deleted Thread**
**Problem**: If active thread is deleted while user is in sequencer, save operations will fail.

**Scenario**:
1. User opens thread in sequencer
2. Another user (or same user from another device) deletes thread
3. User tries to save → API call fails with 404

**Impact**: Silent failure or confusing error

**Location**: `sendMessageFromSequencer()` doesn't check if thread still exists

**Fix Needed**: Validate thread exists before sending, or handle 404 gracefully

---

## Recommended Fixes (Priority Order)

### Priority 1: Critical
1. **Clean up cached messages** in `removeThreadOptimistically()`
2. **Add WebSocket handler** for thread deletion events
3. **Track deleted thread IDs** to prevent restoration during refresh

### Priority 2: Important
4. **Handle offline thread deletion** (don't call API for unsynced threads)
5. **Prevent double deletion** (add in-progress flag)
6. **Navigate away** from sequencer if active thread is deleted

### Priority 3: Nice to Have
7. **Better error recovery** (restore full state on failure)
8. **Filter invalid invites** (check thread exists before showing)
9. **Validate thread exists** before `sendMessageFromSequencer()`

## Implementation Notes

### Message Cache Cleanup
```dart
Thread? removeThreadOptimistically(String threadId) {
  // ... existing code ...
  
  // Clean up cached messages
  _messagesByThread.remove(threadId);
  
  // ... rest of code ...
}
```

### Track Deleted Threads
```dart
final Set<String> _deletedThreadIds = {};

Thread? removeThreadOptimistically(String threadId) {
  _deletedThreadIds.add(threadId);
  // ... rest of code ...
}

Future<void> loadThreads({bool silent = false}) async {
  // ... existing code ...
  final result = await ThreadsApi.getThreads(userId: _currentUserId);
  // Filter out deleted threads
  final filtered = result.where((t) => !_deletedThreadIds.contains(t.id)).toList();
  _threads
    ..clear()
    ..addAll(filtered);
  // ... rest of code ...
}
```

### WebSocket Handler
```dart
void _registerWsHandlers() {
  _wsClient.registerMessageHandler('message_created', _onMessageCreated);
  _wsClient.registerMessageHandler('thread_deleted', _onThreadDeleted);
}

void _onThreadDeleted(Map<String, dynamic> payload) {
  final threadId = payload['thread_id'] as String?;
  if (threadId == null) return;
  
  // Remove optimistically if present
  removeThreadOptimistically(threadId);
  
  // Navigate away if it was active
  if (_activeThread?.id == threadId) {
    // Navigate to projects screen (need to inject navigator or use callback)
  }
}
```














