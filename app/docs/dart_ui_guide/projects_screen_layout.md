# Projects Screen Layout Guide

This document explains how the Projects Screen layout works in simple terms, designed for those new to Flutter/Dart.

## Table of Contents
1. [Overview](#overview)
2. [Screen Structure](#screen-structure)
3. [Layout Control Variables](#layout-control-variables)
4. [How the Layout Works](#how-the-layout-works)
5. [Visual Breakdown](#visual-breakdown)
6. [Making Changes](#making-changes)

---

## Overview

The Projects Screen displays a list of your music projects. Each project is shown as a "tile" (a row) containing:
- A pattern preview (the main sequencer grid)
- A sample bank preview (your loaded samples)
- Created and Modified dates

Everything is sized using **percentages** so it works on any screen size.

---

## Screen Structure

### Big Picture Layout

```
┌─────────────────────────────────────────────────────────┐
│                    Header (top bar)                      │
├─────────────────────────────────────────────────────────┤
│ Invites Section (if any invites)                        │
├─────────────────────────────────────────────────────────┤
│ "Patterns" | Spacer | "Created" ↓ | "Modified" ↓       │  <- Column Headers
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ [Pattern Grid] [Samples] ... [Date] [Date]        │ │  <- Project Tile 1
│  └────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────┐ │
│  │ [Pattern Grid] [Samples] ... [Date] [Date]        │ │  <- Project Tile 2
│  └────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────┐ │
│  │ [Pattern Grid] [Samples] ... [Date] [Date]        │ │  <- Project Tile 3
│  └────────────────────────────────────────────────────┘ │
│                                                          │
└─────────────────────────────────────────────────────────┘
               (+) button (bottom right corner)
```

---

## Layout Control Variables

These variables are at the top of `_ProjectsScreenState` class (around line 36-42):

```dart
static const double _tileHorizontalPaddingPercent = 2.0;
static const double _patternTableWidthPercent = 50.0;
static const double _dateColumnsWidthPercent = 28.0;
static const double _spacingBetweenElementsPercent = 1.5;
static const double _patternTableSizeMultiplier = 0.6;
static const double _sampleTableSizeMultiplier = 0.5;
```

### What Each Variable Controls

| Variable | What It Does | Example |
|----------|--------------|---------|
| `_tileHorizontalPaddingPercent` | Space from screen edge to tile content | 2% = small margins on left/right |
| `_patternTableWidthPercent` | How much width the pattern grid takes | 50% = half the tile width |
| `_dateColumnsWidthPercent` | How much width both date columns take together | 28% = about 1/4 of tile |
| `_spacingBetweenElementsPercent` | Gap between pattern/samples/dates | 1.5% = small gaps |
| `_patternTableSizeMultiplier` | Pattern grid size adjustment | 0.6 = 40% smaller |
| `_sampleTableSizeMultiplier` | Sample grid size adjustment | 0.5 = 50% size (2x smaller) |

---

## How the Layout Works

### 1. Screen Width Calculation

Flutter provides the screen width through `LayoutBuilder`. We use percentages to calculate actual pixel sizes:

```dart
// If screen is 400 pixels wide:
final screenWidth = 400;

// Calculate 2% padding:
final tilePadding = 400 * (2.0 / 100) = 8 pixels

// Calculate 1.5% spacing:
final elementSpacing = 400 * (1.5 / 100) = 6 pixels
```

### 2. Available Space

After subtracting padding from both sides:

```
Screen Width: 400px
Padding Left: 8px
Padding Right: 8px
Available Width: 400 - 8 - 8 = 384px
```

### 3. Distributing Space

The available width is divided among components:

```
Pattern Table: 384px × 50% = 192px
Sample Table: 30px (fixed, scaled down)
Date Columns: 384px × 28% = 107px
Remaining: Used for spacing
```

### 4. Date Columns Split

The date columns area is split evenly:

```
Total Date Width: 107px
Spacing Between: 6px
Each Column: (107 - 6) / 2 = 50.5px each
```

---

## Visual Breakdown

### Single Project Tile (Detailed)

```
┌─[8px]─┬──────────────────────────────────────────────┬─[8px]─┐
│       │                                              │       │
│ EDGE  │  ┌──[Pattern: 192px]──┐  ┌[30px]┐  ┌──[Date Cols: 107px]──┐
│       │  │ ╔═╗╔═╗╔═╗╔═╗│╔═╗╔═╗│  │╔╗╔╗╔╗│  │ [50px] [6px] [50px]  │
│ PAD   │  │ ║█║║ ║║█║║ ║│║ ║║█║│  │║║║║║║│  │ 11/18        11/20   │
│       │  │ ╚═╝╚═╝╚═╝╚═╝│╚═╝╚═╝│  │╚╝╚╝╚╝│  │                      │
│       │  └────────────────────┘  └──────┘  └──────────────────────┘
│       │     [6px gap]              [6px]      [flexible spacer]
│       │                                              │       │
└───────┴──────────────────────────────────────────────────────┘

Legend:
- [8px] = padding values
- ╔═╗ = cell borders
- █ = filled cells
- [6px gap] = element spacing
```

### Pattern Table Grid (Zoomed In)

```
┌─────────────────────────────────────┐
│ ┌─┬─┬─┬─│┬─┬─┬─┬─│┬─┬─┬─┬─│┬─┬─┬─┬─┐ │  <- Row 1
│ └─┴─┴─┴─│┴─┴─┴─┴─│┴─┴─┴─┴─│┴─┴─┴─┴─┘ │
│ ┌─┬─┬─┬─│┬─┬─┬─┬─│┬─┬─┬─┬─│┬─┬─┬─┬─┐ │  <- Row 2
│ └─┴─┴─┴─│┴─┴─┴─┴─│┴─┴─┴─┴─│┴─┴─┴─┴─┘ │
│ ┌─┬─┬─┬─│┬─┬─┬─┬─│┬─┬─┬─┬─│┬─┬─┬─┬─┐ │  <- Row 3
│ └─┴─┴─┴─│┴─┴─┴─┴─│┴─┴─┴─┴─│┴─┴─┴─┴─┘ │
└─────────────────────────────────────┘
         ↑         ↑         ↑
    Layer    Layer    Layer
  Separator Separator Separator
  (every 4 columns)

Details:
- Each ─┬─ is a square cell
- Cells have 0.5px margin (creates the border)
- Border color = tile background (full opacity)
- Vertical lines (│) = light gray layer separators
```

### Sample Table Grid (Zoomed In)

```
┌─────────────┐
│ ┌┬┬┬┬┐      │  <- Row 1 (5 cells)
│ └┴┴┴┴┘      │
│ ┌┬┬┬┬┐      │  <- Row 2
│ └┴┴┴┴┘      │
│ ┌┬┬┬┬┐      │  <- Row 3
│ └┴┴┴┴┘      │
│ ┌┬┬┬┬┐      │  <- Row 4
│ └┴┴┴┴┘      │
└─────────────┘

Details:
- 5 columns × 4 rows = 20 sample slots
- Each cell is square
- 0.5px margin between cells
- 2x smaller than before (multiplier = 0.5)
```

---

## Making Changes

### Common Adjustments

#### 1. Make Pattern Table Bigger/Smaller

**Location:** Line ~40
```dart
static const double _patternTableWidthPercent = 50.0;  // Change this
```

- **Increase value** → Pattern table gets wider
- **Decrease value** → Pattern table gets narrower
- Range: 20.0 - 70.0 (recommended)

#### 2. Adjust Spacing Between Elements

**Location:** Line ~41
```dart
static const double _spacingBetweenElementsPercent = 1.5;  // Change this
```

- **Increase value** → More gaps between pattern/samples/dates
- **Decrease value** → Tighter layout
- Range: 0.5 - 3.0 (recommended)

#### 3. Adjust Tile Padding (Left/Right Margins)

**Location:** Line ~37
```dart
static const double _tileHorizontalPaddingPercent = 2.0;  // Change this
```

- **Increase value** → More space from screen edges
- **Decrease value** → Tiles closer to screen edges
- Range: 1.0 - 4.0 (recommended)

#### 4. Make Pattern/Sample Tables Smaller

**Location:** Lines ~42-43
```dart
static const double _patternTableSizeMultiplier = 0.6;  // Pattern height
static const double _sampleTableSizeMultiplier = 0.5;   // Sample size
```

- **Values closer to 1.0** → Larger tables
- **Values closer to 0.0** → Smaller tables
- Range: 0.3 - 1.0 (recommended)

#### 5. Adjust Date Column Width

**Location:** Line ~39
```dart
static const double _dateColumnsWidthPercent = 28.0;  // Change this
```

- **Increase value** → More space for dates
- **Decrease value** → Less space for dates
- Range: 20.0 - 35.0 (recommended)

### Cell Border Thickness

**Location:** Lines with `margin: const EdgeInsets.all(0.5)`

```dart
margin: const EdgeInsets.all(0.5),  // Change 0.5 to adjust border
```

- **0.5** = thin borders (current)
- **1.0** = thicker borders
- **0.25** = very thin borders
- **0.0** = no borders

---

## Key Flutter Concepts Used

### LayoutBuilder
```dart
LayoutBuilder(
  builder: (context, constraints) {
    final screenWidth = constraints.maxWidth;
    // Now we know the screen width!
  },
)
```
**What it does:** Tells us how much space we have available

### Percentage Calculation
```dart
final pixels = screenWidth * (percentage / 100)
```
**Example:** 400px × (2.0 / 100) = 8px

### SizedBox
```dart
SizedBox(width: 100, height: 50)
```
**What it does:** Creates a box with fixed dimensions

### Spacer
```dart
const Spacer()
```
**What it does:** Pushes things apart (takes up remaining space)

### Container with Margin
```dart
Container(
  margin: const EdgeInsets.all(0.5),  // Space around the cell
  decoration: BoxDecoration(color: Colors.red),
)
```
**What it does:** The margin creates the visual "border" by showing the background color through the gap

---

## Responsive Design

The layout automatically adapts to different screen sizes:

### Small Phone (350px wide)
```
Pattern: 350 × 50% = 175px
Sample: ~30px
Dates: 350 × 28% = 98px
Padding: 350 × 2% = 7px each side
```

### Large Tablet (800px wide)
```
Pattern: 800 × 50% = 400px
Sample: ~30px (scales with multiplier)
Dates: 800 × 28% = 224px
Padding: 800 × 2% = 16px each side
```

**The percentages stay the same, but pixel values scale automatically!**

---

## Tips for Experimentation

1. **Change one variable at a time** to see what it affects
2. **Hot reload** in Flutter shows changes immediately (press `r` in terminal)
3. **Keep total percentages reasonable**:
   - Pattern (50%) + Dates (28%) + Sample + Spacing ≈ 100%
   - If things overlap, reduce some percentages
4. **Test on different screen sizes** using device emulators
5. **Backup your values** before making big changes

---

## File Location

```
app/lib/screens/projects_screen.dart
```

**Variable definitions:** Lines 37-43
**Pattern preview:** Lines 583-881
**Sample preview:** Lines 883-988
**Project tile layout:** Lines 433-536

---

## Need Help?

- If text is cut off → increase `_dateColumnsWidthPercent`
- If tables overlap → increase `_spacingBetweenElementsPercent`
- If layout feels cramped → increase `_tileHorizontalPaddingPercent`
- If layout feels too spacious → decrease padding and spacing values
- If you can't see borders → increase margin from 0.5 to 1.0

Remember: **All values are percentages or multipliers**, so they work on any screen size automatically!

