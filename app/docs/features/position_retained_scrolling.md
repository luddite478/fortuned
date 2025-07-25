# Position-Retained Scrolling

## Overview

Position-Retained Scrolling is a technique to prevent unwanted scroll position changes when dynamic content is added or removed from scrollable widgets. This is particularly useful for "building block" style interfaces where content grows from the top while maintaining the user's current view.

## The Problem

### Default Flutter Behavior

When content is dynamically added or removed from scrollable widgets like `ListView` or `GridView`, Flutter's default scroll physics may cause unwanted position adjustments:

1. **Content addition**: Adding items to the beginning of a list often causes the scroll position to jump
2. **Content removal**: Removing items can cause the view to shift unexpectedly
3. **User experience**: These jumps break the "building blocks" illusion where content should grow naturally outside the current view

### Real-World Example

Imagine a feed where:
- User is viewing items 10-15
- New content is added at the top (items 1-5 become 6-10)
- **Problem**: The view jumps, disrupting the user's focus
- **Desired**: Items 10-15 should become 15-20 visually, but stay in the same screen position

## The Solution: PositionRetainedScrollPhysics

### Core Concept

`PositionRetainedScrollPhysics` is a custom `ScrollPhysics` class that adjusts scroll position when content dimensions change, maintaining the user's visual context.

### Implementation

```dart
class PositionRetainedScrollPhysics extends ScrollPhysics {
  final bool shouldRetain;
  const PositionRetainedScrollPhysics({super.parent, this.shouldRetain = true});

  @override
  PositionRetainedScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return PositionRetainedScrollPhysics(
      parent: buildParent(ancestor),
      shouldRetain: shouldRetain,
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final position = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );

    final diff = newPosition.maxScrollExtent - oldPosition.maxScrollExtent;

    // Always retain position when content is added (diff > 0)
    if (diff > 0 && shouldRetain) {
      return position + diff;
    } else {
      return position;
    }
  }
}
```

### How It Works

1. **Monitor dimension changes**: The `adjustPositionForNewDimensions` method is called when scroll content changes
2. **Calculate offset difference**: `diff = newPosition.maxScrollExtent - oldPosition.maxScrollExtent`
3. **Adjust position**: When content is added (diff > 0), adjust scroll position by the difference
4. **Maintain view**: User sees the same content in the same position, despite underlying changes

## Implementation Patterns

### Pattern 1: ListView with Dynamic ItemCount

**Best for**: Simple lists where items are added/removed

```dart
ListView.builder(
  controller: _scrollController,
  physics: const PositionRetainedScrollPhysics(),
  itemCount: _itemCount + 1, // +1 for control buttons
  itemBuilder: (context, index) {
    if (index < _itemCount) {
      return _buildItem(index);
    } else {
      return _buildControlButtons(); // Attached to content
    }
  },
)
```

**Key advantages**:
- Natural growth from top
- Simple itemCount changes
- Control buttons move with content
- Perfect scroll retention

### Pattern 2: GridView with SingleChildScrollView (Anti-pattern)

**Avoid**: This approach causes jumping

```dart
// ❌ DON'T DO THIS
SingleChildScrollView(
  physics: const PositionRetainedScrollPhysics(),
  child: GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: _items.length, // Changing this rebuilds entire grid
    itemBuilder: (context, index) => _buildItem(index),
  ),
)
```

**Problems**:
- GridView completely rebuilds when itemCount changes
- Array replacement causes widget tree reconstruction
- ScrollPhysics can't prevent the jumping from widget rebuilding

### Pattern 3: ListView with Row-Based Grid (Recommended)

**Best for**: Grid layouts that need dynamic growth

```dart
ListView.builder(
  controller: _scrollController,
  physics: const PositionRetainedScrollPhysics(),
  itemCount: _gridRows + 1, // +1 for control buttons
  itemBuilder: (context, index) {
    if (index < _gridRows) {
      return _buildGridRow(index); // Row of grid cells
    } else {
      return _buildControlButtons();
    }
  },
)

Widget _buildGridRow(int rowIndex) {
  return Row(
    children: List.generate(_gridColumns, (colIndex) {
      final cellIndex = rowIndex * _gridColumns + colIndex;
      return Expanded(child: _buildGridCell(cellIndex));
    }),
  );
}
```

**Advantages**:
- Maintains grid appearance
- Uses ListView benefits (dynamic itemCount)
- Perfect scroll retention
- No widget tree reconstruction

## Usage Guidelines

### When to Use

✅ **Use PositionRetainedScrollPhysics when**:
- Content is added/removed dynamically
- Users should maintain their current view
- Implementing "building blocks" UX
- Control elements are attached to scrollable content

### When NOT to Use

❌ **Don't use when**:
- Normal scrolling behavior is desired
- Content changes should bring user's attention to new items
- Fixed content that doesn't change

### Performance Considerations

- **Lightweight**: Minimal overhead, only calculates during content changes
- **Efficient**: No ongoing performance impact during normal scrolling
- **Compatible**: Works with existing Flutter scroll widgets

## Implementation Checklist

1. **Add the physics class** to your project
2. **Choose the right pattern**:
   - ListView.builder for simple lists
   - ListView.builder with row-based approach for grids
3. **Apply physics** to your scroll widget
4. **Test edge cases**:
   - Adding content when at top/bottom
   - Removing content when at edges
   - Rapid content changes

## Real-World Applications

### Test Screen Example
```dart
ListView.builder(
  physics: const PositionRetainedScrollPhysics(),
  itemCount: _feedItemCount + 1,
  itemBuilder: (context, index) {
    if (index < _feedItemCount) {
      return _buildFeedItem(index);
    } else {
      return _buildControlButtons(); // Always visible when scrolled to bottom
    }
  },
)
```

### Sound Grid Example
```dart
ListView.builder(
  controller: _scrollController,
  physics: const PositionRetainedScrollPhysics(),
  itemCount: sequencer.gridRows + 1,
  itemBuilder: (context, index) {
    if (index < sequencer.gridRows) {
      return _buildGridRow(context, sequencer, index);
    } else {
      return _buildGridRowControls(sequencer);
    }
  },
)
```

## Troubleshooting

### Common Issues

**Issue**: Still experiencing jumps
- **Cause**: Using GridView.builder with array replacement
- **Solution**: Switch to ListView.builder with row-based approach

**Issue**: ScrollPhysics not working
- **Cause**: Widget tree reconstruction overrides physics
- **Solution**: Ensure underlying data structure doesn't get completely replaced

**Issue**: Content doesn't grow from top
- **Cause**: Adding items to end of list instead of beginning
- **Solution**: Use proper data structure that grows from index 0

### Debug Tips

1. **Log dimension changes**: Add debug prints in `adjustPositionForNewDimensions`
2. **Monitor scroll metrics**: Check `oldPosition` vs `newPosition`
3. **Verify item order**: Ensure new items appear at index 0

## Best Practices

1. **Use ListView.builder** over GridView.builder for dynamic content
2. **Minimize data reconstruction** - change itemCount, not underlying arrays
3. **Test extensively** at different scroll positions
4. **Consider user expectations** - when should content growth be visible vs invisible
5. **Combine with animations** for smooth visual transitions when appropriate

## Related Patterns

- **Infinite Scrolling**: Can be combined with position retention
- **Pull to Refresh**: Compatible with position retention
- **Lazy Loading**: Works well with dynamic itemCount changes
- **Virtual Scrolling**: Enhanced by position retention for better UX

---

*This approach was successfully implemented in the Niyya app for both the test screen and sound grid widget, providing smooth "building blocks" behavior where content grows naturally from the top without disrupting the user's current view.* 