# Server-Client Data Sync

This document describes how the app synchronizes data between the server and client, with a focus on maintaining fast, responsive UI while ensuring data consistency.

## Overview

We use two different caching strategies depending on the data type:

1. **User-Owned Data** (e.g., Playlists) - Load once, optimistic updates
2. **Collaborative Data** (e.g., Threads, Followed Users) - Load once, background refresh on view

## 1. Playlist Data Sync (User-Owned)

The playlist feature demonstrates our optimistic update pattern for user-owned data that only the user can modify.

### Strategy

**Key Principle**: Since playlists are user-specific and only modifiable by the owner, we can load once and maintain state in memory for the entire session.

**Benefits**:
- ⚡ **Instant UI** - No loading spinners when switching tabs
- 📱 **Optimistic updates** - Changes appear immediately
- 🔄 **Background sync** - Network requests don't block UI
- 🛡️ **Automatic rollback** - Failed syncs revert UI state

### Initial Load Flow

```
App Startup (user login)
    ↓
main.dart: _syncCurrentUser()
    ↓
LibraryState.loadPlaylist(userId)
    ↓
Check: hasLoaded flag
    ↓
├─ Already loaded → Return immediately
│
└─ Not loaded yet:
      1. Set isLoading = true
      2. Fetch from server: GET /users/playlist?user_id={userId}
      3. Store in _playlist
      4. Set hasLoaded = true
      5. Set isLoading = false
      6. notifyListeners()
```

**Result**: Playlist is in memory for entire session. All subsequent screen visits are instant.

### Add to Playlist Flow

```
User clicks "Add to playlist"
    ↓
thread_screen.dart: _addToPlaylist()
    ↓
LibraryState.addToPlaylist(userId, render)
    ↓
1. Create PlaylistItem from Render
2. Add to _playlist (optimistic update)
3. notifyListeners() ← UI updates immediately
    ↓
4. Background sync: POST /users/playlist/add
    ↓
├─ Success → Done
│
└─ Failure:
      1. Remove item from _playlist (rollback)
      2. notifyListeners()
      3. Return false → Show error to user
```

**Timeline**:
- **T+0ms**: Item appears in playlist UI
- **T+200ms**: Server request completes (or fails and reverts)

### Remove from Playlist Flow

```
User clicks "Remove from playlist"
    ↓
library_screen.dart: _removeFromPlaylist()
    ↓
LibraryState.removeFromPlaylist(userId, renderId)
    ↓
1. Find item and save index + data
2. Remove from _playlist (optimistic update)
3. notifyListeners() ← UI updates immediately
    ↓
4. Background sync: POST /users/playlist/remove
    ↓
├─ Success → Done
│
└─ Failure:
      1. Restore item at original index (rollback)
      2. notifyListeners()
      3. Return false → Show error to user
```

**Timeline**:
- **T+0ms**: Item disappears from playlist UI
- **T+200ms**: Server request completes (or fails and reverts)

### State Management

**LibraryState** (`app/lib/state/library_state.dart`):
```dart
class LibraryState extends ChangeNotifier {
  List<PlaylistItem> _playlist = [];
  bool _isLoading = false;
  bool _hasLoaded = false;  // Session-wide flag
  
  // Private API methods (HTTP calls)
  Future<List<PlaylistItem>> _fetchPlaylistFromServer(String userId)
  Future<bool> _addToPlaylistOnServer({required String userId, required Render render})
  Future<bool> _removeFromPlaylistOnServer({required String userId, required String renderId})
  
  // Public methods
  Future<void> loadPlaylist({required String userId})  // Load once per session
  Future<bool> addToPlaylist({required String userId, required Render render})  // Optimistic add
  Future<bool> removeFromPlaylist({required String userId, required String renderId})  // Optimistic remove
  void clear()  // Clear on logout
}
```

**Note**: All HTTP API calls are encapsulated within `LibraryState`. No separate service layer is needed for playlist operations.

### Lifecycle

1. **Login**: `loadPlaylist()` called automatically in `main.dart`
2. **Session**: All operations use in-memory `_playlist`
3. **Logout**: `clear()` called in `app_settings_screen.dart`
4. **Next login**: Fresh load for new user

### Error Handling

**Network Errors**:
- UI shows optimistic update immediately
- Background sync attempts server request
- On failure: UI automatically reverts to previous state
- User sees error snackbar

**Race Conditions**:
- Not a concern since only the user can modify their playlist
- No concurrent modifications from other devices/users

## 2. Threads Data Sync (Collaborative)

The threads/projects feature demonstrates our caching pattern for collaborative data that multiple users can modify.

### Strategy

**Key Principle**: Since threads are collaborative, we cache data but refresh in background on every view to detect changes from other users.

**Benefits**:
- ⚡ **Instant UI** - Cached data shows immediately
- 🔄 **Background sync** - Detects changes without blocking
- 📡 **WebSocket updates** - Real-time updates for active threads
- 🎯 **No loading spinners** - Smooth tab switching

### Initial Load Flow

```
App Startup (user login)
    ↓
main.dart: _syncCurrentUser()
    ↓
ThreadsState.loadThreads()
    ↓
Check: hasLoaded flag
    ↓
├─ Already loaded → Return immediately
│
└─ Not loaded yet:
      1. Set isLoading = true
      2. Fetch from server: GET /threads?user_id={userId}
      3. Store in _threads
      4. Set hasLoaded = true
      5. Set isLoading = false
      6. notifyListeners()
```

**Result**: Threads list is in memory for entire session.

### Tab Switch Flow (Background Refresh)

```
User switches to Projects tab
    ↓
projects_screen.dart: _loadProjects()
    ↓
1. ThreadsState.loadThreads() - Returns cached data immediately
2. UI shows cached threads instantly
    ↓
3. Background: ThreadsState.refreshThreadsInBackground()
    ↓
4. Fetch from server: GET /threads?user_id={userId}
5. Compare with cached data
6. If changes detected → Update _threads → notifyListeners()
    ↓
7. UI updates automatically (if changes exist)
```

**Timeline**:
- **T+0ms**: Cached threads appear in UI
- **T+200ms**: Background refresh completes, UI updates if needed

### WebSocket Updates

Real-time updates continue to work alongside caching:

```
WebSocket: "message_created" event
    ↓
ThreadsState._onMessageCreated()
    ↓
Update thread in _threads list
    ↓
notifyListeners()
    ↓
UI updates immediately
```

**Integration**: WebSocket updates and cache refreshes work together seamlessly.

### State Management

**ThreadsState** (`app/lib/state/threads_state.dart`):
```dart
class ThreadsState extends ChangeNotifier {
  List<Thread> _threads = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _hasLoaded = false;
  
  // Load with caching
  Future<void> loadThreads({bool silent = false})
  
  // Background refresh
  Future<void> refreshThreadsInBackground()
  
  // WebSocket handlers (unchanged)
  void _onMessageCreated(Map<String, dynamic> payload)
}
```

### Lifecycle

1. **Login**: `loadThreads()` called automatically in `main.dart`
2. **Tab switch**: Show cached data → refresh in background
3. **Real-time updates**: WebSocket events update cache
4. **Logout**: Data cleared for next user

## 3. Followed Users Data Sync (Collaborative)

The network screen's followed users list demonstrates the same caching pattern as threads, since other users can change their online status and profile data.

### Strategy

**Key Principle**: Followed users are cached but refreshed in background on every view to show current online status and profile changes.

**Benefits**:
- ⚡ **Instant UI** - Cached list shows immediately
- 🔄 **Silent refresh** - Updates happen without UI indicators
- 📡 **WebSocket updates** - Real-time online status changes
- 🎯 **No loading spinners** - Smooth tab switching

### Initial Load Flow

```
App Startup (user login)
    ↓
main.dart: _syncCurrentUser()
    ↓
FollowedState.loadFollowedUsers(userId)
    ↓
Check: hasLoaded flag
    ↓
├─ Already loaded → Return immediately
│
└─ Not loaded yet:
      1. Set isLoading = true
      2. Fetch from server: GET /users/followed?user_id={userId}
      3. Store in _followedUsers
      4. Set hasLoaded = true
      5. Set isLoading = false
      6. notifyListeners()
```

**Result**: Followed users list is in memory for entire session.

### Tab Switch Flow (Background Refresh)

```
User switches to Network tab
    ↓
network_screen.dart: _loadFollowedUsers()
    ↓
1. FollowedState.loadFollowedUsers(userId) - Returns cached data immediately
2. UI shows cached followed users instantly
    ↓
3. Background: FollowedState.refreshFollowedUsersInBackground(userId)
    ↓
4. Fetch from server: GET /users/followed?user_id={userId}
5. Compare with cached data
6. If changes detected → Update _followedUsers → notifyListeners()
    ↓
7. UI updates silently (no spinner, no visual feedback)
```

**Timeline**:
- **T+0ms**: Cached followed users appear in UI
- **T+200ms**: Background refresh completes, UI updates silently if needed

**Note**: Unlike threads, we don't show a refresh indicator - the update is completely silent.

### Follow/Unfollow Flow

```
User follows/unfollows someone
    ↓
network_screen.dart: Follow/Unfollow action
    ↓
FollowedState.followUser() / unfollowUser()
    ↓
1. Add/Remove from _followedUsers (optimistic update)
2. notifyListeners() ← UI updates immediately
    ↓
3. Background sync: POST /users/follow or /users/unfollow
    ↓
├─ Success → Done
│
└─ Failure:
      1. Rollback optimistic update
      2. notifyListeners()
      3. Return false → Show error to user
```

**Timeline**:
- **T+0ms**: User appears/disappears from followed list
- **T+200ms**: Server request completes (or fails and reverts)

### WebSocket Updates

Real-time updates work alongside caching:

```
WebSocket: "user_online_status_changed" event
    ↓
network_screen.dart: _handleOnlineStatusChange()
    ↓
Update online status in UI
    ↓
Next background refresh syncs with FollowedState
```

**Integration**: Online status updates via WebSocket are independent of the cached followed users list.

### State Management

**FollowedState** (`app/lib/state/followed_state.dart`):
```dart
class FollowedState extends ChangeNotifier {
  List<UserProfile> _followedUsers = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _hasLoaded = false;
  
  // Load with caching
  Future<void> loadFollowedUsers({required String userId, bool silent = false})
  
  // Background refresh (silent, no UI indicator)
  Future<void> refreshFollowedUsersInBackground(String userId)
  
  // Optimistic updates
  Future<bool> followUser({required String userId, required UserProfile targetUser})
  Future<bool> unfollowUser({required String userId, required String targetUserId})
  
  // Cleanup
  void clear()
}
```

### Lifecycle

1. **Login**: `loadFollowedUsers()` called automatically in `main.dart`
2. **Tab switch**: Show cached data → refresh silently in background
3. **Follow/Unfollow**: Optimistic update with rollback on error
4. **Logout**: Data cleared for next user

## Pattern Comparison

### User-Owned Data (Playlist Pattern)
- ✅ Load once per session
- ✅ No background refresh (only user can modify)
- ✅ Optimistic updates with rollback
- ✅ Best for: playlists, settings, drafts

### Collaborative Data (Threads Pattern)
- ✅ Load once, cache for session
- ✅ Background refresh on view
- ✅ WebSocket for real-time updates
- ✅ Best for: threads, shared projects, collaborative lists, followed users

## Applicability to Other Features

**Use Playlist Pattern for**:
- User-owned data (playlists, settings, drafts)
- Single-user modification scenarios
- Data that doesn't change from server-side

**Use Threads Pattern for**:
- Collaborative data (threads, shared documents)
- Data that other users can modify
- Lists that need periodic refresh
- Social features (followed users, online status)

**Don't use caching for**:
- ❌ Individual messages (too granular)
- ❌ Real-time chat (use WebSocket only)
- ❌ Data requiring strong consistency

For real-time messaging, see WebSocket-based sync in `docs/features/websockets.md` and `docs/features/threads.md`.

## Code References

### Playlist (User-Owned Data)

**State Management & API**:
- `app/lib/state/library_state.dart` - Playlist state with optimistic updates and HTTP API calls

**UI Components**:
- `app/lib/screens/library_screen.dart` - Playlist display
- `app/lib/screens/thread_screen.dart` - Add to playlist

**Models**:
- `app/lib/models/playlist_item.dart` - PlaylistItem data model

### Threads (Collaborative Data)

**State Management**:
- `app/lib/state/threads_state.dart` - Threads state with caching and background refresh

**UI Components**:
- `app/lib/screens/projects_screen.dart` - Threads/projects list with cached display

**API Service**:
- `app/lib/services/threads_api.dart` - HTTP API calls for threads

**Models**:
- `app/lib/models/thread/thread.dart` - Thread data model

### Followed Users (Collaborative Data)

**State Management**:
- `app/lib/state/followed_state.dart` - Followed users state with caching and background refresh

**UI Components**:
- `app/lib/screens/network_screen.dart` - Network screen with followed users list

**API Service**:
- `app/lib/services/users_service.dart` - HTTP API calls for users (getFollowedUsers, followUser, unfollowUser)

**Models**:
- Uses `UserProfile` model from `users_service.dart`

### Shared

**Initialization**:
- `app/lib/main.dart` - App startup, loads playlist, threads, and followed users

**Cleanup**:
- `app/lib/screens/app_settings_screen.dart` - Logout flow (clears all cached data)

