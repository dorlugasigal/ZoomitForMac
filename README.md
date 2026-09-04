# Sysinternals ZoomIt for Mac

Sysinternals ZoomIt for Mac is a macOS menu-bar utility modeled after Sysinternals ZoomIt. It provides screen zoom, live zoom, drawing and typing annotations, screenshots, snips, recording, webcam picture-in-picture, and scrolling panorama capture.

## Install

Install Sysinternals ZoomIt from the [Homebrew Sysinternals tap](https://github.com/microsoft/homebrew-sysinternalstap):

```sh
brew install --cask microsoft/sysinternalstap/zoomit
```

If the tap is already configured, the shorter form also works:

```sh
brew install --cask zoomit
```

## Uninstall

Uninstall ZoomIt with Homebrew:

```sh
brew uninstall --cask zoomit
```

## Features

- Static zoom over a frozen ScreenCaptureKit display capture.
- Live zoom of the running screen, with click-through interaction when not drawing.
- Draw-without-zoom mode for annotating the screen at 1x.
- Pen, line, rectangle, diamond, ellipse, arrow, highlighter, undo, erase, blank-screen sketch pads, and typing annotations.
- Excalidraw-style Architect, Artist, and Cartoonist sloppiness for shapes, arrows, and Pen strokes; regular Lines stay precise.
- Viewport screenshot copy/save and region snip copy/save.
- OCR snip: select a screen region and copy its recognized text to the clipboard.
- Break timer with a configurable countdown, colors, opacity, background, and optional sound.
- MP4 screen recording for the whole screen or a selected region, with optional system audio, microphone audio, and fixed webcam picture-in-picture.
- Post-recording video editor with preview, trim, append, fades, playback controls, volume mute/slider, and export before save.
- Scrolling panorama capture with alignment, fixed header/footer suppression, progress, cancellation, and copy/save output.
- Tabbed Settings dialog for hotkeys, zoom, draw, type, snip, record, webcam, panorama, and launch-at-login preferences.
- Single-instance app behavior, menu-bar status, permission checks, and optional launch at login.

## Requirements

- macOS 14 or newer.
- Xcode command-line tools.
- Screen Recording permission for capture.
- Microphone and Camera permissions are required only for those recording options.

## Build, Test, Run

```sh
swift build
swift run ZoomItMacSelfTest
swift run ZoomIt
```

The self-test covers viewport math, annotation lifecycle/rendering, settings persistence, and panorama stitcher regressions.

Run the sandbox product-surface tests with the App Store compiler condition:

```sh
swift run -Xswiftc -DZOOMIT_APP_STORE ZoomItMacSelfTest
```

Launch at login requires running ZoomIt as an app bundle so macOS attributes the login item to ZoomIt instead of the host process used for development. Build the bundle with:

```sh
zsh Scripts/build-app.sh
open ".build/ZoomIt (Dev).app"
```

The contributor build is named `ZoomIt (Dev).app` (bundle id `com.sysinternals.zoomitmac.dev`) so it stays distinct from an installed official `ZoomIt.app` in the Screen Recording list. See [Bundle identity](#bundle-identity-dev-vs-official) below.

## Default Hotkeys

| Action | Shortcut |
| --- | --- |
| Static zoom | `Control+1` |
| Draw without zoom | `Control+2` |
| Break timer | `Control+3` |
| Live zoom | `Control+4` |
| Record screen | `Control+5` |
| Record region | `Control+Shift+5` |
| Snip region to clipboard | `Control+6` |
| Snip region to file | `Control+Shift+6` |
| OCR region to clipboard | `Control+Option+6` |
| Panorama to clipboard | `Control+8` |
| Panorama to file | `Control+Shift+8` |

All global hotkeys are configurable in Settings. While zoomed, use `Option+Up` and `Option+Down` to change zoom level, mouse wheel to zoom or resize tools depending on mode, and `Command+S` / `Command+C` to save or copy the viewport. `Esc` exits the active overlay mode; right-click only leaves drawing mode and does not close an overlay when drawing is inactive.

## Drawing And Typing

The native drawing UI appears automatically while drawing in static zoom, live
zoom, and draw-without-zoom mode, and remains visible when drawing transitions
into typing. A persistent horizontal tool strip starts near the top center and
uses a 698-by-54-point desktop shell with a 5-point inset, 15-point pill radius,
no border, and transparent 44-by-44 tool tiles. Icons use 20-point regular
symbols and groups use 6-point gaps. Its measured shadows remain
black at 17% with 1-point blur, black at 8% with 3-point blur, and black at 5%
with a 7-point vertical offset and 14-point blur. It groups the keep-active lock, Hand, the
numbered `1`-`8`/`0` tools (with unsupported Image/`9` omitted), an unnumbered
Highlighter beside Pen with the `H` shortcut, and overflow using clear
separators. Shortcut numbers use regular 11-point type at the lower right.
Undo/redo, Clear, grouping, ordering, locking, and other secondary actions
remain available from overflow. A subtle 24-point grip at the leading edge,
plus unused toolbar background, repositions the toolbar and attached inspector
with open-hand/closed-hand feedback; tool buttons never initiate a drag.
Fresh sessions without a saved position start top-center, while moved positions
remain persisted. There is no hamburger; the visible leading grip is the
toolbar's dedicated drag affordance.

Drawing properties live in one always-attached native inspector card directly
below the horizontal toolbar with a 6-point gap, or above it only when required
by screen space. The inspector is a child of the toolbar panel, so both frames
move in the same event-loop iteration with an invariant relative offset and no
visible drag lag. The card is a content-hugging horizontal strip that does not
stretch to the toolbar width. Pen properties use only 12 points of padding per
side. Sections remain atomic and pack into at most two tight rows; if a
narrow display needs more room, the document scrolls horizontally instead of
truncating controls. There is no side mode, docking preference, visibility
toggle, pin, close button, or presentation switch. The card appears whenever
the active tool or selection exposes properties and naturally disappears for
Hand, Eraser, and empty Select. Compact 32-point rounded-square
palettes use SF Symbols and programmatic previews for finite choices, with a
lavender selected state,
mixed-selection indicators, tooltips, accessibility labels, and first-click
interaction. Colors use native minimal custom color wells and opacity uses a
native continuous slider; the inspector does not use dropdowns for styling
choices. Stroke, Background, and text Stroke share one active native minimal
color popover and one continuous history transaction. Switching channels closes
the prior well cleanly without presenting or reparenting `NSColorPanel`.
Changing tools resets horizontal overflow to the origin while updates within
the same context retain the useful scroll position. The combined toolbar and
inspector surface starts top-center when no position is saved and persists only
its moved position.

The compact inspector uses this exact supported section matrix:

| Tool or selected element | Sections, in order |
| --- | --- |
| Rectangle, Diamond | Stroke, Background, Stroke width, Stroke style, Sloppiness, Edges, Opacity, Layers |
| Ellipse | Stroke, Background, Stroke width, Stroke style, Sloppiness, Opacity, Layers |
| Arrow | Stroke, Stroke width, Stroke style, Sloppiness, Arrow type, Arrowheads, Arrowhead size, Opacity, Layers |
| Line | Stroke, Stroke width, Stroke style, Edges, Opacity, Layers |
| Pen | Stroke, Stroke width, Smart Draw, Pressure, Opacity |
| Highlighter | Stroke, Stroke width, Opacity |
| Text | Stroke, Font family, Font size, Text align, Opacity, Layers |
| Hand, Eraser, empty Select | No inspector |

For mixed selections, only sections supported by every selected element remain.
Selecting a nontransparent shape Background inserts Fill immediately after
Background; selecting Transparent removes Fill. Duplicate, delete, group,
ungroup, lock, point editing, endpoint unbinding, and other editing actions stay
in the canvas context menu or toolbar overflow instead of increasing inspector
height.

The Layers row uses four 32-point controls in this order: Send to back
(`Command+Option+[`), Send backward (`Command+[`), Bring forward
(`Command+]`), and Bring to front (`Command+Option+]`). Terminal actions use
arrow-to-bar glyphs; one-step actions use plain arrows. Eraser hits are staged
while the pointer is held and shown at reduced opacity, then removed together
on mouse release as one undo step. Escape, mode exit, or cancellation restores
them without history, and captures omit this transient fade.

Shapes and arrows expose Excalidraw-style Sloppiness choices: **Architect**
uses one precise path, **Artist** is the moderately hand-drawn default, and
**Cartoonist** adds a stronger rough double stroke. Roughness is seeded from
each annotation's stable ID, so redraws, zoom, screenshots, and recordings keep
the same marks while selection, hit-testing, bindings, and point editing remain
based on the original geometry. Artist and Cartoonist use calibrated
perturbation and secondary-stroke separation so shapes remain visibly distinct.
Artist remains modest; Cartoonist deliberately uses broad independent bends,
crossings/merges, separated traces over substantial thin/normal-width edge
portions, and up to roughly 11-point corner overruns. Stroke width participates in
the roughness profile, so the second trace stays outside the first stroke's
antialias footprint at 1-, 3-, and 6-point widths without becoming symmetric
parallel rails. Dashed and dotted strokes retain those independent
rough passes instead of being widened into one precise-looking path. Selection
outlines sit beyond half the stroke width plus the maximum rough deviation.
The Edges control uses two 32-point icon-only Sharp/Round corner tiles with
dotted right and bottom edges. Text glyphs remain native and legible.
Regular Lines, including stored headless linear elements, always render with
Architect precision. Adding an arrowhead restores the Arrow sloppiness controls.

Shapes expose separate stroke and background palettes, deterministic
**hachure**, **cross-hatch**, and solid fill previews, stroke width/style,
Sloppiness, sharp/round edges where supported, opacity, and layer actions.
Stroke colors are five semantic Excalidraw-style presets plus one separated
custom/current tile: neutral, coral, green, light blue, and orange. Dark mode
resolves them to `#E9ECEF`, `#FF8787`, `#69DB7C`, `#74C0FC`, and `#FFA94D`;
light mode uses `#1B1B1F`, `#E03131`, `#2F9E44`, `#1971C2`, and `#E8590C`.
Background colors are exactly transparent plus muted red, green, blue, and
yellow, using darker dark-mode shades and pastel light-mode shades. Presets and
the preset tiles are solid 35-point rounded squares inside fixed 38-point
controls, separated by 7-point gaps and a thin divider. The custom/current
native color well is a separate 26-by-26-point tile with a 5-point radius and
no border. Selection uses a thin
lavender/indigo outer ring without changing layout; hover uses a subtler ring,
and Transparent uses a dark/light checkerboard. Fill offers only hachure,
cross-hatch, and solid after a nontransparent background is active.
New rectangles use horizontal and vertical edges, and new diamonds use
top/right/bottom/left vertices, with zero initial rotation. Hold `Shift` while
using either persistent tool to constrain its bounding box to a square while
keeping the original drag anchor and quadrant. Selection rotation handles
remain available for explicitly rotating an existing shape afterward.
Pen exposes stroke, width, Constant/Variable pressure, and opacity. Variable
pressure uses native tablet input when observed and deterministic mouse-speed
pressure otherwise; advanced pressure and smoothing choices remain in Draw
settings. Pen defaults to 7 points with 3/7/11-point inspector choices.
Mouse-speed pressure
filters timestamped velocity and acceleration, resamples uneven input, bounds
width changes, and applies short start/end tapers so sparse events do not create
visible spikes. Every drag event replaces the latest raw-pointer visual lane
immediately; a bounded 24-sample/50 ms compositor tail therefore terminates
directly at the latest AppKit cursor point on the next display frame independently of canonical
refinement. Mouse coalescing remains enabled, while the canonical queue keeps
at most 32 compacted samples and roughly two 60 Hz frames of history, preserving
endpoints, significant turns, pressure extrema, and timestamps while dropping
obsolete collinear input. A 60/120 Hz display link drains strict adaptive
per-frame budgets, and mouse-up commits the exact latest endpoint without
draining stale history. Moving strokes never add a second endpoint dot or
stamp; the standalone nib is used only before movement or for a true
single-click stroke. Active strokes render from overlapping 128-sample
cached chunks, rebuilding only the dirty tail instead of the full growing
stroke. Variable width is interpolated as a continuous filled outline with a
1.25-destination-pixel minimum rather than disconnected width steps.

Highlighter uses a constant-width clean marker path with flat butt ends and a
rectangular single-click stamp/cursor. It defaults to 18 points with
10/18/28-point inspector choices and a separately persisted Draw setting. Its
context palette is Light Yellow
`#FFF45C` (default), Cyan `#32D7FF`, Pink `#FF5CAD`, Green `#66F26F`, and Orange
`#FF9F43`. Preset and custom/current tiles preview the effective translucent
sRGB color against the inspector background, including custom alpha, style
opacity, and the highlighter multiplier exactly once. Canvas highlighter runs
use the same resolver and preserve non-darkening overlap semantics. Dotted or
dashed geometry styles never leak into Pen/Highlighter; outlined geometry keeps
its previous pattern when selected again. Smart Draw is a wand toggle directly
in Pen properties and remains available in Draw settings and toolbar overflow.
When enabled, it temporarily replaces the Pressure section and restores the
saved Pen pressure mode when disabled.
Line Edges map to ZoomIt's supported sharp/curved open-linear behavior and stay
precise regardless of a legacy stored sloppiness value. Arrows
use visual straight/curved type buttons plus start/end popover palettes and
Small/Medium/Large head sizes at 1.0x/1.35x/1.75x. The
expanded head catalog includes none,
open arrow, outlined/filled triangles, circles, and diamonds, one/bar, many/
crow-foot, one-or-many, zero-or-one, and zero-or-many. Shafts are trimmed to
outlined and filled heads so straight and curved arrows attach cleanly
at every stroke width; endpoint unbinding and point editing remain available
as icon actions. A single selected line, arrow, or curve always shows its
anchors; curves also show Bezier controls and tangent guides. Clicking or
dragging a visible anchor/control enters point editing directly, while
unselected elements remain uncluttered and inapplicable insert/remove/unbind
actions stay disabled.

Text exposes stroke color, Hand-drawn/Normal/Code presets plus a font-picker
button. Hand-drawn resolves through Marker Felt, Chalkboard, or Noteworthy
fallbacks; Normal uses the native system sans; Code uses Menlo or the native
monospaced fallback. Preview buttons draw an actual `A` with the selected font.
Small/Medium/Large/Very large size buttons, alignment, opacity, and
layers. No property sections appear for Select until an annotation is selected.
Inspector changes update
immediately and each click or continuous gesture is recorded as one atomic
history mutation. The Draw settings pane controls drawing defaults including
Sloppiness and patterned fills, saved combined-surface placement reset, and
whether the last tool and style are
remembered. The tool strip and inspector stay above the
overlay but are excluded from copied, captured, and recorded output.

Smart Draw is disabled by default and only affects Pen strokes. When enabled,
ZoomIt locally recognizes circles, ellipses, squares, rectangles, diamonds, and
arrow gestures. Recognition tolerates modest closure gaps and overshoot, ignores
isolated outliers, and robustly fits the intended center and size instead of
stretching a shape to raw stroke extremes. Recognized rectangles and squares
always use horizontal/vertical edges, and recognized diamonds always use
vertical/horizontal vertices; freehand gesture angle never rotates those
outputs. A faint provisional dashed shadow can appear after five points; stable
same-class recognition strengthens it. Preview work runs off the main actor at
up to 25 Hz after four new samples with one in-flight request and one
replaceable latest pending snapshot, so delivery is not starved by new input.
Preview input is capped at 144 points and final input at 320. Releasing the pointer
runs the authoritative full-quality fit;
high-confidence results, or medium-confidence results matching a stable
preview, commit as a clean native shape in one undo step using the active
Sloppiness style. Smart Draw always uses effective fixed pressure; disabling it
restores the previously selected Pen pressure mode. Ambiguous, tiny,
intersecting, overtraced, or scribbled strokes remain normal freehand ink.
Recognition is deterministic and
does not use a network service or machine-learning model.

### Drawing shortcuts

- Left click enters drawing mode while zoomed; draw-without-zoom starts armed so
  the first drag draws immediately. Right click or `Escape` exits according to
  the active zoom mode.
- Hold `Shift` while dragging for a line, `Control` for a rectangle,
  `Control+Shift` for an arrow, or `Tab` for an ellipse. These temporary gestures
  do not replace the selected toolbar tool. When Rectangle or Diamond is the
  selected tool, plain `Shift` instead constrains that direct shape to equal
  width and height.
- With the persistent Line or Arrow tool, drag for the existing one-shot
  gesture, or click once to place the start and continue clicking to add path
  anchors. A live ghost segment follows the pointer. Double-click the last
  point, click the highlighted terminal handle, press `Return`, or use the
  toolbar's Finish Path button to complete it. `Escape` discards a one-point
  path and otherwise keeps the placed segments; Cancel Path always discards the
  pending path.
- Press the plain number keys while drawing to select tools in Excalidraw order:
  `1` Select, `2` Rectangle, `3` Diamond, `4` Ellipse, `5` Arrow, `6` Line,
  `7` Pen, `8` Text, and `0` Eraser. Number-row and numeric-keypad input use
  the character reported by macOS. Modified number shortcuts are left alone,
  and number keys continue to type normally while editing text. `9` is reserved
  for Excalidraw's Image tool and is intentionally unassigned because ZoomIt
  does not currently support image insertion.
- The legacy shortcuts remain available: `F`, `L`, `A`, or `H` select pen,
  line, arrow, or highlighter; `T` enters a new left-aligned typing session in
  the Text tool context, while `Shift+T` enters right-aligned typing. `V`
  selects elements, `Space` selects the hand tool, and `Shift+E` selects the
  eraser. Press `E` without Shift to clear
  all annotations. The display-safe toolbar uses a 54-point shell, 44-point
  tiles, 20-point icons, and regular 11-point lower-right numeric shortcuts;
  tooltips include
  both numeric and legacy shortcuts.
- Press `R/G/B/O/Y/P/W/K` for red, green, blue, orange, yellow, pink, white, or
  black. Hold `Shift` with a color key for translucent highlight ink.
- Use `[` and `]`, `Shift+Up` and `Shift+Down`, or the mouse wheel while drawing
  to change stroke width. Use `Command+Z` or `Control+Z` to undo and
  `Command+Shift+Z` to redo.
- Press `Control+W` or `Control+K` for a white or black sketch-pad background.
  `Command+C` copies and `Command+S` saves the current viewport without toolbar
  chrome or selection handles.

### Editing and advanced arrows

With the Select tool, click or marquee-select elements; `Shift` adds to the
selection and `Command` toggles selected elements. Drag to move, use the visible
handles to resize or rotate, hold `Option` while moving to duplicate, and use
`Shift` where available to constrain the edit. The arrow keys nudge a selection
by one point, or ten points with `Shift`.

Selection shortcuts include `Command+A` select all, `Command+D` duplicate,
`Delete` remove, `Command+G` group, `Command+Shift+G` ungroup,
`Command+Shift+L` lock/unlock, `Command+]` / `Command+[` move one level forward
or backward, and `Command+Option+]` / `Command+Option+[` move to the front or
back. The older Shift terminal variants remain compatible.
Right-clicking a selected element opens the same editing actions.

Lines and arrows support straight and curved routes plus none, arrow,
triangle, circle, bar, and diamond endpoint styles in Small, Medium, and Large
sizes. Fresh Line defaults are straight while fresh Arrow defaults are curved;
the two route choices are remembered independently. Select one linear element
and press `Return` to enter or leave point editing; press `I` to insert a point
and `Delete` to remove selected points. Every anchor, including the base and
head, can be dragged independently. Curved routes expose incoming and outgoing
Bezier handles with tangent guides; dragging a handle keeps the opposite
tangent smooth, `Command` mirrors its length, and `Option` breaks the tangent
for independent shaping. `Option+1` and `Option+2` choose straight and curved
routing. Dragging or placing an endpoint near a rectangle, diamond, or ellipse binds it to that shape;
`Option`-dragging a bound endpoint or pressing `Command+Option+B` unbinds it.

### Typing

Press `T` for left-aligned typing or `Shift+T` for right-aligned typing. This
clears any prior selection, selects the Text context in the toolbar and
inspector, and starts a new text insertion; Text remains the current tool after
typing finishes. Use `Up` / `Down` or the mouse wheel to adjust font size, and
press `Escape` or click the canvas to finish. Text uses the current stroke color and the selected
native font preset; choosing **Type** uses the custom font configured on the
Type settings pane without overwriting it when another preset is selected.
Existing text can be selected and edited again from the canvas. Before
placement, Text uses the native system I-beam without a second canvas cursor.
Once text editing is active, only the insertion caret is shown at the actual
text position. A Text click or `T` shortcut resolves one content-space insertion
point before focus or mode changes; the annotation origin is exactly that point
at every zoom and backing scale. Native glyph ink still begins at the font's
normal baseline inset from that origin.

## Snip And OCR

Press the snip shortcut (`Control+6`) and drag a rectangle to copy that region of the screen to the clipboard; hold `Shift` (`Control+Shift+6`) to save it to a PNG file instead. Snip also works while zoomed, capturing the magnified view.

Press the OCR shortcut (`Control+Option+6`) and drag a rectangle to recognize the text inside it and copy that text to the clipboard. OCR uses Apple's on-device Vision text recognition, runs entirely on-device, and needs no extra permissions. Both shortcuts are configurable on the Snip tab in Settings.

## Recording

Recording uses ScreenCaptureKit and AVAssetWriter. Static zoom and drawing overlays are captured even when ScreenCaptureKit omits ZoomIt's own windows; live zoom remains excluded from its own capture to avoid feedback. Webcam picture-in-picture stays fixed in the recorded viewport and is composited into overlay recordings instead of being zoomed into the source image.

When recording stops, ZoomItMac opens the built-in editor before the save panel so the clip can be trimmed, appended to another clip, faded, muted, and exported.

## Panorama

Panorama capture records a selected scroll region while you scroll, then stitches the frames into one image. It filters repeated frames, handles vertical or horizontal scrolls, suppresses fixed headers and footers, shows stitch progress, and can be canceled with `Esc`.

## Settings And Permissions

Settings are saved immediately to `UserDefaults`. The app includes permission checks for Screen Recording, Microphone, and Camera. Running from SwiftPM is supported for development; launch at login and production distribution are intended for the bundled app form.

## Distributing To Testers

Testers should run the bundled app, not `swift run`. Build a release app bundle:

```sh
zsh Scripts/build-app.sh release
```

Local bundles default to version `1.0`. Set `ZOOMIT_VERSION` to stamp a
specific dotted-numeric version into both `CFBundleShortVersionString` and
`CFBundleVersion`:

```sh
ZOOMIT_VERSION=1.2.0 zsh Scripts/build-app.sh release
defaults read "$PWD/.build/ZoomIt (Dev).app/Contents/Info" CFBundleShortVersionString
defaults read "$PWD/.build/ZoomIt (Dev).app/Contents/Info" CFBundleVersion
```

The official Azure DevOps build supplies `ZOOMIT_VERSION` from the version
entered when the pipeline is queued. Values must contain two or three numeric
components, such as `1.2` or `1.2.0`; malformed values fail before compilation
or signing begins.

## Build Variants

One source tree produces the standard unsandboxed application and the sandboxed
product surface used for Mac App Store releases.

| Variant | Product surface |
| --- | --- |
| Homebrew | Unsandboxed, including DemoType |
| Mac App Store | App Sandbox; DemoType is compiled out |

`ZOOMIT_DISTRIBUTION` selects the channel and defaults to `homebrew`, preserving
the existing local build command. `ZOOMIT_BUILD_NUMBER` independently stamps a
numeric `CFBundleVersion` when a specific local value is needed.

```sh
# Existing contributor/Homebrew behavior
zsh Scripts/build-app.sh release

# Explicit Homebrew variant
ZOOMIT_DISTRIBUTION=homebrew ZOOMIT_BUILD_NUMBER=101 \
  zsh Scripts/build-app.sh release

# Sandboxed local prototype (still uses the separate contributor identity)
ZOOMIT_DISTRIBUTION=appstore ZOOMIT_BUILD_NUMBER=101 \
  zsh Scripts/build-app.sh release
```

The App Store variant uses security-scoped bookmarks for the selected break
sound, break background, and automatic snip folder. Re-select a resource in
Settings if macOS reports that its authorization can no longer be restored.
Screen recording remains controlled by macOS privacy consent and has no app
entitlement.

By default this produces `.build/ZoomIt (Dev).app` with the app icon, bundled resources, and an `Info.plist` declaring the microphone and camera usage descriptions. `release` builds are **Universal** (Apple Silicon + Intel) by default; `debug` builds are native to the build machine for speed. Override the architectures with `ZOOMIT_ARCHS` (e.g. `ZOOMIT_ARCHS=arm64`). A Universal build routes through Xcode's build system, so it requires a **full Xcode** install — with only the Command Line Tools the script warns and falls back to a native build. The build summary prints the resulting architectures.

### Create and install a local development DMG

Build the Universal development app, stage it with an Applications shortcut, and create a compressed disk image using macOS's built-in `hdiutil`:

```sh
zsh Scripts/build-app.sh release

STAGE="$(mktemp -d)"
ditto ".build/ZoomIt (Dev).app" "$STAGE/ZoomIt (Dev).app"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
  -volname "ZoomIt Dev" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  ".build/ZoomIt-Dev.dmg"
rm -rf "$STAGE"

hdiutil verify ".build/ZoomIt-Dev.dmg"
open ".build/ZoomIt-Dev.dmg"
```

Drag **ZoomIt (Dev)** to the Applications shortcut in the mounted image, then launch the installed copy:

```sh
open "/Applications/ZoomIt (Dev).app"
```

A `.dmg` is a disk image, not an executable; use `open path/to/file.dmg` rather than invoking the path directly. Do **not** override a local ad-hoc build to use `com.sysinternals.zoomitmac` or the `ZoomIt.app` name. That identity is reserved for the officially Developer ID-signed release; an ad-hoc app using it conflicts with the official app's macOS privacy (TCC) grants even when System Settings shows Screen Recording as enabled.

### Bundle identity: dev vs. official

`Scripts/build-app.sh` picks the bundle identity from the signing identity so a locally built copy never fights the officially distributed app over macOS privacy (TCC) grants, which are keyed by bundle id **and** code-signing requirement:

- **Contributor / ad-hoc build (default):** app bundle `ZoomIt (Dev).app`, bundle id `com.sysinternals.zoomitmac.dev`, display name “ZoomIt (Dev)”, ad-hoc signed. Both the distinct file name and bundle id keep it separate from an installed official `ZoomIt.app`, so its Screen Recording grant is its own row in System Settings and the two never clobber each other.
- **Official build:** pass a real Developer ID identity and it keeps the canonical `com.sysinternals.zoomitmac` id:

  ```sh
  ZOOMIT_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
    zsh Scripts/build-app.sh release
  ```

Override any field explicitly with `ZOOMIT_SIGN_IDENTITY`, `ZOOMIT_BUNDLE_ID`, and `ZOOMIT_DISPLAY_NAME`. Because a real signing identity has a stable, team-based designated requirement, the official app keeps its Screen Recording permission across updates; an ad-hoc build cannot share that grant since contributors don't have the certificate.

### Entitlements (camera & microphone)

`build-app.sh` signs the bundle with `Scripts/ZoomIt.entitlements`, which grants `com.apple.security.device.camera` and `com.apple.security.device.audio-input`. Under the hardened runtime (used by notarized builds) these are **required** for the webcam overlay and microphone recording — without them macOS denies both even after the user approves the TCC prompt. Screen Recording is pure TCC and needs no entitlement. The entitlements are embedded even for ad-hoc builds so that when the official pipeline re-signs the bundle with ESRP (`MacAppDeveloperSign`), the existing entitlements are preserved. Verify on the first signed build with `codesign -d --entitlements :- ZoomIt.app`.

### Signing options

- **Distributing widely (recommended):** sign with a Developer ID Application certificate, notarize with Apple, and staple the ticket, then zip or wrap the app in a `.dmg`:

  ```sh
  ZOOMIT_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
    zsh Scripts/build-app.sh release
  ditto -c -k --keepParent .build/ZoomIt.app ZoomIt.zip
  xcrun notarytool submit ZoomIt.zip --apple-id you@example.com \
    --team-id TEAMID --password APP_SPECIFIC_PASSWORD --wait
  xcrun stapler staple .build/ZoomIt.app
  ```

  A notarized app opens with a normal double-click and keeps its Screen Recording permission across updates.

- **Quick internal testing (unsigned/ad-hoc):** use the development identity and `ZoomIt-Dev.dmg` procedure above. If another Mac downloads the unnotarized DMG, Gatekeeper may block it. After copying the app to `/Applications`, testers can clear the quarantine flag:

  ```sh
  xattr -dr com.apple.quarantine "/Applications/ZoomIt (Dev).app"
  open "/Applications/ZoomIt (Dev).app"
  ```

  Note that rebuilding an ad-hoc/unsigned app can reset its Screen Recording permission, so testers may need to re-grant it after an update.

### First run

1. Move `ZoomIt (Dev).app` (local testing) or `ZoomIt.app` (official release) to `/Applications` and open it. It runs as a menu-bar item (no Dock icon).
2. macOS prompts for **Screen Recording** the first time a capture feature is used; enable the matching **ZoomIt (Dev)** or **ZoomIt** row in System Settings ▸ Privacy & Security ▸ Screen Recording, then relaunch that same app.
3. **Microphone** and **Camera** are only requested when those recording options are enabled.
4. Use the menu-bar icon or the default hotkeys above to drive the app, and the Settings dialog to customize shortcuts and behavior.

### Clear stale Screen Recording permissions

macOS privacy permissions (TCC) are tied to both an app's bundle identifier and its code-signing requirement. If an ad-hoc build previously used the official `com.sysinternals.zoomitmac` identifier, System Settings can show **ZoomIt** as enabled while macOS rejects the currently installed Developer ID-signed app. Typical symptoms are:

- `Control+1` repeatedly opens Screen Recording settings even though ZoomIt is enabled.
- Closing the permission dialog and pressing `Control+1` again does nothing.
- A newly installed, correctly signed build still cannot capture the screen.

Reset only the Screen Recording record for the identity you are running. This removes the stale grant; it does not uninstall the app or clear ZoomIt settings.

For the **officially signed** `/Applications/ZoomIt.app`:

```sh
pkill -f "/Applications/ZoomIt.app/Contents/MacOS/ZoomIt" 2>/dev/null || true
tccutil reset ScreenCapture com.sysinternals.zoomitmac

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "/Applications/ZoomIt.app"
open "/Applications/ZoomIt.app"
```

For the local **development** `/Applications/ZoomIt (Dev).app`:

```sh
pkill -f "/Applications/ZoomIt (Dev).app/Contents/MacOS/ZoomIt" 2>/dev/null || true
tccutil reset ScreenCapture com.sysinternals.zoomitmac.dev

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "/Applications/ZoomIt (Dev).app"
open "/Applications/ZoomIt (Dev).app"
```

After relaunching:

1. Press `Control+1` once to request Screen Recording access.
2. Enable the matching **ZoomIt** or **ZoomIt (Dev)** row in System Settings.
3. Use macOS's **Quit & Reopen** button, or quit and reopen that same app manually.
4. Press `Control+1` again.

Static zoom requires **Screen Recording** only. Microphone and Camera permissions are unrelated unless their optional recording features are enabled. If the problem immediately returns after the reset, verify that the installed app has the expected identity:

```sh
codesign -dv --verbose=2 "/Applications/ZoomIt.app" 2>&1 \
  | grep -E "Identifier=|Authority=Developer ID Application|TeamIdentifier="
```

The official app should report identifier `com.sysinternals.zoomitmac` and a Developer ID authority. Never distribute or install an ad-hoc-signed app under that official identifier; local builds must remain `ZoomIt (Dev).app` with identifier `com.sysinternals.zoomitmac.dev`.
