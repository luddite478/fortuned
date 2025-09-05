# Native-to-Flutter State Synchronization Pattern

This document describes our pattern for efficiently synchronizing state from native C/C++ to Flutter/Dart using FFI, the seqlock pattern, and zero‑copy reads — now with a single authoritative state struct per module (no separate "public" snapshot).

## Overview

Our audio application requires real-time synchronization between native audio engine state and Flutter UI state. The challenge is to efficiently read changing native state from Dart without blocking the audio thread or causing UI stutters.

## Core Pattern

### 1. **Native Side: Single State + Seqlock Writer**

Each module exposes one authoritative state struct. The first field is a seqlock version used for consistency. Optionally, include pointer “views” to internal arrays for zero‑copy reads.

```c
typedef struct {
    uint32_t version;        // Seqlock version (even=stable, odd=writer)

    // Scalars visible to Flutter
    bool is_playing;
    int current_step;
    int bpm;

    // Optional pointer views for zero‑copy arrays
    int* items_ptr;          // &items_storage[0]

    // Canonical storage
    int items_storage[64];
} StateStruct;

static StateStruct g_state = {0};

static inline void state_write_begin() { g_state.version++; }
static inline void state_write_end()   { g_state.version++; }

static inline void state_update_prefix() {
    // keep prefix fields coherent; set pointer views if any
    g_state.items_ptr = &g_state.items_storage[0];
}

const StateStruct* get_state_ptr() { return &g_state; }
```

**Key Points:**
- One state struct per module (single source of truth)
- Version starts at 0 (even = stable)
- Odd version = writer in progress; even = stable, safe to read
- Wrap visible mutations with `state_write_begin()`/`state_write_end()` and refresh pointer views in `state_update_prefix()` as needed

### 2. **FFI Bindings: Struct Mapping**

Dart FFI structs mirror the native prefix layout exactly (version + scalars + pointer views):

```dart
final class NativeStateStruct extends Struct {
  @Uint32()
  external int version;
  
  @Bool()
  external bool is_playing;
  
  @Int32()
  external int current_step;
  
  @Int32()
  external int bpm;

  external Pointer<Int32> items_ptr; // pointer view
}

class StateBindings {
  late final ffi.Pointer<ffi.NativeFunction<ffi.Pointer<NativeStateStruct> Function()>> _getStatePtr;
  
  ffi.Pointer<NativeStateStruct> getStatePtr() => _getStatePtr.asFunction()();
}
```

### 3. **Flutter Side: Seqlock Reader Pattern**

Flutter uses a retry loop to ensure consistent reads from the single state struct:

```dart
class AppState extends ChangeNotifier {
  // Local state fields
  bool _isPlaying = false;
  int _currentStep = 0;
  int _bpm = 120;
  
  // ValueNotifiers for UI binding
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> currentStepNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> bpmNotifier = ValueNotifier<int>(120);
  
  void syncFromNative() {
    final ptr = _bindings.getStatePtr();
    late final _NativeSnapshot snapshot;
    
    // Seqlock reader pattern
    int tries = 0;
    const maxTries = 3;
    while (true) {
      final v1 = ptr.ref.version;
      if ((v1 & 1) != 0) { // Odd = writer active
        if (++tries >= maxTries) return; // Skip this frame
        continue;
      }
      
      // Read all fields atomically from the single state struct
      snapshot = _NativeSnapshot(
        isPlaying: ptr.ref.is_playing,
        currentStep: ptr.ref.current_step,
        bpm: ptr.ref.bpm,
      );
      
      final v2 = ptr.ref.version;
      if (v1 == v2) break; // Consistent read
      if (++tries >= maxTries) return;
    }
    
    _updateFromSnapshot(snapshot);
  }
  
  void _updateFromSnapshot(_NativeSnapshot snapshot) {
    bool anyChanged = false;
    
    if (_isPlaying != snapshot.isPlaying) {
      _isPlaying = snapshot.isPlaying;
      isPlayingNotifier.value = snapshot.isPlaying;
      anyChanged = true;
    }
    
    if (_currentStep != snapshot.currentStep) {
      _currentStep = snapshot.currentStep;
      currentStepNotifier.value = snapshot.currentStep;
      anyChanged = true;
    }
    
    if (_bpm != snapshot.bpm) {
      _bpm = snapshot.bpm;
      bpmNotifier.value = snapshot.bpm;
      anyChanged = true;
    }
    
    if (anyChanged) notifyListeners();
  }
}

class _NativeSnapshot {
  final bool isPlaying;
  final int currentStep;
  final int bpm;
  
  const _NativeSnapshot({
    required this.isPlaying,
    required this.currentStep,
    required this.bpm,
  });
}
```

### 4. **Timer Integration**

A high-frequency timer drives the synchronization:

```dart
class TimerState {
  Timer? _timer;
  final AppState _appState;
  
  void start() {
    _timer = Timer.periodic(Duration(milliseconds: 16), (_) {
      _appState.syncFromNative();
    });
  }
  
  void stop() {
    _timer?.cancel();
  }
}
```

## Architecture Benefits

### **Performance**
- **Zero-copy reads**: Direct access to the single state’s pointer views
- **Minimal allocations**: Single snapshot object per frame
- **Efficient diffing**: Only changed fields trigger UI updates
- **Lock-free**: No mutexes blocking audio thread

### **Reliability**
- **Consistency**: Seqlock ensures atomic reads
- **Graceful degradation**: Retry limit prevents infinite loops
- **Thread safety**: No shared mutable state between threads

### **Maintainability**
- **Clear separation**: Native truth, Dart presentation
- **Explicit flow**: Easy to trace data path
- **Type safety**: FFI structs catch layout mismatches

## Implementation Steps

### Step 1: Define Native State
```c
// In your_module.h
typedef struct {
    uint32_t version;          // seqlock prefix
    bool my_field;             // scalars
    int another_field;
    int* items_ptr;            // pointer view
    int items_storage[64];     // storage
} YourStateStruct;

extern const YourStateStruct* your_module_get_state_ptr();
```

### Step 2: Implement Native Writer
```c
// In your_module.c
static YourStateStruct g_state = {0};

static inline void state_write_begin() { g_state.version++; }
static inline void state_write_end()   { g_state.version++; }
static inline void state_update_prefix() { g_state.items_ptr = &g_state.items_storage[0]; }

const YourStateStruct* your_module_get_state_ptr() {
    return &g_state;
}

void update_my_field(bool value) {
    state_write_begin();
    g_state.my_field = value;
    state_write_end();
}
```

### Step 3: Create FFI Bindings
```dart
// In your_module_bindings.dart
final class NativeYourStateStruct extends Struct {
  @Uint32()
  external int version;
  
  @Bool()
  external bool my_field;
  
  @Int32()
  external int another_field;

  external Pointer<Int32> items_ptr;
}

class YourModuleBindings {
  late final _getStatePtr = _lookup<ffi.NativeFunction<ffi.Pointer<NativeYourStateStruct> Function()>>('your_module_get_state_ptr');
  
  ffi.Pointer<NativeYourStateStruct> getStatePtr() => _getStatePtr.asFunction()();
}
```

### Step 4: Implement Flutter State Manager
```dart
// Follow the pattern shown in the Flutter side example above
```

## Best Practices

### **Native Side**
- Keep write sections short to minimize audio thread blocking
- Update state only when values actually change
- Use atomic operations for version if high contention expected

### **Flutter Side**
- Limit retry attempts to prevent frame drops
- Group related fields in single snapshot read
- Only call `notifyListeners()` once per sync cycle
- Dispose ValueNotifiers properly

### **FFI Bindings**
- Keep struct prefix layouts identical between C and Dart
- Use explicit sized types (@Int32, @Uint32, etc.)
- Validate pointer lifetime management

## Common Pitfalls

1. **Struct layout mismatch**: Use `@pragma('vm:ffi:struct-fields')` for verification
2. **Infinite retry loops**: Always set maxTries limit
3. **Memory leaks**: Don't dispose native pointers from Dart
4. **Race conditions**: Always use seqlock pattern for concurrent access
5. **UI stutters**: Batch multiple field updates in single notifyListeners() call

## Performance Characteristics

- **Read latency**: ~1-5 microseconds for typical struct
- **Memory overhead**: One snapshot object per sync cycle
- **CPU usage**: Negligible when no changes occur
- **Scalability**: Linear with number of state fields

This pattern has proven effective for real-time audio applications where low latency and high reliability are essential.
