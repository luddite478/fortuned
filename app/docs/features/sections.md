# Sections Implementation

## Overview
**Sections** are different parts of a song that can be looped independently or chained together in song mode. Each section contains its own set of sound grid layers and supports two distinct playback modes: **Loop Mode** (repeat current section) and **Song Mode** (play through all sections sequentially).

## Playback Modes

### Loop Mode (Default)
- **Behavior**: Current section repeats infinitely  
- **Native Logic**: Playback wraps from last step of section back to first step
- **Use Case**: Practice, live performance, jamming on specific sections
- **Visual**: Loop button highlighted in accent color
- **End Condition**: Never stops automatically (manual stop only)

### Song Mode  
- **Behavior**: Sections play sequentially according to their loop counts, then advance to next section
- **Native Logic**: Continuous playback across all sections, stops at end of final section
- **Use Case**: Full song playback, recording complete arrangements  
- **Visual**: Loop button dimmed
- **End Condition**: Stops automatically after last section completes
- **UI Updates**: Section display advances automatically during playback

## UI Components

### Section Button (Left Side Control)
- **Display**: Shows "S" over current section number (e.g., "S" over "1" for Section 1)
- **Function**: Opens section control overlay when tapped
- **Visual State**: Highlights when overlay is open
- **Song Mode**: Updates automatically to show currently playing section

### Loop Mode Button (Left Side Control) 
- **Icon**: `Icons.repeat`
- **Active State**: Bright accent color when in loop mode
- **Inactive State**: Dimmed color when in song mode
- **Function**: Toggles between loop and song playback modes
- **Effect**: Changes native sequencer behavior immediately

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

## Native Implementation

### Data Structure
```cpp
static int g_current_section = 0;        // UI metadata only (doesn't affect playback)
static int g_total_sections = 1;         // Total sections for song length calculation
static int g_steps_per_section = 16;     // Steps per section
static int g_section_start_step = 0;     // Calculated metadata for UI
static int g_song_mode = 0;              // 0 = loop mode, 1 = song mode
```

### Continuous Playback Architecture

**KEY CHANGE**: Native sequencer now operates on **absolute steps** across all sections:

- **Section Layout**: Sections are vertical stacks in a continuous table
  - Section 1: Steps 0-15 (16 steps)
  - Section 2: Steps 16-31 (16 steps) 
  - Section 3: Steps 32-47 (16 steps)

- **Playback Logic**: No section boundaries during playback
  ```cpp
  // Native handles mode-specific looping
  if (g_song_mode) {
      // Song mode: stop at end of all sections
      int song_end_step = g_total_sections * g_steps_per_section;
      if (g_current_step >= song_end_step) {
          g_sequencer_playing = 0;  // Stop naturally
      }
  } else {
      // Loop mode: wrap within current section
      int section_end_step = g_section_start_step + g_steps_per_section;
      if (g_current_step >= section_end_step) {
          g_current_step = g_section_start_step;  // Wrap to section start
      }
  }
  ```

### Native API Functions
- `start_sequencer(bpm, steps, startStep)`: **NEW** - Start with absolute step position
- `set_song_mode(isSongMode)`: **NEW** - Set playback mode (0=loop, 1=song)
- `set_current_section(section)`: **CHANGED** - Now UI metadata only, doesn't affect playback
- `set_total_sections(sections)`: Update section count for song length calculation
- `get_current_section()`: Get UI metadata section index
- `get_total_sections()`: Get total section count

### Section Metadata vs Playback

**IMPORTANT DISTINCTION**: Section functions are now **UI metadata only**:

```cpp
void set_current_section(int section) {
    // Update metadata only; playback is continuous across absolute steps
    g_current_section = section;
    g_section_start_step = g_current_section * g_steps_per_section;
    
    // NO PLAYBACK INTERRUPTION - audio continues smoothly
    prnt("ℹ️ [SECTION] Meta set current section to %d. Playback unaffected.", section);
}
```

**Benefits**:
- No audio artifacts at section boundaries
- Smooth continuous playback across all sections
- Section UI updates don't interrupt audio flow

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
4. **UI Sync**: Native metadata updated with `set_current_section()` (UI only)
5. **Interface**: UI refreshes to show new section's content

**Note**: During playback, section switching only affects UI display - audio continues uninterrupted.

### Song Mode UI Tracking

**NEW APPROACH**: UI computes current section from native absolute step:

```dart
// During playback polling:
final absoluteStep = sequencerLibrary.currentStep;

if (sectionPlaybackMode == SectionPlaybackMode.song) {
    // Compute current section from absolute step
    final currentSectionFromAbsoluteStep = absoluteStep ~/ gridRows;
    
    // Update UI if section changed
    if (currentSectionFromAbsoluteStep != currentSectionIndex) {
        currentSectionIndex = currentSectionFromAbsoluteStep;
        notifyListeners(); // Update section display
    }
}
```

**Benefits**:
- Section display always matches actual playback position
- No timing-dependent wrap-around detection
- Immediate UI updates during song mode progression
- Simpler, more reliable logic

### Sample Placement
- Samples placed in both working data and section storage
- Native sequencer sees complete concatenated table of all sections
- Grid sync operation sends all sections to native as continuous table
- Individual cell changes sync immediately for real-time updates

## Key Behaviors

### Section Navigation
- **Manual Navigation**: Left/Right arrows navigate between sections (UI only)
- **Automatic Navigation**: In song mode, UI follows playback automatically
- **During Playback**: Manual navigation changes UI view but doesn't interrupt audio
- **Auto-save**: Grid changes saved automatically per section

### Section Creation
- **Trigger**: Right arrow on last section opens creation overlay
- **Blank sections**: Start with empty grid, default 1 loop
- **Copied sections**: Inherit loop count, independent grid data
- **Auto-switch**: Automatically switch to newly created section
- **Native Update**: Total section count updated for song length calculation

### Playback Integration

#### Loop Mode
- **Behavior**: Playback stays within current section boundaries
- **Native**: Wraps from section end back to section start
- **UI**: Section display remains static
- **Manual Override**: User can navigate to different section (changes view only)

#### Song Mode  
- **Behavior**: Continuous playback across all sections
- **Native**: Stops automatically at end of final section
- **UI**: Section display advances automatically with playback
- **End Detection**: Both native and Flutter monitor for end condition
- **Natural Stop**: Final sounds allowed to decay naturally

## Error Handling
- **Bounds checking**: Section indices validated before access
- **Data consistency**: Section count kept in sync between Flutter and native
- **Playback isolation**: UI navigation errors don't affect audio playback
- **Fallback behavior**: Empty grid returned if section data missing

## Performance Improvements

### Eliminated Issues
1. **Section Boundary Clicks**: No more audio artifacts when sections change
2. **Timing Dependencies**: Removed complex wrap-around detection logic
3. **Playback Interruptions**: Section changes don't restart or seek audio
4. **UI Lag**: Section display updates immediately during song mode

### Enhanced Experience
1. **Continuous Audio**: Seamless playback across entire song
2. **Responsive UI**: Section display always matches playback position  
3. **Professional Quality**: Natural song endings without artifacts
4. **Simplified Logic**: More reliable section tracking and fewer edge cases

This architecture provides professional-quality song mode playback while maintaining the flexibility of individual section editing and preview. 