# User Flow Documentation

## Main Navigation Flow

### 1. Initial Users Screen
**Entry Point**: App launches to users list
- **Content**: List of online users with status indicators
- **User Indicator**: Current user name displayed at top (clickable)

#### User List Features:
- **User Cards**: Show name, online status (purple dot), and current project
- **Online Indicator**: Small purple circle for active users
- **My Profile Access**: Click on your own name to view your profile

### 2. User Interaction Logic (Smart Navigation)

When clicking on any user, the system performs intelligent routing:

```
Click User → Check Common Threads
    ↓
Has Collaborations? 
    ├─ YES → Navigate to Checkpoints Screen (chat-like interface)
    └─ NO  → Navigate to User Profile Screen
```

#### Common Threads Detection:
- System queries server for threads where both users are participants
- Uses `ThreadsService.getUserThreads()` to fetch shared collaborations
- Sorts by most recent activity (`updatedAt`)

### 3. User Profile Screen

**When**: No existing collaborations with selected user
**Purpose**: Browse user's published projects and initiate new collaborations

#### Profile Layout:
```
┌─────────────────────────────────┐
│ [← Back] [Username] [Profile]   │ ← Header with purple "Profile" button
├─────────────────────────────────┤
│ 👤 [Avatar]                     │
│ User Name                       │ ← Compact profile info
│ ● Online/Offline                │
├─────────────────────────────────┤
│ Projects                        │ ← Section title
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Project Title               │ │ ← Minimalist project cards
│ │ [5] [12] [3] counters       │ │
│ │ [Listen] [Source]           │ │ ← Action buttons
│ └─────────────────────────────┘ │
│                                 │
│ [More project cards...]         │
└─────────────────────────────────┘
```

#### Project Card Elements:
- **Title**: Auto-generated or user-defined project name
- **Counters**: 
  - Checkpoints count (history icon)
  - Plays count (play icon) 
  - Collaborators count (group icon)
- **Action Buttons**:
  - **Listen**: Preview/playback (placeholder functionality)
  - **Source**: Load project for collaboration

#### Profile Button Functionality:
- Purple "Profile" button in header
- Refreshes profile data when clicked
- Ensures most up-to-date project list

### 4. Collaboration Flow (Source Button)

When user clicks **"Source"** on a project:

```
Source Button → Load Project into Sequencer
    ↓
sequencerState.loadFromThread(projectId)
    ↓
Set Collaboration Mode (isCollaborating = true)
    ↓
Navigate to Sequencer Screen
```

#### Technical Process:
1. **HTTP Request**: Fetch thread data from server
2. **State Loading**: Reconstruct sequencer state from latest checkpoint
3. **Collaboration Mode**: Enable collaboration features in UI
4. **Navigation**: Replace current screen with sequencer

### 5. Sequencer Screen (Collaboration Mode)

**Visual Changes in Collaboration Mode**:
- Share widget shows **purple "Collaborate"** button instead of gray "Publish"
- Button text: "Collaborate" vs "Publish"
- Button icon: `group_work` vs `cloud_upload`
- Button color: Purple (#764295) vs Gray

#### Share Widget Behavior:
```
Open Share Widget → Check Collaboration Mode
    ↓
isCollaborating?
    ├─ YES → Show "Collaborate" button (purple)
    └─ NO  → Show "Publish" button (gray)
```

### 6. Publishing vs Collaboration

#### New Project Publishing (Non-Collaboration):
- **Trigger**: Gray "Publish" button in share widget
- **Action**: `sequencerState.publishToDatabase()`
- **Title**: Auto-generated "Project DD/MM/YYYY HH:MM"
- **Result**: Creates new thread with current user as owner

#### Collaboration Checkpoint (Collaboration Mode):
- **Trigger**: Purple "Collaborate" button in share widget  
- **Action**: `sequencerState.createCollaborationCheckpoint()`
- **Comment**: Auto-generated "Update DD/MM/YYYY HH:MM"
- **Process**:
  1. Auto-join thread as participant (`ThreadsService.joinThread()`)
  2. Create checkpoint with current sequencer state
  3. Send to server via `ThreadsService.addCheckpoint()`

### 7. Checkpoints Screen (Chat-like Interface)

**When**: Users with existing collaborations click each other
**Purpose**: View and manage collaboration history

#### Screen Layout:
```
┌─────────────────────────────────┐
│ [← Back] [Username] [●] [Threads]│ ← Header with user context
├─────────────────────────────────┤
│ Common Threads (Pinned)         │ ← Other shared projects
│ ┌─────────────────────────────┐ │
│ │ 📌 Other Project Title      │ │
│ └─────────────────────────────┘ │
├─────────────────────────────────┤
│ Checkpoints (Chat Timeline)     │ ← Main collaboration feed
│                                 │
│ 💬 User A: "Initial version"    │
│    [Timestamp]                  │
│                                 │
│ 💬 User B: "Update 15/01 14:30" │
│    [Timestamp]                  │
│                                 │
│ 💬 You: "Update 15/01 15:45"    │
│    [Timestamp]                  │
└─────────────────────────────────┘
```

#### Header Elements:
- **Back Button**: Return to users list
- **Username**: Currently collaborating with
- **Online Indicator**: Real-time status
- **Threads Button**: Navigate between common projects

#### Pinned Common Threads:
- Shows other projects shared between users
- Allows switching between collaboration contexts
- Maintains collaboration history per project

#### Checkpoint Timeline:
- **Chat-like Interface**: Messages represent project updates
- **User Attribution**: Shows who made each update
- **Timestamps**: When each checkpoint was created
- **Chronological Order**: Latest updates at bottom

### Server Endpoints Used:
- `GET /api/v1/threads/list` - Fetch user threads
- `GET /api/v1/threads/thread?id={threadId}` - Get specific thread
- `POST /api/v1/threads/create` - Create new thread (publish)
- `POST /api/v1/threads/{threadId}/checkpoints` - Add collaboration checkpoint
- `POST /api/v1/threads/{threadId}/users` - Join thread as participant

## Data Flow

### User Authentication:
- Uses `AuthService` for current user context
- User IDs tracked throughout collaboration flow
- Automatic user addition to threads on first collaboration

### Thread Management:
- **Thread**: Container for collaborative project
- **Checkpoints**: Individual updates/saves in collaboration
- **Users**: Participants in thread with join timestamps
- **Metadata**: Project info (title, description, public/private status)

### Sequencer State:
- **Collaboration Properties**:
  - `isCollaborating`: Boolean flag for UI mode
  - `sourceThread`: Reference to original project thread
- **Snapshot System**: Captures complete sequencer state for sharing
- **Auto-save**: Background saves every 30 seconds (non-collaborative)

## Smart Navigation Examples

### Scenario 1: First-time Collaboration
```
1. User A clicks User B → No common threads → Profile Screen
2. User A clicks "Source" on User B's project → Loads in collaboration mode
3. User A makes changes → Clicks purple "Collaborate" → Creates checkpoint
4. User A returns to main menu → Clicks User B → Now goes to Checkpoints Screen
```

### Scenario 2: Ongoing Collaboration
```
1. User B clicks User A → Common threads found → Checkpoints Screen
2. Shows pinned common projects + checkpoint timeline
3. User B can see User A's latest "Update" checkpoint
4. User B clicks "Threads" to switch between shared projects
```

### Scenario 3: Multiple Collaborations
```
1. Users have 3 shared projects
2. Clicking user → Goes to most recently updated thread
3. Checkpoints screen shows other projects as "pinned"
4. Can navigate between different collaboration contexts
```

### Minimalist Design:
- Compact layouts maximizing content space
- Essential information only (counters vs verbose metadata)
- Clean typography with consistent spacing
- Reduced visual clutter for mobile-first experience

### Real-time Indicators:
- Online status dots
- Live collaboration state
- Immediate feedback via SnackBar notifications
- Dynamic button states based on context

## Technical Architecture

### State Management:
- **Provider Pattern**: React-style state management
- **SequencerState**: Audio engine and collaboration state
- **ThreadsState**: Project/thread management
- **AuthService**: User authentication and context

### HTTP Integration:
- **ThreadsService**: All server communication
- **Environment Variables**: Configurable endpoints and tokens
- **Error Handling**: Graceful fallbacks with user feedback
- **Async Operations**: Non-blocking UI with loading indicators

### Collaboration System:
- **Real-time**: Checkpoints immediately visible to all participants
- **State Synchronization**: Complete sequencer state sharing
- **Conflict Resolution**: Last-update-wins model
- **User Management**: Automatic participant tracking
