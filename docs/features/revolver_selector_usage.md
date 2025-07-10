# 🎯 Revolver Selector Widget

**Visual tile-based selector that replaces sliders with an intuitive revolver-style interface.**

## Features

- **Dynamic Scaling**: Center tile is larger, others scale down based on distance
- **Smooth Animation**: Animated scrolling, scaling, and opacity transitions  
- **Flexible Alignment**: Items can start from left or center
- **Touch Interaction**: Tap any tile to select it and auto-scroll to position
- **Visual Feedback**: Selected tile has accent color and shadow

## Usage Examples

### Step Jump Selector (Center Aligned)
```dart
RevolverSelectorWidget(
  items: createStepJumpItems(), // 1-16
  selectedValue: stepInsertSize,
  onChanged: (value) => setStepInsertSize(value),
  alignment: RevolverAlignment.center, // First item (1) in center
  height: 64,
  centerTileSize: 36,
  sideTileSize: 28,
)
```

### Musical Key Selector (Center Default)
```dart
RevolverSelectorWidget(
  items: createKeyItems(centerKey: 60, range: 12), // C4 ± 12 semitones
  selectedValue: currentKey,
  onChanged: (value) => setKey(value),
  alignment: RevolverAlignment.center, // Default key (0) in center
  height: 80,
  centerTileSize: 48,
  sideTileSize: 32,
  title: "Key Transpose",
)
```

### Custom Items (Left Aligned)
```dart
final customItems = [
  RevolverItem(displayText: "Off", value: 0),
  RevolverItem(displayText: "Low", value: 1),
  RevolverItem(displayText: "Med", value: 2),
  RevolverItem(displayText: "High", value: 3),
];

RevolverSelectorWidget(
  items: customItems,
  selectedValue: currentValue,
  onChanged: (value) => setValue(value),
  alignment: RevolverAlignment.left, // First item on left
  height: 60,
)
```

## Helper Functions

### createStepJumpItems()
Creates items 1-16 for step jump selection:
- **Display**: "1", "2", "3"... "16"
- **Values**: 1, 2, 3... 16
- **Best with**: `RevolverAlignment.center`

### createKeyItems({centerKey, range})
Creates musical key items with + and - notation:
- **centerKey**: MIDI note number for center (default: 0)
- **range**: Semitones above/below center (default: 12)
- **Display**: "-12", "-11"... "0"... "+11", "+12"
- **Best with**: `RevolverAlignment.center`

## Visual Behavior

**Distance-Based Scaling:**
- Center tile: 100% scale
- Adjacent tiles: ~85% scale  
- Far tiles: ~70% scale

**Distance-Based Opacity:**
- Center tile: 100% opacity
- Adjacent tiles: ~80% opacity
- Far tiles: ~60% opacity

**Alignment Modes:**
- **Center**: Selected item scrolls to viewport center (ideal for symmetric ranges)
- **Left**: Selected item scrolls to viewport left (ideal for sequential lists)

## Implementation

The widget automatically handles:
- ✅ Smooth scrolling to selected items
- ✅ Dynamic visual scaling based on viewport position  
- ✅ Touch interaction with visual feedback
- ✅ Responsive sizing and spacing
- ✅ Consistent theming with sequencer color scheme 