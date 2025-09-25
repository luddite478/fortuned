## Messaging Loading Optimization (Proposal)

This doc outlines a minimal, low-risk optimization to reduce redundant network calls and payload sizes for threads/messages, while keeping the current product behavior intact.

### Current state (summary)
- Projects screen:
  - Loads threads list and, for invite IDs not yet in memory, calls `loadThread(id)` to fetch thread docs.
  - Does not need full message lists.
- Thread screen:
  - Calls `loadThread(threadId)` and then shows the full message list (via GET `/messages?thread_id=...`).
- Realtime:
  - WebSocket notifies on `thread_invitation`, `message_created`, `invitation_accepted`.
- Observed issue:
  - When an invite arrives, multiple call sites may call `loadThread(...)` for the same `threadId`, leading to repeated GET `/messages` with empty arrays. A client-side in‑flight lock and short debounce were added to mitigate this.

### Goals
- Avoid fetching messages unless we are on the thread screen (or explicitly requested).
- Minimize duplicate HTTP requests during screen rebuilds and invite notifications.
- Make “continue/open in sequencer” use only the latest snapshot instead of all messages.

### Proposed client changes
1) Split summary vs messages loading
   - Introduce two public methods in `ThreadsState`:
     - `ensureThreadSummary(threadId)`: fetches only the thread document (`GET /threads/{id}`) and merges it into state. No messages call.
     - `loadMessages(threadId, {force=false, limit, order})`: fetches messages for a thread on demand.
   - Keep per-thread locks and short TTL caches for both (e.g., 15 seconds), to coalesce concurrent callers and suppress noisy refreshes during builds.

2) Update call sites
   - Projects screen init and invite handling → call `ensureThreadSummary(...)` only.
   - Thread screen init → call `ensureThreadSummary(...)` then `loadMessages(threadId, force: true)`.
   - Sequencer “continue” → get only the newest snapshot (see server tweak below), not the full list.

3) Prefetch for invites without churn
   - Replace per-build `addPostFrameCallback` loops with a local Set `requestedInviteIds` to ensure each invite thread is requested at most once while the screen is mounted.
   - Alternatively, rely exclusively on the WS invitation path in `main.dart` to call `ensureThreadSummary(threadId)`; the Projects screen then simply renders from state without triggering additional loads.

4) Realtime reconciliation
   - On `message_created`: if the affected thread’s messages are already cached, append the incoming message (and mark as `sent` if reconciling with a pending). If not cached, defer until the user opens the thread.
   - On `invitation_accepted`: remove the thread ID from `pending_invites_to_threads` and update the thread’s `users` in state if it is in memory.

### Proposed server tweak (optional but recommended)
- Extend existing endpoint `GET /messages` with optional query params:
  - `limit` (int), default 100
  - `order` ("asc" | "desc"), default "asc"
- This allows the client to fetch just the newest snapshot for sequencer resume with `GET /messages?thread_id=...&limit=1&order=desc`.

### Indexing (sanity check)
- Ensure `messages` collection has an index on `{ parent_thread: 1, timestamp: -1 }` for fast per-thread pagination. If an older index references `thread_id`, align it with the `parent_thread` field currently used by the API.

### Rollout plan
1) Add `ensureThreadSummary` and `loadMessages` to `ThreadsState` with in‑flight locks and TTL caches.
2) Update Projects to stop calling messages and to dedupe invite prefetch requests.
3) Update Thread screen to call `loadMessages(threadId, force: true)`.
4) (Optional) Add `limit` and `order` support on the server and switch sequencer resume to `limit=1&order=desc`.

### Expected impact
- Fewer GET `/messages` calls (especially duplicates), lower payloads.
- No visible UX regressions; INVITES still appear instantly via WS + summary loads.
- Clear separation of concerns: list views fetch summaries; detail view fetches messages on demand.



