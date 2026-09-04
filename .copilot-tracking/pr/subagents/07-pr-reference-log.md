## Chunks 73-84 Review

### Files Changed

- `Sources/ZoomItMacCore/SelfTest/SelfTestRunner.swift` (modified): Added self-test coverage for drawing toolbar behavior, style transactions, erasing, freehand input and rendering, Smart Draw recognition, capture policy, and deterministic rough rendering.

### Technical Details

The assigned range began in the latter portion of `testDrawingInspectorRuntimePresentationSwitch()` and verified that propertyless Hand, empty Select, and Eraser states hid the inspector without allowing zero or stale inspector frames to affect toolbar edge clamping. Switching back to a property-bearing tool reattached the inspector around the current toolbar position, combined toolbar and inspector dragging preserved their exact offset, and completed grip dragging persisted the clamped normalized position.

Drawing controls and style state gained broad interaction coverage:

- The color picker coordinator kept one continuous style transaction active while switching among stroke, background, and text channels. The tests also checked custom color-well selection, enablement, accessibility state, tooltips, duplicate dismissal handling, and preservation of the shared `NSColorPanel` parent, level, sharing type, and visibility.
- Toolbar actions updated selected element stroke, fill, pattern, width, sloppiness, opacity, and roundness through the annotation editor boundary. Continuous opacity and overlapping color-picker/slider edits committed as one undoable transaction, and legacy highlight color changes grouped color, opacity, and highlight compositing semantics atomically.
- Text creation cleared unrelated selection state, exposed the text-specific inspector sections, applied contextual color and opacity only to the active text element, and kept text insertion plus style changes in one undo/redo transaction. Mixed shape-and-text selection exposed only shared controls, while text-scoped actions left shapes unchanged.
- Pen, Highlighter, and geometry tools retained independent width, color, opacity, pressure, and sloppiness defaults across tool switches, persisted defaults, and selection-only edits. Highlighter remained fixed-pressure with a solid marker presentation, while transient modifier gestures used geometry defaults without replacing the selected Highlighter scope.
- The compact toolbar tests fixed the primary item order, visible Highlighter action, 698-by-54 layout, 44-point buttons, 24-by-44 drag handle, hit testing, accessibility labels and help, three-layer shadow metrics, selected and idle tile appearances, lower-right numeric hint placement, and one-shot tool behavior controlled by the lock tile.

Eraser tests covered both presentation and scale:

- Pending deletion faded only on-screen annotation rendering to approximately 28 percent while still-image capture retained committed content. Cancellation restored presentation without history, release removed all staged elements in one notification and one undo step, and zero-hit gestures did not create history.
- Pending-raster scaling was checked at 1x, 2x, and 4x for rough hachure and cross-hatch shapes, solid fill plus stroke, pressure-sensitive freehand, Highlighter, compound arrowheads, text, headless lines, and stacked elements.
- A fast sweep crossed Pen, Highlighter, shape, filled shape, Arrow, and text elements with at most 38 sweep samples, one redraw, and no duplicate rescanning. Hit coverage included Cartoonist displacement, filled interiors, curves, arrowheads, and text bounds. A 10,000-element stack required one linear candidate scan and excluded already staged elements from subsequent scans.

Freehand tests established deterministic input, pressure, presentation, and cache contracts:

- Smoothing preserved first and last samples, used deterministic subdivisions, interpolated pressure, retained ordered coalesced locations and timestamps, and deduplicated current events. Tablet pressure stayed clamped during resampling, simulated mouse pressure tracked calibrated velocity with bounded filters, equivalent screen-space motion matched across zoom levels, and final tapering retained a readable pressure floor.
- Corner-aware resampling reduced jitter without losing intentional corners, timestamps, endpoints, pressure extrema, or loop topology. Sparse high-speed strokes and figure-eight paths remained locally bounded and avoided extra spline intersections.
- A 1,000-event, 10,000-pixel input stream drained within per-frame raw-event and generated-sample budgets. Input arriving at 240 Hz coalesced to 60 display invalidations, Smart Draw preview submissions remained bounded, and stale recognition generations were rejected.
- Active stroke caching rebuilt at most two chunks for a 10,000-sample append and rebuilt none for an unchanged redraw. Committed caching rebuilt only new or mutated elements, retained at most two scale variants per element, reused promotable active entries, evicted deleted and cleared entries across undo/redo, and enforced configured LRU entry and estimated-memory limits.
- Sustained 125, 240, 500, and 1,000 Hz streams used a per-frame budget of 12 raw events and 96 generated samples while bounding queue size and age. The latest-pointer lane exposed the newest event immediately, queue compaction retained endpoints, significant turns, and pressure extrema, and final geometry remained ordered and ended at the latest cursor location.
- Immediate-layer raster tests preserved the unreflected cursor endpoint at 1x and 2x, rendered one nib component, assigned a single owner to Highlighter opacity, and kept the canonical renderer responsible for committed content while immediate layers exclusively owned the queued tail.

Smart Draw coverage validated recognition quality, bounded asynchronous work, and history behavior:

- Recognition differentiated circles, ellipses, squares, rectangles, and diamonds from noisy, rotated, incomplete, unevenly sampled, or overshooting gestures. Arrow fitting detected heads at either endpoint and preserved shaft direction. Intersecting scribbles, double-loop overtraces, tiny gestures, and slow scribbles remained freehand, with minimum gesture distances scaled by zoom.
- Preview analysis used a deterministic 20-30 Hz cadence, started with at most five points, required four additional points between eligible updates, and resampled dense input before expensive recognition. A 12,000-point circle produced the same result after bounded preparation.
- Recognition allowed one in-flight request plus one replaceable latest snapshot. The pending request ran after the current result, maximum concurrency stayed at one, and no recognition results were rejected in the tested sequence.
- Stability tracking supported immediate high-confidence previews, faint provisional candidates, same-class geometric smoothing, resistance to one competing classification, medium-confidence commits after stable previews, and final high-confidence commits when no preview interval elapsed.
- Controller tests kept asynchronous previews out of scene history, exposed inspector analysis or candidate status, replaced accepted Pen ink with native typed geometry carrying current sloppiness, and made replacement undoable in one step. Ambiguous input retained fixed-pressure Pen ink and restored the saved Pen pressure mode. Final pointer-release recognition remained independent of preview throttling.

Rendering and capture tests exercised pixel-level output:

- Offscreen raster assertions covered rotation around shape centers, independent fill and stroke colors, distinct rectangle, diamond, and ellipse geometry, deterministic dashed and dotted runs, smoothed Pen output, legacy arrow anchoring, pressure-based width, text glyphs and baselines, style opacity, and selection-decoration isolation.
- Highlighter tests checked a flat rectangular marker nib, gap-free variable-width outlines, smoothed Pen continuity, single-pass overlap compositing, and matching effective colors between canvas output, preset swatches, and custom sRGB wells. Custom color alpha, style opacity, and Highlighter opacity were applied once.
- Seeded hachure and cross-hatch fills rendered byte-identically across redraws, clipped correctly, retained consistent opacity, used deterministic rough passes, added a second cross-hatch direction, and avoided opacity accumulation at intersections.
- Still-image capture omitted in-progress annotations, Smart Draw previews, editor chrome, eraser feedback, and immediate freehand layers. Recording retained canonical in-progress Pen and shape content while continuing to exclude presentation-only chrome and eraser feedback.

Rough-rendering tests fixed deterministic geometry and measured raster behavior:

- Stable element-derived seeds produced repeatable Artist and Cartoonist paths, while duplicated element IDs produced distinct rough output. Unbound passes retained independent endpoints, explicit bindings and arrow tips stayed pinned, Architect returned the canonical path, and hit testing continued to use canonical geometry.
- Destination-space deviation caps were fixed at 0 points for Architect, 5.5 for Artist, and 11 for Cartoonist. Tests measured Artist waviness, pass separation, and maximum deviation; required stronger Cartoonist separation; preserved screen-space roughness across zoom; and verified two independent passes for rough solid, dashed, and dotted strokes without widening.
- Closed-shape sides and passes sampled independent corners, Cartoonist passes crossed rather than forming parallel rails, multiple line lengths retained substantial variation, rough ellipses adapted sampling density with at least nine perimeter samples, and pressure paths stayed linear in sample count with two bounded fills and stable finalized prefixes.
- A raster matrix covered stroke widths 1, 3, and 6; solid, dashed, and dotted patterns; all three sloppiness levels; and 1x and 2x backing scales. It compared logical silhouettes and alpha masks, retained visible pattern gaps, preserved rough pixels under selection chrome, and placed selection outlines beyond stroke width plus maximum rough deviation.
- Headless straight and curved Line output ignored stored sloppiness at both backing scales. Line creation and selection hid or rejected sloppiness changes without mutating shared shape and Arrow defaults, while adding an arrowhead restored roughness controls and rough rendering.
- The range ended after beginning a cross-family sloppiness and opacity fixture for rectangle, diamond, ellipse, legacy Pen, curved Arrow, and elbow Line elements; its assertions continue in the following reference chunk.

### Notable Patterns

All changes in chunks 73-84 were additions to the monolithic self-test runner; no production implementation file changed within this range. The tests relied heavily on deterministic UUIDs, offscreen bitmap comparison, explicit timing and work budgets, stable cache counters, and `ForTesting` inspection hooks.

The added coverage encoded exact UI dimensions, pixel-alpha ranges, rendering tolerances, timing cadence, queue limits, and cache ceilings. Intentional changes to drawing presentation or performance contracts will require corresponding baseline updates. No ambiguous behavior or correctness concern was identified in the assigned chunks.
