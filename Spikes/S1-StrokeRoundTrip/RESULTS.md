# S1 — PencilKit stroke round trip

**Question:** can a `PKStroke` be turned into a plain `Codable` Swift struct, written as
JSON, read back, and rebuilt as a `PKStroke` with nothing lost — for every PencilKit pen
style?

**Answer: no — not bit-exactly, for any of the eight styles.** The loss is small, is
confined to four fields that PencilKit itself stores in a compressed form, and the
rendered output is pixel-identical. Details below and in the verdict.

- Toolchain: Xcode 27.2, Swift 6.4.2, macOS 27.2 SDK, arm64, macOS 27.2 host.
- Interface read from
  `MacOSX27.2.sdk/.../PencilKit.framework/Modules/PencilKit.swiftmodule/arm64e-apple-macos.swiftinterface`
  and the framework headers (`PKStroke.h`, `PKStrokePath.h`, `PKStrokePoint.h`,
  `PKInk.h`, `PKInkType.h`, `PKDrawing.h`, `PKStrokeRenderState.h`, `PKContentVersion.h`).
- Package: `Sources/StrokeRoundTrip` (library) + `Tests/StrokeRoundTripTests`
  (Swift Testing, `import Testing`).
- Run: `cd Spikes/S1-StrokeRoundTrip && swift test` (see *Environment note* for this machine).

## What was built

- `SpikeStroke` (`Sources/StrokeRoundTrip/SpikeStroke.swift`) — plain Foundation-only record:
  stroke UUID, ink type + colour (native components + colour-space name, optional ICC
  profile, catalog/colour names, resolved sRGB), all 10 `PKStrokePoint` fields per control
  point, path UUID/creation date, 6 transform components, mask as path elements with
  winding rule, random seed, render group UUID, render state, `requiredContentVersion`.
  Encoded with `JSONEncoder`; no PencilKit type appears in the record.
- `toRecord(_:)` / `toStroke(_:)` (`Conversion.swift`), including `NSBezierPath`
  element round trip (move/line/cubic/quadratic/close) and `NSColor` colour-space
  handling (named CoreGraphics spaces, ICC data for unnamed spaces, catalog colours).
- `StrokeFactory` (`StrokeFactory.swift`) — deterministic SplitMix64 PRNG. Per style:
  5 strokes with 2, 17, 64, 133 and 200 control points; varying force/azimuth/altitude/
  size/opacity/time offset/secondaryScale/threshold/lateralJitter; sRGB, Display P3 and
  translucent colours (alpha 0.35 and 0.70); translation / rotation+scale / skew /
  sub-point transforms; a mask on 4 of 5 strokes (rectangle, 4-cubic circle, two-subpath
  path, quadratic path); distinct seeds; distinct stroke and path UUIDs. 40 strokes total.
- Checks A–F, one parameterised test per style so each style fails independently, plus
  diagnostics for JSON exactness, point-quantisation, second round trip, masks, erased
  strokes, colour spaces and content versions.

## Results

Columns are the checks in the brief. "fail" is honest: the check's own assertion failed.
`fields` counts stored state per stroke (54 numeric + 10 string); 5 strokes audited per style.

| Style (raw `inkType`) | A. Field equality after JSON round trip | B. Record stability | C. Rendering at scale 2 | D. `PKDrawing.dataRepresentation()` | E. Identity | F. `requiredContentVersion` |
|---|---|---|---|---|---|---|
| `com.apple.ink.pen` | **fail** — 156/320 fields differ; not bit-exact; max Δ **0.01** at `mask[3].point[0].x`; 156 fields also exceed 1e-6 (azimuth up to 9.59e-5, altitude up to 2.40e-5) | **fail** — `toRecord(rebuilt) != toRecord(original)` at `path.controlPoints[0]` | **pass** — 1004×716; **0** of 718,864 pixels differ; max channel Δ 0; 23,393 opaque px in both | **fail** — bytes differ; 13,751 B vs 13,751 B | **pass** — 5 strokes, stroke ids and path ids preserved, 5 distinct ids in the rebuilt `PKDrawing` | **pass** — stroke v1, ink v1; rebuilt v1 |
| `com.apple.ink.pencil` | **fail** — 180/320 differ; max Δ **0.01** at `mask[3].point[0].x`; 180 exceed 1e-6 | **fail** — at `path.controlPoints[0]` | **pass** — 1002×716; 0 differing pixels; max Δ 0; 40,656 opaque px | **fail** — bytes differ; 14,598 B vs 14,598 B | **pass** — 5 preserved, 5 distinct | **pass** — stroke v1, ink v1 |
| `com.apple.ink.marker` | **fail** — 169/320 differ; max Δ **0.0284** at `point[55].size.height`; 169 exceed 1e-6 | **fail** — at `path.controlPoints[0]` | **pass** — 1016×716; 0 differing pixels; max Δ 0; 147,106 opaque px | **fail** — bytes differ; 13,776 B vs 13,776 B | **pass** — 5 preserved, 5 distinct | **pass** — stroke v1, ink v1 |
| `com.apple.ink.monoline` | **fail** — 167/320 differ; max Δ **0.01** at `mask[3].point[0].x`; 167 exceed 1e-6 | **fail** — at `path.controlPoints[0]` | **pass** — 998×716; 0 differing pixels; max Δ 0; 21,537 opaque px | **fail** — bytes differ; 13,826 B vs 13,826 B | **pass** — 5 preserved, 5 distinct | **pass** — stroke v2, ink v2 |
| `com.apple.ink.fountainpen` | **fail** — 163/320 differ; max Δ **0.01** at `mask[3].point[0].x`; 163 exceed 1e-6 | **fail** — at `path.controlPoints[0]` | **pass** — 1004×716; 0 differing pixels; max Δ 0; 29,717 opaque px | **fail** — bytes differ; 14,119 B vs 14,119 B | **pass** — 5 preserved, 5 distinct | **pass** — stroke v3, ink v2 (see F note), drawing v3 |
| `com.apple.ink.watercolor` | **fail** — 173/320 differ; max Δ **0.0566** at `point[43].size.height`; 173 exceed 1e-6 | **fail** — at `path.controlPoints[0]` | **pass** — 1078×716; 0 differing pixels; max Δ 0; 271,513 opaque px | **fail** — bytes differ; 13,958 B vs 14,084 B (**+126 B**) | **pass** — 5 preserved, 5 distinct | **pass** — stroke v2, ink v2 |
| `com.apple.ink.crayon` | **fail** — 182/320 differ; max Δ **0.054** at `point[28].size.height`; 182 exceed 1e-6 | **fail** — at `path.controlPoints[0]` | **pass** — 1092×716; 0 differing pixels; max Δ 0; 296,344 opaque px | **fail** — bytes differ; 13,776 B vs 13,776 B | **pass** — 5 preserved, 5 distinct | **pass** — stroke v2, ink v2 |
| `com.apple.ink.reedcalligraphy` | **fail** — 156/320 differ; max Δ **0.0524** at `point[19].size.height`; 156 exceed 1e-6 | **fail** — at `path.controlPoints[0]` | **pass** — 1108×716; 0 differing pixels; max Δ 0; 218,915 opaque px | **fail** — bytes differ; 13,957 B vs 13,957 B | **pass** — 5 preserved, 5 distinct | **pass** — stroke v4, ink v4 |

C never reported "could not run": `PKDrawing.image(from:scale:)` worked in a plain
command-line test on native macOS. Every image contained 21k–296k non-transparent pixels,
so "identical" is not two blank images. C passes for all eight styles.

### What exactly differs (diagnostics, 3,328 points total, 40 strokes)

| Field | Points affected | Largest difference | Notes |
|---|---|---|---|
| `PKStrokePoint.azimuth` | 684 / 3,328 | **9.59e-5 rad** | one storage step (≈2.4e-5 rad); `f(f(x)) != f(x)` |
| `PKStrokePoint.altitude` | 612 / 3,328 | **2.40e-5 rad** | one storage step |
| `PKStrokePoint.size.height` | 18 / 3,328 | **0.0566 pt** | size is stored in a coarser format than width (a half-float-like step) |
| mask vertex coordinates | a few vertices per masked stroke | **0.01 pt** | mask coordinates are stored on a 0.01 pt grid |
| mask element order | PencilKit-erased masks | — | closed rings come back rotated, duplicated start vertex moves; shape unchanged (max vertex Δ 0.01 pt) |

Everything else is exactly equal: stroke UUID, ink type, ink colour components, transform,
path UUID and creation date, control point count, `location`, `timeOffset`, `size.width`,
`opacity`, `force`, `secondaryScale`, `threshold`, `lateralJitter`, `randomSeed`,
`renderGroupID`, `requiredContentVersion`.

`RESULT|JSON|all|pass|recordChangedByJSON=0`: the JSON layer is exact — encode → decode
returns a bit-identical record for all 40 strokes. The drift is introduced only when
PencilKit re-creates `PKStrokePoint`s (and re-stores a mask), not by the format.

The drift is not random: values move by whole storage steps. 13 of 40 strokes reach a
fixed point after 2 round trips, 27 after 3 (`RESULT|FIXPOINT|...|2:13,3:27`); no point
oscillated. So repeated save/load does not drift cumulatively without bound; it settles.

### Supplementary checks

- Mask round trip (hand-built masks, all 8 styles): **pass** for the first masked stroke
  of every style — its mask fields are exactly equal (`RESULT|MASK`). Check A shows the
  later, more complex synthetic masks still move a few vertices by 0.01 pt.
- PencilKit mask normalisation: a 7-element input path (move, 4 cubic segments, close,
  trailing move) is stored as a **66-element polyline** (63 line segments), with the same
  shape and bounds; our record then reproduces those 66 elements and their kinds exactly
  (`RESULT|MASKSTRUCT`).
- PencilKit-erased strokes: **pass** — the eraser leaves 2 strokes, each with a mask
  (39 and 35 elements). Round trip preserves element count and kinds, the closed-ring
  shape (max vertex Δ 0.01 pt) and renders pixel-identically; the ring's start vertex
  rotates on re-ingestion, so field-by-field mask comparison fails.
- Render state: **pass** — a constructed `PKStroke.RenderState(grainOffset:)` survives
  (`grainOffset` equal, `renderState` equal). But its `Codable` encoding is a binary
  `NSKeyedArchiver` plist of `PKStrokeRenderState` (271 bytes, containing opaque bytes
  such as `0d0000484115000050c0`), base64-encoded inside our JSON. The record therefore
  carries an opaque blob for this one field.
- Colour spaces: sRGB, Display P3, grey, extended-range sRGB and catalog colours all pass
  the round trip (record stable, rendering identical). PencilKit itself normalises the
  ink colour to sRGB when the stroke is created: a Display P3 or catalog input reads back
  as `kCGColorSpaceSRGB`. A pattern colour cannot be represented as components; rebuild
  throws (documented failure, not silently wrong).
- `F` note: for `fountainPen`, `PKInk.requiredContentVersion` is **2** while the stroke's
  (and drawing's) `requiredContentVersion` is **3**. Both are preserved by the round trip;
  storing only the ink's version would understate the requirement.

## Written answers

### Are there properties that can be read but not set, or set but not read?

Read-only in the public API (no setter; some can only be supplied through an initialiser):

- `PKStroke.requiredContentVersion`, `renderBounds`, `maskedPathRanges` — computed/derived,
  no setters.
- `PKStrokePath.count`, `creationDate`, `id`, `bezierRepresentation` — `id` and
  `creationDate` are settable only via `PKStrokePath(controlPoints:creationDate:id:)`;
  `bezierRepresentation` is derived.
- All ten `PKStrokePoint` properties — settable only through the four versioned
  initialisers (7, 8, 9 or 10 parameters depending on macOS version).
- `PKInk.requiredContentVersion`, `PKDrawing.bounds`, `PKDrawing.requiredContentVersion`.
- `PKConvertedBezierPoint` fields are read-only by construction.

Set but not read back as set (the important ones for storage — these are *silent*
normalisations, not API asymmetry):

- **`PKStroke.mask`**: you set an `NSBezierPath`, but PencilKit stores a normalised
  representation. Cubic and quadratic segments are flattened to line segments (a
  4-cubic circle becomes a 66-vertex polyline), element order is reversed/rotated, an
  extra trailing `moveTo` is common, and an empty path becomes `nil`. You never read
  back the curve you set.
- **`PKInk.color`**: a Display P3, grey or catalog colour reads back as sRGB.
- **Every `PKStrokePoint` numeric field**: the header states values are stored compressed
  and "the value you read back may not exactly equal the value you set". This is the
  source of all A/B failures above.
- **`PKStroke.renderState`**: only `grainOffset` is exposed; the header says other state
  is opaque and only `NSSecureCoding` persists it. Its Swift `Codable` form is that keyed
  archive, not a documented value.
- **`PKStroke.randomSeed` / `id` / `renderGroupID`**: fully symmetric (get and Swift set).

No property was found that can be set but cannot be read *at all*.

### Does any pen style behave differently?

Not in the round trip: all eight fail A, B and D for the same reason and pass C, E and F.
Differences found:

- **Magnitude of the size drift tracks ink width.** Marker, watercolour, crayon and reed
  have larger default widths, so their `size.height` steps are larger (0.028–0.057 pt);
  pen/pencil/monoline/fountain pen are limited to the 0.01 pt mask drift and the
  azimuth/altitude steps.
- **Content version:** pen/pencil/marker = 1, monoline/watercolor/crayon = 2,
  fountainPen = 3 (ink reports 2), reed = 4.
- **Watercolour is the only style whose `PKDrawing.dataRepresentation()` changed size**
  (+126 bytes) rather than only its bytes; the other seven produced equal-length data.
- **Monoline has a rendering floor:** point sizes below about 2 pt render *nothing* on
  this OS (a 0.5 pt default-width monoline stroke is invisible). The generator uses a
  3 pt minimum base width so C is meaningful; this is an Apple rendering quirk, unrelated
  to the record format.
- Everything else (mask handling, ids, colours, transforms) behaved the same for all styles.

### Does a partly erased stroke (with a mask) survive?

Yes, geometrically and visually. `PKDrawing.erasingPath(_:)` split a 64-point marker
stroke into two strokes, each carrying a mask (39 and 35 elements, 74 vertices total).
After JSON round trip: same element counts and kinds, same closed-ring shape (largest
vertex delta 0.01 pt), and rendered bitmaps identical (48,315 pixels compared in the
aggregate image, 0 differing pixels, max channel delta 0). It does **not** survive field-for-field: the
mask ring comes back rotated (a different start vertex and a duplicated vertex at the
other end), and a few vertices move by 0.01 pt. Those are PencilKit mask-storage
normalisations, not losses in the record.

Caveat found while probing: a mask containing only quadratic curves produced a mask whose
`elementCount` read traps (SIGABRT) in this SDK, and an empty mask cannot be read
(`NSBezierPath().bounds` traps). The suite avoids both; treat quadratic-only masks as
unsupported.

## Verdict

**Not lossless for any of the eight pen styles — but the loss is tiny and well bounded.**
A `PKStroke` can be represented as a plain Codable struct and rebuilt so that ids, ink
type, colour, transform, path date/id, every point location/time offset, opacity, force,
secondary scale, threshold, lateral jitter, random seed, render group and content version
are exactly identical; JSON itself round-trips bit-exactly. What does not come back
exactly is the content of PencilKit's compressed storage: azimuth (≤9.6e-5 rad), altitude
(≤2.4e-5 rad), point `size.height` (≤0.057 pt) and mask vertices (0.01 pt), plus mask
vertex ordering. Rendering is pixel-identical for all eight styles at scale 2, and Apple's
own serialisation has identical length for seven styles (watercolour +126 B), so the
practical difference is invisible. For a notes app this format is good enough for display
and editing, but it is not an archival bit-for-bit substitute for PencilKit's own data:
if the app must guarantee exact reproduction (e.g. hashing, legal archive, or future
feature parity), keep `PKDrawing.dataRepresentation()` alongside it. Two extra caveats:
`renderState` can only be carried as an opaque keyed archive, and the mask you pass in is
never the mask you read back (PencilKit flattens curves), so a "plain documented" format
must document that masks are stored as polylines.

## Environment note (reproducing the run on this machine)

On this macOS 27.2 host, PencilKit's `PKReplicaManager` traps inside CoreFoundation
(`CFEqual() called with NULL first argument`) when `cfprefsd` still holds replica state
and the test process has no bundle identifier — as is the case for
`swiftpm-testing-helper`. The first `swift test` after restarting `cfprefsd` runs
normally; the next one dies with signal 5 before any assertion (the preference file on
disk is not the problem — only the daemon's cache is). `./run-tests.sh` runs
`swift test "$@"` after `killall cfprefsd`; `killall cfprefsd && swift test` is the manual
equivalent. This is an OS/harness issue, not package code; no test was skipped or
weakened because of it.

## Files

- `Sources/StrokeRoundTrip/SpikeStroke.swift` — record types and JSON helpers.
- `Sources/StrokeRoundTrip/Conversion.swift` — `toRecord` / `toStroke`, colour and mask conversion.
- `Sources/StrokeRoundTrip/StrokeFactory.swift` — seeded generator.
- `Sources/StrokeRoundTrip/Comparison.swift` — field flattening and exact/tolerance comparison.
- `Sources/StrokeRoundTrip/Rendering.swift` — `PKDrawing.image(from:scale:)` → RGBA bitmap and diff.
- `Tests/StrokeRoundTripTests/RoundTripTests.swift` — checks A–F.
- `Tests/StrokeRoundTripTests/EdgeCaseTests.swift` — generator coverage, masks, erased strokes, render state, colour spaces.
- `Tests/StrokeRoundTripTests/DiagnosticsTests.swift` — JSON exactness, point replay, second round trip, fixpoint.
- `test-output.txt` — raw output of the final run (all `RESULT|` lines).
