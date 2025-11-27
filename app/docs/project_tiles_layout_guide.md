# Project Tiles Layout Control Guide

This guide explains how to customize the project tiles layout in `app/lib/screens/projects_screen.dart`.

## Quick Reference

**All layout controls are CENTRALIZED at the top of the `_ProjectsScreenState` class (around line 37-130).**

This centralized approach follows best practices from `flutter_overflow_prevention_guide.md`:
- Uses flex ratios instead of percentages (overflow-safe)
- Uses relative measurements instead of fixed pixels (responsive)
- All adjustable values in one place (easy to maintain)

---

## 1. Tile Height Control

**Location:** `_tileHeightPercent` constant

**What it does:** Controls how tall each project tile is as a percentage of screen height.

### Recommended Values

| Value | Effect | Use Case |
|-------|--------|----------|
| 8-10% | Compact view | Show more projects at once, less detail visible |
| 10-12% | Balanced view | Good mix of projects visible and detail |
| **12-14%** | **Comfortable view** | **Recommended - Best for most use cases** |
| 15%+ | Spacious view | Fewer projects, maximum detail (tablets/large screens) |

### Example

```dart
static const double _tileHeightPercent = 12.0; // 12% of screen height
```

**To make tiles taller:** Increase the value (e.g., 14.0)  
**To make tiles shorter:** Decrease the value (e.g., 10.0)

---

## 2. Pattern Preview Size Control

**Location:** `_patternPreviewMargin*` constants

**What it does:** Controls the margins (padding) around the pattern preview widget.

### Key Concept

⚠️ **Important:** SMALLER margins = BIGGER pattern preview inside its container!

- **Less padding** → More space for pattern → Pattern appears larger
- **More padding** → Less space for pattern → Pattern appears smaller

### Recommended Values

| Margin Size | Effect | Visual Feel |
|-------------|--------|-------------|
| 0-3px | Minimal margins | Maximum preview size, very tight fit |
| **4-8px** | **Compact margins** | **Recommended - Larger preview with breathing room** |
| 8-12px | Comfortable margins | Balanced, professional spacing |
| 12px+ | Spacious margins | Smaller preview, lots of whitespace |

### Current Configuration (Optimized)

```dart
static const double _patternPreviewMarginLeft = 3.0;    // Minimal left margin
static const double _patternPreviewMarginTop = 3.0;     // Minimal top margin
static const double _patternPreviewMarginRight = 6.0;   // Compact right margin
static const double _patternPreviewMarginBottom = 3.0;  // Minimal bottom margin
```

### Best Practices

1. **Top/Bottom smaller than Left/Right**: Creates better visual balance
2. **Symmetric margins**: Keeps pattern centered and balanced
3. **Minimal margins (3-6px)**: Maximizes pattern visibility while providing breathing room

### Examples

**Maximum Pattern Size (Minimal Margins):**
```dart
static const double _patternPreviewMarginLeft = 3.0;
static const double _patternPreviewMarginTop = 2.0;
static const double _patternPreviewMarginRight = 3.0;
static const double _patternPreviewMarginBottom = 2.0;
```

**Balanced Professional Look:**
```dart
static const double _patternPreviewMarginLeft = 8.0;
static const double _patternPreviewMarginTop = 6.0;
static const double _patternPreviewMarginRight = 8.0;
static const double _patternPreviewMarginBottom = 6.0;
```

**Extra Spacious (More Whitespace):**
```dart
static const double _patternPreviewMarginLeft = 12.0;
static const double _patternPreviewMarginTop = 10.0;
static const double _patternPreviewMarginRight = 12.0;
static const double _patternPreviewMarginBottom = 10.0;
```

---

## 3. Tile Structure

Each project tile is divided into **5 columns**:

### Column 1: Pattern Preview (38%)

**Pattern Grid:**
- **Square cells** (1:1 aspect ratio, easily adjustable)
- **Centered** in its container for balanced presentation
- Layer headers showing layer numbers (1, 2, 3, 4, etc.)
- Pattern cells showing sample data
- Horizontal fade on column 17+ (when layers exceed 16 columns)
- Vertical fade on bottom rows (when many rows are visible)

**Cell Dimensions Control:**
- `patternCellMargin`: 0.4px (space between cells)
- `cellAspectRatio`: 1.0 (square cells, change to 0.6 for rectangular)

**Visual Example:**
```
      [Layer Headers: 1  2  3  4]
      ████████████████████████
      ████████████████████████
      ████████████████████████
```
*(centered in column)*

The pattern preview is centered within its padded container, automatically scaling with the tile height.

### Column 2: Sample Bank (14%)

**Grid Size Control (CENTRALIZED):**
```dart
// ----------------------------------------------------------------------------
// SAMPLE BANK GRID SIZE CONTROL
// ----------------------------------------------------------------------------
static const int _sampleBankColumns = 5;  // Number of columns
static const int _sampleBankRows = 4;     // Number of rows
// Total samples shown = 5 × 4 = 20

// ----------------------------------------------------------------------------
// SAMPLE BANK SIZE CONTROL (Independent Width & Height Control)
// ----------------------------------------------------------------------------
// Controls how much space the sample grid occupies inside its column
// Cells automatically fill the specified dimensions using Expanded widgets
//
// WIDTH CONTROL (% of column width):
// - 50-70%: Narrow grid
// - 70-85%: Comfortable width (recommended)
// - 85-100%: Wide grid (maximum visibility)
static const double _sampleBankWidthPercent = 80.0;
  
// HEIGHT CONTROL (% of column height):
// - 40-55%: Compact height
// - 55-70%: Comfortable height (recommended)
// - 70-85%: Tall grid (maximum visibility)
static const double _sampleBankHeightPercent = 65.0;
```

**Recommended configurations:**
- **5×4 = 20 samples** (current, good balance)
- 4×4 = 16 samples (square grid)
- 6×4 = 24 samples (more samples)
- 5×3 = 15 samples (shorter grid)
- 4×5 = 20 samples (taller grid)

**Size Control:**
- **Width:** Adjust `_sampleBankWidthPercent` (80% = comfortable width)
- **Height:** Adjust `_sampleBankHeightPercent` (65% = comfortable height)
- Control both dimensions independently for precise sizing
- Cells automatically fill available space (responsive using `Expanded`)
- Higher values = bigger grid, more visible samples
- Lower values = smaller grid, more compact

**Features:**
- Shows first N samples from the project's sample bank (N = columns × rows)
- **Responsive cell sizing:** Cells automatically adjust to fill available width AND height using `Expanded` widgets
- **Independent size control:** Width and height controlled separately
- Each cell displays the sample's color
- Empty cells shown in gray
- Thin border around grid (0.5px, 0.3 opacity)
- Centered in column (both horizontally and vertically)
- **Configurable inner padding** between border and cells
- Cell dimensions adapt to grid size changes (no fixed aspect ratio)

**Visual Example (5×4):**
```
[20 samples in grid]
████████████████
████████████████
████████████████
████████████████
```

### Column 3: Counters (12%)

**Two counters displayed compactly and centered:**

**LEN (Length):**
- Centered layout with label and number close together
- Number of sections in the pattern
- Example: `LEN: 3`
- Responsive width: 15-50% of column width (adapts to screen size)
- Numbers scale down automatically if larger than available space (using `FittedBox`)

**HST (History):**
- Centered layout with label and number close together
- Number of messages/checkpoints in the thread
- Example: `HST: 7`
- Responsive width: 15-50% of column width (adapts to screen size)
- Numbers scale down automatically if larger than available space (using `FittedBox`)
- Represents collaboration history

**Visual Example:**
```
    LEN: 3
    
    HST: 7
```
*(centered in column)*

**Design Notes (Following flutter_overflow_prevention_guide.md):**
- **Centered box**: Entire counters box is centered within the column
- **Flexible layout**: Uses `Flexible` widgets (Strategy 1 from guide - RECOMMENDED)
  - Labels: `flex: 2` (ensures vertical alignment)
  - Numbers: `flex: 3` (proportional space for values)
- **Small vertical gap**: Relative to column height between counters
- **Small horizontal gap**: Relative to column width between label and number
- **Auto-scaling**: `FittedBox` ensures large numbers (3+ digits) scale to fit
- **Alignment**: Numbers align left within their flexible space
- **Overflow-safe**: No fixed widths, uses proportional flex ratios (zero overflow risk)

### Columns 4 & 5: Dates (18% each)

**Created Date** and **Modified Date**:
- Sortable columns (click header to sort)
- Smart date formatting:
  - **Today**: Relative time ("2h ago", "5m ago", "just now")
  - **Yesterday**: "Yesterday"
  - **All other dates**: Always show year in short format ("8/17/25")
- Typography: Crimson Pro font, 13px, bold (FontWeight.w600)
- Centered text for clean presentation

---

## 4. Pattern Cell Shape Control

**Location:** `cellAspectRatio` constant in `app/lib/widgets/pattern_preview_widget.dart`

**What it does:** Controls the aspect ratio of pattern preview cells (height as percentage of width).

### Cell Shape Options

| Value | Effect | Visual Result |
|-------|--------|---------------|
| 1.0 | Square cells | Height = Width (traditional grid) |
| 0.8 | Slightly rectangular | 20% less height (subtle compression) |
| **0.6** | **Rectangular cells** | **40% less height (more compact, recommended)** |
| 0.5 | Very rectangular | 50% less height (very compact) |
| 0.4 | Extremely flat | 60% less height (ultra-compact) |

### Current Configuration (Square Cells)

```dart
// In pattern_preview_widget.dart
// Cell spacing
static const double patternCellMargin = 0.4;

// Cell aspect ratio
static const double cellAspectRatio = 1.0; // Square cells (height = width)
```

**Benefits of square cells (1.0):**
- ✅ Clear, consistent visual grid
- ✅ Easier to count and scan
- ✅ Traditional pattern view familiar to users
- ✅ Better for visualizing rhythmic patterns

**To change cell dimensions:**
1. Open `app/lib/widgets/pattern_preview_widget.dart`
2. Find the "CELL DIMENSIONS CONTROL" section (around line 12-22)
3. Modify the values:

**Cell Spacing (patternCellMargin):**
- `0.2` - Very tight grid
- `0.4` - Compact (current, recommended)
- `0.6` - Comfortable spacing
- `1.0` - Spacious grid

**Cell Shape (cellAspectRatio):**
- `1.0` - Square cells (current, recommended)
- `0.8` - Slightly rectangular (20% less height)
- `0.6` - Rectangular (40% less height, more compact)
- `0.5` - Very flat (50% less height)

### Examples

**Square Cells (Current):**
```dart
static const double patternCellMargin = 0.4;
static const double cellAspectRatio = 1.0;
```

**Rectangular Cells (More Compact):**
```dart
static const double patternCellMargin = 0.4;
static const double cellAspectRatio = 0.6;
```

**Spacious Square Grid:**
```dart
static const double patternCellMargin = 1.0;
static const double cellAspectRatio = 1.0;
```

---

## 5. Column Width Ratios (CENTRALIZED)

**Location:** Top of `_ProjectsScreenState` class (COLUMN FLEX RATIOS section)

**✅ All column widths controlled from one place:**
```dart
// ----------------------------------------------------------------------------
// COLUMN FLEX RATIOS - CENTRALIZED (Total must equal 100)
// ----------------------------------------------------------------------------
static const int _patternColumnFlex = 32;      // Pattern preview (32%)
static const int _sampleBankColumnFlex = 14;   // Sample bank grid (14%)
static const int _countersColumnFlex = 12;     // LEN/HST counters (12%)
static const int _createdColumnFlex = 21;      // Created date (21%)
static const int _modifiedColumnFlex = 21;     // Modified date (21%)
// Total: 100 (exact, no floating-point errors, overflow-safe)
```

**Benefits of centralized flex ratios:**
- ✅ Change all column widths from one place
- ✅ Guaranteed no overflow (integers, no floating-point)
- ✅ Easy to maintain and adjust
- ✅ Follows flutter_overflow_prevention_guide.md best practices

**Column Descriptions:**

1. **Patterns Column (32%)**: Full pattern preview with square cells, layer headers, and fade effects
2. **Sample Bank Column (14%)**: 5x4 grid showing first 20 samples, uses same cell style as pattern preview (square cells with 0.4px margins)
3. **Counters Column (12%)**: 
   - **LEN**: Number of sections (compact layout, numbers scale to fit)
   - **HST**: Number of messages/history (compact layout, numbers scale to fit)
4. **Created Column (21%)**: Project creation date (sortable)
5. **Modified Column (21%)**: Last modified date (sortable)

**To adjust column proportions:**
- Increase pattern flex (e.g., 55) for more pattern space
- Adjust other column flex values to maintain total of 100
- Sample bank and counters columns work best in 8-12% range

---

## 6. Common Scenarios

### Scenario: "I want to see more pattern detail"

**Solution:** Increase both tile height and pattern preview size

```dart
// 1. Make tiles taller
static const double _tileHeightPercent = 14.0; // Up from 12.0

// 2. Reduce margins (= bigger preview)
static const double _patternPreviewMarginLeft = 4.0;
static const double _patternPreviewMarginTop = 2.0;
static const double _patternPreviewMarginRight = 4.0;
static const double _patternPreviewMarginBottom = 2.0;
```

### Scenario: "I want to see more projects at once"

**Solution:** Decrease tile height, keep margins moderate

```dart
// Make tiles shorter
static const double _tileHeightPercent = 9.0; // Down from 12.0

// Keep margins moderate for readability
// (no change needed to margins)
```

### Scenario: "Pattern preview looks cramped/touching edges"

**Solution:** Increase margins slightly

```dart
// Add more breathing room
static const double _patternPreviewMarginLeft = 10.0;
static const double _patternPreviewMarginTop = 8.0;
static const double _patternPreviewMarginRight = 10.0;
static const double _patternPreviewMarginBottom = 8.0;
```

### Scenario: "I want maximum pattern preview size"

**Solution:** Increase tile height, minimize margins, maximize flex ratio

```dart
// 1. Taller tiles
static const double _tileHeightPercent = 15.0;

// 2. Minimal margins
static const double _patternPreviewMarginLeft = 3.0;
static const double _patternPreviewMarginTop = 2.0;
static const double _patternPreviewMarginRight = 3.0;
static const double _patternPreviewMarginBottom = 2.0;

// 3. In _buildPatternsColumn, increase flex:
Expanded(flex: 80, child: PatternPreview()),  // 80% instead of 75%
Expanded(flex: 20, child: ReservedSpace()),   // 20% instead of 25%
```

### Scenario: "Pattern cells look too tall/stretched"

**Solution:** Adjust cell aspect ratio in PatternPreviewWidget

```dart
// In pattern_preview_widget.dart
// More compact (shorter cells)
static const double cellAspectRatio = 0.5;  // 50% height
```

### Scenario: "I want to see more pattern rows in the preview"

**Solution:** Use rectangular cells to fit more rows vertically

```dart
// In pattern_preview_widget.dart
// Very compact cells to maximize row count
static const double cellAspectRatio = 0.5;  // 50% height = fits ~2x more rows

// Or ultra-compact
static const double cellAspectRatio = 0.4;  // 40% height = fits even more rows
```

### Scenario: "Sample bank grid is too small/too big"

**Solution:** Adjust width and/or height independently (easy dual variable control)

```dart
// Sample bank looks too small - increase both dimensions
static const double _sampleBankWidthPercent = 90.0;   // Up from 80% (wider)
static const double _sampleBankHeightPercent = 75.0;  // Up from 65% (taller)

// Sample bank looks too big - decrease both dimensions
static const double _sampleBankWidthPercent = 65.0;   // Down from 80% (narrower)
static const double _sampleBankHeightPercent = 50.0;  // Down from 65% (shorter)

// Want maximum visibility - nearly full column space
static const double _sampleBankWidthPercent = 95.0;   // Nearly full width
static const double _sampleBankHeightPercent = 85.0;  // Nearly full height

// Want wider but shorter grid (rectangular samples)
static const double _sampleBankWidthPercent = 90.0;   // Wide
static const double _sampleBankHeightPercent = 55.0;  // Compact height

// Want narrower but taller grid (tall rectangular samples)
static const double _sampleBankWidthPercent = 70.0;   // Narrow
static const double _sampleBankHeightPercent = 80.0;  // Tall
```

**Remember:** 
- Both dimensions are controlled independently
- Cells automatically fill the specified width AND height using `Expanded` widgets
- Cell shape adapts to the width/height ratio you set
- Spacing and padding variables are separate from size control

---

## 7. Testing Your Changes

After modifying these values:

1. **Hot reload** the app (press `r` in terminal or save the file)
2. **Check on multiple screen sizes** if possible
3. **Verify no overflow errors** (yellow/black stripes)
4. **Ensure pattern preview is clearly visible**
5. **Check alignment** (should be top-left with your chosen margins)

### Debug Colors

The current implementation has debug colors enabled to help visualize boundaries:

- 🔴 Light Red: Pattern preview area
- 🟢 Light Green: Sample bank column
- 🔵 Light Blue: Counters column (LEN/HST)
- 🟡 Light Yellow: Created date column
- 🟣 Light Purple: Modified date column

To disable debug colors, set them to `null`:

```dart
static const Color? _patternPreviewDebugColor = null;
static const Color? _sampleBankDebugColor = null;
static const Color? _countersDebugColor = null;
static const Color? _createdColumnDebugColor = null;
static const Color? _modifiedColumnDebugColor = null;
```

---

## 8. Overflow Prevention

All layout calculations use **`Expanded` widgets with flex ratios** instead of percentage calculations to prevent overflow issues. See `app/docs/flutter_overflow_prevention_guide.md` for detailed explanation.

**Key principle:** Never change `SizedBox` with calculated widths - always use `Expanded` with flex ratios!

---

## 9. Element Padding Control (Boxed Layout)

Each main element is now wrapped in its own box with controllable padding, following `flutter_overflow_prevention_guide.md` best practices.

### Centralized Element Padding (% of tile height)

**All padding is responsive and controlled from one place:**

```dart
// ----------------------------------------------------------------------------
// ELEMENT PADDING CONTROL (Responsive, as % of tile dimensions)
// ----------------------------------------------------------------------------
// Each main element gets its own box with controlled padding

// Pattern preview element padding (% of tile height)
static const double _patternElementPaddingTopPercent = 3.0;       // 3% top
static const double _patternElementPaddingBottomPercent = 3.0;    // 3% bottom
static const double _patternElementPaddingLeftPercent = 2.0;      // 2% left
static const double _patternElementPaddingRightPercent = 2.0;     // 2% right

// Sample bank element padding (% of tile height)
static const double _sampleElementPaddingTopPercent = 3.0;
static const double _sampleElementPaddingBottomPercent = 3.0;
static const double _sampleElementPaddingLeftPercent = 2.0;
static const double _sampleElementPaddingRightPercent = 2.0;

// Counters element padding (% of tile height)
static const double _countersElementPaddingTopPercent = 3.0;
static const double _countersElementPaddingBottomPercent = 3.0;
static const double _countersElementPaddingLeftPercent = 3.0;
static const double _countersElementPaddingRightPercent = 3.0;

// Date columns element padding (% of tile height)
static const double _dateElementPaddingTopPercent = 3.0;
static const double _dateElementPaddingBottomPercent = 3.0;
static const double _dateElementPaddingLeftPercent = 2.0;
static const double _dateElementPaddingRightPercent = 2.0;
```

### Layout Structure

Each column now has this structure:
```
Container (with debug color)
└── Padding (element padding - configurable)
    └── [Element content]
```

**Benefits:**
- ✅ Each element in its own padded box
- ✅ Independent padding control per element type
- ✅ Padding scales with tile height (responsive)
- ✅ Easy to adjust spacing from centralized constants
- ✅ Clean visual separation between elements

### Examples

**More spacing around pattern preview:**
```dart
static const double _patternElementPaddingTopPercent = 5.0;     // 3% → 5%
static const double _patternElementPaddingBottomPercent = 5.0;  // 3% → 5%
```

**Tighter counters layout:**
```dart
static const double _countersElementPaddingTopPercent = 1.0;    // 3% → 1%
static const double _countersElementPaddingBottomPercent = 1.0; // 3% → 1%
```

**Asymmetric padding (more space on sides):**
```dart
static const double _sampleElementPaddingLeftPercent = 4.0;     // 2% → 4%
static const double _sampleElementPaddingRightPercent = 4.0;    // 2% → 4%
```

---

## 10. Responsive Sizing (Following Best Practices)

All sizing uses **relative measurements** instead of fixed pixels, following `flutter_overflow_prevention_guide.md`:

### Centralized Flex Ratios (Overflow-Safe)
```dart
// All column widths use integer flex ratios
// Total always equals exactly 100 (no floating-point errors)
static const int _patternColumnFlex = 35;
static const int _sampleBankColumnFlex = 11;
// ... etc
```

### Relative Sizing (Responsive)
```dart
// Pattern preview margins as % of tile height
static const double _patternPreviewMarginLeftPercent = 0.3;  // 0.3% of height

// Element padding as % of tile height
static const double _patternElementPaddingTopPercent = 3.0;  // 3% of height

// Counter spacing as % of dimensions
static const double _counterLabelGapPercent = 3.0;  // 3% of width
```

**Benefits:**
- ✅ No overflow possible (integer flex ratios)
- ✅ Scales perfectly on all screen sizes
- ✅ No fixed pixels (fully responsive)
- ✅ Easy to adjust from one place
- ✅ Each element has its own controlled padding box

---

## Summary

**All controls centralized at top of file (~line 37-165):**

| What to Control | Constant Name | Location |
|-----------------|---------------|----------|
| **Tile height** | `_tileHeightPercent` | Line ~55 |
| **Column widths** | `_*ColumnFlex` (5 constants) | Line ~64-68 |
| **Pattern margins** | `_patternPreviewMargin*Percent` | Line ~82-85 |
| **Sample grid size** | `_sampleBankColumns`, `_sampleBankRows` | Line ~101-102 |
| **Sample grid width** | `_sampleBankWidthPercent` | Line ~120 |
| **Sample grid height** | `_sampleBankHeightPercent` | Line ~127 |
| **Sample inner padding** | `_sampleBankInnerPaddingPercent` | Line ~134 |
| **Pattern element padding** | `_patternElementPadding*Percent` (4 values) | Line ~135-138 |
| **Sample element padding** | `_sampleElementPadding*Percent` (4 values) | Line ~141-144 |
| **Counters element padding** | `_countersElementPadding*Percent` (4 values) | Line ~147-150 |
| **Date element padding** | `_dateElementPadding*Percent` (4 values) | Line ~153-156 |
| **Counter spacing** | `_counterLabelGapPercent`, `_counterRowGapPercent` | Line ~162-164 |

**Key Principles:**
- 🎯 **All flex ratios in one place** (easy to adjust, overflow-safe)
- 📦 **Each element in its own padded box** (independent control)
- 📐 **All measurements relative** (responsive, no fixed pixels)
- ✅ **Follows best practices** (flutter_overflow_prevention_guide.md)

**Remember:** The relationship between margins and preview size is inverse:
- ⬇️ Smaller margins = ⬆️ Bigger preview
- ⬆️ Larger margins = ⬇️ Smaller preview

