# Sequencer Header Layout

## New Button Structure

```mermaid
graph TD
    A[Sequencer Header] --> B[Left Side: Checkpoints Button]
    A --> C[Center: Recording Controls]
    A --> D[Right Side: Action Buttons]
    
    B --> E[📋 Checkpoints<br/>Orange, Always Visible]
    
    C --> F[🔴 Record Button]
    C --> G[▶️ Play Button]
    
    D --> H{Thread Context}
    H -->|All Contexts| I[💾/📤 Save/Send + 📊 Share]
```

## Button Behaviors

```mermaid
graph TD
    A[Header Buttons] --> B[Save/Send Button]
    A --> C[Share Button]
    
    B --> D{Thread Context Check}
    D -->|Unpublished Solo| E[💾 Save: Create Checkpoint<br/>Stay in same thread]
    D -->|Sourced Project| F[📤 Send: Add to Source Thread<br/>Join collaboration]
    D -->|Collaborative| G[📤 Send: Add New Checkpoint<br/>To existing thread]
    
    C --> H[Show Share Menu]
    H --> I{Thread Type?}
    I -->|Unpublished Solo| J[Show Publish Button + Recordings]
    I -->|Other| K[Show Recordings Only]
```

## Share Menu Content

```mermaid
graph TD
    A[Share Menu] --> B{Thread Context}
    B -->|Unpublished Solo| C[🟠 Publish Button<br/>+ Recordings List]
    B -->|Published/Collaborative| D[Recordings List Only]
    
    C --> E[Publish: Make Thread Public]
    C --> F[Recordings: Play/Share Audio]
    
    D --> F
```