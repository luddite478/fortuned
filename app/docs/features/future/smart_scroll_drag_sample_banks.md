This did not work as expected

prompt:
please chaneg sample_banks widget behaviour:
currently it is scrollable horizontaly, but when slots are filled and i move finger to th right or left i just select samle and this horizontal list does not scroll
i  need to be able still to select sample by tapping on them and also be able to scroll when i move finger to the selected slot
i have an idea how to implement this
when i press anywhere on the slots but not yet released finger and then movign finger - this is when we scroll, 
but wehn i press on the slot and release finger - this is when select happens
this is just my idea, if you ahve any other ideas how to keep horizontal scrollable posiblity with keep select functionality - please share

also we should keep drag and drop behaviour when i drag sample slots to sound grid, this is vertical movement, so we need to distinguish between horizontal srolling and vertical dragging - the angle should be controllable throught variable in the code


### Smart scrolling and drag for Sample Banks

This document describes how horizontal scrolling and drag-to-grid gestures are combined on the Sample Banks bar (v1/v2/v3), and how to tune the behavior.

### Goals
- Keep tap-to-select on any slot
- Allow comfortable horizontal scrolling even when touching a filled slot
- Start drag-to-grid immediately (no long-press) when movement is not near-horizontal
- Distinguish scrolling (horizontal) from dragging (mostly vertical or diagonal), with a configurable angle

### Behavior summary
- Within ±N degrees of horizontal movement: horizontal scroll
- Otherwise: start drag-to-grid
- Tap selects; long-press opens file picker (unchanged)

### Configuration knob
- Constant at top of each widget file:
  - `app/lib/widgets/sequencer/v1/sample_banks_widget.dart`
  - `app/lib/widgets/sequencer/v2/sample_banks_widget.dart`
  - `app/lib/widgets/sequencer/v3/sample_banks_widget.dart`

```dart
const double _horizontalAngleThresholdDeg = 10.0; // within ±10° of horizontal counts as scroll
```
- Decrease value to make scrolling harder to trigger (drag wins more)
- Increase value to make scrolling easier to trigger (scroll wins more)

### Implementation details
- Each Sample Banks widget was converted to `StatefulWidget` and given a dedicated horizontal `ScrollController` attached to the `SingleChildScrollView`.
- Each slot is wrapped with a `RawGestureDetector` that installs a custom recognizer `_AngleHorizontalScrollRecognizer`.
- The recognizer:
  - Tracks the first move delta from the pointer-down position
  - Computes `angleDeg = atan2(|dy|, |dx|)`; 0° = perfectly horizontal, 90° = perfectly vertical
  - If the angle is ≤ `_horizontalAngleThresholdDeg`, it accepts and drives horizontal scrolling by calling `jumpTo()` on the controller
  - Otherwise it rejects so the underlying `Draggable<int>(affinity: Axis.vertical)` can win and start a drag
- `Draggable` remains immediate (no long-press) and uses `affinity: Axis.vertical` to compete for vertical drags only.

### Key pieces (simplified)
```dart
// Angle gate constant
const double _horizontalAngleThresholdDeg = 10.0; // tune here

// Custom recognizer
class _AngleHorizontalScrollRecognizer extends OneSequenceGestureRecognizer {
  _AngleHorizontalScrollRecognizer({required this.angleThresholdDeg});
  double angleThresholdDeg; // degrees from horizontal
  VoidCallback? onAcceptedStart;
  void Function(double dxTotal)? onHorizontalDelta;

  // On first significant move, decide scroll vs drag using angle
  // angleDeg = atan2(|dy|, |dx|)  ->  <= threshold => scroll
}

// Usage around each slot
RawGestureDetector(
  gestures: {
    _AngleHorizontalScrollRecognizer:
      GestureRecognizerFactoryWithHandlers<_AngleHorizontalScrollRecognizer>(
        () => _AngleHorizontalScrollRecognizer(angleThresholdDeg: _horizontalAngleThresholdDeg),
        (recognizer) {
          double startPixels = 0.0;
          recognizer
            ..onAcceptedStart = () { startPixels = _hScrollController.position.pixels; }
            ..onHorizontalDelta = (dxTotal) {
              final pos = _hScrollController.position;
              final target = (startPixels - dxTotal).clamp(0.0, pos.maxScrollExtent);
              _hScrollController.jumpTo(target);
            };
        },
      ),
  },
  child: Draggable<int>(
    data: bank,
    affinity: Axis.vertical, // lets diagonal/vertical drags become a drag-to-grid
    child: GestureDetector(
      onTap: () => sequencer.handleBankChange(bank, context),
      onLongPress: () => sequencer.pickFileForSlot(bank, context),
      child: sampleButton,
    ),
  ),
)
```

### Tap and long-press
- Tap (`onTap`) selects the slot
- Long-press (`onLongPress`) opens file picker (unchanged)

### Notes
- We keep the `SingleChildScrollView` scrollable; our recognizer simply ensures near-horizontal movements are treated as scroll even over filled slots.
- The recognizer uses a small touch slop (~6 px) before deciding; after acceptance it streams dx to the controller.
- Implemented identically in v1/v2/v3 for consistent UX.

### Tuning recommendations
- Start with `10.0` degrees for strong drag bias (scroll only on near-horizontal swipes)
- If users struggle to scroll, increase to `15.0–20.0`
- If drags trigger too easily when intending to scroll, reduce value

### Future improvements
- Extract `_horizontalAngleThresholdDeg` to a shared config (e.g., `lib/utils/gesture_config.dart`) to control across versions in one place
- Add device-specific tuning (e.g., larger threshold on small screens)
- Smooth scrolling via `animateTo` after acceptance rather than `jumpTo` 