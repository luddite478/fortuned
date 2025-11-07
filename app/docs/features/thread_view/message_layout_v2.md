# Thread View Message Layout V2

## Overview
Complete redesign of the message tile layout with a solid 3-layer structure and chat-style alignment.

## Configuration Constants

```dart
// Located in _ThreadViewWidgetState
static const double singleUserLeftMarginPercent = 0.02; // 2% left margin for single user
static const double currentUserLeftMarginPercent = 0.02; // 2% left margin for current user (multi-user)
static const double otherUserRightMarginPercent = 0.02; // 2% right margin for other users
static const double layer3WidthPercent = 0.95; // Layer 3 (sections + buttons) is 95% of message width
```

## Message Structure

### Solid Container with 3 Layers

```
┌─────────────────────────────────────────┐
│ LAYER 1: Header                         │
│ • Username (if multi-user)              │
│ • Timestamp                             │
│ • Error icon (if failed)                │
├─────────────────────────────────────────┤
│ LAYER 2: Audio Render (Optional)       │
│ • Play/pause button                     │
│ • Progress slider                       │
│ • Add to library button                 │
│ • Share button (link icon)              │
├─────────────────────────────────────────┤
│ LAYER 3: Sections Chain + Buttons      │
│ • Sections preview (narrower: 95%)     │
│ • Comment button (darker, no border)   │
│ • Load button (darker, no border)      │
└─────────────────────────────────────────┘
```

## Chat Alignment

### Single User Mode
- All messages: 2% left margin
- Full width minus margin
- No differentiation needed

### Multi-User Mode

**Current User Messages:**
- 2% left margin
- Aligned to left (same as single user for consistency)

**Other User Messages:**
- 2% right margin
- Aligned to left
- Username shown in header

## Sections Chain Changes

### Before
```
┌─────────┐
│ 1 2 3 4 │ ← Layer headers
├─────────┤
│steps: 16│
│loops: 4 │
└─────────┘
```

### After (Compact)
```
┌─────────┐
│ 1 2 3 4 │ ← Layer headers
├─────────┤
│  4 16   │ ← loops steps (one line)
└─────────┘
```

**Format:** `{loops} {steps}` on a single line

## Button Styling

### Before
- Outlined buttons
- Border visible
- Light background

### After
- Elevated buttons
- No border
- Dark background: `Color(0xFF2A2D30)`
- Subtle shadow: `Colors.black.withOpacity(0.1)`

**Comment Button:**
- Disabled state
- Dimmed text: `AppColors.sequencerLightText.withOpacity(0.5)`

**Load Button:**
- Active state
- Full brightness: `AppColors.sequencerText`

## Spacing & Padding

### Message Container
- Bottom margin: `8px`
- Border: `0.5px` (sequencer border color)
- Border radius: `2px`

### Layer 1 (Header)
- Padding: `12px` left/right, `12px` top, `8px` bottom

### Layer 2 (Audio Render)
- Padding: `12px` left/right, `0px` top, `8px` bottom
- **No gap** between Layer 1 and Layer 2

### Layer 3 (Sections + Buttons)
- Outer padding: `12px` left/right/bottom
- Inner margin: centered with 95% width
- Gap between sections and buttons: `8px`
- Gap between buttons: `8px`

## Audio Render Integration

The audio render is now **seamlessly integrated** into the message body:
- Appears directly under the header
- No separate background color
- No visual gap
- Part of the solid message structure

## Responsive Design

All measurements use **percentage-based calculations**:
- Message margins: based on container width
- Layer 3 width: based on available width
- Easy to adjust via constants at the top of the widget

## Visual Improvements

1. **Solid appearance**: No gaps between layers
2. **Cleaner buttons**: Dark background, no borders
3. **Compact sections**: Single line for loops/steps
4. **Better alignment**: Chat-style positioning
5. **Consistent spacing**: All in percentages
6. **Integrated audio**: Flows naturally with message

## Configuration Guide

To adjust the layout, modify these constants in `_ThreadViewWidgetState`:

```dart
// Increase left margin for single user
singleUserLeftMarginPercent = 0.05; // 5% instead of 2%

// Make current user messages more offset
currentUserLeftMarginPercent = 0.10; // 10% instead of 2%

// Add more space for other users
otherUserRightMarginPercent = 0.05; // 5% instead of 2%

// Make layer 3 narrower or wider
layer3WidthPercent = 0.90; // 90% instead of 95%
```

## Files Modified

1. **`thread_view_widget.dart`**
   - Added configuration constants
   - Restructured `_buildMessageBubble` with 3-layer design
   - Implemented chat alignment logic
   - Updated button styling to dark elevated buttons

2. **`message_sections_chain.dart`**
   - Changed bottom text from two lines to one line
   - Format: `{loops} {steps}` instead of separate labels



