#ifndef UNDO_REDO_H
#define UNDO_REDO_H

#include "table.h"
#include "playback.h"
#include "sample_bank.h"

#ifdef __cplusplus
extern "C" {
#endif

#define UNDO_REDO_MAX_HISTORY 100

// A single undo/redo history snapshot holds pointers to independent module state copies
typedef struct {
    TableState* table;
    PlaybackState* playback;
    SampleBankState* sample_bank;
} SequencerSnapshot;

// Unified live state for Undo/Redo (authoritative)
typedef struct {
    // FFI-visible prefix (read directly by Dart)
    uint32_t version;            // even=stable, odd=writer in progress
    int count;                   // number of snapshots
    int cursor;                  // index of current snapshot (-1 when empty)
    int can_undo;                // 0/1 convenience
    int can_redo;                // 0/1 convenience

    // Canonical storage
    SequencerSnapshot history[UNDO_REDO_MAX_HISTORY];
    int history_count;           // number of valid snapshots in history
    int is_applying;             // guard to suppress recording while applying
} UndoRedoState;

// No separate public state; prefix fields are added to UndoRedoState below if needed.

__attribute__((visibility("default"))) __attribute__((used))
void UndoRedoManager_init(void);

__attribute__((visibility("default"))) __attribute__((used))
void UndoRedoManager_clear(void);

// Unified record: capture composite post-mutation snapshot
__attribute__((visibility("default"))) __attribute__((used))
void UndoRedoManager_record(void);

__attribute__((visibility("default"))) __attribute__((used))
int UndoRedoManager_canUndo(void);

__attribute__((visibility("default"))) __attribute__((used))
int UndoRedoManager_canRedo(void);

__attribute__((visibility("default"))) __attribute__((used))
int UndoRedoManager_undo(void);

__attribute__((visibility("default"))) __attribute__((used))
int UndoRedoManager_redo(void);

// Expose pointer to live state (can be prefix-mapped if we add visible fields)
__attribute__((visibility("default"))) __attribute__((used))
const UndoRedoState* UndoRedoManager_get_state_ptr(void);

// Expose pointer to unified live state (read-only for Dart)
__attribute__((visibility("default"))) __attribute__((used))
const UndoRedoState* undo_redo_state_get_ptr(void);

#ifdef __cplusplus
}
#endif

#endif // UNDO_REDO_H


