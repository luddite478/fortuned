# Performance Optimization Guide

## UI/Audio Thread Separation Strategies

### Current Architecture Issues
- Direct FFI calls from UI thread to audio thread
- UI polling for sequencer state (100ms timer)
- No buffering of UI commands
- Potential audio dropouts from UI operations

## Architecture Options

### 1. Command Queue Pattern (Recommended)

#### Implementation
```dart
// Dart side - non-blocking command queue
class SequencerCommandQueue {
  static const int queueSize = 1024;
  late final Pointer<Uint8> _commandBuffer;
  late final Pointer<Int32> _writeIndex;
  late final Pointer<Int32> _readIndex;
  
  void enqueueSetCell(int step, int column, int sample) {
    final command = SequencerCommand(
      type: CommandType.setCell,
      step: step,
      column: column,
      sample: sample,
    );
    _writeCommand(command);
  }
  
  void enqueueVolumeChange(int slot, double volume) {
    final command = SequencerCommand(
      type: CommandType.setSampleVolume,
      slot: slot,
      floatValue: volume,
    );
    _writeCommand(command);
  }
}
```

```c++
// Native side - lock-free circular buffer
typedef struct {
    CommandType type;
    int step, column, sample, slot;
    float floatValue;
} sequencer_command_t;

typedef struct {
    sequencer_command_t commands[COMMAND_QUEUE_SIZE];
    volatile int write_index;
    volatile int read_index;
} command_queue_t;

// Audio thread processes commands (no locks needed)
void process_command_queue() {
    while (command_queue.read_index != command_queue.write_index) {
        sequencer_command_t* cmd = &command_queue.commands[command_queue.read_index];
        
        switch (cmd->type) {
            case CMD_SET_CELL:
                internal_set_cell(cmd->step, cmd->column, cmd->sample);
                break;
            case CMD_SET_VOLUME:
                internal_set_volume(cmd->slot, cmd->floatValue);
                break;
        }
        
        command_queue.read_index = (command_queue.read_index + 1) % COMMAND_QUEUE_SIZE;
  }
}
```

#### Benefits
- **Zero blocking**: UI never waits for audio thread
- **Batched processing**: Commands processed efficiently in audio thread
- **Lock-free**: Uses atomic operations for thread safety
- **Low latency**: Commands processed within one audio buffer (~11ms)

### 2. Shared Memory + Event System

#### Implementation
```dart
// Dart side - shared memory state
class SharedSequencerState {
  late final Pointer<SequencerState> _sharedState;
  late final SequencerLibrary _lib;
  
  void updateGridCell(int step, int column, int sample) {
    // Write directly to shared memory
    _sharedState.ref.grid[step][column] = sample;
    // Signal audio thread about change
    _lib.notifyGridChanged(step, column);
  }
  
  int getCurrentStep() {
    // Read directly from shared memory (no FFI call)
    return _sharedState.ref.currentStep;
  }
}
```

```c++
// Native side - memory-mapped state
typedef struct {
    volatile int grid[MAX_STEPS][MAX_COLUMNS];
    volatile float sampleVolumes[MAX_SLOTS];
    volatile int currentStep;
    volatile int isPlaying;
    volatile int bpm;
} shared_sequencer_state_t;

// Audio thread updates state, UI reads it
void audio_callback() {
    // Update sequencer
    run_sequencer();
    
    // Update shared state for UI
    g_shared_state->currentStep = g_current_step;
    g_shared_state->isPlaying = g_sequencer_playing;
}
```

#### Benefits
- **No FFI calls for reads**: UI reads state directly from memory
- **Fast updates**: Direct memory access
- **Real-time**: UI gets updates every audio frame

### 3. Native-Side UI State Cache

#### Implementation
```c++
// Native side maintains UI state separately from audio state
typedef struct {
    int ui_grid[MAX_STEPS][MAX_COLUMNS];    // UI view of grid
    int audio_grid[MAX_STEPS][MAX_COLUMNS]; // Audio engine grid
    int needs_sync;                         // Flag for sync needed
} dual_state_t;

// UI commands update UI state immediately
void ui_set_cell(int step, int column, int sample) {
    g_dual_state.ui_grid[step][column] = sample;
    g_dual_state.needs_sync = 1;
}

// Audio thread syncs periodically
void audio_callback() {
    if (g_dual_state.needs_sync) {
        sync_ui_to_audio_state();
        g_dual_state.needs_sync = 0;
    }
    
    run_sequencer(); // Uses audio_grid
}
```

#### Benefits
- **Immediate UI feedback**: UI state updates instantly
- **Controlled sync**: Audio state synced at safe times
- **No audio interruption**: Sync happens between audio buffers

## Recommended Implementation

### Phase 1: Command Queue System

1. **Create command queue in shared memory**
```c++
// In sequencer.h
typedef enum {
    CMD_SET_CELL,
    CMD_CLEAR_CELL,
    CMD_SET_SAMPLE_VOLUME,
    CMD_SET_CELL_VOLUME,
    CMD_SET_BPM,
    CMD_START_SEQUENCER,
    CMD_STOP_SEQUENCER
} command_type_t;

extern void enqueue_command(command_type_t type, int arg1, int arg2, float farg);
extern int get_current_step_cached(void);
extern int is_playing_cached(void);
```

2. **Update Dart FFI wrapper**
```dart
// In sequencer_library.dart
void setGridCell(int step, int column, int sampleSlot) {
  // Non-blocking enqueue instead of direct call
  _bindings.enqueue_command(CommandType.setCell.index, step, column, sampleSlot.toDouble());
}

int get currentStep {
  // Read cached value instead of calling into audio thread
  return _bindings.get_current_step_cached();
}
```

3. **Remove UI polling timer**
```dart
// Replace timer-based polling with direct memory reads
class SequencerState {
  void _startUIUpdateTimer() {
    // Remove Timer.periodic approach
    // UI updates on every frame via cached reads
  }
}
```

### Phase 2: Event-Driven UI Updates

1. **Add event callback system**
```c++
// Native side posts events to UI
typedef void (*ui_event_callback_t)(int event_type, int arg1, int arg2);

void set_ui_callback(ui_event_callback_t callback);
void post_ui_event(int event_type, int arg1, int arg2);
```

2. **Replace polling with events**
```dart
// Dart side receives push events instead of polling
void onSequencerEvent(int eventType, int arg1, int arg2) {
  switch (eventType) {
    case EVENT_STEP_CHANGED:
      _currentStepNotifier.value = arg1;
      break;
    case EVENT_PLAYBACK_STOPPED:
      _isSequencerPlayingNotifier.value = false;
      break;
  }
}
```

## Performance Gains Expected

- **Audio stability**: Eliminate FFI-induced audio dropouts
- **UI responsiveness**: Immediate feedback for all controls
- **CPU efficiency**: Reduce FFI overhead by 90%
- **Scalability**: Handle hundreds of UI operations without audio impact

## Migration Strategy

1. **Week 1**: Implement command queue for grid operations
2. **Week 2**: Move volume/pitch controls to command queue  
3. **Week 3**: Replace polling with cached state reads
4. **Week 4**: Add event-driven updates for real-time state

This approach will give you true independence between UI and audio threads while maintaining responsive user experience. 