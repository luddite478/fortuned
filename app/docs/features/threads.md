# Threads System Documentation

## Overview

The Threads system provides a collaborative framework for music production where users can work together on sequencer projects or maintain versioning history for solo projects. Each thread represents a project timeline with checkpoints that capture complete project snapshots at specific points in time.

## Architecture

### Core Concept

**Thread as Project Timeline**: A thread represents a project's evolution over time, containing multiple checkpoints (snapshots) that users can create, view, and apply. Unlike traditional text-based chat systems, each "message" in a thread is a complete project snapshot rather than text.

**Multi-User Collaboration**: Threads support multiple users, with the first user being the original author. Users can join existing threads to collaborate or create solo threads for personal project versioning.

**Complete Snapshots**: Each project checkpoint contains a complete project state snapshot rather than incremental changes, ensuring any checkpoint can be independently applied to recreate the exact project state.

## Data Models

### Thread

The main container for collaborative or solo project work:

```dart
class Thread {
  final String id;
  final String title;
  final List<ThreadUser> users;        // Multiple users, first is author
  final List<ProjectCheckpoint> checkpoints;  // Project snapshots over time
  final ThreadStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> metadata;
}
```

**Key Features:**
- Supports unlimited users (multi-user collaboration)
- First user in the list is always the original author
- Can be used for solo versioning (single user)
- Tracks project evolution through checkpoints

### ThreadUser

Represents a user within a thread:

```dart
class ThreadUser {
  final String id;
  final String name;
  final DateTime joinedAt;
}
```

### ProjectCheckpoint

A complete project snapshot at a specific point in time:

```dart
class ProjectCheckpoint {
  final String id;
  final String userId;          // User who created this checkpoint
  final String userName;
  final DateTime timestamp;
  final String comment;         // Description of changes/additions
  final SequencerSnapshot snapshot;  // Complete project state
}
```

### SequencerSnapshot

Complete project data that can recreate the entire sequencer state:

```dart
class SequencerSnapshot {
  final String id;
  final String name;
  final DateTime createdAt;
  final String version;
  final ProjectAudio audio;     // Contains all project data
}
```

### ProjectAudio Structure

The complete project data structure matching the database schema:

```dart
class ProjectAudio {
  final String format;          // mp3, wav, etc.
  final double duration;        // seconds
  final int sampleRate;         // 44100, etc.
  final int channels;           // 1 (mono), 2 (stereo)
  final String url;             // URL to rendered audio (if available)
  final List<AudioRender> renders;  // Different quality renders
  final List<AudioSource> sources;  // The actual sequencer data
}
```

**AudioSource contains:**
- **Scenes**: Sequencer grid layouts with layers
- **Samples**: All audio samples used in the project

## User Flows

### 1. Solo Project Versioning

```
User A creates project → Works on beat → Saves checkpoint
                                     → Continues working → Saves another checkpoint
                                     → Can view history and revert to any checkpoint
```

### 2. Collaborative Project Creation

```
User A creates project → Saves initial checkpoint → Invites User B
User B joins thread → Views User A's checkpoint → Makes changes → Saves new checkpoint
Both users can see full history and apply any checkpoint
```

### 3. Project Improvement Flow

```
User sees another user's project → Clicks "Improve" → Creates new thread
                                                    → Applies original project as first checkpoint
                                                    → Makes improvements → Saves new checkpoint
                                                    → Original user can join thread to collaborate
```

## Technical Implementation

### Frontend (Dart/Flutter)

**State Management:**
- `ThreadsState`: Manages thread data, user interactions, and API communication
- `SequencerState`: Enhanced with snapshot creation and application methods

**Key Methods:**
```dart
// Create complete project snapshot
SequencerSnapshot createSnapshot({String? name, String? comment})

// Apply snapshot to current sequencer state
void applySnapshot(SequencerSnapshot snapshot)
```

**Services:**
- `ThreadsService`: HTTP API communication for CRUD operations
- Environment-based configuration using `SERVER_HOST` and `API_TOKEN`

### Backend (Python/FastAPI)

**Database Collection: `threads`**

```json
{
  "id": "string (UUID)",
  "title": "string",
  "users": [
    {
      "id": "string (UUID)",
      "name": "string",
      "joined_at": "datetime"
    }
  ],
  "checkpoints": [
    {
      "id": "string (UUID)",
      "user_id": "string (UUID)",
      "user_name": "string",
      "timestamp": "datetime",
      "comment": "string",
      "snapshot": {
        // Complete SequencerSnapshot with ProjectAudio data
      }
    }
  ],
  "status": "active|paused|completed|archived",
  "created_at": "datetime",
  "updated_at": "datetime",
  "metadata": {
    "original_project_id": "string (UUID) | null",
    "project_type": "collaboration|solo|remix",
    "genre": "string",
    "tags": ["string"],
    "description": "string",
    "is_public": "boolean",
    "plays_num": "number",
    "likes_num": "number",
    "forks_num": "number"
  }
}
```

**API Endpoints:**

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/threads` | Create new thread |
| GET | `/api/v1/threads` | List threads (with user filtering) |
| GET | `/api/v1/threads/{id}` | Get specific thread |
| PUT | `/api/v1/threads/{id}` | Update thread metadata |
| DELETE | `/api/v1/threads/{id}` | Archive thread |
| POST | `/api/v1/threads/{id}/checkpoints` | Add project checkpoint to thread |
| POST | `/api/v1/threads/{id}/users` | Join user to thread |
| GET | `/api/v1/threads/search` | Search threads |
| GET | `/api/v1/threads/stats` | Thread statistics |

## Database Alignment

The thread checkpoint snapshots are fully compatible with the existing database structure. Each `SequencerSnapshot` contains a `ProjectAudio` object that matches the previous `projects.audio` structure, ensuring:

1. **Backward Compatibility**: Existing project data can be imported as thread checkpoints
2. **Complete Data Preservation**: All sequencer state (grids, samples, metadata) is captured
3. **Efficient Storage**: Each checkpoint is a complete snapshot, eliminating dependency chains

## Migration from Projects to Threads

### What Changed:
- **Collection**: `projects` → `threads`
- **Structure**: Single project → Thread with checkpoints
- **Collaboration**: Individual ownership → Multi-user threads
- **Versioning**: Manual saves → Checkpoint-based history

### Migration Strategy:
1. Existing `projects` can be converted to threads with single checkpoints
2. Users maintain ownership as thread authors
3. Collaboration features become available for existing projects

## Thread Status Management

- **active**: Thread is actively being worked on
- **paused**: Temporarily inactive but can resume
- **completed**: Finished project, read-only
- **archived**: Hidden from normal views, preserved for history

## Security & Permissions

- **Thread Access**: Users must be in the thread's user list
- **Checkpoint Creation**: Any thread member can create checkpoints
- **Thread Management**: Original author can manage thread settings
- **Public/Private**: Controlled via `metadata.is_public`

## Performance Considerations

1. **Complete Snapshots**: While snapshots are complete, they enable independent checkpoint restoration
2. **Efficient Queries**: Database indexes on `users.id`, `created_at`, `updated_at`, and `status`
3. **Pagination**: All list endpoints support limit/offset pagination
4. **Search Optimization**: Text search across titles, descriptions, and tags

## Example Use Cases

### 1. Solo Producer Workflow
- Creates thread for new track
- Works on beat, saves project checkpoint: "Initial drum pattern"
- Adds bassline, saves project checkpoint: "Added bass"
- Experiments with melody, saves project checkpoint: "Melody experiment v1"
- Can revert to any previous project checkpoint if needed

### 2. Collaborative Beat Making
- Producer A creates thread with initial idea
- Producer B joins, adds elements, saves project checkpoint
- Producer A refines B's additions, saves new project checkpoint
- Both can see full evolution and contribute iteratively

### 3. Remix/Improvement Workflow
- User discovers interesting project from another user
- Clicks "Improve" to create new collaborative thread
- Original project becomes first project checkpoint
- User makes improvements and saves new project checkpoint
- Original creator can join to see improvements and collaborate

## Future Enhancements

1. **Real-time Collaboration**: WebSocket integration for live editing
2. **Branching**: Allow threads to branch into multiple parallel timelines
3. **Merge Capabilities**: Combine different thread branches
4. **Audio Rendering**: Automatic audio rendering for each project checkpoint
5. **Version Tagging**: Tag specific project checkpoints as releases or milestones
6. **Export Options**: Export thread history or specific project checkpoints

## API Usage Examples

### Creating a Thread
```javascript
POST /api/v1/threads
{
  "title": "My New Beat",
  "users": [{"id": "user123", "name": "Producer A", "joined_at": "2024-03-20T10:00:00Z"}],
  "initial_checkpoint": {
    "user_id": "user123",
    "user_name": "Producer A",
    "comment": "Initial project setup",
    "snapshot": { /* complete sequencer state */ }
  },
  "metadata": {
    "project_type": "solo",
    "genre": "electronic",
    "is_public": true
  }
}
```

### Adding a Project Checkpoint
```javascript
POST /api/v1/threads/thread123/checkpoints
{
  "checkpoint": {
    "user_id": "user123",
    "user_name": "Producer A",
    "comment": "Added snare pattern and hi-hats",
    "snapshot": { /* updated sequencer state */ }
  }
}
```

### Joining a Thread
```javascript
POST /api/v1/threads/thread123/users
{
  "user_id": "user456",
  "user_name": "Producer B"
}
```

This threads system provides a robust foundation for both solo project versioning and collaborative music creation, maintaining complete project history while enabling seamless collaboration between multiple users.

