# Projects Screen - New 4-Section Layout

## Overview

The projects screen now uses a structured 4-section layout where each project tile is divided into distinct sections with controllable spacing.

---

## Tile Structure

Each project tile has **4 main sections** arranged horizontally:

```
┌─────────────────────────────────────────────────────────────────┐
│ Section 1 (55%)    │ Sec 2 (10%)  │ Sec 3 (17.5%) │ Sec 4 (17.5%) │
│ Pattern + Sample   │ Collab Icon  │ Created Date  │ Modified Date │
│                    │   (empty)    │               │               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Layout Variables (Lines 37-58)

### Section Width Distribution

```dart
static const double _section1WidthPercent = 55.0;   // Pattern + Sample
static const double _section2WidthPercent = 10.0;   // Collaborative icon (empty)
static const double _section3WidthPercent = 17.5;   // Created date
static const double _section4WidthPercent = 17.5;   // Modified date
```

**Total should equal 100%**

### Section 1 (Pattern + Sample) Internal Layout

```dart
// Padding around Section 1 content (% of section size)
static const double _section1PaddingTopPercent = 10.0;
static const double _section1PaddingBottomPercent = 10.0;
static const double _section1PaddingLeftPercent = 3.0;
static const double _section1PaddingRightPercent = 3.0;

// Content distribution within Section 1
static const double _patternWidthPercent = 70.0;    // Pattern table width
static const double _sampleWidthPercent = 25.0;     // Sample table width
static const double _patternSampleSpacingPercent = 5.0;  // Space between them
```

**These percentages are relative to Section 1's content area (after padding)**

### Section 3 & 4 (Date Columns) Padding

```dart
// Padding for date sections (% of their respective sizes)
static const double _datePaddingTopPercent = 0.0;
static const double _datePaddingBottomPercent = 0.0;
static const double _datePaddingLeftPercent = 5.0;
static const double _datePaddingRightPercent = 5.0;
```

### Cell Spacing (Pixels, Not Percentages)

```dart
static const double _patternCellMargin = 0.4;   // Between pattern cells
static const double _sampleCellMargin = 0.5;    // Between sample cells
```

---

## Visual Layout Breakdown

### Tile Structure

```
Project Tile (100% width × 80px height)
├─ Section 1 (55% width)
│  ├─ Padding: top 10%, bottom 10%, left 3%, right 3%
│  └─ Content Area (after padding)
│     ├─ Pattern Preview (70% of content)
│     ├─ Spacing (5% of content)
│     └─ Sample Table (25% of content)
│
├─ Section 2 (10% width)
│  └─ Empty (for collaborative icon)
│
├─ Section 3 (17.5% width)
│  └─ Created Date (centered, with optional padding)
│
└─ Section 4 (17.5% width)
   └─ Modified Date (centered, with optional padding)
```

### Section 1 Detailed Layout

```
┌─ Section 1 (55% of tile) ────────────────────┐
│ ← 3% padding                                  │ ↑
│                                               │ 10% padding
│  ┌───────────────┐  ┌────┐                   │ ↓
│  │  Pattern      │  │Smpl│                   │
│  │  Preview      │  │Tbl │                   │ Content
│  │  (70%)        │  │25% │                   │ Area
│  └───────────────┘  └────┘                   │
│       ↑              ↑                        │ ↑
│       └──── 5% ──────┘                        │ 10% padding
│                                 3% padding → │ ↓
└───────────────────────────────────────────────┘
```

---

## How Sizing Works

### Example Calculation (800px wide screen)

**Step 1: Calculate section widths**
```
Section 1: 800 × 55% = 440px
Section 2: 800 × 10% = 80px
Section 3: 800 × 17.5% = 140px
Section 4: 800 × 17.5% = 140px
```

**Step 2: Section 1 padding (from its 440px width)**
```
Padding Left:   440 × 3% = 13.2px
Padding Right:  440 × 3% = 13.2px
Content Width:  440 - 26.4 = 413.6px

Padding Top:    80 × 10% = 8px
Padding Bottom: 80 × 10% = 8px
Content Height: 80 - 16 = 64px
```

**Step 3: Pattern & Sample distribution (from 413.6px content width)**
```
Pattern Width: 413.6 × 70% = 289.5px
Spacing:       413.6 × 5% = 20.7px
Sample Width:  413.6 × 25% = 103.4px
```

**Step 4: Date sections padding (from their 140px widths)**
```
Date Padding Left:  140 × 5% = 7px
Date Padding Right: 140 × 5% = 7px
Date Content Width: 140 - 14 = 126px
```

---

## Header Alignment

The header now aligns perfectly with the tile sections:

```
┌─────────────────────────────────────────────────────────┐
│ Patterns                        Created ↓    Modified ↓ │  ← Header
├─────────────────────────────────────────────────────────┤
│ [Pattern] [Smpl]   [Empty]      11/18        11/20      │  ← Tile 1
│ [Pattern] [Smpl]   [Empty]      11/16        11/16      │  ← Tile 2
└─────────────────────────────────────────────────────────┘

Section widths:
   55%           10%      17.5%       17.5%
```

- "Patterns" label aligns with Section 1 content (respects left padding)
- Empty space aligns with Section 2
- "Created" header aligns with Section 3
- "Modified" header aligns with Section 4

---

## Adjusting the Layout

### Change Section Widths

**Lines 39-42** - Adjust width distribution:
```dart
static const double _section1WidthPercent = 55.0;   // Increase for more pattern space
static const double _section2WidthPercent = 10.0;   // Collab icon space
static const double _section3WidthPercent = 17.5;   // Date column widths
static const double _section4WidthPercent = 17.5;
```

**Important:** Total should equal 100%

### Adjust Section 1 Padding

**Lines 45-48** - Control spacing around pattern/sample:
```dart
static const double _section1PaddingTopPercent = 10.0;     // More = smaller content
static const double _section1PaddingBottomPercent = 10.0;
static const double _section1PaddingLeftPercent = 3.0;     // More = content moves right
static const double _section1PaddingRightPercent = 3.0;
```

### Adjust Pattern vs Sample Size

**Lines 49-51** - Control relative sizes:
```dart
static const double _patternWidthPercent = 70.0;   // Larger pattern
static const double _sampleWidthPercent = 25.0;    // Smaller sample
static const double _patternSampleSpacingPercent = 5.0;  // Gap between them
```

**These must add up to 100% (70 + 25 + 5 = 100)**

### Adjust Date Column Padding

**Lines 54-57** - Control date text spacing:
```dart
static const double _datePaddingTopPercent = 0.0;      // Add top spacing
static const double _datePaddingBottomPercent = 0.0;   // Add bottom spacing
static const double _datePaddingLeftPercent = 5.0;     // Left margin
static const double _datePaddingRightPercent = 5.0;    // Right margin
```

---

## Key Functions

### `_buildProjectCard` (Line 493)
- Main tile builder
- Calculates section widths
- Delegates to sub-builders

### `_buildSection1PatternAndSample` (Line 557)
- Handles Section 1 layout
- Calculates padding
- Positions pattern and sample tables

### `_buildDateSection` (Line 599)
- Handles Section 3 & 4 layout
- Centers date text
- Applies padding

---

## Common Adjustments

### Make Pattern Table Larger
1. Increase `_section1WidthPercent` (e.g., from 55% to 60%)
2. Decrease `_section3WidthPercent` and `_section4WidthPercent` accordingly

### Add More Space Around Pattern/Sample
Increase padding percentages:
```dart
static const double _section1PaddingTopPercent = 15.0;     // Was 10.0
static const double _section1PaddingLeftPercent = 5.0;     // Was 3.0
```

### Adjust Pattern vs Sample Ratio
```dart
static const double _patternWidthPercent = 75.0;   // Was 70.0 (bigger pattern)
static const double _sampleWidthPercent = 20.0;    // Was 25.0 (smaller sample)
static const double _patternSampleSpacingPercent = 5.0;  // Keep spacing
```

### Center Date Text Better
```dart
static const double _datePaddingLeftPercent = 10.0;   // Was 5.0
static const double _datePaddingRightPercent = 10.0;  // Was 5.0
```

---

## Responsive Behavior

All dimensions scale automatically with screen size:

**Small Phone (350px)**
```
Section 1: 192.5px
Section 2: 35px
Section 3: 61.25px
Section 4: 61.25px
```

**Tablet (1000px)**
```
Section 1: 550px
Section 2: 100px
Section 3: 175px
Section 4: 175px
```

The percentages ensure consistent proportions across all screen sizes.

---

## Tips

1. **Keep section totals at 100%**
   - Section widths: 55 + 10 + 17.5 + 17.5 = 100%
   - Section 1 content: 70 + 5 + 25 = 100%

2. **Use padding for spacing**
   - Don't adjust section widths for spacing
   - Use padding percentages instead

3. **Test on different screens**
   - Small (350px), Medium (400px), Large (800px)
   - Ensure tables don't overflow

4. **Padding is relative to parent**
   - Section 1 padding: % of Section 1 size
   - Date padding: % of date section size

5. **Hot reload after changes**
   - Press `r` to see layout changes
   - Press `R` for full restart if needed

---

## Future: Collaborative Icon (Section 2)

Section 2 is currently empty but reserved for a collaborative icon:

```dart
// Future implementation in Section 2
if (project.users.length > 1) {
  Icon(Icons.people, size: 24, color: AppColors.menuOnlineIndicator)
}
```

The 10% width provides space for this future feature.



