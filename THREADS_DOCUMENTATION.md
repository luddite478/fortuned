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

