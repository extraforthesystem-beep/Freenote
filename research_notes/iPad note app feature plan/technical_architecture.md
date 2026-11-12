# Technical Architecture for an iPad-First Handwritten Note App (SwiftUI, macOS companion)

Scope note: this covers local technical architecture only. Cloud sync through Google Drive is out of scope except where a local format choice constrains it. Date of research: November 2026. Current shipping OS generation is iOS/iPadOS 27 and macOS 27 (announced WWDC26, June 2026); the previous generation was iOS/iPadOS 26 and macOS 26 "Tahoe" (WWDC25).

A naming warning that matters for every version claim below: Apple's 2025 releases were numbered **26**, not 19, and the 2026 releases are **27**. Several sources say "the 2027 releases" when they mean the OS versions shipped in late 2026 — the WWDC26 SwiftUI session uses that phrasing for iOS 27 APIs.

---

## Ink engine: what PencilKit provides today, and its limits

### Takeaway
PencilKit in iPadOS 27 is dramatically more capable than the 2023-era version: it now has on-device handwriting recognition, stable stroke identity, programmatic stroke slicing and Bézier path conversion. But it still does not expose the brush engine, pressure curves, layers or custom erasers, and that gap — not stroke rendering quality — is the reason serious note apps still write their own engine.

### Cited Findings
- PencilKit is described by Apple as "the core framework for freehand drawing support on Apple's platforms," giving "a low-latency canvas with expressive inks, full Apple Pencil support, and access to the underlying data model" — [Apple, WWDC26 session 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- PencilKit implements rendering in Metal, with optimisations that keep stroke animation smooth — [Apple, WWDC26 session 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- Stroke paths are stored as **cubic uniform B-splines**, not Bézier curves; this is why path interchange historically required conversion work — [Apple, WWDC26 session 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- **iPadOS 26 introduced PaperKit**, which "builds on top of PencilKit to power Apple's drawing experience system-wide"; all new PencilKit APIs also work in PaperKit — [Apple, WWDC26 session 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- PaperKit is Apple's own markup stack, used in Notes, Screenshots, QuickLook and Journal, and it "provides a canvas that you can both draw on and add a variety of markup elements to, including shapes, images, textboxes, and much more" — [Apple, WWDC25 session 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- PaperKit exposes `PaperMarkupViewController` (canvas), `PaperMarkup` (data model container that "handles saving and loading both the PaperKit markup and PencilKit drawing data, and … rendering"), and `MarkupEditViewController` for insertion — [Apple, WWDC25 session 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- PaperKit's feature set is subtractable: `FeatureSet.latest` can be edited with `remove(.text)` / `insert(.stickers)`, and a new calligraphy "Reed" tool shipped in PencilKit — [Apple, WWDC25 session 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- PaperKit supports a custom page background by assigning any `UIView` to `contentView` — directly usable for paper templates — [Apple, WWDC25 session 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- **Documented PencilKit customisation ceiling**: you can control tool UI, tool selection, pen/pencil/marker with any colour or width, bitmap and vector erasers, undo/redo and persistence. You **cannot** control custom brush textures or patterns, pressure response curves ("PencilKit handles this internally"), special-effect erasers, real-time stroke filters, or the drawing context during strokes — [Wesley Matlock, "Customizing PencilKit" (Sep 2025)](https://medium.com/@wesleymatlock/customizing-pencilkit-going-past-apples-tool-picker-b82eca7bfbe2).
- There is no highlighter ink type in PencilKit; the common workaround is a marker tool with reduced alpha and doubled width — [Wesley Matlock, "Customizing PencilKit"](https://medium.com/@wesleymatlock/customizing-pencilkit-going-past-apples-tool-picker-b82eca7bfbe2).
- Known gesture trap: attaching `MagnificationGesture` or `DragGesture` to the canvas view causes the screen to go black during drawing because they conflict with PencilKit's internal touch handling; the workaround is gestures on a container behind the canvas, or explicit zoom buttons — [Wesley Matlock, "Customizing PencilKit"](https://medium.com/@wesleymatlock/customizing-pencilkit-going-past-apples-tool-picker-b82eca7bfbe2).
- **New in iPadOS 27**: `PKStroke` and `PKStrokePath` conform to `Identifiable` with "a stable UUID, so you can track a stroke across transforms, edits, and undo operations" — [Apple, WWDC26 session 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- **New in iPadOS 27**: selection state on `PKCanvasView` is programmatically controllable, with a `canvasViewSelectionDidChange` delegate callback — [Apple, WWDC26 session 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- **New in iPadOS 27**: `PKStrokePath` converts to and from Bézier paths; round-tripping "will result in the same control point locations, allowing for storing PencilKit strokes in a Bézier-based format, and reconstructing without any loss of fidelity" — [Apple, WWDC26 session 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- **New in iPadOS 27**: programmatic erasing accepts a `PKStrokePath` as the eraser and slices one stroke into multiple independent strokes with their own masks; Apple warns "slicing can be expensive on complex drawings" and suggests erasing on a background thread — [Apple, WWDC26 session 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- **New in iPadOS 27**: substroke extraction via parametric range subscripting on `PKStroke`/`PKStrokePath`, preserving texture particle consistency — [Apple, WWDC26 session 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- Wet-ink compositing is controlled by an `equal renderGroupID`; strokes drawn in quick succession composite as if still wet, and this became controllable in iOS 27 — [Apple, WWDC26 session 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- PencilKit has had stroke *reading* since iOS 14, when "PencilKit … provides access to strokes" — [WWDCNotes, WWDC20 session 10107](https://wwdcnotes.com/documentation/wwdc20-10107-whats-new-in-pencilkit/).
- PencilKit's own selection UX dates to iOS 14: double-tap to select word, double-tap again for line, grab handles, non-contiguous selection by brushing over strokes, and insert-space between lines — [WWDCNotes, WWDC20 session 10107](https://wwdcnotes.com/documentation/wwdc20-10107-whats-new-in-pencilkit/).
- Drawing input policy is `PKCanvasView.drawingPolicy` with `anyInput`, `pencilOnly`, and `default` (follows the system pencil-only preference when the tool picker is visible) — [WWDCNotes, WWDC20 session 10107](https://wwdcnotes.com/documentation/wwdc20-10107-whats-new-in-pencilkit/).
- Shape recognition exists as a user-facing behaviour: pausing at the end of a stroke triggers it, and with Pencil Pro you get haptic confirmation — [Apple, WWDC24 session 10214](https://developer.apple.com/videos/play/wwdc2024/10214/).
- Apple's own docs describe PencilKit as "expressive, low-latency drawing" with availability from iOS 13 — [Apple, Drawing with PencilKit](https://developer.apple.com/documentation/pencilkit/drawing-with-pencilkit).

### Inferences
- For a GoodNotes-style app, PencilKit's ceiling is not visual quality but **control of the mark-making model**. A notebook app needs per-tool pressure curves, texture, and per-layer compositing to feel distinctive; PencilKit gives you three inks and no parameter access. That is a product-differentiation limit, not a bug.
- The iOS 27 additions (stable IDs, slicing, Bézier conversion, selection delegate) materially reduce the cost of *hybrid* architectures: you could render with PencilKit and still build a real object model on top, because strokes now have durable identity that survives undo.
- The "expensive slicing on complex drawings" warning is the single best proxy Apple gives for where PencilKit performance degrades: stroke-count-driven operations, not canvas size per se.
- Because `PKStrokePath` now round-trips to Bézier losslessly, the classic reason to avoid PencilKit for storage ("we can't get our curves back out") has largely evaporated in iPadOS 27.

### Gaps
- No source found that quantifies PencilKit's canvas-size or stroke-count limits (e.g. "N strokes before frame drops"). Apple's only performance statement is qualitative ("slicing can be expensive"). Treat any specific number as unverified.
- No source confirmed whether the tool picker is supported on Mac Catalyst in current OS versions; the WWDC20 material only asserts "Catalyst support" for the framework generally — [WWDCNotes, WWDC20 10107](https://wwdcnotes.com/documentation/wwdc20-10107-whats-new-in-pencilkit/). **Unconfirmed.**
- PencilKit layering: no source found indicating PencilKit has any layer model. Assume it does not, but marked **unconfirmed** rather than asserted.
- No first-party statement found on PencilKit's tiling strategy or its behaviour on very large (poster-sized) canvases. **Unconfirmed.**

---

## When to build a custom Metal / Core Graphics engine, and what that involves

### Takeaway
A custom engine is justified by control (brushes, layers, stroke-level editing, infinite canvas) and by frame-rate guarantees under heavy load — not by latency, which PencilKit already wins. The realistic cost is a permanent second product: rasteriser, smoothing, tiling, and a serialisation format you now own.

### Cited Findings
- The explicit decision rule from a practitioner: "If you need those advanced features, you'll have to leave PencilKit behind and use Core Graphics or Metal" — [Wesley Matlock](https://medium.com/@wesleymatlock/customizing-pencilkit-going-past-apples-tool-picker-b82eca7bfbe2).
- Goodnotes states it needs "more than 60 Frames Per Second (FPS) for real-time ink rendering, which makes performance critical," and that its rendering engine is built directly on low-level graphics APIs (Metal on iOS, WebGL on web) with only thin platform abstraction layers — [Swift.org, "Bringing Goodnotes to the web with Swift and WebAssembly" (Jun 2026)](https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/).
- Goodnotes reports its iOS app is roughly 4.3M lines total, of which 1.47M (34%) is the shared cross-platform Swift core; the web build is 2.2M lines, 66% shared — [Swift.org](https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/). This is a direct signal of how large a mature custom ink stack becomes.
- Goodnotes' shared core is explicitly split into three parts: a Content Rendering Engine (Metal/WebGL), a Business Logic Layer (document modelling, handwriting recognition, indexing), and shared View Models for tool interaction and gestures — [Swift.org](https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/).
- Rendering parity across platforms is a stated reason for the custom engine: "the same curves, the same pressure sensitivity, the same ink flow" on iPad and web, because it is literally the same Swift code — [Swift.org](https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/).
- A developer porting handwriting to MetalKit without PencilKit describes doing so under constraint rather than preference, i.e. the custom path is usually forced by a requirement, not chosen for quality — [Stack Overflow question on Metal handwriting rendering](https://stackoverflow.com/questions/78344741/is-this-right-way-to-implement-handwriting-rendering-in-ios-without-pencilkit).
- PencilKit-specific gesture and rendering pitfalls (black screen on gesture conflict, `isOpaque = true` needed to prevent rendering issues) show that even the "easy" path has sharp edges that consume debugging time — [Wesley Matlock](https://medium.com/@wesleymatlock/customizing-pencilkit-going-past-apples-tool-picker-b82eca7bfbe2).
- Rnote demonstrates the feature surface a custom vector engine must eventually cover: pressure-sensitive configurable stroke styles, shape tools, move/rotate/resize selection, multiple document expansion layouts (fixed pages, continuous vertical, infinite), and SVG/PDF/Xopp export — [Rnote README](https://github.com/flxzt/rnote).

### Inferences
- Predicted/coalesced touch handling, tile-based rendering and latency budgets are standard technique but I found **no Apple or vendor document in this research that states a numeric latency target**. Apple's own phrasing is "low-latency" without a figure. Any "8 ms" or "9 ms" claim encountered elsewhere should be treated as unverified for this purpose.
- The honest build/buy line for a solo developer: custom engine is defensible only if the brush model *is* the product. For a GoodNotes competitor whose differentiator is organisation, PDF workflow and search, a PencilKit-based hybrid is the lower-risk path in 2026 — and iOS 27's new stroke APIs make that hybrid much more viable than it was in 2023.
- The strongest argument *for* a custom engine at small-team scale is not brushes but **unified serialisation**: one engine gives you one stroke format, deterministic rendering for thumbnails and export, and no duality between "PencilKit drawing" and "our model."

### Gaps
- No public engineering write-up found that gives a concrete person-month or LOC estimate for building an ink engine from scratch. Effort figures in this area are essentially unpublished. **Unconfirmed.**
- No source found comparing measured input-to-photon latency of PencilKit versus a hand-rolled Metal pipeline on the same device. **Unconfirmed.**

---

## Which engine GoodNotes, Notability and peers actually use

### Takeaway
Goodnotes is confirmed custom (Metal) with CRDT-based conflict resolution. Notability's engine is **not** publicly documented; its visible iOS 27 features (ink stabilisation, MyScript-derived recognition) suggest a hybrid, but I could not confirm this from a primary engineering source.

### Cited Findings
- Goodnotes, confirmed and primary: "We use a custom rendering engine built on low-level graphics APIs: Metal on iOS and WebGL on the web. The rendering logic is almost entirely shared, with only platform abstraction layers implemented separately for each platform." — [Swift.org, authored by a Goodnotes engineer](https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/).
- Goodnotes, confirmed: its accumulated Swift code implements "digital ink rendering, document synchronization, conflict resolution using Conflict-Free Replicated Data Types (CRDTs), and content search and document indexing" — [Swift.org](https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/).
- Goodnotes, confirmed: handwriting recognition and document indexing live in shared Swift packages (i.e. in their own codebase, not stated to be a third-party SDK) — [Swift.org](https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/).
- Goodnotes took "two years of development and over two years in production" to bring the shared Swift core to WebAssembly — a data point on the cost of cross-platform ink infrastructure even for a well-resourced team — [Swift.org](https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/).
- Notability, confirmed: it uses **AVFoundation** for iOS audio encoding/upload and keeps only a few seconds of audio in memory — an implementation detail that implies a native pipeline rather than a web wrapper — [Notability blog, "How We Built Live Transcription"](https://blog.notability.com/post/how-we-built-live-transcription).
- Notability, confirmed: transcription runs on **server-side Whisper** (OpenAI's model), resampled to 16 kHz, with 3–15 second overlapping chunks and self-correcting output — [Notability blog](https://blog.notability.com/post/how-we-built-live-transcription).
- Notability, confirmed: it shipped "Ink Stabilization" smoothing in the iOS 27 cycle, alongside Siri integration — [Notability blog, related-post summary](https://blog.notability.com/post/hey-siri-find-my-notes-in-notability).
- Notability is a cross-platform product (iOS, iPadOS, macOS, Android, web), which constrains any single-platform engine choice — [Wikipedia, Notability](https://en.wikipedia.org/wiki/Notability_(application)).
- MyScript's own blog announces a partnership with Ginger Labs (Notability's maker) covering "MyScript handwriting and math recognition" for Notability — [MyScript blog](https://www.myscript.com/blog/myscript-and-gingerlabs/). *Caveat: I read only the search-result summary of this page, not the full article; treat the exact scope as reported-but-unverified.*

### Inferences
- Notability most plausibly uses a **hybrid**: its own stroke rendering/smoothing (hence "Ink Stabilization" as a shippable feature) plus licensed MyScript recognition. This is inference from the two facts above, not a stated architecture.
- Goodnotes' choice is the template for "engine as moat": they rebuilt the same engine for a second platform rather than reimplement rendering, which only makes sense if the renderer encodes years of tuning.
- Nobody in this set uses stock PencilKit for their core canvas. That is the strongest available signal that PencilKit alone will not produce a competitive GoodNotes clone.

### Gaps
- No Goodnotes or Notability engineering talk/blog found that names the ink engine's internal design (tiling, batching, smoothing algorithm). **Unconfirmed.**
- Whether Notability uses PencilKit anywhere in its canvas: **unconfirmed**, no source.
- No source for Concepts, Procreate, Linea or Muse engines was found in this pass. **Unconfirmed** for all of them; do not attribute architectures to them.

---

## Apple Pencil APIs: hover, double-tap, squeeze, barrel roll, haptics, Scribble

### Takeaway
The Pencil Pro interaction set (squeeze, barrel roll, hover pose, haptics) is well-supported and most of it is free if you adopt `PKToolPicker`, but each capability is a discrete gesture contract you must respect or explicitly suppress.

### Cited Findings
- **Squeeze** (Apple Pencil Pro, iPadOS 18+): opens the tool picker wherever the hand is; also provides access to an undo/redo slider "in all apps; even if you don't use PKToolPicker" — [Apple, WWDC24 10214](https://developer.apple.com/videos/play/wwdc2024/10214/).
- Squeeze is delivered via `UIPencilInteraction` with a delegate, or in SwiftUI via the `onPencilSqueeze` modifier; `UIPencilInteraction.preferredSqueezeAction` reflects the user's global preference, and "if the preference is set to run a shortcut, your app will not be sent the squeeze event" — [Apple, WWDC24 10214](https://developer.apple.com/videos/play/wwdc2024/10214/).
- Treat squeeze as "a single gesture that performs a discrete action" — Apple's explicit design guidance — [Apple, WWDC24 10214](https://developer.apple.com/videos/play/wwdc2024/10214/).
- **Hover pose**: double-tap and squeeze events now carry hover pose data — location above the screen, z-offset, azimuth, altitude and roll — [Apple, WWDC24 10214](https://developer.apple.com/videos/play/wwdc2024/10214/).
- **Barrel roll** (`rollAngle`): available on both `UITouch` and `UIHoverGestureRecognizer`; Apple advises adding roll and azimuth together to retain a fallback on devices without roll, and warns roll "is estimated when first sent and later updated over Bluetooth," so you must implement `touchesEstimatedPropertiesUpdated` for final accuracy — [Apple, WWDC24 10214](https://developer.apple.com/videos/play/wwdc2024/10214/).
- With `PKCanvasView`, barrel roll controls stroke angle for marker and fountain pen automatically, and all PencilKit tools show a tool-shaped hover shadow — [Apple, WWDC24 10214](https://developer.apple.com/videos/play/wwdc2024/10214/).
- **Haptics**: Pencil Pro haptics use existing feedback APIs; new feedback types for alignment snapping and path completion exist in both SwiftUI (`SensoryFeedback.alignment`, `.pathComplete`) and UIKit (`UICanvasFeedbackGenerator.alignmentOccurred(at:)`, `.pathCompleted(at:)`) — [Apple, WWDC24 10214](https://developer.apple.com/videos/play/wwdc2024/10214/).
- `UIFeedbackGenerator` and subclasses now take a view and a point at init so UIKit can pick the best feedback — [Apple, WWDC24 10214](https://developer.apple.com/videos/play/wwdc2024/10214/).
- **Scribble** is a tool-picker item as of iPadOS 18: adding it "unifies your Scribble and drawing features into a single place to switch pencil modes," and it hides itself according to the user's Apple Pencil settings — [Apple, WWDC24 10214](https://developer.apple.com/videos/play/wwdc2024/10214/).
- Apple's HIG page for Apple Pencil and Scribble is the normative reference for these behaviours — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/apple-pencil-and-scribble), linked from [WWDC24 10214](https://developer.apple.com/videos/play/wwdc2024/10214/).
- Goodnotes states Apple Pencil Pro's Squeeze and Barrel Roll are "already compatible with Goodnotes," i.e. shipping apps support them — [Goodnotes support](https://support.goodnotes.com/hc/en-us/articles/9757771783823-Utilize-the-new-features-of-Apple-Pencil-Pro).
- The tool picker can be kept "hidden yet fully functional — still responding to interactions like double-tap and squeeze gestures — and allows any app to support the mini tool picker experience" via `pencilKitResponderState.toolPickerVisibility` — [Apple, WWDC25 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- `activeToolPicker` on `UIResponder` controls tool-picker visibility for the current responder (new in iOS 26) — [Apple, WWDC25 285](https://developer.apple.com/videos/play/wwdc2025/285/).

### Inferences
- Adopting `PKToolPicker` even with a custom canvas is high-leverage: you inherit squeeze, hover, double-tap, Scribble toggling and preference handling for free, and the WWDC24 session explicitly supports "your own drawing canvas."
- `touchesEstimatedPropertiesUpdated` is easy to skip and is the difference between "roll feels noisy" and "roll feels like a real nib." Budget for it explicitly.
- Suppressing squeeze (by installing a `UIPencilInteraction` delegate) is a trap: you lose the system undo slider for all users, including those who never use your custom palette.

### Gaps
- No source found on Apple Pencil **double-tap** customisation specifics in current OS versions beyond the general `UIPencilInteraction` delegate path; double-tap's supported actions are documented but I did not read that page. **Unconfirmed** for exact current action set.
- Apple Pencil hover (M2 iPad Air/Pro and later) was not covered by a source I read in this pass; the roll/hover material above is Pencil Pro-specific. **Unconfirmed** for pre-Pencil-Pro hover capabilities.

---

## Hosting a low-latency canvas inside SwiftUI

### Takeaway
The consensus is unambiguous: SwiftUI hosts, UIKit draws. Wrap `PKCanvasView`, `PaperMarkupViewController` or a custom Metal view in `UIViewRepresentable` (or `NSViewRepresentable` on Mac), and never put per-stroke state in SwiftUI's update path.

### Cited Findings
- Apple's own guidance for PaperKit in SwiftUI: "The components are encapsulated within a UIViewControllerRepresentable, which is then incorporated directly into a SwiftUI view's body" — [Apple, WWDC25 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- PaperKit's markup controller "conforms to Observable, providing an alternative to using a delegate for managing state and updates" — a rare case of a canvas controller that is SwiftUI-observable natively — [Apple, WWDC25 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- The standard wrapping pattern in practice: a `UIViewRepresentable` holding a `@Binding var canvasView: PKCanvasView`, with a `Coordinator` implementing `PKCanvasViewDelegate` — [Wesley Matlock](https://medium.com/@wesleymatlock/customizing-pencilkit-going-past-apples-tool-picker-b82eca7bfbe2).
- "Don't add gesture recognizers directly to the canvas view — they'll conflict with PencilKit's internal drawing gestures and cause a black screen during drawing" — [Wesley Matlock](https://medium.com/@wesleymatlock/customizing-pencilkit-going-past-apples-tool-picker-b82eca7bfbe2).
- Injecting zoom/pan gestures via SwiftUI `.gesture()` on the canvas breaks drawing the same way; use a container behind the canvas or explicit zoom controls — [Wesley Matlock](https://medium.com/@wesleymatlock/customizing-pencilkit-going-past-apples-tool-picker-b82eca7bfbe2).
- Persisting via `PKDrawing.dataRepresentation()` / `PKDrawing(data:)` is the supported round-trip and is cheap enough to do per-drawing — [Wesley Matlock](https://medium.com/@wesleymatlock/customizing-pencilkit-going-past-apples-tool-picker-b82eca7bfbe2).
- SwiftUI's lazy-container behaviour has documented sharp edges relevant to long page lists: offscreen subview heights are "estimated from average of placed subviews," and you should "avoid conditional content in `ForEach` (filter at data level and unwrap optionals)" and "not change layout after they appear" — [Apple, WWDC26 session 321, as summarised by Use Your Loaf](https://useyourloaf.com/blog/wwdc-2026-viewing-guide/).
- `@State` became a macro in the 2027 releases, so `@Observable` classes stored in `@State` are initialised only once; this is back-ported to iOS 17/macOS 14 — [Apple, WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- SwiftUI's type-checker blowups on deeply nested views are addressed by the new unified `ContentBuilder` in Xcode 27, which "provides a substantial improvement in type checking performance" — [Apple, WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- Mixing frameworks is now explicitly blessed: SwiftUI for new views, wrapped in `NSHostingView`/`NSHostingMenu`, with `NSGestureRecognizer` mixed in — [Apple, WWDC26 session 272, via Use Your Loaf](https://useyourloaf.com/blog/wwdc-2026-viewing-guide/).

### Inferences
- The specific failure mode to design against is **SwiftUI re-entrancy during a stroke**: if `updateUIView` assigns `canvasView.drawing` on every state change, you will interrupt in-progress ink. The safe pattern is one-way flow — UIKit owns the live drawing, and only commits to SwiftUI state on stroke end / idle.
- For a hundreds-of-pages notebook, a `LazyVStack` of canvases is the wrong shape regardless of framework: you want a paged scroll container that keeps a small window of live canvases and substitutes cached page images outside it. Neither Apple nor the practitioner sources state this, but it follows directly from the lazy-container height-estimation behaviour above.
- Everything Apple shipped for PaperKit (Observable conformance, versioned data representation, thumbnail generation) is a template for how to wrap a canvas correctly: model object observable, controller delegate-driven, serialisation async.

### Gaps
- No source found quantifying SwiftUI-vs-UIKit overhead specifically for ink views (e.g. frame-time comparisons). **Unconfirmed.**
- No source found on `NSViewRepresentable`-hosted drawing performance on Apple-silicon Macs for a full ink canvas. **Unconfirmed.**

---

## iPad plus Mac: multiplatform SwiftUI vs native macOS vs Mac Catalyst

### Takeaway
Go native multiplatform with two thin UI layers over one shared core. Catalyst is the weakest option here because the drawing stack Apple actually recommends on Mac (PaperKit's AppKit controllers) is not a Catalyst-shaped API, and Mac drawing input is fundamentally pointer/trackpad, not Pencil.

### Cited Findings
- PaperKit shipped on macOS in Tahoe with a genuinely AppKit-shaped API: `PaperMarkupViewController` plus a `MarkupToolbarViewController` "complete with drawing tools and buttons for annotating," added "using the standard NSViewController embedding process" — [Apple, WWDC25 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- Apple's framing: "new to macOS Tahoe, PaperKit provides the same rich markup experience, so drawing and markup elements on any macOS app work great as well, just like the new Journal app" — [Apple, WWDC25 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- PDFKit is explicitly cross-platform with a platform-view abstraction: "PDFKitPlatformView is just a define of UIView or NSView, depending on the platform," and PDFKit "is available on iOS, macOS, and Mac Catalyst" — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- PencilKit's own docs list availability as iOS 13 / iPadOS 13 / **Mac Catalyst 13** — i.e. Catalyst is a first-class listed target for the framework — [Apple, Drawing with PencilKit](https://developer.apple.com/documentation/pencilkit/drawing-with-pencilkit).
- `PKCanvasView` is documented as "a UIView" that captures Pencil or finger input — [Apple, PKCanvasView documentation](https://developer.apple.com/documentation/pencilkit/pkcanvasview). This is the structural reason native AppKit cannot host it directly.
- The 2027 releases push resizability hard: "Apps need to be adaptive. iPhone apps mirrored to the Mac or running on the iPad can be resized," and layout decisions should use size classes rather than idiom or orientation — [Apple, WWDC26 session 278, via Use Your Loaf](https://useyourloaf.com/blog/wwdc-2026-viewing-guide/).
- iPad and Mac menu bars now default to a minimal icon set, with `labelStyle(.titleAndIcon)` to opt individual items back in — evidence that Apple treats iPad and Mac as one adaptive design surface — [Apple, WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- The `appearsActive` environment value lets a view dim when its window is inactive, explicitly for iPad/Mac multi-window correctness — [Apple, WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- Notability ships on iOS, iPadOS, macOS, Android and web — i.e. the category leader treats Mac as a companion surface within a multi-platform product, not a separate app — [Wikipedia, Notability](https://en.wikipedia.org/wiki/Notability_(application)).

### Inferences
- **Recommended shape**: one SwiftUI multiplatform app target with a shared Swift package for the document model, ink serialisation and PDF pipeline; `UIViewRepresentable` canvas on iPad, `NSViewRepresentable` (or PaperKit's AppKit controllers) on Mac; shared library browser in SwiftUI.
- Catalyst is the wrong default for *this* app: you would get PencilKit via Catalyst, but you would fight AppKit conventions (menus, toolbars, window behaviour) and you would not get the native `MarkupToolbarViewController` path Apple built for Mac. Catalyst is defensible only if the Mac app is explicitly a "same app, bigger window" companion with no Mac-specific UI ambition.
- Mac drawing input reality: no source I read describes Pencil-on-Mac; the supported Mac story is pointer/trackpad/Sidecar plus PaperKit's own toolbar UI. Design the Mac experience around **annotation and review** (highlight, comment, text, shapes) rather than freehand note-taking parity.
- The honest trade-off: a native Mac target roughly doubles UI surface work (menus, keyboard, window/scene management) but a Catalyst target roughly doubles *debugging* work because you inherit neither platform cleanly.

### Gaps
- Whether Sidecar Apple Pencil input reaches a Mac app as Pencil-quality touch, and whether Continuity Markup/Sidecar exposes pressure and tilt: **no source found; unconfirmed.** This matters a lot for the Mac feature set and should be tested empirically on hardware before committing.
- No source found on `PKCanvasView` working under AppKit directly (non-Catalyst). Assume it cannot, but marked **unconfirmed**.
- What comparable apps ship on Mac specifically (native vs Catalyst) for Goodnotes, Notability, Concepts: **unconfirmed** — no engineering source found naming their Mac build strategy.
- Short cross-platform note, as requested: Flutter/React Native/KMP/web-canvas are the wrong fit here because the ceiling is the ink pipeline, not the UI — Goodnotes' own account says a Flutter or KMP rewrite "would all require rewriting our entire rendering engine from scratch, a substantial undertaking that would have delayed our web launch by years" — [Swift.org](https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/). Saber (Flutter, GPL-3.0) is the useful counter-example of what a cross-platform ink app looks like when it *is* viable — [Saber README](https://github.com/saber-notes/saber).

---

## SwiftUI document-app support: DocumentGroup vs a custom library browser

### Takeaway
Do **not** model a GoodNotes-style app as one `FileDocument` per notebook opened through `DocumentGroup`. Use the document APIs for *file I/O primitives* (and for PDF/backup export), but own the library browser, because folders, thumbnails, and multi-document browsing are not document-scene concerns.

### Cited Findings
- SwiftUI's document support has rested on `FileDocument` and `ReferenceFileDocument` "for quite some time"; the 2027 releases add a broader `Document` API on that foundation — [Apple, WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- What `DocumentGroup` buys you out of the box: Command-N/Command-O, the edited indicator, smart autosave, and keyboard shortcuts — [Apple, WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- New **WritableDocument / ReadableDocument** protocols split writing and reading; `DocumentWriter.write(snapshot:to:previous:progress:)` is `nonisolated` and `async`, so "expensive disk writing operations" happen off the main actor — [Apple, WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- Critically for notebook formats: the writer receives the **previous snapshot** and can "write only the parts of the package that actually need updating, by comparing the current and the previous snapshots" — [Apple, WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- Writing progress is reportable through the Foundation `Subprogress` API — [Apple, WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- `DocumentCreationSource` + `NewDocumentButton(source:)` let one launch scene offer multiple creation paths (blank vs from-photo) and pass context into the document initialiser — [Apple, WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- Multiple formats are first-class: adding `.png` to `writableContentTypes` and branching inside `write` lets the same document export as a flattened image (via Core Graphics) — a direct analogue for "export page as PNG/PDF" — [Apple, WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- PaperKit's own guidance for forward compatibility: always verify a stored **content version**, and pre-render a thumbnail so a newer-format file can still be shown as a preview when the app can't open it — "it is exactly what apps like Notes are using" — [Apple, WWDC25 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- PaperKit provides an async `draw(in:frame:)` on the markup model specifically to render thumbnails into a `CGContext` — [Apple, WWDC25 285](https://developer.apple.com/videos/play/wwdc2025/285/).

### Inferences
- The architecture that fits a GoodNotes-style library is: **`WindowGroup` + custom library browser** (folders, grid/list of notebooks, thumbnails) that owns a per-notebook package on disk. `DocumentGroup` is then reserved for imports/exports (PDF, image, backup archive), where the system's open/save mental model genuinely matches.
- If you do want a document scene, `ReferenceFileDocument` (or the new `WritableDocument`/`ReadableDocument`) is the right choice over `FileDocument`, because a notebook is a large mutable object graph and value-semantic copying per edit is not viable.
- The `previous:` snapshot parameter is the single most useful new API for this app category: it makes incremental package writes a framework-supported pattern instead of hand-rolled diffing, which directly reduces the risk of janky autosave on a 300-page notebook.
- Storing a `contentVersion` plus a pre-rendered thumbnail per notebook is cheap insurance and is what Apple's own apps do; treat it as MVP, not polish.

### Gaps
- No source found describing how `DocumentGroup` behaves with very large packages or how it interacts with iCloud/third-party file providers beyond the generic autosave description. **Unconfirmed.**
- Whether the new `Document` protocols fully replace `FileDocument`/`ReferenceFileDocument` or coexist long-term: Apple says the new APIs "build on that foundation," and the summary mentions "first-class support for direct document URL access via the FileDocument and ReferenceFileDocument protocols" — so coexistence, but the migration path is **unconfirmed**.

---

## Document and page model: notebooks, pages, layers, templates, and staying fast at hundreds of pages

### Takeaway
Model it as a package containing an ordered page manifest plus per-page content, with strokes as the authoritative vector data and page images as a disposable cache. Discrete pages (not infinite canvas) is the right default for this product category — the infinite canvas is a different app.

### Cited Findings
- PaperKit's model is the closest thing to an Apple-blessed reference: `PaperMarkup` is a container that holds both markup elements and PencilKit drawing data and also renders, i.e. model and renderer are deliberately co-located — [Apple, WWDC25 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- PaperKit's element vocabulary is explicitly "shapes, images, textboxes, and much more," with stickers as a named feature-set item (`featureSet.insert(.stickers)`) — [Apple, WWDC25 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- Paper templates are handled as a background view, not as document content: assign any `UIView` (e.g. a `UIImageView` of a template) to `paperViewController.contentView`, and "all markup and drawing will be rendered on top of it" — [Apple, WWDC25 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- Adobe-style page-count reasoning from Apple's PDF session: "PDFs can contain hundreds, if not thousands, of pages, there's no way you want to create views for all of those pages when opening" — and the solution is a provider protocol that creates views on demand as pages scroll in — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- Rnote is the best open reference for multiple expansion layouts, offering "fixed pages, continuous vertical, infinite in every direction" as distinct document modes — [Rnote README](https://github.com/flxzt/rnote).
- Rnote stores pages as vector strokes and exports to SVG/PDF, with an explicit warning that "the file format is still unstable" — a cautionary data point about format churn in vector note apps — [Rnote README](https://github.com/flxzt/rnote).
- Saber demonstrates that unbounded nested folders are expected in this category ("Create folders inside folders inside folders … with no limit on the number of nested folders") while still surfacing recent notes on the home screen — [Saber README](https://github.com/saber-notes/saber).
- PencilKit's own serialisation is a single opaque `Data` blob per drawing, so per-page storage maps naturally onto per-page `PKDrawing` blobs — [Wesley Matlock](https://medium.com/@wesleymatlock/customizing-pencilkit-going-past-apples-tool-picker-b82eca7bfbe2).
- Goodnotes separates "Content Rendering Engine" from "Business Logic Layer (document modelling, handwriting recognition, and document indexing)" — evidence that model and renderer should be separable even in a custom engine — [Swift.org](https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/).

### Inferences
- Concrete recommended model: `Notebook` (metadata, page order, template ref, contentVersion, thumbnail) → `Page` (index, size, background template id, layer list) → `Layer` (strokes, images, text boxes, shapes). Keep template definitions *outside* the notebook (referenced by id + a bundled asset version), so changing a template doesn't rewrite every page.
- Keep a **dual representation per page**: vector strokes (truth) and a rendered page image (cache). The cache makes the library grid, page thumbnails, and PDF export fast, and can be regenerated at will. This is the standard rendering-cache pattern and is implied by Apple's on-demand overlay-view guidance.
- Discrete pages over infinite canvas: infinite canvas changes the scroll container, the thumbnail model, the PDF mapping and the search index simultaneously. It is a v2 architectural fork, not a setting.
- Cap the live canvas window (current page ± 1) and render everything else from cache. This follows directly from Apple's "don't create views for all pages" statement and from SwiftUI lazy-container height estimation behaviour.

### Gaps
- No source found giving concrete performance thresholds (e.g. strokes per page, pages per notebook, thumbnail cache sizes) for any shipping note app. **Unconfirmed.**
- No source found on how Goodnotes or Notability model layers internally, or whether they offer true layers at all. **Unconfirmed.**

---

## PDF: PDFKit capabilities, limits, and the hyperlinked-planner case

### Takeaway
PDFKit covers import, render, annotate, text selection/search and burn-in export — enough for annotation and for linked planners. The hard limits are performance with very many annotations and the absence of a real object model for ink, which pushes you toward storing your own ink alongside the PDF rather than only as annotations.

### Cited Findings
- PDFKit is "a full-featured framework that helps your app view, edit, and write PDF files," available on iOS, macOS and Mac Catalyst, usable in SwiftUI via `UIViewRepresentable` — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- Core object graph: `PDFView` (display/navigation/zoom/copy), `PDFDocument` (root), `PDFPage` (content + per-page resources), `PDFAnnotation` (the editable layer, since "the content of a PDFPage is not intended to be edited") — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- **Live Text** (iOS 16 / macOS Ventura): text selection and search inside scanned, bitmap-only PDFs; OCR is done **on demand per page** as you interact, in place, with an option to save text for the whole document — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- Form fields are auto-recognised and tabbable even without built-in text fields — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- **`PDFPageOverlayViewProvider`** (iOS 16 / macOS Ventura) is the sanctioned way to draw on PDF pages: implement `overlayViewForPage`, and PDFKit sizes, rotates and recycles your view; Apple's own demo overlays `PKCanvasView` "in about 30 lines" — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- PDFKit "is already designed to intelligently prepare content before people scroll pages into view," which is why the provider pattern exists rather than eager view creation — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- Round-trip persistence pattern: custom `PDFAnnotation` subclass overriding `draw(with:in:)`, with drawing data archived into a **private key/value pair** on the annotation, restored via `value:forAnnotationKey` — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- **Flattening** is supported: `PDFDocumentWriteOption.burnInAnnotationsOption = true` "burns in" annotations as page content so recipients can't move or delete them — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- Appearance streams record "nearly anything that you can draw using Quartz2D," and anything else "can be rendered into an image" — including Metal output — so custom engine ink can be serialised into a PDF appearance stream — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- Export size controls exist: `saveAllImagesAsJPEG`, `optimizeImagesForScreen` (downsamples to HiDPI screen resolution), and `createLinearizedPDF` for fast first-page display — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- Annotations can be created from images with page-size options (`MediaBox`, `Rotation`, `UpscaleIfSmaller`) and high-quality JPEG compression — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- Reported real-world limit: developers on Apple's forums describe "serious performance" problems with PDFKit when a document has "a large number of annotations" — [Apple Developer Forums, PDFKit tag](https://developer.apple.com/forums/tags/pdfkit?page=2).
- Annotation mutation is fragile in practice: forum and Stack Overflow reports of `removeAnnotation` succeeding in the data model without visual effect, and of annotations that can be edited but not moved — [Apple Developer Forums](https://developer.apple.com/forums/tags/pdfkit); [Stack Overflow](https://stackoverflow.com/questions/74733055/unable-to-move-annotation-with-pdfkit).
- A vendor-side summary of the gap: handling "the full PDF specification means dealing with various objects like pages, annotations, form fields" — i.e. PDFKit abstracts the common path but not the whole spec — [Joyfill, "Overcoming the PDF limitations in native Swift mobile apps"](https://dev.to/joyfill/overcoming-the-pdf-limitations-in-native-swift-mobile-apps-54ck).

### Inferences
- For **hyperlinked digital planners**, the critical question is whether PDFKit resolves internal `/Link` annotations and destination actions on tap inside `PDFView`. Apple's session does not state this either way, and I found no source confirming it. **This is the single highest-risk unverified item in this brief** — validate with a real planner PDF before designing around PDFKit.
- The annotation-performance reports argue against "one annotation per stroke." Store ink as **one annotation per page** (or per page-layer) carrying your own serialised stroke data, and render it in an overlay view. That matches Apple's own demo (one annotation holding the whole drawing) rather than a naive per-stroke annotation model.
- Because appearance streams accept Metal-rendered images and Quartz2D drawing, the PDF export path works for either engine choice — you are not locked into PencilKit by choosing PDFKit.
- Nutrient/PSPDFKit and PDFium: I did not verify licensing or pricing for either in this pass, so no claim is made. If planner link support or annotation performance fails in PDFKit, that is the moment to cost out a commercial SDK.

### Gaps
- **Nutrient (PSPDFKit) pricing/licensing: not researched, unconfirmed.** **PDFium licensing: unconfirmed.** No figures are asserted here.
- PDFKit internal-link/outline/hyperlink navigation behaviour: **unconfirmed.**
- Whether PDFKit exposes PDF outlines (`PDFOutline`) in a usable form for a planner sidebar: **unconfirmed** (class exists per the object-graph description, but I did not read its documentation).
- No source found on PDFKit memory behaviour with very large (100 MB+) PDFs. **Unconfirmed.**

---

## Handwriting recognition and search

### Takeaway
This problem largely solved itself in iPadOS 27: `PKStrokeRecognizer` gives on-device recognition, indexing and search across 29 languages, for free, with no SDK and no per-device licence. Third-party SDKs are now only justified for math, or for languages/behaviours Apple doesn't cover.

### Cited Findings
- Handwriting recognition arrived in PencilKit in **iOS/iPadOS/macOS/visionOS 27**, and is "the same powerful technology behind Apple apps like Freeform and Notes" — [Apple, WWDC26 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- `PKStrokeRecognizer` is "a Swift actor, so it's thread-safe by design," with all methods async because "recognition takes time" — [Apple, WWDC26 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- Three APIs: `recognizedText()` (single best result), `indexableContent` (one string for the whole drawing), and `search(_:)` returning results with `bounds` for highlighting — [Apple, WWDC26 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- Language coverage: **29 languages** as of iOS 27, enumerable via `supportedLanguages`; defaults to device languages, overridable with `preferredLanguages` — [Apple, WWDC26 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- Runs "entirely on device"; "the recognition model is offline and included with the operating system"; works "on all devices supported by iOS 27" — [Apple, WWDC26 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- Recognition can target a subset of strokes via `strokeIDs`, or a whole drawing — [Apple, WWDC26 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- **Search indexing guidance from Apple**: `indexableContent` concatenates all candidate interpretations so users find content regardless of ambiguity ("Is that a '1' or a lowercase 'L'?"); persist it alongside `recognizerVersion` and re-index when the version changes, because "recognition results can improve over time"; and throttle calls because "updating the results on every stroke may use more power than you need" — [Apple, WWDC26 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- `search()` pairs with `UIFindInteraction` via `UIFindInteractionDelegate`, giving the system find UI with result navigation and highlighting for free — [Apple, WWDC26 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- Accessibility payoff: recognition enables VoiceOver to speak handwriting and lets assistive features navigate to words — [Apple, WWDC26 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- **Simulator caveat**: "handwriting recognition in Simulator only supports languages that use Latin characters" — a real testing trap for non-Latin markets — [Apple, WWDC26 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- Recognition is usable **without** `PKCanvasView`: convert your own Bézier strokes to `PKStrokePath`, build a `PKDrawing`, and feed it to `PKStrokeRecognizer` — "This makes handwriting recognition compatible with any canvas, not just PKCanvasView" — [Apple, WWDC26 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- Google ML Kit Digital Ink Recognition: on-device, offline, "near real time," **300+ languages and 25+ writing systems**, gesture classification, emoji and basic shape recognition, with language packs downloaded dynamically to keep storage low — [Google ML Kit docs](https://developers.google.com/ml-kit/vision/digital-ink-recognition).
- ML Kit's input model is an `Ink` object of strokes with x/y/**t** (time) per touch point, returning ranked `RecognitionCandidate`s with confidence — note the `t` field, which also enables stroke-timing features — [Google ML Kit docs](https://developers.google.com/ml-kit/vision/digital-ink-recognition).
- ML Kit recognises 9 gesture classes including `circle`, `strike`, `scribble`, `caret`, `verticalbar`, `writing` — usable as a cheap shape/gesture recogniser — [Google ML Kit docs](https://developers.google.com/ml-kit/vision/digital-ink-recognition).
- ML Kit warns gesture and text classification genuinely collide ("the `verticalbar` gesture may look exactly like the digit `1` or letter `l`"), and suggests using position/context to disambiguate — [Google ML Kit docs](https://developers.google.com/ml-kit/vision/digital-ink-recognition).
- MyScript iink (on-device): **25 free licences** for development/testing only; production is "Contact us to set up a contract," with pricing "based on licenses per device" — [MyScript pricing page](https://developer.myscript.com/pricing/).
- MyScript states a certificate "is required to use the MyScript handwriting recognition engine and gives the right to use the Interactive Ink SDK," scoped per certificate — [MyScript on-device license management](https://developer.myscript.com/support/on-device/on-device-license-management/).
- MyScript iink SDK 4.5 (Jun 2026) added text-to-handwriting for Latin-script languages with 22 curated handwriting profiles — evidence the SDK is actively developed — [MyScript blog](https://www.myscript.com/blog/myscript-iink-sdk-4-5-adds-text-to-handwriting-for-latin-script-languages/).
- Notability exposes math/graph/text conversion as a shipped feature, implying production-grade math recognition is achievable in a consumer note app — [Notability blog, "Turn Your Handwritten Notes Into Graphs, Text, and Math"](https://blog.notability.com/post/turn-your-handwritten-notes-into-graphs-text-and-math).
- Goodnotes performs handwriting recognition and document indexing **in its own shared Swift packages** — no third-party SDK is named — [Swift.org](https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/).

### Inferences
- Default plan: **`PKStrokeRecognizer` for text + index + search**, on the strength of zero cost, per-stroke granularity, `bounds` for highlight UI, and first-party support. MyScript becomes a *targeted* licence only if math recognition or a specific language is a hard requirement.
- Indexing strategy: store `indexableContent` + `recognizerVersion` per page, run recognition on idle/background (Apple explicitly warns to throttle), and rebuild the index on version change. For cross-notebook search, push page-level `indexableContent` into a single search store (SQLite FTS or Core Spotlight).
- ML Kit is the better *shape/gesture* recogniser (9 explicit classes) but a worse fit as the primary text engine on Apple platforms, because it adds a cross-platform dependency for a capability Apple now ships natively.
- Math recognition should be explicitly deferred: neither PencilKit nor ML Kit offers it, and it is the one capability where a commercial SDK is genuinely hard to replace.

### Gaps
- **MyScript per-device price: not confirmed.** The public pricing page shows only "contact us." A MyScript enterprise page reportedly quoted "packs, starting at 100 licenses priced €12 each" — [myscript.com/enterprise](https://www.myscript.com/enterprise/) — but I did not read that page, so **treat the €12 figure as unconfirmed.**
- **Accuracy benchmarks** for `PKStrokeRecognizer` (character/word error rates, per-language differences) are not published in anything I read. **Unconfirmed.** No independent comparison of PencilKit vs ML Kit vs MyScript accuracy was found.
- Whether `PKStrokeRecognizer` supports math notation: Apple's session mentions 29 languages, not math; assume no, but **unconfirmed.**
- Vision-framework OCR on *rendered* ink as a fallback: viable in principle (Vision does printed-text OCR), but I found no source evaluating it on handwriting; Apple's PDF session describes Live Text OCR for scanned PDFs — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/). Accuracy on cursive handwriting is **unconfirmed** and likely poor.
- Scribble as a recognition API (as opposed to a text-entry feature) is **unconfirmed** — no source found exposing Scribble results programmatically.

---

## Audio recording synced to strokes

### Takeaway
The mechanism is simple and fully documented by Notability: timestamp every stroke on creation, then on playback render only the strokes whose timestamp precedes the current audio time. The hard parts are clock accuracy and storage, not the algorithm.

### Cited Findings
- Notability, primary source: "Handwritten notes sync with audio playback using timestamps assigned to every ink stroke, so your notes reappear in real time as you scrub through a recording" — [Notability blog, "How We Built Live Transcription"](https://blog.notability.com/post/how-we-built-live-transcription).
- The playback algorithm, quoted from their engineer: "If the application knows when the handwritten strokes were recorded, it can just say, 'Okay, I'm at minute three of the transcription. Render all the ink that had been created before minute three'" — [Notability blog](https://blog.notability.com/post/how-we-built-live-transcription).
- "Every edit to a note and ink stroke is assigned a timestamp when it's created" — so the timestamp is per-edit, not per-document — [Notability blog](https://blog.notability.com/post/how-we-built-live-transcription).
- Their transcription output also carries per-segment start/end timestamps, "making the pairing between spoken words and written notes precise" — [Notability blog](https://blog.notability.com/post/how-we-built-live-transcription).
- iOS-side audio work is built on **AVFoundation**, and "only a few seconds of audio data are loaded into memory at any given time during upload" for battery and memory reasons — [Notability blog](https://blog.notability.com/post/how-we-built-live-transcription).
- Chunking strategy: audio sliced into 3–15 second overlapping segments, re-transcribed beyond a "chunk index" high-water mark so the transcript self-corrects — [Notability blog](https://blog.notability.com/post/how-we-built-live-transcription).
- Notability's transcription is **server-side Whisper** at 16 kHz, not on-device — a deliberate architecture choice a solo developer would likely invert for privacy and cost — [Notability blog](https://blog.notability.com/post/how-we-built-live-transcription).
- Product-level behaviour: annotations added during playback are synced to the recording, and recordings are linked to annotations — [Notability support](https://support.gingerlabs.com/en-us/articles/16300122-recording-and-playing-audio).
- Notability's stated roadmap gaps are timestamp support in *live* transcription and speaker diarization — useful signal that these are genuinely non-trivial — [Notability blog](https://blog.notability.com/post/how-we-built-live-transcription).
- On-device transcription in the OS: Apple's 2026 accessibility session describes "Apple AI-generated subtitles created live, locally on device as media plays," with speech transcription from audio (**English only**) and translation of existing subtitles — [Apple, WWDC26 session 256, via Use Your Loaf](https://useyourloaf.com/blog/wwdc-2026-viewing-guide/).

### Inferences
- Minimal viable implementation: `AVAudioRecorder` writing AAC/m4a, a monotonic clock captured at record-start, and a `recordedAt: TimeInterval` on every stroke and every edit. Playback = `AVAudioPlayer` + a predicate filter over strokes. That is genuinely small — days, not months — and is the highest value-per-effort feature in the whole brief.
- Store stroke timestamps **outside** the PencilKit blob (in your own page model keyed by stroke UUID), because `PKDrawing` has no timestamp field. This is exactly the kind of thing iOS 27's stable `Identifiable` stroke UUIDs now makes robust across edits and undo.
- Prefer on-device transcription: it removes upload cost, latency, and the privacy objection, at the cost of language coverage (English-only per the source above). Do it as a background pass over the finished recording, not live.
- Diarization and live timestamps are explicitly unsolved even at Notability's scale; scope them out of MVP.

### Gaps
- Whether Apple's on-device speech APIs are available to third-party apps generally (vs. only powering system subtitles) is **unconfirmed** — the session is framed around media subtitles. The older `Speech` framework and any 2025–26 successor ("SpeechAnalyzer") were **not verified in this research**. This needs a dedicated check before committing to on-device transcription.
- No source found on clock-drift handling between `AVAudioRecorder` time and `CADisplayLink`/touch timestamps. **Unconfirmed**, but this is the classic bug in this feature and should be tested.
- No source found on audio storage format/size trade-offs for multi-hour lecture recordings. **Unconfirmed.**

---

## Local storage format

### Takeaway
Use a **file package** (a directory the OS treats as one document) containing a JSON/binary page manifest plus one content file per page, with a versioned schema and a per-page thumbnail cache. This is the format that makes later file-based sync tractable, because a conflict becomes "which page files differ" rather than "whose opaque blob wins."

### Cited Findings
- Apple's new `DocumentWriter` receives the previous snapshot and can "write only the parts of the package that actually need updating, by comparing the current and the previous snapshots" — framework support for incremental package writes — [Apple, WWDC26 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- Writes are `nonisolated` and async, so disk work is off the main actor; progress is reportable via `Subprogress` — [Apple, WWDC26 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- A custom package format containing a photo and stickers is Apple's own worked example (`UTType(exportedAs: "stickerdocument")` with a `PageSnapshot` struct) — [Apple, WWDC26 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- PaperKit's persistence is a single versioned blob: `markupModel.dataRepresentation()` written to disk, with a `contentVersion` check plus a pre-rendered thumbnail on load for forward compatibility — [Apple, WWDC25 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- **SwiftData gained a `HistoryObserver`** "to observe persistent history transactions for syncing with external server" (2027 releases) — i.e. Apple now has a first-party story for change-tracking out of SwiftData — [Apple, WWDC26 session 274, via Use Your Loaf](https://useyourloaf.com/blog/wwdc-2026-viewing-guide/).
- SwiftData also gained sectioned fetch requests, `Codable` storage (not usable in predicates), and `ResultsObserver` for observing changes outside SwiftUI views — [Apple, WWDC26 session 274, via Use Your Loaf](https://useyourloaf.com/blog/wwdc-2026-viewing-guide/).
- Rnote's format is a **gzipped JSON file** with breaking changes across v0.2–v0.5 and an explicit "still unstable" disclaimer — a concrete warning about versioning discipline in vector note formats — [Rnote README](https://github.com/flxzt/rnote).
- Saber uses folders-nested-arbitrarily as its organising model and syncs to a server, with a dual-password scheme — an existence proof that a folder-tree + file model survives real sync — [Saber README](https://github.com/saber-notes/saber).
- Goodnotes uses **CRDTs for conflict resolution** in production, at scale, for ink and document sync — [Swift.org](https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/).
- Automerge is available for Swift: the library "enables collaborative, multi-user editing experience akin to Apple's Notes app or Google docs, or fully offline" — [Swift Forums announcement of automerge-swift](https://forums.swift.org/t/introducing-automerge-enable-collaborative-asynchronous-syncing-for-your-data-structures/67985).
- Automerge's positioning is local-first with immediate local edits and no server round-trip on the critical path — [automerge.org](https://automerge.org/).

### Inferences
- Recommended concrete layout: `Notebook.noteapp/` package → `manifest.json` (schema version, page order, template refs, per-page content hashes) + `pages/<uuid>.ink` (per-page stroke data, one file per page) + `cache/<uuid>.png` (thumbnails, regenerable, excluded from sync) + `assets/` (imported images, PDFs). One file per page is the key decision: it bounds write amplification, makes diffing trivial, and gives sync a natural conflict unit.
- **Append-only stroke logs** are tempting but I found no source recommending them for this use case, and PencilKit's blob serialisation works against them. Prefer whole-page files with per-page hashes; revisit only if you need real-time collaboration.
- CRDTs are a **phase-3** decision, not an MVP one. Goodnotes needed them because it does live multi-device sync; a Good Drive-backed single-writer-at-a-time model can survive on last-writer-wins per page file, which is far cheaper. Adding Automerge at MVP would put a complex dependency on the critical path of a solo project.
- SQLite (GRDB) vs SwiftData: SwiftData is fine for the **library index** (notebook metadata, folders, tags, search index) but a poor fit for stroke payloads. The pragmatic split is SwiftData/SQLite for catalog + files for content — and the new `HistoryObserver` makes the catalog syncable later.
- Whatever you choose, ship a `schemaVersion` in the manifest from day one. Rnote's v0.2→v0.5 breaking changes are the cautionary tale.

### Gaps
- No source found comparing SwiftData vs GRDB/SQLite for this scale, or documenting SwiftData performance limits with many records/large blobs. **Unconfirmed.**
- Whether `ReferenceFileDocument` autosave cooperates cleanly with a package containing many files: **unconfirmed.**
- No source found on `NSFileCoordinator`/`UIDocument` requirements for third-party (non-iCloud) file providers, which matters for Google Drive sync. Out of scope here but flagged as a real risk for the separate sync research.

---

## Open-source references worth studying

### Takeaway
Saber and Rnote are the two most instructive references for a small team — Saber for a complete hand-rolled ink canvas with a real file format and sync, Rnote for a vector engine with multiple page layouts. Both are GPL-3.0, which means **read, don't link**.

### Cited Findings
- **Saber** — "the notes app built for handwriting," cross-platform (Android, iOS, Windows, Linux, macOS) via Flutter/Dart, 5.0k stars, **GPL-3.0** — [Saber GitHub](https://github.com/saber-notes/saber).
- Saber's highlighter is a genuinely novel technique worth reading: it "utilizes canvas compositing to render the highlighter in a way that is consistent with/better than traditional paper, where it handles overlaps and maintains color consistency" — solving the "highlighter darkens where it self-overlaps" problem — [Saber GitHub](https://github.com/saber-notes/saber).
- Saber supports dark-mode inversion of notes *and* imported images/PDFs, keeping white ink on black usable — [Saber GitHub](https://github.com/saber-notes/saber).
- Saber uses a dual-password scheme so notes stay protected even against a hostile server, and supports self-hosting — [Saber GitHub](https://github.com/saber-notes/saber).
- **Rnote** — "an open-source vector-based drawing app for sketching, handwritten notes and to annotate documents and pictures," Rust + GTK4, 11.9k stars, **GPL-3.0-or-later** — [Rnote GitHub](https://github.com/flxzt/rnote).
- Rnote's feature list is effectively a requirements document for a vector ink engine: pressure-sensitive configurable stroke styles, shape tool, move/rotate/resize selection, four document expansion layouts, customisable backgrounds/page formats, optional pen sounds, stylus button remapping, an integrated workspace browser, and export to Svg/Pdf/Xopp — [Rnote GitHub](https://github.com/flxzt/rnote).
- Rnote's own stated debt to prior art is worth following: it credits **Pizarra** for "advanced shaping and featuring an infinite zoom" as "a great inspiration of the architecture of Rnote," and **Rough.js** for its rough-shape algorithms — [Rnote GitHub](https://github.com/flxzt/rnote).
- Rnote's known-issue list is a catalogue of platform ink pitfalls: X11 stylus/touch unreliability, palm rejection being device-side and non-disableable, and stylus buttons that emit "Eraser Tool" events instead of button events — [Rnote GitHub](https://github.com/flxzt/rnote).
- Rnote has an official macOS app bundle maintained separately, i.e. a GTK app does reach Mac but via a port rather than natively — [Rnote GitHub](https://github.com/flxzt/rnote).
- Apple's official PencilKit sample and reference material: "Drawing with PencilKit" sample project, plus docs on converting external drawing data, controlling stroke rendering for animation/editing, and building a handwriting recognition experience — [Apple, Drawing with PencilKit](https://developer.apple.com/documentation/pencilkit/drawing-with-pencilkit); [WWDC26 203 resources](https://developer.apple.com/videos/play/wwdc2026/203/).
- Apple's WWDC22 PDFKit session ships a complete, copyable PencilKit-on-PDF overlay sample (~30 lines of provider code in the transcript) — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- Apple's WWDC24 PencilKit session ships a sample project implementing a custom tool-picker item (an "animal stamp" tool) with barrel-roll support — [Apple, WWDC24 10214](https://developer.apple.com/videos/play/wwdc2024/10214/).

### Inferences
- Read Saber for **architecture and canvas compositing tricks**, Rnote for **document model and page layouts**. Neither is licence-compatible with a closed-source App Store app (GPL-3.0), so the value is conceptual — be disciplined about not copying code.
- Xournal++ and Stylus Labs Write were **not** examined in this pass; do not represent them as reviewed. Saber exports to `.xopp` (Xournal++'s format), which makes Xournal++ relevant mainly as a format prior art — [Rnote GitHub](https://github.com/flxzt/rnote).
- The most underrated reference is Apple's own WWDC sample code: the PDF overlay and the custom tool-picker item are each ~30 lines and remove days of guessing.

### Gaps
- **Xournal++, Stylus Labs Write, Excalidraw, tldraw: not examined.** No licence or architecture claims made for them. Excalidraw/tldraw are web-canvas projects and likely of limited direct relevance to a Swift ink engine.
- No open-source **Swift** ink engine or note app was found in this pass. This is a notable gap: there appears to be no Swift equivalent of Saber/Rnote to study, which raises the value of Apple's sample code. **Unconfirmed** that none exists — search was not exhaustive.

---

## On-device AI features feasible in 2026

### Takeaway
The Foundation Models framework is real and free at small scale, but the **on-device context window is small (8,192 tokens)**, which rules out "summarise this notebook" as a naive prompt. Design AI around retrieval (Spotlight/RAG) plus page-scoped operations, and use Private Cloud Compute only for genuinely large-context work.

### Cited Findings
- The Foundation Models framework "provides access to any large language model, like the on-device and Private Cloud Compute models designed for Apple Intelligence" — [Apple, Foundation Models documentation](https://developer.apple.com/documentation/foundationmodels).
- Introduced in **iOS 26** — [Create with Swift, "Exploring the Foundation Models framework"](https://www.createwithswift.com/exploring-the-foundation-models-framework/).
- **On-device context size is 8,192 tokens**, shown directly in Apple's own sample (`print(model.contextSize) // 8192`) — [Apple, WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/).
- Token-counting and context-inspection APIs arrived in **iOS 26.4**, and Apple advises using them "to adapt your app to the hardware it's running on" — [Apple, WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/).
- The 2027 on-device model was "rebuilt from the ground up," better at logic and tool calling, with refined guardrails reducing false positives — [Apple, WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/).
- **Vision is now available to the on-device model**: images can be attached to a prompt (`UIImage`, `NSImage`, `CGImage`, Core Image types, pixel buffers, file URLs), any size/aspect ratio, but "larger images will consume more tokens and incur more latency" — [Apple, WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/).
- **Private Cloud Compute** offers a **32,000-token context** with a reasoning capability and `reasoningLevel` control, requires no account or API key, stores no prompts, and is "available with no cloud API costs to developers who have less than 2 million first time downloads"; iCloud+ subscribers get higher limits — [Apple, WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/).
- New **system tools** directly useful for a notes app: `OCRTool` (Vision-backed structured text extraction from images) and a **Spotlight-powered search tool enabling "fully local Retrieval-Augmented Generation"** — Apple calls local RAG "one of our most requested features" — [Apple, WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/).
- `BarcodeReaderTool` also exists — minor, but free — [Apple, WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/).
- The framework, and many of its new APIs, went **open source** in the 2027 cycle, plus a `Foundation Models framework utilities` package updated between OS releases — [Apple, WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/).
- A `LanguageModel` protocol now abstracts models, with open-source `CoreAILanguageModel` and `MLXLanguageModel` implementations, and Anthropic/Google publishing Swift packages — [Apple, WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/).
- Third-party models bring auth and billing obligations ("you'll typically be billed per-token"), with `usage` properties exposing token counts including cached and reasoning tokens — [Apple, WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/).
- The **Evaluations framework** exists to quantify quality as you change prompts/models, "because language models are inherently non-deterministic" — relevant if AI summarisation is a headline feature — [Apple, WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/).
- An `fm` CLI ships on macOS 27 and a Python SDK exists for the same on-device model — useful for prototyping prompts outside the app — [Apple, WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/).
- Apple's own third-generation AFM family is described as "a family of five foundation models custom-built in collaboration with Google," spanning on-device to server models — [Apple Machine Learning Research](https://machinelearning.apple.com/research/introducing-third-generation-apple-foundation-models).

### Inferences
- **Hard constraint to design around**: at 8,192 tokens on-device, a 200-page notebook cannot be summarised in one prompt. Feasible MVP AI features are page-scoped or selection-scoped: "summarise this page", "explain this diagram", "make flashcards from this section", "clean up my handwriting into text".
- Notebook-level Q&A is a **RAG problem**, not a context-window problem — which is exactly what Apple shipped (Spotlight search tool + local RAG). This maps cleanly onto the handwriting index you already need for search: same index, two consumers.
- The free tier (<2M first-time downloads, no API cost for PCC) makes AI features economically viable for an indie app, unlike per-token third-party models.
- Device gating is the real product risk: these features are tied to Apple Intelligence-capable hardware. Treat AI as an enhancement with a graceful "not available on this device" path, never as core functionality.

### Gaps
- **The exact device eligibility list for Apple Intelligence / Foundation Models in Nov 2026 was not confirmed.** No source read enumerates supported iPad/Mac models. **Unconfirmed** — verify against Apple's official requirements before promising AI features.
- Latency and thermal behaviour of on-device inference on older supported iPads: **unconfirmed**, no source.
- Whether `SystemLanguageModel` availability check APIs behave per-device at runtime is implied by the Python SDK's `model.is_available()` but I did not read the Swift equivalent. **Unconfirmed.**

---

## Realistic complexity ranking for a solo developer or very small team

### Takeaway
Ink rendering, PDF round-tripping, and handwriting search are the three hard pillars. Audio sync, templates, and export are surprisingly cheap. Custom brushes and infinite canvas are the expensive vanity features that should come last — and in 2026 the OS has absorbed two former hard problems (recognition and stroke slicing), which meaningfully lowers the floor.

### Cited Findings
- Easy/cheap, evidenced as ~30 lines of framework code: PencilKit-over-PDF annotation via `PDFPageOverlayViewProvider` — [Apple, WWDC22 10089](https://developer.apple.com/videos/play/wwdc2022/10089/).
- Easy/cheap: the audio-to-stroke replay algorithm, which Notability describes as a timestamp per stroke plus a filter — [Notability blog](https://blog.notability.com/post/how-we-built-live-transcription).
- Easy/cheap: paper templates as a background view rather than document content (`contentView = UIImageView`) — [Apple, WWDC25 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- Easy/cheap: page export to PNG/PDF by adding a content type and branching in `write` — [Apple, WWDC26 269](https://developer.apple.com/videos/play/wwdc2026/269/).
- Moderate: handwriting search and indexing, *if* you follow Apple's guidance (throttle recognition, store `indexableContent` + `recognizerVersion`, re-index on version change) — [Apple, WWDC26 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- Moderate: forward-compatible persistence (version check + thumbnail fallback), which Apple treats as a small, standard step — [Apple, WWDC25 285](https://developer.apple.com/videos/play/wwdc2025/285/).
- Hard: custom brush textures, pressure curves, effect erasers, and real-time stroke filters — explicitly outside PencilKit and requiring Core Graphics or Metal — [Wesley Matlock](https://medium.com/@wesleymatlock/customizing-pencilkit-going-past-apples-tool-picker-b82eca7bfbe2).
- Hard: performance under load for stroke-level operations — "slicing can be expensive on complex drawings," with Apple recommending background-thread erasing — [Apple, WWDC26 203](https://developer.apple.com/videos/play/wwdc2026/203/).
- Hard: PDF annotation at scale, with developer reports of "serious performance" issues on annotation-heavy documents — [Apple Developer Forums](https://developer.apple.com/forums/tags/pdfkit?page=2).
- Hard: a full custom vector engine — Rnote's scope (selection transforms, four layout modes, SVG/PDF/Xopp export, stylus remapping, pen sounds) shows how wide the surface gets — [Rnote GitHub](https://github.com/flxzt/rnote).
- Hard: cross-platform ink parity — 2 years dev + 2 years production, 1.47M shared lines, 50 MB wasm binary — [Swift.org](https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/).
- Hard/genuinely unsolved even at scale: live transcript timestamps and speaker diarization — [Notability blog](https://blog.notability.com/post/how-we-built-live-transcription).
- Hard: math recognition — not offered by PencilKit; a commercial SDK or bespoke work — [Apple, WWDC26 203](https://developer.apple.com/videos/play/wwdc2026/203/) (no math claim in the 29-language feature set); [MyScript pricing](https://developer.myscript.com/pricing/) for the commercial route.
- Maintenance trap: gesture conflicts causing black-screen rendering during drawing — [Wesley Matlock](https://medium.com/@wesleymatlock/customizing-pencilkit-going-past-apples-tool-picker-b82eca7bfbe2); and framework-imposed layout constraints in lazy containers — [Use Your Loaf on WWDC26 321](https://useyourloaf.com/blog/wwdc-2026-viewing-guide/).
- Format churn is a recurring maintenance cost: Rnote broke its format in v0.2, v0.3, v0.4 and v0.5 — [Rnote GitHub](https://github.com/flxzt/rnote).

### Inferences
- Suggested MVP (all cheap-or-moderate, one hard pillar): PencilKit canvas per page + paper templates + vector page storage in a package + PDF import/annotate + page thumbnails + handwriting search (free in iPadOS 27) + audio recording with stroke replay + PNG/PDF export. That is a credible Notability-class v1 without writing a renderer.
- Phase 2 should buy the *second hard pillar* rather than a third easy feature: performance work (live-canvas windowing, thumbnail pipeline, incremental package writes), plus the Mac companion.
- Phase 3 is where custom-engine temptation appears. My read: only take it if brush fidelity has become the stated reason people choose the app. Otherwise spend the same effort on the library/organisation/search surface, which is where GoodNotes actually wins users and where competitors are weakest.
- Infinite canvas should be treated as a separate product decision, not a roadmap item — it invalidates the page model, thumbnail model and PDF mapping simultaneously.

### Gaps
- **No source found that publishes effort estimates (weeks/months) for any of these features.** The ranking above is derived from framework-code volume and vendor warnings, not from any developer's stated timeline. Treat the easy/moderate/hard buckets as directionally useful, not as scheduling data.
- No post-mortem found from an indie developer who shipped an ink app and described what went wrong. This was specifically sought and is a real gap in the available literature.
- SwiftUI-specific ink performance on real hardware: unmeasured here.

---

## Consolidated list of unconfirmed items

These are the claims a report-writer should **not** state as fact without further verification:

1. MyScript per-device price (the "€12 / 100-pack" figure appears only in a search snippet of an unread page).
2. Nutrient/PSPDFKit and PDFium pricing and licensing — not researched at all.
3. PDFKit's handling of internal hyperlinks/outlines in hyperlinked planner PDFs — highest-risk gap for that feature.
4. PencilKit on native AppKit (non-Catalyst); and tool-picker availability under Catalyst in current OS versions.
5. Apple Intelligence / Foundation Models eligible-device list.
6. On-device speech-to-text API availability to third-party apps (Speech / "SpeechAnalyzer" / SpeechAnalyzer-era APIs) — not verified.
7. Sidecar/Continuity Markup Pencil input fidelity on Mac (pressure, tilt, latency).
8. Accuracy benchmarks for `PKStrokeRecognizer`, ML Kit, and MyScript — none published in sources read.
9. Whether Notability uses PencilKit anywhere; engines of Concepts, Procreate, Linea, Muse.
10. Any numeric latency target or measured PencilKit-vs-custom latency comparison.
11. Xournal++, Stylus Labs Write, Excalidraw, tldraw — not examined; no claims made.
12. That no open-source Swift ink engine exists (search was not exhaustive).
