# Bug: Nickname Not Syncing to Collaborators

> ℹ️ **For complete implementation guide**, see [REALTIME_COLLABORATION_SYSTEM.md](../features/REALTIME_COLLABORATION_SYSTEM.md)

## Issue Description

Multiple related issues with username/nickname synchronization:

### Issue 1: Empty Username for Link Joiner
When a user joins a project via invite link, if they don't have a username yet, other participants see them with an empty/blank username.

### Issue 2: Username Not Refreshed After Creation  
When a user creates a username via the share dialog, the username is updated in `UserState` but NOT propagated to `ThreadsState`, so subsequent join operations still use the empty name.

### Issue 3: Users Show as Offline
Both users appear offline even though they should be online (WebSocket connection issue or last_online not updating).

## Root Cause Analysis

### Issue 1 & 2: Username Synchronization Bug

**Critical Bug Location**: `app/lib/main.dart:384-387`

```dart
threadsState.setCurrentUser(
  userState.currentUser!.id,
  userState.currentUser!.name,  // ❌ WRONG: Uses 'name' instead of 'username'
);
```

**Flow**:
1. New anonymous user is created with `username = ''` and `name = ''`
2. `main.dart` calls `threadsState.setCurrentUser()` with empty `name`
3. User clicks share button and creates username "alice123"
4. `UserState.updateUsername()` updates user document on server
5. **BUT** `ThreadsState._currentUserName` is NOT updated
6. When another user joins via link, they call `joinThread()` which sends the stale empty name
7. Server receives empty username and stores it in thread document

**Server-Side Mitigation** (partially working):

In `threads.py:join_thread_handler` (lines 118-120):
```python
# Fetch username from users collection
user_doc = db.users.find_one({"id": user_id}, {"username": 1, "name": 1})
username = user_doc.get("username", user_name) if user_doc else user_name
```

This tries to fetch from database, but:
- If user just created username but `threadsState` wasn't refreshed
- The client still sends empty `user_name`
- Server fallback gets empty string from database if not synced yet

### Issue 3: Offline Status

Users appear offline because:
1. WebSocket connection may not be established
2. `last_online` timestamp not being updated frequently enough
3. No real-time online status synchronization between client/server

## Testing Scenario (Your Current Setup)

**Command**: `./run-ios.sh stage device "" clear`

**Expected Behavior**:
1. App clears storage (fresh start)
2. Creates random anonymous user
3. User clicks share → prompted for username
4. User creates username "alice123"
5. Share link generated
6. Another device joins via link
7. Should see "alice123" as participant

**Actual Behavior**:
1. ✅ Storage cleared, user created
2. ✅ Username creation prompt shown
3. ✅ Username saved to server
4. ❌ ThreadsState still has empty name
5. ❌ Link generated but username not propagated
6. ❌ Joiner sees empty username for creator
7. ❌ Both users show as offline

## Related Files

### Client-side:
- `/app/lib/main.dart:384-387` - **Bug source**: Uses `name` instead of `username`
- `/app/lib/state/user_state.dart` - Manages user profile
- `/app/lib/state/threads_state.dart:119-122` - `setCurrentUser()` method
- `/app/lib/state/threads_state.dart:1178-1195` - `joinThread()` method
- `/app/lib/services/threads_api.dart:51-64` - API call for joining

### Server-side:
- `/server/app/http_api/threads.py:101-150` - `join_thread_handler`
- `/server/app/http_api/threads.py:27-94` - `create_thread_handler`  
- `/server/app/http_api/threads.py:482-567` - `manage_invitation_handler`
- `/server/app/http_api/users.py:501-536` - `update_username_handler`

## Solutions

### Fix 1: Update ThreadsState When Username Changes (Critical)

**File**: `app/lib/main.dart`

**Change line 386**:
```dart
// BEFORE (wrong)
threadsState.setCurrentUser(
  userState.currentUser!.id,
  userState.currentUser!.name,  // ❌ Wrong field
);

// AFTER (correct)
threadsState.setCurrentUser(
  userState.currentUser!.id,
  userState.currentUser!.username,  // ✅ Use username field
);
```

**Add listener in main.dart** to update ThreadsState when username changes:

```dart
// In _syncCurrentUser() or after setCurrentUser
userState.addListener(() {
  if (userState.currentUser != null) {
    threadsState.setCurrentUser(
      userState.currentUser!.id,
      userState.currentUser!.username,
    );
  }
});
```

### Fix 2: Server-Side Thread Document Update (from previous analysis)

**File**: `server/app/http_api/users.py`

Update `update_username_handler` to sync username to thread documents:

```python
async def update_username_handler(request: Request, user_id: str, username_data: UpdateUsernameRequest):
    """Update user's username"""
    try:
        username = username_data.username.strip()
        
        # Validation (existing code)
        if len(username) < 3:
            raise HTTPException(status_code=400, detail="Username must be at least 3 characters")
        
        import re
        if not re.match(r'^[a-zA-Z0-9_-]+$', username):
            raise HTTPException(status_code=400, detail="Username can only contain letters, numbers, underscores, and hyphens")
        
        # Check if user exists
        user = db.users.find_one({"id": user_id})
        if not user:
            raise HTTPException(status_code=404, detail=f"User not found: {user_id}")
        
        # Update username in users collection
        db.users.update_one(
            {"id": user_id},
            {"$set": {
                "username": username,
                "name": username,
                "last_online": datetime.now(timezone.utc).isoformat()
            }}
        )
        
        # ✨ NEW: Update username in all threads where this user is a participant
        db.threads.update_many(
            {"users.id": user_id},
            {"$set": {
                "users.$[elem].username": username,
                "users.$[elem].name": username
            }},
            array_filters=[{"elem.id": user_id}]
        )
        
        # ✨ NEW: Broadcast username update to online collaborators via WebSocket
        from ws.router import send_user_profile_updated_notification
        try:
            await send_user_profile_updated_notification(user_id, username)
        except Exception as e:
            logger.warning(f"Failed to broadcast username update: {e}")
        
        # Return updated user
        updated_user = db.users.find_one({"id": user_id}, {"_id": 0, "password_hash": 0, "salt": 0})
        return JSONResponse(content=updated_user, status_code=200)
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update username: {str(e)}")
```

### Fix 3: WebSocket Handler for Username Updates

**File**: `server/app/ws/router.py`

Add new WebSocket notification function:

```python
async def send_user_profile_updated_notification(user_id: str, username: str) -> int:
    """Broadcast user profile update to all threads where this user is a participant.
    Returns number of recipients notified.
    """
    try:
        # Find all threads where this user is a participant
        threads_cursor = db.threads.find({"users.id": user_id}, {"id": 1, "users": 1})
        threads = list(threads_cursor)
        
        if not threads:
            return 0
        
        # Collect all unique user IDs from these threads (excluding the user who updated)
        recipient_ids = set()
        for thread in threads:
            for user in thread.get("users", []):
                if isinstance(user, dict) and user.get("id") and user["id"] != user_id:
                    recipient_ids.add(user["id"])
        
        # Send notification to all online recipients
        delivered = 0
        for recipient_id in recipient_ids:
            ws = clients.get(recipient_id)
            if ws:
                try:
                    await send_json(ws, {
                        "type": "user_profile_updated",
                        "user_id": user_id,
                        "username": username,
                        "timestamp": int(time.time())
                    })
                    delivered += 1
                except Exception as e:
                    logger.error(f"Failed to send user_profile_updated to {recipient_id}: {e}")
        
        logger.info(f"Broadcasted username update for {user_id} to {delivered} online users")
        return delivered
        
    except Exception as e:
        logger.error(f"Failed to broadcast user profile update: {e}")
        return 0
```

### Fix 4: Client WebSocket Handler

**File**: `app/lib/state/threads_state.dart`

Add handler in `_registerWsHandlers()`:

```dart
void _registerWsHandlers() {
  _wsClient.registerMessageHandler('message_created', _onMessageCreated);
  _wsClient.registerMessageHandler('user_profile_updated', _onUserProfileUpdated);  // ✨ NEW
}

void _onUserProfileUpdated(Map<String, dynamic> payload) {
  final userId = payload['user_id'] as String?;
  final username = payload['username'] as String?;
  
  if (userId == null || username == null) return;
  
  debugPrint('🔄 [THREADS] User profile updated: $userId -> $username');
  
  // Update username in all loaded threads
  bool updated = false;
  for (int i = 0; i < _threads.length; i++) {
    final thread = _threads[i];
    final updatedUsers = thread.users.map((user) {
      if (user.id == userId) {
        updated = true;
        return ThreadUser(
          id: user.id,
          username: username,
          name: username,
          joinedAt: user.joinedAt,
        );
      }
      return user;
    }).toList();
    
    if (updated) {
      _threads[i] = thread.copyWith(users: updatedUsers);
    }
  }
  
  // Also update active thread if affected
  if (_activeThread != null && updated) {
    final activeIndex = _threads.indexWhere((t) => t.id == _activeThread!.id);
    if (activeIndex >= 0) {
      _activeThread = _threads[activeIndex];
    }
  }
  
  if (updated) {
    notifyListeners();
  }
}
```

Don't forget to unregister in `disposeWs()`:

```dart
void disposeWs() {
  _wsClient.unregisterAllHandlers('message_created');
  _wsClient.unregisterAllHandlers('user_profile_updated');  // ✨ NEW
  _autoSaveTimer?.cancel();
}
```

### Fix 5: Ensure ThreadUser has copyWith

**File**: `app/lib/models/thread/thread_user.dart`

Check if `ThreadUser` has a `copyWith` method. If not, Thread model needs one:

```dart
class Thread {
  // ... existing fields ...
  
  Thread copyWith({
    String? id,
    String? name,
    List<ThreadUser>? users,
    List<Message>? messages,
    // ... other fields
  }) {
    return Thread(
      id: id ?? this.id,
      name: name ?? this.name,
      users: users ?? this.users,
      messages: messages ?? this.messages,
      // ... other fields
    );
  }
}
```

## Offline Status Fix

### Server-Side: Update last_online Regularly

**File**: `server/app/ws/router.py`

Add periodic heartbeat to update `last_online`:

```python
async def heartbeat_loop():
    """Update last_online for connected users every 30 seconds"""
    while True:
        await asyncio.sleep(30)
        for user_id in list(clients.keys()):
            try:
                db.users.update_one(
                    {"id": user_id},
                    {"$set": {"last_online": datetime.utcnow().isoformat() + "Z"}}
                )
            except Exception as e:
                logger.error(f"Failed to update last_online for {user_id}: {e}")

# Start heartbeat in start_websocket_server
async def start_websocket_server():
    logger.info("Starting WebSocket server at ws://0.0.0.0:8765")
    
    # Start heartbeat task
    asyncio.create_task(heartbeat_loop())
    
    async with websockets.serve(...):
        await asyncio.Future()
```

## Recommended Implementation Order

1. **CRITICAL**: Fix 1 (main.dart username field) - Immediate fix
2. **HIGH**: Fix 2 (server thread sync) - Ensures consistency
3. **MEDIUM**: Fix 3 & 4 (WebSocket real-time updates) - Better UX
4. **LOW**: Fix 5 (offline status) - Nice to have

## Testing Steps

1. **Setup**: Two devices/simulators
2. Device A: Run with `./run-ios.sh stage device "" clear`
3. Device A: Launch app → creates random user
4. Device A: Open sequencer → click share → create username "alice123"
5. **Verify**: Check `ThreadsState._currentUserName` is updated to "alice123"
6. Device A: Copy invite link
7. Device B: Click link
8. **Expected**: Device B sees "alice123" in participants
9. **Expected**: Both users show as online (green dot)
10. Device B: Create username "bob456"  
11. **Expected**: Device A immediately sees "bob456" update

## Additional Considerations

### Schema Consistency
The thread schema embeds user data which can become stale. Consider:
- Fetching fresh user data when displaying participants
- Periodic background sync of user data in threads
- Cache invalidation strategy

### "Dev User" Name Issue
The "Dev User" name appears when:
- `DEV_USER_ID` is set in environment
- `user_state.dart:41` uses hardcoded name "Dev User"

If you see this with empty `DEV_USER_ID=""`, check:
- Shell script parameter passing
- Environment variable parsing in Dart
- Cached build artifacts (try `flutter clean`)

### WebSocket Connection
Ensure WebSocket is connecting properly:
- Check `WEBSOCKET_HOST` and `WEBSOCKET_PORT` in `.env`
- Verify WebSocket server is running
- Check for connection errors in logs
- Test with `wscat -c wss://your-server:8765`
