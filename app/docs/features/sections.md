# Sections Implementation

## Overview
**Sections** are different parts of a song that can be looped independently. Each section contains its own set of sound grid layers and can be chained together to create full songs.

## UI Components

### Section Button (Left Side Control)
- **Display**: Shows "S" over current section number (e.g., "S" over "1" for Section 1)
- **Function**: Opens section control overlay when tapped
- **Visual State**: Highlights when overlay is open

### Loop Mode Button (Left Side Control) 
- **Icon**: `Icons.repeat`
- **Active State**: Bright accent color when in loop mode
- **Inactive State**: Dimmed color when in song mode
- **Function**: Toggles between loop and song playback modes

### Navigation Arrows (Side Controls)
- **Left Arrow**: Navigate to previous section (disabled if only 1 section)
- **Right Arrow**: 
  - Navigate to next section (if not on last section)
  - Open section creation overlay (if on last section)

## Section Control Overlay
- **Purpose**: Configure existing sections
- **Features**:
  - View all sections with current section highlighted
  - Adjust loop count per section (1-16 loops)
  - Display current playback mode (Loop/Song)
- **Access**: Tap section button (S1, S2, etc.)

## Section Creation Overlay
- **Purpose**: Create new sections
- **Options**:
  - **Create Blank**: Empty section with default settings
  - **Create From**: Copy existing section's content and settings
- **Access**: Right arrow when on last section

## Playback Modes

### Loop Mode
- **Behavior**: Current section repeats infinitely
- **Use Case**: Practice, live performance, jamming
- **Visual**: Loop button highlighted in accent color

### Song Mode  
- **Behavior**: Section plays specified number of times, then advances to next
- **Use Case**: Full song playback
- **End Condition**: When last section completes, playback stops
- **Visual**: Loop button dimmed

## Native Implementation

### Data Structure
```cpp
static int g_current_section = 0;        // Active section (0, 1, 2...)
static int g_total_sections = 1;         // Total number of sections  
static int g_steps_per_section = 16;     // Steps per section
static int g_section_start_step = 0;     // Starting step for current section
```

### Section Layout in Native Table
- **Concept**: Sections are **vertical stacks of steps** in the same sequencer table
- **Example**: 
  - Section 1: Steps 0-15 (16 steps)
  - Section 2: Steps 16-31 (16 steps) 
  - Section 3: Steps 32-47 (16 steps)

### Playback Logic
```cpp
void play_samples_for_step(int step) {
    // step parameter is already absolute position in sequencer table
    // Flutter calculates: absoluteStep = currentSection * stepsPerSection + relativeStep
    
    // Play samples from absolute step position
    // Uses same column logic as before
}
```

### Native API Functions
- `set_current_section(int section)`: Switch active section
- `set_total_sections(int sections)`: Update section count
- `get_current_section()`: Get current section index
- `get_total_sections()`: Get total section count

## Flutter State Management

### Data Storage
```dart
// Working grid data (current view)
List<List<int?>> _soundGridSamples;

// Section-specific storage (persistence)
Map<int, List<List<int?>>> _sectionGridData;

// Section settings
int _currentSectionIndex = 0;
List<int> _sectionLoopCounts = [1];
SectionPlaybackMode _sectionPlaybackMode = SectionPlaybackMode.loop;
```

### Section Switching Process
1. **Save**: Current grid data saved to `_sectionGridData[current]`
2. **Update**: `_currentSectionIndex` changed
3. **Load**: New section's data loaded into `_soundGridSamples`
4. **Sync**: Native sequencer updated with new section index
5. **UI**: Interface refreshes to show new section's content

### Sample Placement
- Samples placed in both working data and section storage
- Ensures visual consistency and data persistence
- Native sequencer updated immediately for audio playback

## Key Behaviors

### Section Navigation
- **Left/Right arrows**: Navigate between existing sections
- **Wrap-around**: Disabled (doesn't loop from last to first)
- **Auto-save**: Grid changes saved automatically per section

### Section Creation
- **Trigger**: Right arrow on last section opens creation overlay
- **Blank sections**: Start with empty grid, default 1 loop
- **Copied sections**: Inherit loop count, independent grid data
- **Auto-switch**: Automatically switch to newly created section

### Playback Integration
- **Loop completion**: Detected when step counter wraps from last to 0
- **Section advancement**: In song mode, advance after completing loop count
- **Native sync**: Section changes immediately update native sequencer position

## Error Handling
- **Bounds checking**: Section indices validated before access
- **Data consistency**: Section count kept in sync between Flutter and native
- **Fallback behavior**: Empty grid returned if section data missing 