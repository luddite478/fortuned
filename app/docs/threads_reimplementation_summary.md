## Threads Reimplementation Summary

### Overview
- Migrated from legacy checkpoints-centric implementation to schema-aligned threads/messages.
- Introduced a simplified architecture: thin `ThreadsApi` + stateful `ThreadsState` leveraging `SnapshotService`.
- Replaced `CheckpointsScreen` everywhere with `ThreadScreen`. Removed publish flow entirely.
- Implemented optimistic message sending, WebSocket reconciliation, and invite handling.

### New/Updated Data Models
- `app/lib/models/thread/thread.dart`: `Thread { id, createdAt, updatedAt, users: List<ThreadUser>, messageIds: List<String>, invites: List<ThreadInvite>, metadata }`.
- `app/lib/models/thread/message.dart`: `Message { id, createdAt, timestamp, userId, parentThread, metadata, snapshot: Map<String,dynamic>, localTempId?, sendStatus? }` with `SendStatus { sending, failed, sent }`.
- `app/lib/models/thread/thread_user.dart`: Lightweight thread member model.
- `app/lib/models/thread/thread_invite.dart`: Invite model with `status` as string (e.g., 'pending').

### Services
- `app/lib/services/threads_api.dart` (new): Stateless HTTP client for threads and messages:
  - getThreads, getThread, createThread, getMessages, createMessage, sendInvite, acceptInvite, declineInvite.
- `app/lib/services/snapshot/snapshot_service.dart`: Used for exporting/importing sequencer snapshots.
- WebSocket: `app/lib/services/ws_client.dart` used by `ThreadsState` to handle `message_created`.

### State Management
- `app/lib/state/threads_state.dart` (new implementation):
  - Holds identity, threads list, active thread, messages map, and UI loading/error state.
  - Depends on `WebSocketClient`, `TableState`, `PlaybackState`, `SampleBankState`.
  - Methods: loadThreads, loadThread, createThread, sendMessageFromSequencer (optimistic), retrySendMessage, applyMessage, sendInvite, acceptInvite, declineInvite.
  - WebSocket reconciliation for incoming messages, mapping to pending sends.
  - Legacy state moved out; only this state is used now.

### UI Changes
- `app/lib/screens/thread_screen.dart` (new): Replaces checkpoints UI; shows messages and integrates snapshot apply/invite UI. Publish flow removed.
- Replacements and refactors:
  - `sequencer_screen_v1.dart`, `sequencer_screen_v3.dart`, `sequencer_settings_screen.dart`: Updated to navigate to `ThreadScreen` and use new state where needed.
  - `app/lib/widgets/sequencer/v2/message_bar_widget.dart` and `v3/message_bar_widget.dart`: Updated send/navigation to `ThreadScreen` and `ThreadsState.sendMessageFromSequencer`. v3 now consumes `TableState` + `ThreadsState` only.
  - `app/lib/screens/users_screen.dart`: Migrated to new `Thread` model (`messageIds`, `invites`), replaced enum `InviteStatus` with string 'pending', fixed `AppColors` names, removed legacy checkpoints fields and navigation.

### App Bootstrap
- `app/lib/main.dart`: Wires `ThreadsState` with `wsClient`, `TableState`, `PlaybackState(tableState)`, `SampleBankState`. Removed legacy `ThreadsService` provider.

### Legacy Cleanup
- Deleted/moved legacy files:
  - Removed `app/lib/screens/checkpoints_screen.dart` and legacy wrapper.
  - Removed `app/lib/state/threads_store.dart` and `threads_state_v2.dart`.
  - Moved old state to legacy folder (no longer imported).

### WebSocket & Optimistic UI
- Register `message_created` handler in `ThreadsState` to reconcile server-created messages with pending local messages by timestamp/user and ensure unique insertion.
- Optimistic send flow with local pending message (`localTempId`, `SendStatus.sending`), update to `sent` on success, `failed` on error with retry support.

### Lint/Build Fixes Applied
- Removed uses of `ThreadV2`, `ProjectCheckpoint`, and old enums.
- Fixed `AppColors` getters to new naming (e.g., `menuBorder`, `menuText`, `menuLightText`, `menuEntryBackground`, `menuButtonBackground`, `menuOnlineIndicator`).
- Purged unused/duplicate imports across updated files.
- Adjusted `users_screen.dart` to compute pending invites via `thread.invites.any(... status == 'pending')`.

### Remaining Work (as of last update)
- Complete removal of `SequencerState` dependencies in `sequencer_screen_v1.dart`, `sequencer_screen_v3.dart`, and `sequencer_settings_screen.dart` by switching to modular states or pruning legacy selectors.
- Final pass to remove any lingering unused imports and warnings.

### Notes
- No client-side ID generation; server provides IDs.
- Threads load all messages for now; `ThreadsApi.getMessages(threadId)` used.
- No Kubernetes changes performed.


