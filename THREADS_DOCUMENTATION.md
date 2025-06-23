# Threads Functionality Documentation

## Overview

This document describes the implementation of the "threads" functionality in the Niyya audio sequencer app, which enables collaborative project work between users. Additionally, this document covers the systematic renaming of "soundseries" terminology to "project" throughout the codebase.

## 1. Threads Functionality

### Core Concept
Threads work like a regular text chat, but each "message" contains a complete sequencer project snapshot instead of text. Users can collaborate on sequencer projects by exchanging these snapshots and applying different versions of the project.

### Architecture

#### Data Models

**ThreadMessage**
- `id`: Unique message identifier
- `userId`: User who sent the message
- `userName`: Display name of the sender
- `timestamp`: When the message was sent
- `comment`: Optional text description
- `sequencerState`: Complete project snapshot (SequencerSnapshot)

**SequencerSnapshot**
- `id`: Unique snapshot identifier
- `name`: Descriptive name for this version
- `createdAt`: Timestamp
- `version`: Version string (e.g., "1.0", "2.1")
- `audio`: ProjectAudio structure matching database schema

**ProjectAudio**
- `format`: Audio format (mp3, wav, etc.)
- `duration`: Duration in seconds
- `sampleRate`: Sample rate
- `channels`: Number of channels
- `url`: Audio file URL
- `renders`: List of AudioRender objects
- `sources`: List of AudioSource objects containing sequencer data

**CollaborativeThread**
- `id`: Unique thread identifier
- `originalProjectId`: ID of the original project being collaborated on
- `originalUserId`: Creator of the original project
- `originalUserName`: Name of original creator
- `collaboratorUserId`: ID of the collaborating user
- `collaboratorUserName`: Name of collaborator
- `projectTitle`: Title of the project
- `messages`: List of ThreadMessage objects
- `status`: Thread status (active, paused, completed, abandoned)

#### Database Schema Alignment

The sequencer snapshot structure perfectly matches the existing database schema:

```
project.audio.sources[].scenes[].layers[].rows[].cells[].sample
```

Each layer has:
- `id`: Layer identifier
- `index`: Layer position
- `rows`: Array of sequencer rows

Each cell contains:
- `sample_id`: Reference to sample
- `sample_name`: Sample display name

Metadata includes:
- `user`: Creator
- `bpm`: Beats per minute
- `key`: Musical key
- `time_signature`: Time signature

### State Management

**ThreadsState** (Provider-based state management)
- Manages all active threads
- Handles thread creation and messaging
- Provides methods for sending/receiving snapshots
- Integrates with SequencerState for snapshot creation

**SequencerState Integration**
- `createSnapshot()`: Converts current sequencer state to database-compatible format
- `applySnapshot()`: Loads a thread message state into the sequencer
- Thread-aware state tracking for collaborative features

### Service Layer

**ThreadsService**
- Handles network communication for threads
- Manages WebSocket connections for real-time collaboration
- Provides REST API integration for thread persistence
- Handles snapshot serialization/deserialization

### User Interface Integration

**User Profile Screen**
- "Improve" button starts collaborative threads
- Replaced "View All Soundseries" with "View All Projects"
- Thread creation flow with loading states and error handling

**Navigation Flow**
1. User clicks "Improve" on another user's project
2. System creates thread with initial project snapshot
3. Sequencer opens with collaborative thread active
4. Users can exchange project modifications through snapshots

## 2. Soundseries → Project Terminology Migration

### Files Modified

#### Frontend (Dart/Flutter)
- `lib/state/threads_state.dart`: Updated all data models
- `lib/services/threads_service.dart`: Updated API endpoints and parameters
- `lib/services/user_profile_service.dart`: Renamed methods and endpoints
- `lib/screens/user_profile_screen.dart`: Updated UI text and method calls
- `lib/screens/user_soundseries_screen.dart` → `lib/screens/user_projects_screen.dart`: Complete file rename and content update
- `lib/state/sequencer_state.dart`: Updated snapshot creation logic

#### Backend (Python/FastAPI)
- `server/app/http_api/router.py`: Updated all endpoints and database queries
- `server/app/db/init_collections.py`: Updated database schema and sample data

#### Design Documentation
- `server/app/db/design_patterns.py`: Updated terminology in comments and examples

### API Endpoint Changes

```
GET /soundseries → GET /projects
GET /soundseries/user → GET /projects/user  
GET /soundseries/recent → GET /projects/recent
```

### Database Schema Changes

```javascript
// Before
{
  "soundseries": {
    // collection structure
  }
}

// After  
{
  "projects": {
    // same structure, renamed collection
  }
}
```

### Class/Type Renames

| Original | Updated |
|----------|---------|
| `SoundSeriesData` | `ProjectData` |
| `SoundseriesAudio` | `ProjectAudio` |
| `originalSoundSeriesId` | `originalProjectId` |
| `soundSeriesTitle` | `projectTitle` |
| `UserSoundseriesScreen` | `UserProjectsScreen` |
| `_soundseries` variables | `_projects` |

### UI Text Updates

- "View All Soundseries" → "View All Projects"
- "No soundseries found" → "No projects found"
- "This user hasn't created any soundseries yet" → "This user hasn't created any projects yet"
- Error messages and loading states updated accordingly

## 3. Implementation Details

### Thread Creation Flow

1. **User Action**: User clicks "Improve" button on a project
2. **State Capture**: Current sequencer state is captured as initial snapshot
3. **Thread Initialization**: New thread created with:
   - Original project metadata
   - Collaborator information
   - Initial project snapshot
4. **Navigation**: User redirected to sequencer with active thread
5. **Real-time Sync**: Thread messages synchronized via WebSocket

### Snapshot Management

**Creation Process**:
1. Sequencer state extracted from current session
2. Audio structure built matching database schema
3. Metadata added (timestamp, version, user info)
4. Snapshot serialized for transmission

**Application Process**:
1. Snapshot received from thread message
2. Sequencer state cleared
3. New state applied from snapshot data
4. UI updated to reflect changes

### Error Handling

- Network failures during thread creation
- Snapshot corruption or invalid data
- User permission validation
- Database connection issues
- Rate limiting for API calls

## 4. Technical Architecture

### State Flow
```
User Action → SequencerState → ThreadsState → ThreadsService → Backend API
                     ↓
UI Updates ← ThreadsState ← WebSocket ← Backend Events
```

### Data Flow
```
Sequencer Grid → Snapshot Creation → Thread Message → Network Transmission
                                                              ↓
Network Reception ← Snapshot Application ← Thread Processing ← Message Receipt
```

### Integration Points

1. **Provider Pattern**: ThreadsState integrated into main app provider tree
2. **Service Layer**: Clean separation between business logic and network operations  
3. **Database Compatibility**: Snapshot format matches existing schema exactly
4. **Real-time Communication**: WebSocket integration for collaborative features

## 5. Future Considerations

### Scalability
- Thread message pagination for long collaborations
- Snapshot compression for large projects
- Batch operations for multiple project modifications

### Features
- Thread branching for alternative versions
- Conflict resolution for simultaneous edits
- Project version tagging and rollback
- Integration with project sharing and discovery

### Performance
- Lazy loading of thread history
- Snapshot delta compression
- Client-side caching of frequently accessed threads
- Background synchronization optimization

## 6. Development Notes

### Naming Conventions
- Consistently use "project" instead of "soundseries" in new code
- API endpoints follow RESTful conventions
- Database collections use plural naming
- Thread-related classes use "Collaborative" prefix for clarity

### Code Organization
- Thread functionality isolated in dedicated state/service files
- Clear separation between UI, business logic, and network layers
- Comprehensive error handling at all levels
- Extensive documentation for complex data transformations

This implementation provides a solid foundation for collaborative project work while maintaining compatibility with existing database schemas and user workflows. 