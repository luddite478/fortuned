# Online Status Testing Checklist

## Quick Test (2 minutes)

### Setup
1. **Restart server** (to load changes)
2. **Device A**: Run `./run-ios.sh stage device`
3. **Device B**: Run `./run-ios.sh stage simulator "iPhone 15"`

### Test: Close App → User Goes Offline

**Steps:**
1. Device A: Create thread, share link
2. Device B: Join thread
3. Both devices: Verify both show as online (green dots)
4. **Device B: Close app** (swipe up to kill)
5. **Wait 60 seconds**
6. Device A: Check participants widget

**Expected Result:**
- ✅ Device B shows as offline (gray dot)
- ✅ No manual refresh needed

**Server Logs:**
```
user_b disconnected (remaining: 1)
Broadcasted user user_b went offline to 1/1 online user(s)
```

**Device A Logs:**
```
🔄 [THREADS] User status changed: user_b is now offline
```

---

## Full Test Suite (10 minutes)

### Test 1: Clean Disconnect ✅
- Close app → User goes offline in <60s
- Other users see status change immediately

### Test 2: Network Failure ✅
- Turn off WiFi → User goes offline in <65s
- Other users see status change

### Test 3: Auto-Reconnect ✅
- Turn off WiFi → Turn on WiFi
- User reconnects automatically in 1-30s
- Other users see user come back online

### Test 4: Long Outage ✅
- Airplane mode for 5 minutes
- Turn off airplane mode
- User reconnects automatically
- Other users see user come back online

### Test 5: Force Quit ✅
- Force quit app (double-tap home, swipe up)
- User goes offline in <65s
- Other users see status change

---

## Expected Behavior

### Online Status Updates

| Action | Detection Time | UI Update |
|--------|---------------|-----------|
| User closes app | <60s | Immediate |
| Network dies | <65s | Immediate |
| Battery dies | <65s | Immediate |
| Force quit | <65s | Immediate |
| User reconnects | 1-30s | Immediate |

### Auto-Reconnect Timing

| Attempt | Delay |
|---------|-------|
| 1 | 1s |
| 2 | 2s |
| 3 | 4s |
| 4 | 8s |
| 5 | 16s |
| 6+ | 30s (capped) |

---

## Troubleshooting

### User Not Going Offline

**Check:**
1. Server logs: Look for "disconnected" message
2. Server logs: Look for "Broadcasted user ... went offline"
3. Client logs: Look for "User status changed"

**Common Issues:**
- Server not restarted (changes not loaded)
- Heartbeat not running (check server startup logs)
- WebSocket handler not registered (check client logs)

### User Not Reconnecting

**Check:**
1. Client logs: Look for "Reconnecting in Xs"
2. Client logs: Look for "Attempting reconnection"
3. Network connectivity

**Common Issues:**
- Auto-reconnect disabled
- Invalid user ID
- Network firewall blocking WebSocket

### Status Not Updating in UI

**Check:**
1. Is notification received? (check logs)
2. Is handler registered? (check startup logs)
3. Is notifyListeners() called?

**Solution:**
- Restart app to re-register handlers
- Check WebSocket connection status

---

## Quick Verification Commands

### Server: Check Active Clients
```bash
# In server logs, look for:
📋 Active clients: ['user1', 'user2']
```

### Server: Check Heartbeat
```bash
# Should see every 60s:
Heartbeat: Checking N connection(s)
Heartbeat: N active connection(s)
```

### Client: Check WebSocket Status
```dart
// In Flutter console:
✅ [MAIN] WebSocket connected successfully
🔌 WebSocket connected: true
```

### Client: Check Handler Registration
```dart
// In Flutter console:
Registered handler for message type: user_status_changed
```

---

## Success Criteria

✅ User goes offline when app closed  
✅ Status updates in <65s  
✅ No manual refresh needed  
✅ Auto-reconnect works  
✅ UI updates immediately  
✅ Works with bad network  
✅ Zero polling requests  

---

## If Everything Works

You should see:
1. **Real-time status updates** (no refresh needed)
2. **Automatic reconnection** (no user action)
3. **Reliable detection** (all disconnect types)
4. **Zero polling** (check network tab - no periodic requests)

**Result:** Production-ready online status system! 🎉

