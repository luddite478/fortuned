# Log Spam Reduction - Summary

## Problem
The app was generating excessive log output (350+ lines) during startup, making it difficult to debug issues:

- Every HTTP request logged: URL, params, request body, response status, response body (including huge JSON dumps)
- Every WebSocket message logged: connection, authentication, message routing
- Every native operation logged: cell updates, pattern syncs, audio callbacks
- Flutter state management logging everything

## Solution Implemented

### 1. Created Log Level System

**Flutter (Dart)** - `lib/utils/log.dart`:
- 5 log levels: `none`, `error`, `warning`, `info`, `debug`
- Configured via `.env` file: `LOG_LEVEL=info`
- Methods: `Log.d()`, `Log.i()`, `Log.w()`, `Log.e()`, `Log.s()`

**Native (C++)** - `native/log.h`:
- 5 log levels: 0=NONE, 1=ERROR, 2=WARNING, 3=INFO, 4=DEBUG
- Compile-time filtering (zero overhead)
- Macros: `prnt_debug()`, `prnt_info()`, `prnt_warn()`, `prnt_err()`

### 2. Updated Major Log Sources

#### HTTP Client (`lib/services/http_client.dart`)
**Before:**
```dart
print('🌐 POST: $finalUrl');
print('📝 Request body: $jsonBody');
print('📥 Response body: ${response.body}');
```

**After:**
```dart
Log.d('POST: $finalUrl', 'HTTP');           // debug level
Log.d('Request body: $jsonBody', 'HTTP');   // debug level
Log.d('Response body: ${response.body}', 'HTTP'); // debug level
```

#### WebSocket Client (`lib/services/ws_client.dart`)
**Before:**
```dart
print('🔗 Connecting to $serverUrl...');
print('📋 Registered handler for message type: $messageType');
print('📩 Routing message type "$type" to ${handlers.length} handler(s)');
```

**After:**
```dart
Log.d('Connecting to $serverUrl...', 'WS');  // debug level
Log.d('Registered handler for message type: $messageType', 'WS'); // debug level
Log.d('Routing message type "$type" to ${handlers.length} handler(s)', 'WS'); // debug level
```

#### Native Code (table.mm, playback_sunvox.mm, sunvox_wrapper.mm, sample_bank.mm)
**Before:**
```cpp
prnt("🎵 [TABLE] Set cell [%d, %d]", row, col);  // Always shown
prnt("✅ [TABLE] Table initialized");             // Always shown
```

**After:**
```cpp
prnt_debug("🎵 [TABLE] Set cell [%d, %d]", row, col);  // debug level only
prnt_info("✅ [TABLE] Table initialized");             // info level
```

#### Updated Files
- `lib/services/http_client.dart` - All HTTP methods
- `lib/services/ws_client.dart` - Connection and routing
- `lib/services/users_service.dart` - User API calls
- `lib/screens/sequencer_screen_v2.dart` - Sequencer lifecycle
- `native/table.mm` - Cell operations → debug
- `native/playback_sunvox.mm` - Playback operations → debug
- `native/sunvox_wrapper.mm` - SunVox operations → debug
- `native/sample_bank.mm` - Sample operations → debug

### 3. Environment Configuration

**`.env` (local development):**
```env
LOG_LEVEL=info
```

**`.stage.env` (staging):**
```env
LOG_LEVEL=info
```

**`.prod.env` (production):**
```env
LOG_LEVEL=warning  # Quieter for production
```

## Results

### Before (LOG_LEVEL not set / all logs shown)

From startup to sequencer entry (**~350+ lines** in 100 lines of terminal):
```
flutter: 🌐 POST: https://devtest.4tnd.link/api/v1/users/session
flutter: 📝 Request body: {"id":"551c849d70bd1330a9502bdf"...} [HUGE JSON]
flutter: 📥 Response status: 200
flutter: 📥 Response body: {"id":"551c849d70bd1330a9502bdf"...} [HUGE JSON]
flutter: ✅ POST /users/session completed successfully
flutter: 🌐 GET: https://devtest.4tnd.link/api/v1/users/playlist...
flutter: 📝 Query params: {user_id: 551c849d70bd1330a9502bdf...}
flutter: 📥 Response status: 200
flutter: 📥 Response body: {"playlist":[...]} [HUGE JSON]
flutter: ✅ GET /users/playlist completed successfully
flutter: 📋 Registered handler for message type: message_created
flutter: 📋 Registered handler for message type: thread_invitation
flutter: 🔗 Connecting to wss://devtest.4tnd.link:8765...
flutter: 🔐 Sent authentication with token: sdfgE$%sfds...
flutter: ✅ WebSocket connection fully established
flutter: 📋 Registered handler for message type: online_users
flutter: 📩 Routing message type "online_users" to 1 handler(s)
TABLE: 🎵 [TABLE] Set cell [0, 0]: slot=0, vol=-1.00
SUNVOX: 📝 [SUNVOX] Set pattern event [section=0, line=0, col=0]
... and 300+ more lines
```

### After (LOG_LEVEL=info)

Same scenario (**~20-30 lines**):
```
TABLE: ✅ [TABLE] Table initialized successfully
SAMPLE_BANK: ✅ [SAMPLE_BANK] Initialized with 26 slots
SUNVOX: ✅ [SUNVOX] sv_init succeeded in OFFLINE mode
SUNVOX: ✅ [SUNVOX] sv_open_slot succeeded
SUNVOX: ✅ [SUNVOX] Supertracks mode enabled
SUNVOX: ⚠️ [SUNVOX] WARNING: SunVox created 1 default pattern(s)!
SUNVOX: ✅ [SUNVOX] Deleted all default patterns
SUNVOX: ⚠️ [SUNVOX] BPM set command sent, but verification shows 125 instead of 120
SUNVOX: ✅ [SUNVOX] Created pattern 0 for section 0
PLAYBACK: ✅ [PLAYBACK] Playback system initialized (BPM: 120)
PLAYBACK: ✅ [PLAYBACK] Audio device started (48kHz, stereo, float32)
ℹ️ [WS] WebSocket connection fully established and authenticated
✅ [USER] User loaded from storage
```

**Result:** ~93% reduction in log spam!

## Benefits

1. **Drastically Cleaner Logs**: Only important information shown by default
2. **Better Performance**: Less string formatting and I/O overhead
3. **Easier Debugging**: Can enable verbose logs (`LOG_LEVEL=debug`) only when needed
4. **Production Ready**: Ship with `LOG_LEVEL=warning` or `error` for minimal overhead
5. **Flexible**: Change verbosity without code modifications
6. **Consistent**: Same system across Flutter and Native code

## Usage Examples

### Quick Toggle

**Normal use** (clean logs):
```env
LOG_LEVEL=info
```

**Debugging** (see everything):
```env
LOG_LEVEL=debug
```

**Production** (quiet):
```env
LOG_LEVEL=warning
```

### Flutter Code

```dart
import 'package:fortuned/utils/log.dart';

// Only shown at debug level
Log.d('Processing cell [$row, $col]', 'TABLE');

// Shown at info+ level (important events)
Log.i('Table initialized successfully', 'TABLE');

// Shown at warning+ level (potential issues)
Log.w('Unexpected state detected', 'TABLE');

// Always shown (except at none level)
Log.e('Failed to initialize', 'TABLE', error);
```

### Native Code

```cpp
#include "log.h"

// Only shown at debug level (NATIVE_LOG_LEVEL >= 4)
prnt_debug("🔍 Processing cell [%d, %d]", row, col);

// Shown at info+ level (NATIVE_LOG_LEVEL >= 3)
prnt_info("✅ Table initialized successfully");

// Shown at warning+ level (NATIVE_LOG_LEVEL >= 2)
prnt_warn("⚠️ Unexpected state detected");

// Always shown (NATIVE_LOG_LEVEL >= 1)
prnt_err("❌ Failed to initialize table");
```

## Migration Status

### ✅ Completed
- HTTP client (all requests/responses)
- WebSocket client (connection, routing)
- User service
- Sequencer screen V2
- Native: table, playback, sunvox wrapper, sample bank

### 🔄 Remaining (Lower Priority)
- Other Flutter screens (can be done incrementally)
- Other Flutter services (threads_service, etc.)
- Remaining native modules (recording, conversion, etc.)

The most verbose sources have been updated, reducing log spam by ~93%. Additional files can be migrated incrementally as needed.

## Documentation

- **Usage Guide**: `app/docs/LOG_LEVELS.md`
- **Full Changelog**: `CHANGELOG_LOGS.md` (if needed)
- **This Summary**: `app/docs/LOG_REDUCTION_SUMMARY.md`

