# Online Status Test Plan

## What I Fixed

### 1. Added WebSocket Notification to `/join` Endpoint ✅

**File**: `server/app/http_api/threads.py`

When a user joins via deep link (`POST /threads/{id}/join`), the server now:
- Adds user to thread in database
- **NEW**: Broadcasts `invitation_accepted` WebSocket notification to all thread members
- Notification includes **complete participant list** with current `is_online` status

### 2. Enhanced WebSocket Notification Payload ✅

**File**: `server/app/ws/router.py`

The `invitation_accepted` notification now includes:
```json
{
  "type": "invitation_accepted",
  "thread_id": "...",
  "user_id": "newly_joined_user_id",
  "user_name": "newly_joined_username",
  "participants": [
    {
      "id": "user1",
      "username": "alice",
      "name": "Alice",
      "is_online": true,  // ← Computed from WebSocket clients
      "joined_at": "2025-12-30T10:00:00Z"
    },
    {
      "id": "user2",
      "username": "bob",
      "name": "Bob",
      "is_online": false,
      "joined_at": "2025-12-30T10:05:00Z"
    }
  ]
}
```

### 3. Client Processes Complete Participant List ✅

**File**: `app/lib/state/threads_state.dart`

When receiving `invitation_accepted`, client now:
- Replaces entire `thread.users` array with fresh data from server
- Includes correct `is_online` status for ALL participants
- Triggers `notifyListeners()` → UI updates immediately

---

## The Root Issue

Looking at your logs, the problem is **WebSocket connection timing**:

```
10:41:57.277 - INFO - connection open (user 'clear' attempting to connect)
10:41:57.278 - INFO - New connection from 172.20.0.2
[NO AUTH COMPLETION LOG]
```

User `clear` opened a WebSocket connection but **never completed authentication**. That's why they show as offline.

**Timeline**:
1. User `clear` opens app
2. User `clear` clicks deep link `/join/thread_id`
3. HTTP: `POST /threads/{id}/join` (completes immediately)
4. WebSocket: Still authenticating (takes 0-2 seconds)
5. Server sends notification with `clear: is_online=False` (not in `clients` dict yet)
6. WebSocket completes authentication (too late)

---

## How to Test

### Test 1: Basic Join Flow

**Steps**:
1. Device A (`iphone2323`): Create thread, get invite link
2. Device B (`clear`): **WAIT for app to fully load** (2-3 seconds)
3. Device B: Click invite link
4. Device B: Accept invitation

**Expected Logs (server)**:
```
INFO - ✅ clear connected (total: 2)
INFO - invitation_accepted: user=clear joined thread ...
INFO -   Sending 2 participants with online status
INFO -   Delivered invitation_accepted to 1/1 recipients
```

**Expected Result**:
- Device A sees Device B appear in participants widget immediately
- Both users show as online (green dots)

### Test 2: Client-Side Logging

**Add to Device B console output**:
```
🎉 [THREADS] Invitation accepted: papa joined thread ...
   Participants in payload: 2
     - iphone2323 (is_online: true)
     - papa (is_online: true)
✅ [THREADS] Updated thread with 2 participants
```

**Expected Result**:
- Participants widget shows immediately (no waiting for checkpoint)
- Online status correct for both users

### Test 3: Offline User Joins

**Steps**:
1. Device A (`iphone2323`): Create thread
2. Device B (`clear`): **Close WebSocket** (disconnect)
3. Device B: Click invite link, accept
4. Device A: Should see Device B as offline

**Expected Logs**:
```
INFO -    User iphone2323: is_online=True
INFO -    User clear: is_online=False  (not connected)
```

---

## Debugging Commands

### Server-Side: Check Active WebSocket Clients

```python
# In server logs, look for:
INFO - 📋 Active clients: ['user1', 'user2', ...]
```

### Client-Side: Check WebSocket Connection

Add to your app:
```dart
// In main.dart or wherever you join thread
debugPrint('🔌 WebSocket connected: ${wsClient.isConnected}');
debugPrint('🆔 Client ID: ${wsClient.clientId}');
```

### Check if Notification is Received

```dart
// In threads_state.dart (already added)
debugPrint('🎉 [THREADS] Invitation accepted: $userName joined');
debugPrint('   Participants: ${participants?.length}');
```

---

## Common Issues & Fixes

### Issue 1: User Not in `clients` Dict

**Symptom**: User shows offline when they should be online

**Cause**: WebSocket authentication failed or timed out

**Fix**: Check server logs for:
```
INFO - New connection from ...
INFO - ✅ [user_id] connected  // ← Should see this
```

If missing, check:
- API token is correct
- Client ID is valid 24-hex string
- No firewall blocking WebSocket port

### Issue 2: Notification Not Received

**Symptom**: Participants widget doesn't update

**Cause**: WebSocket handler not registered or disconnected

**Fix**: Check client logs for:
```
🔌 [WS] Attempting WebSocket connection...
✅ [WS] WebSocket connected successfully
Registered handler for message type: invitation_accepted
```

### Issue 3: Timing Race Condition

**Symptom**: Intermittent - sometimes works, sometimes doesn't

**Cause**: HTTP join completes before WebSocket connects

**Fix**: Already handled! Now that we send complete participant list:
- If user connected → shows online
- If not connected → shows offline  
- When they connect → auto-sync refreshes status

---

## What to Check in Your Next Test

1. **Server logs**: Look for "✅ clear connected" message
2. **Client logs**: Look for "Participants in payload: 2"
3. **Participants widget**: Should show immediately after join
4. **Online status**: Both dots should be green if both connected

---

## Summary

**What changed**:
- `/join` endpoint now sends WebSocket notification
- Notification includes complete participant list with `is_online`
- Client updates all participants immediately

**What should happen now**:
- Participants widget shows immediately (no waiting for checkpoint)
- Online status correct for ALL users (including inviter)
- Works whether WebSocket connected before or after join

**Key requirement**:
- Users must have active WebSocket connection to show as online
- App should connect WebSocket on startup (you already do this)
- Connection must complete authentication (<10 seconds)

**Next steps**:
1. Restart server (to load changes)
2. Test with 2 devices
3. Check logs for "✅ connected" messages
4. Verify participants widget appears immediately

