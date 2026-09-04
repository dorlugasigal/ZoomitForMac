<!-- markdownlint-disable-file -->
# Subagent PR Review Log 04

## Review Scope

* Repository: `microsoft/ZoomitForMac`
* PR reference: `.copilot-tracking/pr/pr-reference.xml`
* Assigned chunks: 37 through 48 inclusive
* Review mode: Read-only
* Status: **FINDINGS**
* Tests/builds run: None
* Source files modified: None
* Tracking files modified: This review log only

## Coverage

All assigned chunks were read using the required `read-diff.sh` script:

* Chunk 37
* Chunk 38
* Chunk 39
* Chunk 40
* Chunk 41
* Chunk 42
* Chunk 43
* Chunk 44
* Chunk 45
* Chunk 46
* Chunk 47
* Chunk 48

The command used for each chunk was:

```bash
/Users/dorlugasigal/.copilot/installed-plugins/hve-core/hve-core/skills/shared/pr-reference/scripts/read-diff.sh --input .copilot-tracking/pr/pr-reference.xml --chunk N
```

Boundary context and repository source were inspected only where necessary to validate behavior exposed by these chunks.

## Findings

### Finding 1: Custom color wells continuously invalidate themselves during drawing

* Severity: **Medium**
* Category: Reliability / Performance
* Affected file: [Sources/ZoomItMacCore/Overlay/DrawingPropertiesController.swift](../../../Sources/ZoomItMacCore/Overlay/DrawingPropertiesController.swift#L1275-L1349)
* New-side lines: 1275 through 1277 and 1344 through 1349
* Exposed by: Chunk 43

**Exact evidence**

```swift
override func draw(_ dirtyRect: NSRect) {
    updateAppearance()
    super.draw(dirtyRect)
    // ...
}

private func updateAppearance() {
    layer?.cornerRadius = DrawingCustomColorTileGeometry.cornerRadius
    layer?.borderWidth = 0
    layer?.backgroundColor = NSColor.clear.cgColor
    setAccessibilityValue(isMixed ? "Mixed" : (isSelected ? "Selected" : "Not selected"))
    needsDisplay = true
}
```

`draw(_:)` calls `updateAppearance()`, and that method marks the view as needing display again. The custom stroke and background color wells can therefore schedule another drawing pass from inside every drawing pass.

**Impact**

While the inspector is visible, these color wells may redraw continuously even when their state has not changed. This can consume main-thread CPU, increase battery usage, and degrade drawing or pointer responsiveness.

**Suggested correction**

Separate applying layer/accessibility state from invalidating the view. Do not set `needsDisplay` from a method called by `draw(_:)`. For example, remove `updateAppearance()` from `draw(_:)` and invoke it only when hover, pressed, selected, enabled, mixed, color, or effective-appearance state changes. Alternatively, split it into a non-invalidating `applyAppearance()` method for use during drawing.

---

### Finding 2: Dragging the toolbar to a differently sized display does not reflow either panel

* Severity: **Medium**
* Category: Correctness / Multi-display Reliability
* Affected file: [Sources/ZoomItMacCore/Overlay/DrawingToolbarController.swift](../../../Sources/ZoomItMacCore/Overlay/DrawingToolbarController.swift#L386-L456)
* New-side lines: 386 through 456
* Exposed by: Chunks 44 and 45

**Exact evidence**

During a drag, the destination display contributes only its `visibleFrame` to origin clamping:

```swift
let activeScreen = screen(containing: finalPointerLocation)
    ?? bestScreen(for: CGRect(origin: proposedOrigin, size: toolbarPanel.frame.size))
guard let activeScreen else { continue }
applyDragSample(
    proposedOrigin: proposedOrigin,
    visibleFrame: activeScreen.visibleFrame
)
```

`applyDragSample` moves the existing toolbar and inspector frames without recalculating their sizes or inspector layout:

```swift
toolbarPanel.setFrameOrigin(toolbarOrigin)
inspectorPanel.setFrameOrigin(
    DrawingAttachedInspectorDragLock.inspectorOrigin(
        toolbarOrigin: toolbarOrigin,
        inspectorOffset: inspectorOffset
    )
)
```

When dragging finishes, the controller only persists the existing toolbar origin:

```swift
private func finishToolbarDragging(at pointerLocation: CGPoint) {
    guard let activeScreen = screen(containing: pointerLocation)
        ?? bestScreen(for: toolbarPanel.frame) else {
        return
    }
    persistToolbarPosition(
        origin: toolbarPanel.frame.origin,
        visibleFrame: activeScreen.visibleFrame
    )
}
```

The screen-dependent resizing and inspector reflow occur in `applyToolbarFrame` and `applyInspectorFrame`, but neither is invoked when the toolbar crosses displays or when the drag ends.

**Impact**

Moving the accessory from a wide display to a narrower or portrait display retains panel dimensions calculated for the source display. Origin clamping cannot make an oversized toolbar or inspector fit, so controls can remain clipped or off-screen until another state update or screen-configuration notification happens to recalculate the frames.

**Suggested correction**

At minimum, recompute both panels against the destination `NSScreen` before persisting the completed drag:

1. Resize and clamp the toolbar using `applyToolbarFrame(animated: false, preservingCurrentOrigin: true, screen: activeScreen)`.
2. Recalculate the inspector width, section packing, placement, and frame using `applyInspectorFrame(screen: activeScreen)`.
3. Persist the normalized position after the updated frames are applied.

For smoother behavior, detect display changes during dragging and perform the reflow when the pointer first crosses onto a different screen.

---

### Finding 3: Advertised numeric shortcuts cannot work on keyboard layouts that require Shift for digits

* Severity: **Medium**
* Category: Functional Regression
* Affected file: [Sources/ZoomItMacCore/Overlay/DrawingToolbarState.swift](../../../Sources/ZoomItMacCore/Overlay/DrawingToolbarState.swift#L55-L81)
* New-side lines: 55 through 81
* Exposed by: Chunk 45

**Exact evidence**

The shortcut resolver requires the generated character to be an ASCII digit while rejecting every event containing Shift:

```swift
let excludedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
guard isDrawingMode,
      !isTyping,
      modifierFlags.intersection(excludedModifiers).isEmpty,
      let character = characters?.first else {
    return nil
}

let tool: AnnotationTool? = switch character {
case "1": .select
case "2": .rectangle
case "3": .diamond
case "4": .ellipse
case "5": .arrow
case "6": .line
case "7": .pen
case "8": .text
case "0": .eraser
default: nil
}
```

The caller passes `event.charactersIgnoringModifiers` first. On keyboard layouts whose unshifted number row produces symbols and requires Shift to produce digits, the unshifted event does not yield `"0"` through `"8"`, while the shifted event is rejected by the modifier guard.

**Impact**

The toolbar visibly advertises numeric shortcuts that are unusable on common non-US keyboard layouts, preventing affected users from invoking the new tool-selection workflow as documented by the UI.

**Suggested correction**

Resolve number-row shortcuts from layout-independent key codes, or pass sufficient event information to distinguish Shift used to produce a digit from Shift used as an application modifier. Preserve existing modified-key gestures while allowing the displayed digit shortcuts on keyboard layouts where digits require Shift.

## Review Summary

* Assigned chunks reviewed: **12 of 12**
* Correctness findings: **2**
* Reliability/performance findings: **1**
* Security findings: **0**
* Overall status: **FINDINGS**

## Open Questions

* None. Each finding is directly supported by the assigned diff and narrowly scoped source validation.

## Continuation

* The parent reviewer should validate prioritization, deduplicate these findings against other subagent reports, and merge accepted items into the main PR review tracking document.
