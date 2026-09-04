## Chunks 61-72 Review

### Files Changed

- `Sources/ZoomItMacCore/SelfTest/SelfTestRunner.swift` (modified): Added 6,000 lines of self-test coverage for annotation geometry and editing, drawing toolbar and inspector state, visual controls, shortcuts, text interaction, accessory-window lifecycle, and related undo/locking behavior.

### Technical Details

The assigned chunks consisted entirely of added lines within one continuous diff region. Chunk 61 began in the middle of an added test that exercised selected linear-element arrowhead editing. That continuation verified preservation of the opposite endpoint across mixed selections, atomic undo and redo for endpoint-family and arrowhead-size changes, immediate updates to selected elements, disabling of locked-only controls without changing defaults, editable-only mutation in mixed locked selections, and point-edit state revalidation after undo restored a lock.

#### Linear geometry, bindings, and hit testing

- Added binding lifecycle tests verified nearest-edge attachment, Option-drag unbinding, live endpoint refresh after target movement, resizing, and rotation, preservation of explicitly unbound endpoints, and target deletion clearing a binding without deleting or moving the connector.
- Added rotated-connector tests verified that binding refresh retained a stable local rotation pivot and did not drift after a bound target moved. Direction-routing cases transformed top, trailing, bottom, and leading bindings through target-local, world, and connector-local coordinate spaces, while automatic sides retained the stored fallback direction.
- Added legacy gesture tests preserved the existing Control, Shift, and Tab tool mappings. Control+Shift arrow creation retained a straight route, a small start arrowhead at the drag origin, and no end arrowhead; Shift-drag retained a straight headless line even when persistent linear defaults had been customized.
- Added Line and Arrow default-transition tests covered independent route scopes, the fresh straight Line and curved Arrow defaults, medium arrowhead size, implicit forward Arrow heads, preservation of explicitly customized endpoint heads, headless nonlegacy Arrow creation, and direct application of stored defaults without implicit tool-transition rewriting.
- Added shape hit-testing cases covered solid and patterned interiors, transparent fills, rounded rectangle and diamond paths, ellipse outlines, rough-render displacement, element rotation, zoom-scaled tolerance, and shared selection/eraser path semantics. Selection handles were required to keep a fixed destination-space size and to take precedence over body hits.
- Added adaptive cubic tests exercised an extreme Bezier at high zoom and bounded approximation work with `maximumAdaptiveCubicSegmentsPerCurve`. Arrowhead tests used exact filled or stroked geometry for circle, outlined triangle, bar, crow-foot, and compound heads rather than expanded bounding boxes.

#### Selection, transforms, commands, and text editing

- Added mixed-lock selection tests filtered decoration geometry to editable elements, rejected stale or inferred handles produced by locked-inclusive bounds, and left locked elements unchanged during attempted handle interaction and mixed-selection resize.
- Added editor-selection tests covered topmost click selection, Shift-add, Command-toggle, empty-space marquee entry, marquee intersection, and return to idle on mouse-up. Select-mode arrow handling fell through when no movable selection existed, while Shift-arrow retained ten-point nudging for movable selections.
- Added transaction tests covered moving, resizing, and rotating selected elements across multiple drag updates, with each complete gesture represented by one undo operation. Option-drag duplicated and selected the moved copy, and locked elements ignored transforms and deletion.
- Added duplication tests required a ten-point destination-space offset across zoom levels. Text resizing exposed only uniform corner handles, scaled the font into the requested bounds, and preserved double-click editability. Rotated single- and multi-selection resizing preserved the opposite handle through inverse/forward coordinate transforms.
- Added command tests covered grouping, duplication with new group identifiers, ungrouping, locking, z-order changes, deletion, and undo. Nested ungrouping removed only the active common outer group while retaining inner grouping.
- Added editor-state tests covered explicit creation, marquee, cancellation, text insertion-caret publication, existing-text reselection, append-through-editing, one-transaction undo, and right-aligned Shift+T-compatible text behavior.
- Added coordinator tests kept an existing text target, toolbar, inspector, and single caret active when transitioning from drawing to typing; committed edits on click or Escape; preserved undo/redo; restored prior state after failed edit entry; and distinguished that path from fresh Text-tool placement.
- Added insertion-placement tests required one owner for an exact insertion point across display origins, backing scales, zoom levels, keyboard activation, and moved global cursor positions. Locked text was rejected at editor and controller text-edit boundaries.

#### Toolbar and inspector state

- Added toolbar-state mapping tests mirrored tool, stroke, fill, width, sloppiness, and capability state. The tests asserted exact inspector section matrices and ordering for tools and selections, including conditional Fill after nontransparent Background, roundness behavior, linear route and endpoint controls, text-only properties, path completion/cancellation actions, grouping capability, and mixed-value presentation.
- Smart Draw tests replaced Pen Pressure with a wand control, exposed selected state, forced fixed-pressure samples while active, and restored the previous pressure mode and section when disabled. Pen and Highlighter retained independent stroke and pressure-related scopes.
- Locked-selection tests disabled unavailable inspector controls and overflow actions, preserved elements and defaults for locked-only or incompatible mutations, ignored locked values when resolving mixed state, changed only compatible editable elements, and kept no-selection commands available for creation defaults.
- Inspector layout tests tied visibility to property availability, omitted empty inspectors for propertyless tools, restored the inspector for property-bearing tools, reset horizontal scrolling only when tool context changed, detached hidden sections, retained intrinsic content height, and constrained attached Pen sections to at most two compact rows. Additional rendering checks measured title height, baseline, and descender pixels for one- and two-row layouts.
- Mapping tests asserted compact option and preset counts, selectable route shortcuts, the typed fill and endpoint-specific arrowhead commands, rejection of out-of-range arrowhead indices, exact section titles, the neon Highlighter palette, and font-preset mapping including a 72-point “Very large” preset. Pressure mapping used mouse speed without tablet input and preferred observed tablet pressure when present.
- Text-preset tests updated all editable selected text elements in one undoable mutation, preserved custom Type settings where required, avoided overwriting text-creation defaults when editing selected text, resolved native fonts at requested sizes, and required distinct hand-drawn, sans-serif, and monospaced previews.

#### Visual controls, palettes, previews, and shortcuts

- Added compact-control appearance tests for audited geometry and exact light/dark idle, hover, pressed, selected, mixed, focused, and disabled states. Wiring tests exercised labeled option buttons, scoped color buttons and wells, Smart Draw, the shared opacity slider, visual start/end arrowhead pickers, and the compact font picker.
- Added palette parity tests checked ordered light and dark stroke/background palettes, five square presets, separate custom wells, fixed gaps and dividers, ring-only selection and hover treatment, rendered semantic colors, transparent checkerboard selection, and the dedicated neon Highlighter palette.
- Added preview-geometry tests distinguished straight, cubic curved, and orthogonal elbow routes; checked sharp and rounded corner previews; verified arrowhead shaft direction and outward-facing start/end heads without clipping; and asserted exact Layers labels, Option shortcuts, glyph geometry, mirrored layer arrows, Sloppiness pass counts, and audited colors.
- Added shortcut tests covered larger toolbar tiles and numeric hints, top-row and numeric-keypad tool selection, preservation of modified-number gestures, suppression while typing or outside drawing mode, legacy letter commands, plain `E` remaining Clear, `H` advertising Highlighter, unsupported Image reserving `9` without displaying a misleading tool, terminal layer shortcuts, and tooltip composition.

#### Accessory windows and interaction lifecycle

- Added toolbar lifecycle tests showed drawing accessories only during active sessions, prevented hiding during inspector interaction, kept drawing-originated typing in the same lifecycle, applied global drag deltas, clamped and normalized placement to the active display, and placed the horizontal toolbar near the top center.
- Attached-inspector layout tests retained toolbar frame stability as content height changed, flipped the inspector above when required, clamped it on the toolbar’s secondary display, and kept toolbar/inspector offsets invariant through drag samples. Mouse-down dispatch bracketed control tracking, and first-click tool selection updated state synchronously while resolving typing or pending path interactions.
- Cursor and caret tests distinguished native I-beam behavior before text placement, insertion-caret behavior during editing, native pointers over inspector controls, system cursors for Text, Select, and Hand, arrow cursors over toolbar interaction, and restoration of the drawing indicator for Pen input.
- Menu and popover tests tracked accessory interaction independently across overflow menus, inspector controls, color panels, toolbar dragging, and arrowhead popovers. Physical arrowhead-palette tests retained selection and point-edit mode, applied start/end endpoint commands and size changes on first click, produced isolated undo steps, restored canvas focus, and dismissed the palette with Escape.
- Suppression tests covered nested external-selector/modal suppression, idempotent teardown, generation-aware stale teardown, and restoration only after the final active suppression ended.
- Runtime presentation-switch tests began with a propertyless Hand tool and zero inspector frame, kept the toolbar window delegate-free and inspector chrome-free, ignored the hidden inspector during edge clamping, left the toolbar fixed when an attached inspector appeared, and hid the inspector for an empty Select state without relying on frame reset.

### Notable Patterns

- The additions used the project’s self-test conventions consistently: `try expect` for assertions, `SelfTestError.failure` for required setup, direct construction of annotation scenes/controllers/editors, and programmatic AppKit view inspection.
- Many tests paired visible state with mutation boundaries: locked versus editable selections, creation defaults versus selected-element edits, and interaction state versus accessory-window visibility. Undo assertions commonly required one user operation to map to one transaction.
- Visual tests inspected control geometry, cached bitmap pixels, palette ordering, glyph signatures, and light/dark appearance values in addition to command dispatch.
- Chunk 61 began after the start of an added test, so the report described only the continuation visible in the assigned range. Chunk 72 ended inside `testDrawingInspectorRuntimePresentationSwitch`, so that test and the surrounding file diff continued beyond the assigned range. No file header or hunk boundary appeared in chunks 61-72.
