## Chunk 01 Review

### Files Changed

- `.gitignore`
- `README.md`
- `Sources/ZoomItMacCore/Annotations/Annotation.swift` (beginning of a much larger model expansion)

### Technical Details

- Ignores Playwright CLI artifacts.
- Replaces the short drawing documentation with a detailed product and interaction contract for the native toolbar, attached inspector, tool shortcuts, selection/editing, pressure-sensitive pen input, highlighter behavior, rough/sloppy rendering, Smart Draw, advanced arrows, and text.
- Adds Hand, Select, Diamond, and Eraser tools.
- Extends the color catalog with appearance-aware stroke/background presets and dedicated highlighter colors. Semantic colors resolve through an `NSAppearance` provider, while highlighter colors use fixed sRGB values.
- Introduces `AnnotationColorValue` so styles can retain either a palette identity or arbitrary RGBA values rather than collapsing custom colors into the legacy enum.

### Notable Patterns

- The README functions as a detailed acceptance specification, including exact dimensions, spacing, shadows, palette values, shortcuts, and inspector section ordering. That is useful for implementation fidelity but creates a substantial documentation-maintenance surface if behavior changes.
- The change is deliberately compatibility-oriented: legacy shortcuts and existing ZoomIt gesture behavior remain alongside the new persistent tools.
- Color semantics are centralized in the model rather than scattered through toolbar/rendering code.
- This chunk begins a broad migration from a simple annotation representation toward a scene/editor architecture; later chunks must preserve the compatibility paths introduced here.

## Chunk 02 Review

### Files Changed

- `Sources/ZoomItMacCore/Annotations/Annotation.swift` (continued)

### Technical Details

- Adds centralized color resolution and explicit alpha compositing helpers, including compositing previews over an inspector background.
- Defines fill styles, stroke patterns, sloppiness levels, edge style, pressure modes, line caps/joins, and per-tool default widths.
- Expands `AnnotationStyle` from color/width/alpha into a full style record covering stroke/fill, pattern, sloppiness, opacity, legacy highlight compositing, line geometry, pressure, and smoothing.
- Retains compatibility accessors and initializer labels for `color`, `rootWidth`, and `alpha`.
- Adds stable element/group identifiers and timestamped pressure samples.
- Introduces a bounded raw-input buffer that deduplicates identical input, replaces low-value collinear middle samples, preserves corners and pressure extrema, trims data older than roughly two display frames, and caps storage.

### Notable Patterns

- Compatibility properties isolate old call sites while allowing the new renderer/editor to consume richer styles.
- The input buffer uses geometry-aware compaction rather than FIFO dropping, matching the stated goal of retaining endpoints, turns, pressure changes, and timestamps.
- `removeFirst()` is linear-time, but the buffer is intentionally capped at 32 entries, limiting the practical cost.
- `AnnotationColorResolver` is `@MainActor`, which is appropriate for AppKit color conversion but means callers performing background preview work must pass already-resolved/value-only data.
- Alpha is represented in both custom color values and style opacity; all rendering paths need to apply each factor exactly once.

## Chunk 03 Review

### Files Changed

- `Sources/ZoomItMacCore/Annotations/Annotation.swift` (continued)

### Technical Details

- Adds a stateful freehand resampler with zoom-aware spacing, bounded interpolation drains, pressure interpolation, timestamp interpolation, trailing preview replacement, and corner preservation.
- Long interpolation runs are represented as pending work and emitted in batches of at most 128 samples instead of blocking one frame.
- Defines per-frame drain budgets/stats and freehand/highlighter geometry records.
- Adds shape kinds and linear routing choices, including precise, curved, and internal elbow routes.
- Introduces endpoint direction, an expanded arrowhead catalog, and small/medium/large arrowhead scales.
- Begins a simulated-pressure tracker driven by screen-space movement and timing.

### Notable Patterns

- The resampler explicitly separates raw pointer intake from canonical path generation, supporting display-link draining and an immediate preview lane.
- Interpolation is bounded per drain while total step count is capped at one million; extreme jumps remain representable without a single huge allocation.
- Corner preservation uses a turn-angle threshold plus minimum leg length so aggressive compaction does not visibly round intentional corners.
- Route and arrowhead types are model-level values with display names, allowing the inspector and renderer to share one source of truth.
- The internal `.elbow` route is retained even though only straight and curved routes are user-selectable, suggesting compatibility or future routing support.

## Chunk 04 Review

### Files Changed

- `Sources/ZoomItMacCore/Annotations/Annotation.swift` (continued)

### Technical Details

- Completes simulated mouse-pressure generation using filtered velocity, asymmetric response constants, start and end taper envelopes, bounded event resampling, and pressure floors.
- Adds pressure backfill for existing strokes, preferring timestamp-based reconstruction and falling back to a deterministic distance envelope.
- Defines transitions between Line and Arrow defaults so switching tools adds or removes the conventional arrowhead only when the current endpoint state is still the default.
- Adds bindings, Bezier controls, complete linear geometry, text alignment/font presets, and text geometry.
- Introduces the typed `AnnotationElementGeometry`, metadata, and `AnnotationElement`, including stable IDs, z-order/group/lock/rotation/visibility state, Smart Draw provenance, and effective precision for headless lines.

### Notable Patterns

- Pressure calculation is deterministic and clamps invalid timestamps/speeds, which supports reproducible capture and tests.
- Backfill lets users enable variable pressure on older fixed-width strokes without requiring historical device pressure.
- The model distinguishes text font presets from persisted custom font names, preventing native preset selection from overwriting the Type setting.
- Headless linear elements force Architect precision through `effectiveSloppiness`, enforcing the README contract even if legacy data contains another value.
- Binding data is normalized to the target shape and carries gap/focus/side information, leaving room for stable endpoint recomputation after target edits.

## Chunk 05 Review

### Files Changed

- `Sources/ZoomItMacCore/Annotations/Annotation.swift` (completion of the reviewed model changes)
- `Sources/ZoomItMacCore/Annotations/AnnotationController.swift` (beginning of a major rewrite)

### Technical Details

- Adds conversion between legacy `Annotation` values and the new typed element geometries. The compatibility `Annotation` now also carries a stable element ID.
- Rejects attempts to create persistent elements from Hand, Select, or Eraser tools.
- Replaces the controller's flat annotation array with `AnnotationScene`, `AnnotationEditor`, and `AnnotationRenderer`.
- Introduces state for in-progress shapes/linear construction, asynchronous Smart Draw, freehand buffering/resampling, per-tool colors/widths/opacities, pressure preferences, staged erasure, text transactions, continuous style edits, linear defaults, and keep-active behavior.
- Tool/style setters normalize styles by context and preserve separate Pen, Highlighter, and outlined-geometry defaults.
- Scene changes synchronize renderer caches, revalidate linear editing, and notify observers.

### Notable Patterns

- The migration keeps a legacy snapshot/conversion layer, reducing disruption to existing rendering tests and integrations while the scene architecture is adopted.
- `SmartDrawCandidateTransfer` and recognition requests are marked `@unchecked Sendable`; correctness depends on all transferred candidate/geometry values remaining immutable value data without AppKit object ownership.
- Per-tool style memory is intentionally separated so selecting Highlighter or geometry does not overwrite Pen choices.
- Controller scope grows substantially and now coordinates model, editor, renderer, input scheduling, recognition, and persistence-facing defaults. Clear ownership boundaries between these subsystems will be important to prevent future state divergence.

## Chunk 06 Review

### Files Changed

- `Sources/ZoomItMacCore/Annotations/AnnotationController.swift` (continued)

### Technical Details

- Exposes snapshots, selection/editing capabilities, renderer cache counters, pending-work diagnostics, linear-construction state, Smart Draw preview/status, and undo/redo availability.
- Adds native font resolution for system, hand-drawn/rounded, serif, monospaced, and custom Type-setting fonts with platform fallbacks.
- Resets all transient and persisted-in-session drawing defaults explicitly.
- Reworks typing into scene transactions, supports editing existing unlocked text, tracks alignment/font preset separately, and updates active text without adding history entries until the transaction is committed.
- Applies persisted `DrawingDefaults` into separate Pen, Highlighter, and geometry state, normalizes the active style, restores Smart Draw pressure state, and restores independent Line/Arrow routes and arrowheads.

### Notable Patterns

- The controller provides extensive test-only observability for caches, queue age, recognition concurrency, insertion writes, and transient state, indicating performance and lifecycle behavior are intended to be regression-tested.
- Text editing is transaction-scoped so a complete typing session becomes one history mutation rather than one mutation per character.
- Font preset storage uses sentinel names for native categories, preserving a custom font choice independently.
- `reset()` and `applyDrawingDefaults()` each reconstruct many related fields; these paths must stay synchronized as new properties are introduced.
- The public `setPressureEnabled(true)` path later maps directly to tablet mode, while `preferredVariablePressureMode` contains the tablet-versus-simulated fallback policy; callers should consistently use the latter policy when no tablet has been observed.

## Chunk 07 Review

### Files Changed

- `Sources/ZoomItMacCore/Annotations/AnnotationController.swift` (continued)

### Technical Details

- Updates text caret placement for left, center, and right alignment.
- Replaces the old begin/update/end drawing flow with typed element creation, shape anchoring/aspect constraints, legacy modifier-gesture compatibility, route/arrowhead initialization, pressure sampling, and Smart Draw startup.
- Adds click-based multi-point Line/Arrow construction with a live preview point, finish/cancel handling, minimum-geometry checks, endpoint binding, and optional immediate point editing.
- Adds freehand raw-input enqueueing and display-budget draining. Adaptive spacing increases when the queue grows, pending interpolation drains before consuming more raw events, and the latest unprocessed point remains available as an immediate tail preview.

### Notable Patterns

- Persistent toolbar tools and temporary modifier gestures deliberately share creation code but preserve different legacy route/arrowhead behavior.
- Shape geometry is regenerated from the original anchor on each update, ensuring Shift-constrained Rectangle/Diamond drags do not accumulate error.
- Linear construction maintains a distinct uncommitted element and only writes to scene history at completion.
- Freehand processing is explicitly back-pressure-aware: queue depth influences spacing, and canonical refinement is separated from visual cursor following.
- `begin` silently ignores non-creating tools; higher input layers must route Hand, Select, and Eraser interactions through their dedicated APIs.

## Chunk 08 Review

### Files Changed

- `Sources/ZoomItMacCore/Annotations/AnnotationController.swift` (continued)

### Technical Details

- Completes queued freehand finalization, including a bounded mouse-up path that can abandon stale canonical work and append the exact latest endpoint.
- Commits visible gestures, applies endpoint bindings, runs final Smart Draw recognition, applies simulated-pressure end tapering, promotes renderer caches, and tracks newly committed linear elements for point editing.
- Adds undo/redo/clear behavior on top of scene history.
- Implements staged whole-element erasure: hits are faded during the gesture, committed together on release, and restored on cancellation.
- Reworks text insertion/deletion around stable element IDs and the active text transaction.
- Delegates rendering to `AnnotationRenderer`, with flags for editor chrome, transient eraser feedback, Smart Draw previews, in-progress content, destination scale, and ownership of immediate freehand presentation.
- Adds selection-decoration rendering and controller wrappers around editor interactions/actions.

### Notable Patterns

- The bounded finalization path prioritizes pointer-up responsiveness and endpoint fidelity over draining obsolete queued detail, matching the README's latency requirement.
- Capture/export callers can explicitly omit editor chrome and transient eraser feedback.
- Canonical rendering, immediate freehand layers, and Smart Draw ghost rendering are separate presentation lanes; ownership flags must be applied consistently to avoid duplicated active-stroke ink.
- Exit handling commits visible in-progress drawing/linear work but cancels erasure and then clears remaining transient state, so mode-specific callers must choose this API only when commit-on-exit is intended.
- Eraser history is atomic and cancellation-safe rather than deleting elements incrementally.

## Chunk 09 Review

### Files Changed

- `Sources/ZoomItMacCore/Annotations/AnnotationController.swift` (continued)

### Technical Details

- Adds controller APIs for selection, arrangement, grouping, locking, stroke/fill/background, width, pattern, sloppiness, opacity, pressure, smoothing, Smart Draw, edge style, linear routes, arrowheads, arrowhead size, and endpoint unbinding.
- Style changes target unlocked compatible selected elements while also updating creation defaults when selection context matches the current tool.
- Continuous controls use owner-keyed scene transactions so multiple callbacks from one native gesture produce one undo record.
- Enabling Smart Draw forces fixed pressure and saves/restores the prior variable-pressure preference.
- Edge style maps Rectangle/Diamond roundness and headless Line straight/curved routing through a shared inspector concept.
- Pressure mode changes can backfill existing freehand samples with deterministic simulated pressure.

### Notable Patterns

- Mixed-selection support is predicate-driven: only properties applicable to editable selected elements are mutated.
- Locked elements are consistently excluded from style and geometry changes.
- Creation defaults and selected-element mutations are coupled intentionally, but the matching rules are complex; tests should cover mixed tools, partial locks, and selection/current-tool mismatches.
- Legacy highlighted colors set both opacity and a compatibility compositing flag, while new opacity edits clear that flag.
- `setPressureEnabled(true)` chooses `.tablet` directly. If legacy callers invoke it without observed tablet input, they may bypass the intended simulated mouse-pressure fallback unless the UI resolves `preferredVariablePressureMode` first.

## Chunk 10 Review

### Files Changed

- `Sources/ZoomItMacCore/Annotations/AnnotationController.swift` (continued)

### Technical Details

- Adds helper predicates for style applicability, creation-tool inference, and decisions about whether selection edits should also update creation defaults.
- Implements route changes for active multi-point constructions, including regeneration of Bezier controls and orthogonal elbow extensions.
- Validates minimum visible geometry for freehand, shapes, and linear elements before committing.
- Centralizes cleanup of creation state and all active annotation work, including recognition tasks, transactions, queues, eraser state, renderer caches, and editor interactions.
- Adds bounded queue draining and exact final-endpoint replacement.
- Applies endpoint bindings to nearby visible, unlocked shapes and resolves the closest boundary candidate within a zoom-scaled tolerance.
- Sweeps the eraser between pointer samples at a spacing derived from hit-test radius, preventing fast drags from skipping elements.

### Notable Patterns

- Cleanup is comprehensive and cancellation-oriented, but it spans many state variables; every new transient feature must be added to both narrow creation cleanup and full cancellation cleanup.
- Linear construction stores explicit points and regenerates derived controls, preserving a clean source geometry.
- Binding currently excludes locked shapes as targets as well as locked linear elements from editing. That may be intentional, but it should remain aligned with the product rule for attaching arrows to locked objects.
- Eraser hit testing snapshots eligible candidates once per sweep and excludes already staged IDs, limiting repeated work.
- Text mutation helpers permit partial edits within mixed selections; the inspector's section-intersection logic must prevent exposing unsupported controls even though the controller safely filters them.

## Chunk 11 Review

### Files Changed

- `Sources/ZoomItMacCore/Annotations/AnnotationController.swift` (completion of the reviewed controller changes)

### Technical Details

- Resolves fixed, tablet, and simulated pressure samples and applies a higher minimum pressure to highlighter strokes.
- Runs Smart Draw preview recognition off the main actor with one active request and one replaceable pending request, generation tokens for stale-result rejection, capped point snapshots, throttling, and synchronous final-quality recognition on pointer release.
- Converts recognized candidates into native elements while retaining the original ID/style and recording rotation/provenance.
- Preserves separate styles while transitioning among Pen, Highlighter, text, and outlined geometry.
- Normalizes geometry, highlighter, and Pen-specific properties so unsupported patterns, pressure, caps, or sloppiness do not leak across tools.
- Finalizes helpers that classify tool support and pressure-capable freehand elements.

### Notable Patterns

- Recognition scheduling matches the stated bounded-concurrency design and includes counters for submission, rejection, and maximum concurrency.
- Generation tokens plus current-tool checks protect against stale preview delivery after cancellation or a new stroke.
- Final recognition intentionally runs synchronously on the main actor path; the input cap limits cost, but final recognition latency remains a critical performance point.
- In simulated mode, `resolvedFreehandSamples` takes only the last sample produced by `resampledSamples`; the canonical geometric resampler later interpolates between endpoints, but intermediate simulated-pressure curvature is collapsed to linear pressure interpolation.
- The `@unchecked Sendable` transfer remains a concurrency trust boundary and should stay limited to value-semantic candidate data.

## Chunk 12 Review

### Files Changed

- `Sources/ZoomItMacCore/Annotations/AnnotationEditor.swift` (new file; first 489 added lines reviewed in this chunk)

### Technical Details

- Introduces editor modifiers, state kinds, arrangement actions, and editor outcomes.
- Defines an explicit editor state machine for idle, creation, marquee selection, moving, resizing, rotating, linear-point editing, and text editing.
- Stores complete interaction snapshots for move/resize/rotate so scene transactions can preview mutations and commit or cancel atomically.
- Adds linear point/segment/control selection state, point insertion/removal, route and arrowhead mutation, endpoint unbinding, and editing revalidation.
- Begins pointer interaction dispatch: active linear editing gets first chance; visible linear anchors/controls can enter point editing directly; double-click starts text or linear editing; selection handles begin resize/rotation transactions.
- Exposes capability checks derived from unlocked selected elements and common group state.

### Notable Patterns

- Interaction behavior is centralized in a dedicated editor instead of continuing to expand the controller, establishing a cleaner boundary between input editing and rendering/model state.
- Transactions begin at gesture start and preserve original elements, supporting reversible previews and one-step undo.
- Locked elements are filtered from destructive and transformational operations while still remaining selectable.
- Linear point editing requires exactly one selected unlocked linear element. Even when an explicit element ID is supplied, the current selection count must already be one, so callers must select the target before entering the mode.
- Direct anchor/control hits are prioritized over general body/selection hit testing, matching the requirement that visible linear handles enter point editing on first interaction.
