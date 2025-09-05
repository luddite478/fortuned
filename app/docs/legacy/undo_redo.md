# Undo-Redo System

**Professional-grade undo-redo functionality for all sequencer operations with smart debouncing for slider controls.**

## Overview

The sequencer includes a comprehensive undo-redo system that tracks all user actions and allows them to experiment freely without fear of losing work. The system maintains up to 100 actions in history with intelligent batching for rapid changes.

## User Interface

**Location:** Bottom edit bar alongside selection, copy, paste, and delete controls

**Buttons:**
- **Undo** (↶): Reverts the last action with descriptive tooltip
- **Redo** (↷): Re-applies undone actions

**Visual Feedback:**
- Buttons are enabled/disabled based on availability
- Tooltips show action descriptions (e.g., "Undo: Place Sample A at R1C2")

## Tracked Operations

### Immediate Recording
- **Grid Operations**: Place/remove samples in cells, multi-cell batch operations
- **Sample Management**: Load/remove samples from slots  
- **Grid Management**: Add/remove sound grid layers
- **Batch Operations**: Copy/paste/delete multiple cells

### Debounced Recording (800ms delay)
- **Volume Controls**: Sample and cell-level volume adjustments
- **Pitch Controls**: Sample and cell-level pitch modifications

## Smart Debouncing

**Problem:** Slider controls generate hundreds of micro-changes that would flood the undo history.

**Solution:** Debounced recording captures initial state on first change and final state after 800ms of inactivity.

**Example:**
- **Before:** Moving volume slider 0% → 100% creates 50+ undo actions
- **After:** Same movement creates 1 clean action: `"Set Sample A Volume: 75%"`

**Auto-Flush:** Pending debounced actions are automatically flushed before major operations (undo/redo, grid changes, sample operations).

## Technical Implementation

### Core Components

```dart
// Action types for different operations
enum UndoRedoActionType {
  gridCellChange, sampleLoad, sampleRemove, 
  volumeChange, pitchChange, gridAdd, gridRemove,
  multipleCellChange
}

// Manages 100-action rolling history
class UndoRedoManager {
  static const int maxHistorySize = 100;
  // ... implementation
}
```

### State Management

**Full State Capture:** Each action stores complete before/after snapshots including:
- Sound grid samples data
- Sample file paths and metadata  
- Volume/pitch settings (sample and cell level)
- Grid labels and ordering
- BPM settings

**Native Sync:** All undo/redo operations automatically synchronize with the native audio engine.

### Performance Optimizations

- **Minimal Overhead:** State capture only occurs during actual changes
- **Memory Efficient:** Rolling 100-action history with automatic cleanup
- **Thread Safe:** Proper isolation during undo/redo operations

## Usage Examples

### Basic Operations
```
User Action                 → Undo Description
─────────────────────────── → ─────────────────────
Place sample in cell       → "Place Sample A at R1C2"
Delete 5 selected cells    → "Delete 5 cells"  
Load drum sample           → "Load Sample B: drum_kick.wav"
Add new sound grid         → "Add Sound Grid 3"
Paste to multiple cells    → "Paste to 8 cells"
```

### Slider Operations
```
User Action                 → Undo Description
─────────────────────────── → ─────────────────────
Adjust volume slider       → "Set Sample A Volume: 85%"
Modify pitch control       → "Set Cell R2C1 Pitch: 1.25x"
```

## Integration Points

- **SequencerState**: Core state management with undo tracking
- **EditButtonsWidget**: UI controls for undo/redo operations
- **Native Audio Engine**: Automatic synchronization during state restoration
- **Settings Widgets**: Debounced recording for slider controls

## Benefits

- **Creative Freedom**: Experiment without fear of losing work
- **Clean History**: Smart debouncing prevents clutter from slider adjustments
- **Descriptive Actions**: Clear, human-readable action descriptions
- **Professional UX**: Industry-standard undo/redo behavior
- **Performance**: Optimized for real-time audio applications 