# Board → freeform: code audit for tool parity with the notebook

Read-only audit of `NoteApp/Boards/`, `Packages/BoardKit/`, `NoteApp/Notebook/` and
`Packages/InkKit/`. Goal: whiteboard with the notebook's *exact* tools on an
infinite Freeform-style canvas. All paths relative to repo root.

---

## 1. What the board does today

### 1.1 Data model (`Packages/BoardKit`, depends on NoteCore only — no InkKit)

- `Board`: `id`, `title`, `items: [BoardItem]`, `deletedItemIDs`, `createdAt`,
  `updatedAt`, `schemaVersion = 1` — `Board.swift:5,8-18`; add/remove/move/resize/
  lock write tombstones and bump `updatedAt` (`Board.swift:63-160`).
- `BoardItemContent` has exactly five cases: `ink([StrokeRecord])`, `image(assetName,
  frame)`, `text(String, frame, fontSize, color)`, `shape(kind, frame, stroke, fill,
  lineWidth)`, `connector(from,to,style)` — `BoardItem.swift:24-44`. The decoder
  *throws* on an unknown `kind` (`BoardItem.swift:66-100`), so any new item kind is a
  breaking schema change for older builds.
- `BoardItem`: `id`, `zIndex`, `isLocked`, `createdAt`, `updatedAt`, `content`
  (`BoardItem.swift:136-166`); `frame` is nil for ink and connectors
  (`BoardItem.swift:168-176`); ink bounds walk every point through
  `stroke.transform` (`BoardItem.swift:208-237`).
- `BoardCamera`: `centerX/centerY/zoom` with `minimumZoom 0.1`, `maximumZoom 8`
  (`BoardCamera.swift:5-30`) plus `worldPoint/viewPoint/visibleWorldRect`
  (`BoardCamera.swift:54-78`). **The editor never calls these conversions** — it
  reads `UIScrollView.zoomScale`/`contentOffset` directly
  (`BoardEditorView.swift:473-486`, `655-673`).
- `BoardDocument`: `schemaVersion`, `board`, `camera` (`BoardDocument.swift:4-20`).
- `BoardStore` (actor): one JSON file per board, `<uuid lowercased>.board.json`
  (`BoardStore.swift:41-46`), atomic write with a schema check that refuses unknown
  versions (`BoardStore.swift:109-141`). **No asset storage** — nothing like
  `LibraryStore.addAsset` exists, so `image(assetName:)` has nowhere to resolve from.
- `BoardMerge` (union merge) and `BoardLayout` (align/distribute) compile and are
  tested, but **no app code references them** (checked: zero `BoardMerge`/`BoardLayout.`
  hits under `NoteApp/`).
- File root: `<library>/Boards` — `AppModel.swift:124`.

### 1.2 Editor and canvas

`NoteApp/Boards/BoardEditorView.swift`:

- Fixed page: `static let boardSize = CGSize(width: 3_000, height: 3_000)`
  (`:21`), a constant `inkLayerID` (`:23`) and `defaultInkItemID` (`:25`).
- State: a single `tool: InkTool` + `PenPresets` (`:30-31`), own save bookkeeping
  (`:32-38`), `canvasMode: CanvasMode`, `PencilCanvasController`,
  `PageZoomController` (`:46-49`).
- Canvas host: `ZoomablePageView(pageSize: Self.boardSize, controller:)` wrapping
  `pageContent` (`:105-108`). `ZoomablePageView` is a `UIViewRepresentable` over a
  `UIScrollView` whose zoom view is a `UIHostingController` **sized exactly to
  `pageSize`** (`ZoomablePageView.swift:59-121`); it fits the page, clamps zoom to
  `fit*0.5 ... fit*8` (`:185-186`) and centres with insets (`:204-215`). So zoom is
  the scroll view's view-transform — page coordinates never change.
- `pageContent`: `ZStack` of `BoardPaper` + `PencilCanvasView(strokes:inkStrokes,
  pageSize: boardSize, tool:, mode: canvasMode, activeLayerID: inkLayerID,
  isEditable: true, controller:, onStrokesChanged:)` with `.id(board.id)`
  (`:116-134`). `PencilCanvasView` is a `PKCanvasView` (`InkCanvasView`) with
  `isScrollEnabled = false` (`PencilCanvasView.swift:273`) and its own zoom locked to
  `bounds/pageSize` (`PencilCanvasView.swift:72-95`) — i.e. it expects **canvas
  bounds == page size at 1:1**.
- Paper: 48 pt dot grid, one tiled 3× image on white plus a hairline border
  (`:675-730`).
- macOS: read-only PNG of the whole 3 000 × 3 000 board (`:137-160`), no editing.

### 1.3 Toolbar (custom, not `EditorToolbar`)

`BoardEditorView.swift:174-228`: one horizontal `ScrollView` row containing
pen / highlighter / eraser (`canvasMode = .eraser(.stroke, width: 12)` at `:185` —
**stroke only, fixed width**), then 5 hard-coded swatches (`:334-340`) and a system
`ColorPicker` (`:195`), then 3 width dots — `[3,8,16]`, highlighter `[12,24,36]`
(`:326-329`) — then undo/redo on the shared `PencilCanvasController` (`:217-228`).
Colour and width are applied by writing a single `InkTool` back through
`PenPresets` (`:344-380`). Nav bar has only Done, Fit and Centre
(`:492-520`; `fitBoard` `:430`, `centerCamera` `:438`).

Missing vs the notebook: pen-style picker, favourite pens, 8-slot favourite colours,
palette popover, pixel eraser, eraser width, erase-highlighter-only, auto-deselect,
lasso, laser, element select/edit, insert (text/image/shape/sticky), read-only,
zoom view, ruler, keyboard shortcuts. Hold-to-shape *is* on by accident through
`PencilCanvasView`'s default `holdToDrawShapes: true` (`PencilCanvasView.swift:226`).

### 1.4 Save flow

- `strokesChanged` rewrites **one** `.ink` item with the whole stroke array (or removes
  it when empty) and bumps `undoRevision`, then `scheduleSave()` (`:539-564`).
- `scheduleSave`: 700 ms debounce, snapshot `board` + `currentCamera`, `model.save`
  (`:566-594`). `finishEditing` awaits the write before dismissing (`:596-611`);
  `flush()` is fire-and-forget on background/disappear (`:632-640`).
- `currentCamera` converts scroll offset/zoom into `BoardCamera` (`:655-673`);
  restore polls up to 40 × 50 ms for a laid-out scroll view, then
  `setZoomScale` + clamped `contentOffset` (`:456-486`).
- `BoardModel` (`NoteApp/Boards/BoardModel.swift`): thin `@Observable` library;
  `load()` reads every file and caches cameras (`:35-70`), `save` writes a
  `BoardDocument` and re-sorts (`:92-114`), `createBoard` `:76-90`, `delete`
  `:135-144`, `camera(for:)` rejects the all-default camera (`:121-126`).
- Library UI: `BoardsView` list + create/rename/delete + sheet editor
  (`BoardsView.swift:14-70`), presented from the notebook library
  (`LibraryView.swift:447`); thumbnails render **ink only** (`BoardThumbnail.swift:15-45`).

---

## 2. What the notebook provides, and how it is wired

### 2.1 Tool state — `NoteApp/Notebook/EditorToolState.swift`

`EditorTool` enum: `pen, highlighter, eraser, lasso, laser, elements, links`, with
`editsInk`/`drawsInk`, display names and P/H/E/V/L shortcuts (`:8-55`).
`EditorToolState` is `@MainActor @Observable` (`:78`) and owns:

| feature | where |
| --- | --- |
| current `tool`, `previousTool`, `isReadOnly`, `isZoomViewShown` | `:79-95` |
| `penStyle` + `PenPresets` (per-style colour/width) | `:98,126` |
| `eraserKind` (stroke/pixel), `eraserWidth`, widths `[6,12,24,48]` | `:99,115,256-270` |
| `laserMode` (dot/line) | `:100,262` |
| 8-slot `penFavorites` / `highlighterFavorites`, `recentColors` | `:102-108` |
| `FavoritePens` (6 saved pens, own persistence) | `:109` |
| palette request id for Pencil double-tap | `:111` |
| tool → `CanvasMode` mapping | `:213-221` |
| width presets per tool, `inkWidthRange` (1–40, highlighter 8–60) | `:225-240` |
| `selectPenStyle`, `setEraser(Width)`, `setLaserMode`, `didEndToolGesture` (auto-deselect) | `:248-283` |
| `handlePencilDoubleTap` (eraser / previous tool / palette) | `:285-305` |
| `setColor` (forces highlighter alpha 0.35), `setWidth` | `:307-321`, `:383-395` |
| favourite colours add/replace/move/remove + names | `:323-390` |
| debounced (600 ms) UserDefaults persistence, `saveNow` | `:397-429` |

Dependencies: `UserDefaults.standard` + `AppSettings` only. **No session, no page,
no page size.** Pen styles/ink: `InkKit/InkTool.swift:26-107` (`PenStyle` eight inks,
`InkTool.inkingTool`, highlighter = translucent marker).

### 2.2 Toolbar — `NoteApp/Notebook/EditorToolbar.swift` (iOS only)

- Generic over two menus: `EditorToolbar<InsertMenu, MoreMenu>(editor:controller:
  showsThumbnails:isRecording:recordingLabel:onBack:onStopRecording:onClearPage:
  insertMenu:moreMenu:)` (`:12-24`).
- Left: back, **page thumbnails**, undo, redo (`:97-118`). Right: read-only toggle,
  recording chip, More (`:119-176`). Centre: tools, then swatches, then widths
  (`:179-189`).
- Tools: pen chip with style popover (`:244-280`), favourite pens (`:282-297`),
  highlighter + width popover (`:299-312`), eraser with context menu + size/filter/
  auto-deselect popover (`:314-334`), lasso (`:222-230`), laser (`:336-351`),
  zoom view (`:353-368`), select elements (`:232-242`), Insert menu (`:244-250`),
  follow links (`:250-260`).
- Colours: 8 favourites with drag-reorder, context menu and VoiceOver moves
  (`:387-536`), palette button (`:499-536`) → `ColorPalettePopover(editor:)`
  (`ColorPalettePopover.swift:9-30`, pure `EditorToolState` dependency).
- Widths: three dots from `editor.widthPresets` (`:539-566`).
- Popovers: `PenSettingsPopover` (`:575`), `WidthSettingsPopover` (`:618`),
  `WidthSlider` (`:633`), `EraserSettingsPopover` (`:666`, takes `onClearPage`),
  `LaserSettingsPopover` (`:740`), `FavoritePensPopover`
  (`FavoritePens.swift:125`).
- No `PKToolPicker` anywhere in app source — the toolbar is fully custom.

### 2.3 Wiring to the canvas — `NoteApp/Notebook/NotebookView.swift`

- `@State private var editor = EditorToolState()` (`:175`), passed straight to
  `EditorToolbar` (`:200-211`), `saveNow()` on disappear (`:253`).
- Canvas mode: `editor.isReadOnly ? .links : editor.canvasMode` (`:998-1003`);
  `panTouches` from the tool (`:1005-1019`); `inkCapture` for strokes on a loading
  page (`:1021-1029`); `canvasIsEditable` false for `.elements`/`.laser`
  (`:1031-1039`).
- `pageContent` (`:1041-1150`): `PaperBackground` (rasterised paper + elements)
  → `PencilCanvasView(strokes: session.visibleStrokes, pageSize: page size,
  tool: editor.inkTool, mode:, activeLayerID: session.activeLayerID, isEditable:,
  holdToDrawShapes: setting, onToolGestureEnded: editor.didEndToolGesture,
  onPencilDoubleTap: editor.handlePencilDoubleTap, eraseHighlighterOnly: setting,
  onStrokesChanged: session.strokesChanged)` (`:1057-1090`) → `LaserPointerOverlay(mode:)`
  (`:1131`) → `ElementEditLayer(page:selectedID:onFrame:onLock:onDelete:onMoveZ:)`
  (`:1135-1149`).
- Page host: `PagedNotebookView` (vertical/horizontal paging over
  `pageOrder` + `activePage` + `PageImageSource` wrapping `LibraryStore`) —
  `ContinuousPagesView.swift:105-152`.

### 2.4 Elements (text / image / shape / sticky / tape)

- Model: `PageElement { id, layerID, frame: ElementFrame, zIndex, updatedAt,
  content, isLocked, textStyle }` (`NoteCore/Model/PageElement.swift:4-25`);
  `ElementContent` = `text(_, fontName, fontSize, color)`, `image(assetName)`,
  `shape(kind, stroke, fill, lineWidth)`, `pdfPage`, `stickyNote(text, color)`,
  `tape(color)` (`:65-83`). Rich style lives in `textStyle` (`TextStyle`).
- Stored per `Page` (`Page.swift:9-20`), layers gate visibility
  (`Page.swift:44-48`).
- Rendered by rasterising the paper (`PaperBackground`, `PageBackground.swift:198-240`)
  using the **internal** `PageElementRenderer` (`InkKit/PageElementRenderer.swift:22`)
  — no public per-element renderer; only `PageRenderer.image(page:)` is public
  (`PageRenderer.swift:18-35`).
- Direct manipulation: `ElementEditLayer` (SwiftUI drag/resize/lock/delete/z,
  page-sized coordinate space) — `ElementEditLayer.swift:4-36, 40-120`.
- Insert + mutations: insert menu `NotebookView.swift:576-593`; `addTextElement`
  `NotebookSession.swift:543-573`, `addImageElement` (asset via
  `LibraryStore.addAsset` `:461`) `:575-611`, `addShapeElement` `:613-640`,
  update/remove/frame/lock/z `:642-700`; text re-edit via `PageElementsSheet`
  (`PageElementsSheet(session:)`, `PageElementViews.swift:102-170`) and
  `TextElementComposer` (pure callbacks, `PageElementViews.swift:4-33`).

---

## 3. Reuse map

| Notebook piece | Reuse | Coupling / adapter |
| --- | --- | --- |
| `EditorToolState` | **as-is** | none (UserDefaults + AppSettings). Shared keys mean board and notebook share pen/colour/eraser state — desirable. |
| `EditorTool` / `LaserMode` / `EraserMode` | **as-is** | none. |
| `EditorToolbar` | **small adapter** | generic menus already; page-specific bits are the thumbnails button (`:100-108`) and `onClearPage`. Add an optional `showsPagesButton`/`onOpenPages` or bind thumbnails to the board list; `isRecording: false`, `onStopRecording: {}`, `recordingLabel: ""`. |
| `PenSettingsPopover`, `WidthSettingsPopover`, `WidthSlider`, `EraserSettingsPopover`, `LaserSettingsPopover` | **as-is** | all take `editor:` only; `EraserSettingsPopover` needs an `onClearPage` closure → "clear board". |
| `ColorPalettePopover`, `FavoritePensPopover`, favourite-colour rows | **as-is** | `editor:` only. |
| `PencilCanvasView` + `PencilCanvasController` | **as-is for ink, adapter for framing** | requires `activeLayerID` and `pageSize` with canvas bounds == page size (`PencilCanvasView.swift:72-95`); board already fakes a layer (`BoardEditorView.swift:23`). |
| Hold-to-shape | **already active** | inside `PencilCanvasView` + `HoldToShape.swift`; just pass `AppSettings.Key.holdToDrawShapes`. |
| Lasso / pixel eraser / laser | **as-is** | all expressed through `CanvasMode` (`PencilCanvasView.swift:115-137`); `LaserPointerOverlay` is page-independent (mode only). |
| `TextElementComposer`, `StickyNoteElementView`, `TapeElementView` | **as-is** | pure props/closures. |
| `ElementEditLayer` | **page-coupled → adapter** | takes `page: Page`, uses `page.width/height`, `page.elements`, `ElementFrame`, page coordinate space (`ElementEditLayer.swift:4-36`). Needs a frame-list variant over `BoardItem.frame`. |
| `PageElementsSheet` | **page-coupled** | `session: NotebookSession` (`PageElementViews.swift:103`) → needs a closure-based data source or skip. |
| `PagedNotebookView` / `ContinuousPagesView` | **not reusable** | needs `pageOrder`, `activePage`, `PageImageSource(LibraryStore)`, `InkCapture` (`ContinuousPagesView.swift:105-140`). Rewrite for infinite canvas. |
| `ZoomablePageView` / `PageScrollView` | **reusable host, wrong framing** | content is exactly `pageSize`, zoom clamped to `fit*0.5...fit*8`, centres via insets (`ZoomablePageView.swift:59-121, 185-215`). Fine for "big fixed board", not for growth. |
| `PageBackground` / `PageRenderer` | **adapter** | `PageRenderer.image(page:)` is public and can render a synthesised `Page`; `PageElementRenderer` is internal (`PageElementRenderer.swift:22`) so board element rendering must go through `PageRenderer` or SwiftUI views. |
| `PaperBackground` (dark paper) | skip for board | board paper is its own dot grid. |
| Page thumbnails, Zoom View, outline, layers, tape, PDF links, search, audio | **not in scope** | session/page bound. |
| `BoardKit` `BoardMerge`/`BoardLayout` | ready but unused | useful for later multi-device sync and align/distribute menus. |

---

## 4. Risks on an infinite canvas

1. **Canvas is page-pinned.** `PencilCanvasView` locks `PKCanvasView` zoom to
   `bounds / pageSize` and expects bounds == page size (`PencilCanvasView.swift:72-95`),
   and `ZoomablePageView` sizes its hosted view to exactly `pageSize`
   (`ZoomablePageView.swift:92-96`). Any growth must be modelled as a *moving
   window* of world space fed into the canvas, not as a growing `pageSize`.
2. **`boardSize` is baked in.** `BoardEditorView.swift:21`, `:105`, `:122`, `:141`,
   plus the fit maths at `:424-431`. Removing it touches geometry, camera restore
   and the macOS render path together.
3. **Camera units are view-dependent.** `currentCamera` stores the raw
   `UIScrollView.zoomScale` (`:655-673`), whose meaning depends on window size and
   the 3 000 pt page; `apply(camera)` then multiplies world centre by that scale and
   clamps to `contentSize` (`:473-486`), ignoring the centring insets. Saved cameras
   already mis-restore across device sizes/rotations. `BoardCamera.minimumZoom 0.1 /
   maximumZoom 8` are never enforced (scroll caps at `fit*8` ≈ 2.6 for a 3 000 pt
   page). Fix by storing `visibleWorldRect` (or zoom relative to fit) and using
   `BoardCamera.worldPoint/viewPoint`.
4. **One ink item for the whole board.** `strokesChanged` rewrites every stroke on
   every edit (`BoardEditorView.swift:539-564`) and every save re-encodes the whole
   board JSON (`BoardModel.swift:92-114`). Cost is O(all strokes) per stroke and per
   keystroke-save; at freeform scale this must become per-item or per-region.
5. **Tombstone resurrection.** `Board.add` clears the tombstone for a reused id
   (`Board.swift:63-72`), and `defaultInkItemID` is a constant
   (`BoardEditorView.swift:25`) — deleting the ink item and drawing again revives it
   in a merge.
6. **Schema is strict.** Unknown `schemaVersion` is refused by the store
   (`BoardStore.swift:96-108`) and unknown `BoardItemContent` kinds throw
   (`BoardItem.swift:66-100`). Adding sticky notes, rich text or images means a
   version bump and old builds refusing the file (no forward-compatible decoding).
7. **Item kinds lag the notebook.** No sticky note, tape, PDF page or `TextStyle`
   (bold/italic/underline/alignment); text carries only `fontSize` + `color`
   (`BoardItem.swift:32` vs `PageElement.swift:66,17`).
8. **No asset store for boards.** `image(assetName:)` (`BoardItem.swift:29`) has no
   directory, and `BoardStore` has no `addAsset`; images need a board assets folder
   before the insert-image tool can work.
9. **Ink z-order.** A single ink item at `zIndex 0` means every element must be
   above it; placing "ink over shape" needs more than one ink item or per-item z.
10. **Element rendering is notebook-shaped.** Live elements are rasterised into the
    page background (`PageBackground.swift:198-240`) and editing is a page-sized
    SwiftUI layer; both need a board equivalent (smallest is live SwiftUI item views).
11. **Undo reach.** Undo is PencilKit's canvas undo manager only
    (`PencilCanvasView.swift:10-40`); notebook element add/move/delete are *not*
    undoable either — so parity does not require new undo plumbing, but a board that
    re-frames its canvas (new `.id`, rebuilt drawing) must not clear the undo stack.
12. **Platform split.** `EditorToolbar` and the whole interactive path are
    `#if os(iOS)`; the macOS board is a static render (`BoardEditorView.swift:137-160`)
    and must stay so, or it needs an AppKit toolbar.
13. **Rebuild-on-frame cost.** Stroke `transform` is part of the change signature
    (`IncrementalStrokeConverter.swift:44-56`), so translating strokes to follow a
    pan would look like a content edit and rebuild the drawing every frame. Pan must
    come from a container transform; only the *committed* world offset may rewrite
    transforms.

---

## 5. Recommended minimal integration (smallest diff)

1. Delete the board's private tool row (`BoardEditorView.swift:174-380`) and adopt
   `@State private var editor = EditorToolState()` (`NotebookView.swift:175`) plus
   `EditorToolbar` in a `safeAreaInset`/`VStack` header, passing
   `controller:`, `isRecording: false`, `showsThumbnails:` bound to the boards list,
   `onBack: dismiss`, `onStopRecording: {}`, `onClearPage:` → "Clear board".
2. Add one optional parameter to `EditorToolbar` (`showsPagesButton: Bool = true`) so
   the board can hide/repurpose the page-thumbnail button without forking the file.
3. Derive the canvas exactly as `NotebookView` does: `editor.canvasMode`
   (read-only → `.links`), `isEditable = !editor.isReadOnly && tool != .elements &&
   tool != .laser`, `holdToDrawShapes`, `eraserHighlighterOnly`,
   `drawsWithFinger`, `onToolGestureEnded: editor.didEndToolGesture`,
   `onPencilDoubleTap: editor.handlePencilDoubleTap` — all params already exist on
   `PencilCanvasView` (`:200-255`).
4. Replace `boardSize` with a `BoardViewport` value = `BoardCamera` + view size;
   compute `visibleWorldRect` with `BoardCamera.visibleWorldRect` (`BoardCamera.swift:70-78`)
   instead of the scroll view's own zoom maths.
5. Keep `ZoomablePageView` for now but drive it as a *viewport window*: `pageSize`
   = padded visible world rect size, and pass the rect origin down so ink records are
   drawn with `transform` translated by `-origin` (records stay in world space on disk).
6. Only feed **visible** ink: filter with `Board.items(in: expandedRect)`
   (`Board.swift:170-186`) instead of the whole `.ink` item, and re-commit the
   translation on pan/zoom *settle* (as `PageScrollView` already coalesces via
   `setZoomScale`/`settle`, `ZoomablePageView.swift:31-45`).
7. Store the camera as `visibleWorldRect` / `zoomRelativeToFit` and restore through
   `apply` using `worldPoint(fromViewPoint:)`; clamp with `BoardCamera.minimumZoom /
   maximumZoom` so the viewport is device-independent (`BoardEditorView.swift:655-673`
   and `:473-486` are the two places to change).
8. Add `zIndex` discipline: keep the ink item behind elements by placing new items at
   `(max zIndex + 1)`; reuse `Board.add` so tombstones stay consistent.
9. Draw text / sticky / shape / image items as live SwiftUI views in the board ZStack
   (modelled on `StickyNoteElementView`, `PageElementViews.swift:280-304`) instead of
   rasterising through `PaperBackground`.
10. Generalise `ElementEditLayer` by extracting its drag/resize/lock/z body into a
    frame-list view (`ElementFrame` in, callbacks out) and having the board pass
    `BoardItem.frame` + a `Board.setFrame`-based callback (`Board.swift:196-210`);
    keep the notebook call site unchanged.
11. Wire the insert menu to `BoardItemContent` factories: `.text` via
    `TextElementComposer`, `.shape` (board already has `BoardShapeKind`), `.image`
    after adding `BoardStore.addAsset`/`assetURL` next to the board JSON; place new
    items at the camera centre to avoid page-relative maths
    (`NotebookSession.swift:543-640` is the page-coupled source to copy from).
12. Bump `Board.currentSchemaVersion` to 2 and add tolerant decoding
    (`decodeIfPresent`) for the new kinds; keep `BoardItemContent`'s `kind`
    discriminator so v1 files still open.
13. Keep the existing 700 ms debounce save, but write only items whose `updatedAt`
    changed (compare against the loaded snapshot) to avoid re-encoding the whole
    board per stroke; thumbnails already key on `board.updatedAt`
    (`BoardThumbnail.swift:52`).
14. Reuse `LaserPointerOverlay` (`LaserPointerOverlay.swift:8-14`) and PencilKit's
    lasso unchanged; both are coordinate-space agnostic, so lasso moves and
    laser trails need zero work.
15. Leave `BoardLayout`/`BoardMerge` unused for this pass, and leave the macOS board
    read-only (`BoardEditorView.swift:137-160`) until the iOS path is stable.
