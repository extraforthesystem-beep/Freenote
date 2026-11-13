# Apple Freeform on iPad — Reference Notes

Research compiled 2026-11-13. Scope: Freeform on iPadOS 18 → 27, focused on what a simplified Pencil-first whiteboard needs to copy Freeform's *feel*.

Confidence legend:

- **[Apple]** = Apple documentation / newsroom, quoted or closely paraphrased.
- **[Review]** = reputable third-party hands-on (MacStories, XDA, Paperless X).
- **[Screenshot]** = read directly off Apple's own Freeform screenshots in the iPad User Guide.
- **UNCONFIRMED** = could not verify in any source; do not treat as fact.

Every claim carries its source link inline.

---

## 1. Canvas

**Infinite canvas.** "The canvas expands as you add content, so you're never constrained by space limits or page formatting." — [Apple: Create a Freeform board on iPad](https://support.apple.com/guide/ipad/create-a-freeform-board-ipade453ddaa/27/ipados/27). Apple's launch PR
calls it an "infinite canvas [that] expands as content is added to the board" — [Apple Newsroom, 13 Dec 2022](https://www.apple.com/newsroom/2022/12/apple-launches-freeform-a-powerful-new-app-designed-for-creative-collaboration/). There is no page size, no page edges, and no page-break UI
anywhere.

**How it grows.** Content is placed anywhere in an unbounded coordinate space and the visible extent grows outward from the origin; there is no "add
page" step — the same point is restated by [Apple: Get started with Freeform](https://support.apple.com/guide/ipad/get-started-with-freeform-ipad9c59637d/27/ipados/27) ("a boundless canvas"). The minimum practical extent is whatever `Zoom to Fit` can frame; see zoom.

**Backgrounds.** Exactly two canvas colours: black or white. "Freeform boards have a black or white background" — [Apple: Change your Freeform settings on iPad](https://support.apple.com/guide/ipad/change-freeform-settings-ipadcb84e16e/27/ipados/27). Dark Mode unlocks `Show with Dark Background` (same
page). There is **no lined/ruled background and no square grid**; the dot grid is the only pattern. A 2026 review states this bluntly: "Backgrounds
are still very limited. You can only choose between plain or dotted white… Something as simple as a lined or squared option could make a huge
difference" — [Paperless X, Freeform in iPadOS 26](https://beingpaperless.com/apple-freeform-in-ipados-26-review/). A coloured region inside the board is faked by inserting a large rectangle, then Send to Back + Lock — [Apple: Change a board's appearance (Mac)](https://support.apple.com/guide/freeform/frfm000074a4e/5.0/mac/27) (same trick documented
for iPad on the settings page above).

**Dot grid.** "Show a grid of grey dots on your board, which allows you to more easily see whether items line up" — [Apple: settings page](https://support.apple.com/guide/ipad/change-freeform-settings-ipadcb84e16e/27/ipados/27). Toggle in full-screen view:
button in the **lower-right corner** (dotted-square glyph, visible in [Screenshot: Position items on a board](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27)). In a smaller window: `More > View Options > Show Grid / Hide Grid` (same Apple page). Dot spacing/colour value:
**UNCONFIRMED** (dots are mid-grey, fixed spacing at all zoom levels as far as screenshots show).

**Snap to Grid.** Off by default; when on, "edges and points align to the nearest dot on the grid as you resize or move an item" — [Apple: settings page](https://support.apple.com/guide/ipad/change-freeform-settings-ipadcb84e16e/27/ipados/27). Same page
documents the three alignment guides (Center / Edge / Spacing), which are independent of the grid.

**Zoom range.** Default 100%, **min 10%, max 400%** — [XDA: Complete guide to Freeform](https://www.xda-developers.com/apple-freeform-app-guide/) ("You can zoom in up to 400% and zoom out up to 10%"). A 2026 reviewer calls 400% "not
impressive" as a maximum — [Paperless X](https://beingpaperless.com/apple-freeform-in-ipados-26-review/). Pinch is continuous; there is no documented rubber-band or step quantisation — **UNCONFIRMED**.

**Zoom percentage indicator.** Bottom-left of the board, always visible while in a board. Apple: "To magnify more precisely, tap the current
percentage in the bottom-left corner, then tap a percent" — [Apple: Create a board](https://support.apple.com/guide/ipad/create-a-freeform-board-ipade453ddaa/27/ipados/27). So tapping the readout opens a **preset list**; the exact preset values are
**UNCONFIRMED** (Apple never lists them; 10/25/50/100 % is claimed only by low-quality blogs). Apple's screenshots show live values of 56 % and 91 % —
[Screenshot: Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27), [Screenshot: Draw or handwrite](https://support.apple.com/guide/ipad/draw-or-handwrite-ipadf825a0bd/27/ipados/27).

**Zoom to fit / zoom to selection.** Mac documents `View > Zoom > Zoom to Fit Content` and `Zoom to Selection` — [Apple: Change a board's appearance](https://support.apple.com/guide/freeform/frfm000074a4e/5.0/mac/27). MacStories confirms the iPad zoom control exposes "predefined zoom percentages,
plus Zoom to Fit Content and Zoom to Selection" — [MacStories review](https://www.macstories.net/reviews/freeform-leverages-the-freedom-and-flexibility-of-a-blank-canvas/). The bottom-left pill in the screenshot has a second button beside the percentage: likely this
menu — **partly UNCONFIRMED** (glyph not documented).

---

## 2. Gestures

**Pan and zoom.**
- One-finger drag on empty canvas pans: "Move around your board by dragging your finger, and zoom in or out by pinching open or closed" — [Apple: Create a board](https://support.apple.com/guide/ipad/create-a-freeform-board-ipade453ddaa/27/ipados/27).
- Pinch = zoom, explicitly "Pinch to zoom in and out as you work" — [Apple: Get started](https://support.apple.com/guide/ipad/get-started-with-freeform-ipad9c59637d/27/ipados/27).
- Two-finger pan as a distinct gesture is **not documented**; one finger already pans, and two fingers on an object rotate it. Treat "two-finger pan"
  as **UNCONFIRMED / absent**.

**Pencil vs finger — the key setting.** By default "Apple Pencil works as a drawing and writing tool in Freeform" — [Apple: Draw or handwrite](https://support.apple.com/guide/ipad/draw-or-handwrite-ipadf825a0bd/27/ipados/27). `Settings > Apps > Freeform > Apple Pencil > Select and Scroll` makes Pencil
select/scroll instead of only drawing (same Apple page, plus [Apple: Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27)). After enabling it, a toolbar button toggles Pencil between drawing and
select/scroll mode. There is also a `Draw with Finger` switch inside the drawing tools, for people who want finger ink alongside Pencil ink ([Apple: Draw or handwrite](https://support.apple.com/guide/ipad/draw-or-handwrite-ipadf825a0bd/27/ipados/27)).

**One-finger behaviour, non-Pencil.** Finger drag on empty canvas = pan. Finger drag on an object = move. Finger drag with the drawing tool active =
ink. There is no documented "finger always selects" mode — finger acts as the pointer, Pencil as the pen — **implied by** the two Apple pages above.

**Tap / double-tap / long-press.**
- Tap object = select. Tap empty canvas = deselect and raise a menu containing **Select Objects** and (if the clipboard has content) **Paste** — [Apple: Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27),
  [Apple: Add images and files](https://support.apple.com/guide/ipad/add-images-scans-links-and-other-files-ipada82c9eff/27/ipados/27).
- Double-tap a text box, shape or sticky note to enter text editing — [Apple: Add text](https://support.apple.com/guide/ipad/add-text-ipad5a22ec43/27/ipados/27).
- Double-tap any media item to Quick Look preview it — [Apple: Add images and files](https://support.apple.com/guide/ipad/add-images-scans-links-and-other-files-ipada82c9eff/27/ipados/27), [Apple Newsroom](https://www.apple.com/newsroom/2022/12/apple-launches-freeform-a-powerful-new-app-designed-for-creative-collaboration/).
- Long-press (touch and hold) on an object starts multi-select chaining: "Touch and hold an item on your board, then, with another finger, tap other
  items" — [Apple: Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27). A long-press context menu is **UNCONFIRMED** on iPad; the contextual commands live in the selection bar's `…` button instead.

**Marquee (drag to multi-select).** "Touch and hold the canvas, then drag the box that appears around the items you want to select" — [Apple: Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27). Note the
interaction: the marquee begins with a **press-and-hold**, not an immediate drag, so a plain drag still pans. Apple's own screenshot shows a
finger-drag selection box ("A finger dragging to select items in Freeform", same page).

**Undo / redo.**
- On-screen undo and redo buttons sit at the left end of the drawing palette [Screenshot: Draw or handwrite](https://support.apple.com/guide/ipad/draw-or-handwrite-ipadf825a0bd/27/ipados/27); XDA notes "hold on it to reveal the Redo menu" (older build) — [XDA](https://www.xda-developers.com/apple-freeform-app-guide/).
- System-wide iPad gestures also apply: **three-finger swipe left = undo, three-finger swipe right = redo, three-finger single tap = undo/redo menu**
  — [9to5Mac](https://9to5mac.com/2019/06/12/gestures-undo-ios-iphone-ipad/).
- **Two-finger tap = undo is NOT a Freeform gesture**; that is Procreate. No Apple source mentions it — mark **UNCONFIRMED / likely false**.

**Apple Pencil double-tap and squeeze.**
- Both are system settings, not Freeform settings: `Settings > Apple Pencil` and `Settings > Accessibility > Apple Pencil` ("Change Apple Pencil double tap and squeeze settings") — [Apple: Adjust double tap and squeeze](https://support.apple.com/guide/ipad/adjust-double-tap-squeeze-settings-apple-ipad63913965/27/ipados/27).
- Double tap = Apple Pencil 2 / Pencil Pro; squeeze = Pencil Pro only (same page).
- Typical double-tap action is "Switch between current tool and eraser", with "Show Color Palette" and Off as alternatives — widely documented
  third-party, **not** stated by Apple in the Freeform guide (UNCONFIRMED for Freeform specifically; it is the system default).
- Freeform-specific double-tap/squeeze behaviour is **UNCONFIRMED**; assume it follows the system preference.

**Scribble.** Freeform has its own Scribble pen in the drawing tools that converts handwriting to typed text as you write, and system Scribble works
in any text field — [Apple: Draw or handwrite](https://support.apple.com/guide/ipad/draw-or-handwrite-ipadf825a0bd/27/ipados/27).

**Other direct-manipulation gestures** (all from
[Apple: Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27)):
- Rotate: two fingers on the item, turn your hand.
- Constrain movement to horizontal/vertical/diagonal: drag with one finger while a second finger touches and holds anywhere on the board.
- Match another object's size: start resizing, then hold a second finger on the target item until "Match Size" appears, and lift both fingers
  together.
- Long-press-drag text to move it ("Touch and hold the selected text, then drag it to a new position") — [Apple: Draw or handwrite](https://support.apple.com/guide/ipad/draw-or-handwrite-ipadf825a0bd/27/ipados/27).

---

## 3. Selection & manipulation

**Selection chrome.** Selected objects show a thin blue outline with **round blue dots** at the corners/edges (resize handles); shapes also expose
**green dots** for form-specific properties (curve, number of points, proportions) — [Apple: Add shapes](https://support.apple.com/guide/ipad/add-shapes-lines-and-arrows-ipadb96d65cb/27/ipados/27). Text boxes use a **green dot** to resize box *and* text
together — [Apple: Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27). Multi-selection draws a thin blue outline around *each* item (not one big box) plus an overall selection frame — visible in [Screenshot: Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27).

**Rotation.** Two-finger rotate on the object; no rotation handle and no snapping to 15° increments documented — [Apple: Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27). Angle-snap behaviour is
**UNCONFIRMED**.

**Resizing.** Blue dots scale freely; text boxes have the green "scale text too" dot; images can be constrained to aspect ratio from the `…` menu —
[Apple: Add images and files](https://support.apple.com/guide/ipad/add-images-scans-links-and-other-files-ipada82c9eff/27/ipados/27) and [MacStories](https://www.macstories.net/reviews/freeform-leverages-the-freedom-and-flexibility-of-a-blank-canvas/).

**Floating contextual bar.** Apple's screenshot of a multi-selection shows a rounded pill floating directly **below** the selection, with a small
pointer notch, containing in this order: `[Arrange] | [Duplicate] [Delete] [… More]` — [Screenshot: Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27). Tapping **Arrange** expands an `ALIGN` panel underneath with eight alignment/distribution buttons in
two rows plus a `Group` button (same screenshot). This is the single most Freeform-specific piece of UI to copy.

**`… More` menu contents** (aggregated from Apple's iPad pages):
- `Style` → Copy Style / Paste Style / Save as Insert Style — [Apple: Apply consistent styles](https://support.apple.com/guide/ipad/apply-consistent-styles-ipad578fa0d8/27/ipados/27)
- `Lock` — [Apple: Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27)
- `Back` / `Front` (layering) — same page.
- `Add Connection Line` (when 2+ items are selected) — [Apple: Add diagrams](https://support.apple.com/guide/ipad/add-diagrams-ipad06d8aa1d/27/ipados/27)
- `Mask with Shape`, `Replace`, `Remove Background`, `Add to Playground` (images) — [Apple: Add images and files](https://support.apple.com/guide/ipad/add-images-scans-links-and-other-files-ipada82c9eff/27/ipados/27)
- `Change Shape`, `Break Apart`, `Combine Shapes` (unite/intersect/subtract/exclude) — [Apple: Add shapes](https://support.apple.com/guide/ipad/add-shapes-lines-and-arrows-ipadb96d65cb/27/ipados/27)
- `Description` (accessibility text for media) — [MacStories](https://www.macstories.net/reviews/freeform-leverages-the-freedom-and-flexibility-of-a-blank-canvas/). Mac mirrors these with a right-click/three-dot menu and richer names (`Bring Forward`, `Send Backward`, `Group`, `Ungroup`) — [Apple: Arrange items (Mac)](https://support.apple.com/guide/freeform/frfm6cb2dcdd/5.0/mac/27).

**Object-specific formatting tools** (the row above the `…`, varies by type):
- Sticky note: **Fill** (colour) + **Text inspector** (font style, size, alignment, list style) — [Apple: Add a sticky note (Mac)](https://support.apple.com/guide/freeform/frfm6b59871e/5.0/mac/27).
- Shape/line: fill colour, border type/thickness/colour, text formatting, line endpoints/arrowheads, connection-line type (straight/cornered/curved) —
  [Apple: Add shapes](https://support.apple.com/guide/ipad/add-shapes-lines-and-arrows-ipadb96d65cb/27/ipados/27).
- Text box: font, colour, size, alignment, lists, indentation — [Apple: Add text](https://support.apple.com/guide/ipad/add-text-ipad5a22ec43/27/ipados/27).
- Drawing: the full drawing palette returns while a stroke is selected (see §5).
- Image: crop/mask, shadow, rounded corners, aspect lock, replace — [Apple: Add images and files](https://support.apple.com/guide/ipad/add-images-scans-links-and-other-files-ipada82c9eff/27/ipados/27).

**Duplicate.** `Duplicate` in the selection bar (screenshot above); XDA describes duplicating whole boards from the library — [XDA](https://www.xda-developers.com/apple-freeform-app-guide/). On Mac, Option+arrow
duplicates to the side, suggesting a consistent "duplicate with offset" model — [Apple: Keyboard shortcuts (Mac)](https://support.apple.com/guide/freeform/frfm46c25187e/5.0/mac/27). iPad offset distance/animation: **UNCONFIRMED**.

**Lock.** `… > Lock` — "lock it so you don't inadvertently move, modify, or delete it" — [Apple: Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27).

**Layering.** `… > Back` / `Front` on iPad (same page). Mac exposes the full four-level model: Bring Forward / Bring to Front / Send Backward / Send to Back —
[Apple: Arrange items](https://support.apple.com/guide/freeform/frfm6cb2dcdd/5.0/mac/27).

**Group.** Available from the Arrange panel and via ⌥⌘G; groups move/rotate/resize as one unit, and individual members can still be formatted by
double-clicking them — [Apple: Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27), [Apple: Arrange items](https://support.apple.com/guide/freeform/frfm6cb2dcdd/5.0/mac/27). Some types (3D objects) cannot be grouped.

**Snapping / alignment guides.** Three guide types, on by default and toggled in `Settings > Apps > Freeform` or `… > Alignment Settings`: **Center Guides** (midpoints align), **Edge Guides**
(edges align), **Spacing Guides** (three or more items equally spaced) — [Apple: settings page](https://support.apple.com/guide/ipad/change-freeform-settings-ipadcb84e16e/27/ipados/27). Guides "appear as you drag an item on a board and it aligns with another
item" (same page); MacStories shows them as thin lines through the dragged object — [MacStories](https://www.macstories.net/reviews/freeform-leverages-the-freedom-and-flexibility-of-a-blank-canvas/).

---

## 4. Object types

| Type | What it is | Notes that matter for a clone |
|---|---|---|
| **Sticky note** | Square note with a 3D curled corner, **7 colours**, default yellow | [MacStories](https://www.macstories.net/reviews/freeform-leverages-the-freedom-and-flexibility-of-a-blank-canvas/), [XDA](https://www.xda-developers.com/apple-freeform-app-guide/). Typed text, not ink. Font is auto-set per note; auto-shrink with content is **UNCONFIRMED**. A 2026 review notes the current version adds "a slight shadow that makes them feel like real paper notes floating above the board" — [Paperless X](https://beingpaperless.com/apple-freeform-in-ipados-26-review/) |
| **Shape** | "Hundreds" of shapes; **700+** at launch, in **16 categories** (Basic, Geometry, Objects, Animals, Nature, Food, Symbols, Education, Arts, Science, People, Places, Activities, Transportation, Work, Ornaments) plus Search | [Apple Newsroom](https://www.apple.com/newsroom/2022/12/apple-launches-freeform-a-powerful-new-app-designed-for-creative-collaboration/) gives 700+; [XDA](https://www.xda-developers.com/apple-freeform-app-guide/) lists the 16 categories. Splittable (`Break Apart`), combinable (unite/intersect/subtract/exclude) — [Apple](https://support.apple.com/guide/ipad/add-shapes-lines-and-arrows-ipadb96d65cb/27/ipados/27) |
| **Text box** | Free text with rich formatting; green dot scales box + text | [Apple: Add text](https://support.apple.com/guide/ipad/add-text-ipad5a22ec43/27/ipados/27), [Apple: Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27) |
| **Drawing** | Ink object with its own palette; strokes are **grouped** into one object on exit | [Apple: Draw or handwrite](https://support.apple.com/guide/ipad/draw-or-handwrite-ipadf825a0bd/27/ipados/27) |
| **Image / video / scan** | Photos, camera, document scans (multi-page PDF card), stickers, generated images | [Apple: Add images](https://support.apple.com/guide/ipad/add-images-scans-links-and-other-files-ipada82c9eff/27/ipados/27) |
| **Connector / diagram** | Drag a connector arrow from an item, drop to get a shape picker and auto-connected next node; endpoints snap to centre/top/bottom/sides, with a filled-circle "connection possible" affordance | [Apple: Add diagrams](https://support.apple.com/guide/ipad/add-diagrams-ipad06d8aa1d/27/ipados/27) |
| **Table** | Real table object (own toolbar button since iPadOS 18) | [Apple: Add tables](https://support.apple.com/guide/ipad/add-tables-ipada5598b90/27/ipados/27) |
| **Link** | Rich link card (web page, Maps place, or collaborative iWork doc) | [Apple: Add images and files](https://support.apple.com/guide/ipad/add-images-scans-links-and-other-files-ipada82c9eff/27/ipados/27) |
| **File** | Any file type, inserted as a **copy**; previews inline | [Apple: same page](https://support.apple.com/guide/ipad/add-images-scans-links-and-other-files-ipada82c9eff/27/ipados/27); copy-semantics caveat in [MacStories](https://www.macstories.net/reviews/freeform-leverages-the-freedom-and-flexibility-of-a-blank-canvas/) |

**Which matter most.** For a personal handwriting whiteboard, in order: **drawing**, **sticky note**, **text box**, **shape (a dozen basics +
line/arrow)**, **connector**. Tables, files, links, 3D objects and Image Playground are all skippable.

---

## 5. Toolbar layout

Apple redesigned the iPad toolbar into floating translucent pills in the iPadOS 26 cycle. The current layout, read from Apple's own screenshot ([Draw or handwrite](https://support.apple.com/guide/ipad/draw-or-handwrite-ipadf825a0bd/27/ipados/27),
[Position items](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27)):

**Top bar, left pill**
1. `<` Back (to All Boards)
2. Board title + chevron (tap the title to rename, or `More > Rename`) — [Apple: Create a board](https://support.apple.com/guide/ipad/create-a-freeform-board-ipade453ddaa/27/ipados/27)

**Top bar, centre insert pill (left → right)**
1. **Drawing / handwriting tools** (pen-in-a-circle glyph; ring-highlighted while active)
2. **Text box** (`A` in a dashed frame)
3. **Shapes** (overlapping rounded square + circle)
4. **Sticky note** (card with lines)
5. **Table** (3×3 grid)
6. **Attach** (paperclip) → photos, video, scan, link, files — [Apple: Add images and files](https://support.apple.com/guide/ipad/add-images-scans-links-and-other-files-ipada82c9eff/27/ipados/27)

Ordering changed over time: the launch build was **Pen, Note, Shapes, Text, Attachment**, then Undo, Share and New board — [XDA](https://www.xda-developers.com/apple-freeform-app-guide/), corroborated by [MacStories](https://www.macstories.net/reviews/freeform-leverages-the-freedom-and-flexibility-of-a-blank-canvas/).
Current build puts Text and Shapes before the sticky note and adds Table.

**Top bar, right pill**
1. **Undo** (curved arrow; hover/hold reveals Redo — [XDA](https://www.xda-developers.com/apple-freeform-app-guide/))
2. **Collaborator avatar + count**
3. **Share** (box with up arrow)
4. **`…` More**
5. A separate round button at the far right (glyph: framed square with a pencil). Its function is **UNCONFIRMED** in the pages reviewed; it is *not*
   the sidebar or share control. Treat as board-options/scenes-class affordance.

**Bottom-left pill**
- **Zoom percentage** (`56 %`, `91 %` in Apple's screenshots) plus one adjacent button.
- Apple says the **Scene Navigator opens at the bottom-left** when you tap the scenes control — [Apple: Scenes](https://support.apple.com/guide/ipad/navigate-and-present-scenes-ipad9c7aadac/27/ipados/27). Which glyph is scenes vs. zoom-menu is
  **UNCONFIRMED**; both live here.

**Bottom-right pill**
- **Connector tool** — "In full-screen view: tap the [connector] in the lower-right corner" — [Apple: Add diagrams](https://support.apple.com/guide/ipad/add-diagrams-ipad06d8aa1d/27/ipados/27).
- **Dot-grid toggle** — dotted-square glyph, same corner ([Apple: settings](https://support.apple.com/guide/ipad/change-freeform-settings-ipadcb84e16e/27/ipados/27)).

**Drawing palette** (floats bottom-centre while drawing mode is on; same pill language):

`[undo] [redo]` then a nib carousel, then the brush colophon of swatches.

- Apple names these tools: **Marker, Pen, Highlighter, Pencil, Crayon, Fountain Pen, Watercolor Brush** (screenshot caption) plus **Fill**, **Reed
  Pen**, **Eraser**, **Lasso**, **Ruler**, **Scribble** ([Apple: Draw or handwrite](https://support.apple.com/guide/ipad/draw-or-handwrite-ipadf825a0bd/27/ipados/27)).
- Tools render as photoreal 3D nibs, not flat glyphs — screenshot caption "Some Freeform drawing tools and their strokes: Marker, Pen, Highlighter,
  Pencil, Crayon, Fountain Pen, and Watercolor Brush" (same page).
- **Lasso sits between Eraser and Ruler**; Fill is the paint-tube; Ruler is rotated by placing two fingers on it (same page).
- Tap a tool a **second time** to open thickness / opacity / angle controls (same page); Reed Pen gained adjustable stroke angle in iPadOS 26 — [Paperless X](https://beingpaperless.com/apple-freeform-in-ipados-26-review/).
- Colour wells: six presets (black, blue, green, yellow, red, multicolour picker) plus a `…` for the full picker — [Screenshot: Draw or handwrite](https://support.apple.com/guide/ipad/draw-or-handwrite-ipadf825a0bd/27/ipados/27).
- **PencilKit:** the tool set is "identical to the one in Apple Notes", including the image-wand omission — [Paperless X](https://beingpaperless.com/apple-freeform-in-ipados-26-review/). Whether Freeform literally embeds `PKToolPicker`
  is **UNCONFIRMED** (Apple does not say), but the behaviour, tool names and picker layout match it exactly; building on PencilKit is the faithful
  choice.

---

## 6. Animations & feel

Apple publishes no motion spec for Freeform; every specific timing/curve below that isn't cited is **UNCONFIRMED**. What is verifiable:

- **Insertion point.** New objects are inserted into the current viewport and selected immediately, with their formatting tools up — implied by every
  "tap a tool, then edit" flow ([Apple: Add text](https://support.apple.com/guide/ipad/add-text-ipad5a22ec43/27/ipados/27)). Exact placement (centre vs. offset) and any insert animation are **UNCONFIRMED**.
- **Sticky note material.** 3D curled corner + soft shadow, described as feeling "like real paper notes floating above the board" — [MacStories](https://www.macstories.net/reviews/freeform-leverages-the-freedom-and-flexibility-of-a-blank-canvas/), [Paperless X](https://beingpaperless.com/apple-freeform-in-ipados-26-review/). The
  *depth* (shadow, slight perspective) is doing more of the "feel" work than any animation.
- **Selection.** Static chrome: 1 px blue outline, round blue 44-ish pt-equivalent handles, and the floating bar attached below with a pointer notch
  ([Screenshot](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27)). Whether the bar springs in or fades is **UNCONFIRMED**.
- **Zoom.** Continuous under pinch; preset jumps (`tap % → tap a percent`) and *Zoom to Fit* / *Zoom to Selection* are discrete transitions — [Apple: Create a board](https://support.apple.com/guide/ipad/create-a-freeform-board-ipade453ddaa/27/ipados/27), [Apple: appearance (Mac)](https://support.apple.com/guide/freeform/frfm000074a4e/5.0/mac/27). Whether those
  transitions animate, and with what curve, is **UNCONFIRMED**.
- **Zoom-to-object / scenes.** Switching scenes moves the viewport to a saved framing — [Apple: Scenes](https://support.apple.com/guide/ipad/navigate-and-present-scenes-ipad9c7aadac/27/ipados/27). Apple documents the *what*, not the *how*; spring vs.
  ease is **UNCONFIRMED**.
- **Bounce / spring.** No Apple or review source describes spring physics, overshoot or bounce anywhere in Freeform. **UNCONFIRMED — do not claim
  it.**
- **Performance ceiling.** Large boards become laggy while scrolling/zooming; the app "starts to slow down — noticeably" — [Paperless X](https://beingpaperless.com/apple-freeform-in-ipados-26-review/). Useful warning for a
  from-scratch canvas renderer.

Practical read: Freeform's "feel" comes from *directness* (everything is under the finger, nothing modal), *material softness* (shadows, translucent
pills, curled notes), and *continuous zoom*, not from a signature spring animation.

---

## 7. Board library

**Structure.** Sidebar sections: **All Boards, Recents, Shared, Favorites**, and **Recently Deleted** once something is deleted — [MacStories](https://www.macstories.net/reviews/freeform-leverages-the-freedom-and-flexibility-of-a-blank-canvas/), [XDA](https://www.xda-developers.com/apple-freeform-app-guide/). Recently
Deleted keeps boards for **30 days** before permanent deletion (XDA).

**Grid vs list.** "Tap [grid] or [list] to switch between grid and list view" — [Apple: settings page](https://support.apple.com/guide/ipad/change-freeform-settings-ipadcb84e16e/27/ipados/27). Grid = thumbnails, list = rows with name/date. Both are supported
in every section.

**Thumbnails.** Board thumbnails are miniature renders of board content, shown in the grid and in Apple's own screenshots ("board thumbnails appear on
the right") — [Apple: Create a board](https://support.apple.com/guide/ipad/create-a-freeform-board-ipade453ddaa/27/ipados/27). Refresh cadence (live vs. on-close) is **UNCONFIRMED**.

**Sorting.** `Sort by Date`, `Sort by Name`, `Sort by Kind`, `Sort by Shared By`, each with an ascending/descending toggle; `Sort by Date > Use Groups` buckets by "how long ago they were last opened", and Shared can group
by owner — [Apple: settings page](https://support.apple.com/guide/ipad/change-freeform-settings-ipadcb84e16e/27/ipados/27). Default is date (most recently updated) — MacStories shows boards "grouped by date".

**Rename.** In a board: tap `Untitled` in the top-left, then `Rename`; in a windowed board it's `More > Rename` — [Apple: Create a board](https://support.apple.com/guide/ipad/create-a-freeform-board-ipade453ddaa/27/ipados/27). From the library: touch and hold the thumbnail/name,
then `Rename` ([XDA](https://www.xda-developers.com/apple-freeform-app-guide/)).

**Favourite.** Touch and hold a board → `Favorite`; while in a board → `More > Favorite` — [Apple: Create a board](https://support.apple.com/guide/ipad/create-a-freeform-board-ipade453ddaa/27/ipados/27). Favourites surface in the Favorites section of the sidebar (MacStories).

**Duplicate.** `Select` mode or touch-and-hold → `Duplicate`; duplicates of shared boards are not shared — [Apple: Create a board](https://support.apple.com/guide/ipad/create-a-freeform-board-ipade453ddaa/27/ipados/27).

**Recents.** A separate section, not merely a sort — "This section includes a list of boards you've recently created or modified" — [XDA](https://www.xda-developers.com/apple-freeform-app-guide/).

**Search.** Toolbar search returns hits from board names and board text; iPadOS 18+ extends this to **handwriting** — [Apple: Search your boards](https://support.apple.com/guide/freeform/frfm18ab658ed/5.0/mac/27), [Paperless X](https://beingpaperless.com/apple-freeform-in-ipados-26-review/). It does **not** search
inside embedded files or text in images — [MacStories](https://www.macstories.net/reviews/freeform-leverages-the-freedom-and-flexibility-of-a-blank-canvas/).

---

## 8. Simplest faithful subset

Ranked by feel-per-unit-of-work for a personal handwriting app. Ten features, in build order.

1. **Infinite canvas + pinch zoom + one-finger pan.** 10 %–400 %, opening at 100 %. Without this nothing else reads as Freeform. ([Apple](https://support.apple.com/guide/ipad/create-a-freeform-board-ipade453ddaa/27/ipados/27), [XDA](https://www.xda-developers.com/apple-freeform-app-guide/))
2. **Zoom % readout (bottom-left) with preset menu + Zoom to Fit.** The readout is the single cheapest "this is a real canvas app" signal. ([Apple](https://support.apple.com/guide/ipad/create-a-freeform-board-ipade453ddaa/27/ipados/27))
3. **Pencil always inks; `Select and Scroll` toggle in Settings.** Removes modality anxiety and is the core of Freeform's Pencil feel. ([Apple](https://support.apple.com/guide/ipad/draw-or-handwrite-ipadf825a0bd/27/ipados/27))
4. **Selection bar below the object: Arrange | Duplicate | Delete | More**, with the notch and the expanding ALIGN panel (8 buttons + Group).
   Highest-visual-signature control in the app. ([Screenshot](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27))
5. **Sticky note object** — square, 7 colours, curled corner + shadow, tap-to-type. The most recognisable object type. ([MacStories](https://www.macstories.net/reviews/freeform-leverages-the-freedom-and-flexibility-of-a-blank-canvas/))
6. **PencilKit drawing palette with photoreal nibs** — pen, pencil, marker, crayon, highlighter, eraser, lasso, ruler, 6 swatches + picker, undo/redo.
   Free fidelity if you use `PKToolPicker`. ([Apple](https://support.apple.com/guide/ipad/draw-or-handwrite-ipadf825a0bd/27/ipados/27))
7. **Blue-dot handles + two-finger rotate + green dot for text scaling.** Direct manipulation with zero tool switching. ([Apple](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27))
8. **Dot-grid toggle (bottom-right) + Snap to Grid + centre/edge guides.** Turns a scribble board into a tidy one. ([Apple](https://support.apple.com/guide/ipad/change-freeform-settings-ipadcb84e16e/27/ipados/27))
9. **`More` menu with Lock + Back/Front + Duplicate.** Minimal layering and safety, one sheet. ([Apple](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27))
10. **Board library: grid + list, thumbnails, sort by date/name, rename, favourites.** Even a personal app needs a front door. ([Apple](https://support.apple.com/guide/ipad/create-a-freeform-board-ipade453ddaa/27/ipados/27))

Deliberately skipped: connectors/diagrams, tables, files, links, scenes, collaboration, shape library beyond ~12 basics, export. Each adds surface
area without adding felt Freeform-ness.

If you add one more: **press-and-hold marquee** (`touch and hold canvas → drag`) rather than drag-to-marquee, because it keeps one-finger pan intact and is what Freeform
actually does. ([Apple](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27))

---

## 9. Source list

Apple documentation (iPad User Guide, iPadOS 27 revision):
- [Get started with Freeform](https://support.apple.com/guide/ipad/get-started-with-freeform-ipad9c59637d/27/ipados/27)
- [Create a Freeform board](https://support.apple.com/guide/ipad/create-a-freeform-board-ipade453ddaa/27/ipados/27)
- [Draw or handwrite](https://support.apple.com/guide/ipad/draw-or-handwrite-ipadf825a0bd/27/ipados/27)
- [Add text](https://support.apple.com/guide/ipad/add-text-ipad5a22ec43/27/ipados/27)
- [Add shapes, lines, and arrows](https://support.apple.com/guide/ipad/add-shapes-lines-and-arrows-ipadb96d65cb/27/ipados/27)
- [Add diagrams](https://support.apple.com/guide/ipad/add-diagrams-ipad06d8aa1d/27/ipados/27)
- [Add tables](https://support.apple.com/guide/ipad/add-tables-ipada5598b90/27/ipados/27)
- [Add images, scans, links, and other files](https://support.apple.com/guide/ipad/add-images-scans-links-and-other-files-ipada82c9eff/27/ipados/27)
- [Apply consistent styles](https://support.apple.com/guide/ipad/apply-consistent-styles-ipad578fa0d8/27/ipados/27)
- [Position items on a board](https://support.apple.com/guide/ipad/position-items-on-a-board-ipad0b4f22b0/27/ipados/27)
- [Navigate and present scenes](https://support.apple.com/guide/ipad/navigate-and-present-scenes-ipad9c7aadac/27/ipados/27)
- [Change your Freeform settings](https://support.apple.com/guide/ipad/change-freeform-settings-ipadcb84e16e/27/ipados/27)
- [Use keyboard shortcuts](https://support.apple.com/guide/ipad/use-keyboard-shortcuts-ipad6ff38700/27/ipados/27)
- [Change Apple Pencil double tap and squeeze settings](https://support.apple.com/guide/ipad/adjust-double-tap-squeeze-settings-apple-ipad63913965/27/ipados/27)

Apple documentation (Freeform User Guide, macOS 27 revision):
- [Change a board's appearance](https://support.apple.com/guide/freeform/frfm000074a4e/5.0/mac/27)
- [Arrange items](https://support.apple.com/guide/freeform/frfm6cb2dcdd/5.0/mac/27)
- [Add a sticky note](https://support.apple.com/guide/freeform/frfm6b59871e/5.0/mac/27)
- [Search your boards](https://support.apple.com/guide/freeform/frfm18ab658ed/5.0/mac/27)
- [Keyboard shortcuts and gestures](https://support.apple.com/guide/freeform/frfm46c25187e/5.0/mac/27)

Apple Newsroom and press:
- [Apple launches Freeform (13 Dec 2022)](https://www.apple.com/newsroom/2022/12/apple-launches-freeform-a-powerful-new-app-designed-for-creative-collaboration/)

Reviews:
- [MacStories — Freeform Leverages the Freedom and Flexibility of a Blank Canvas](https://www.macstories.net/reviews/freeform-leverages-the-freedom-and-flexibility-of-a-blank-canvas/)
- [XDA — Complete guide to Freeform](https://www.xda-developers.com/apple-freeform-app-guide/)
- [Paperless X — Apple Freeform in iPadOS 26 (review)](https://beingpaperless.com/apple-freeform-in-ipados-26-review/)
- [9to5Mac — gestures for undo/copy/paste](https://9to5mac.com/2019/06/12/gestures-undo-ios-iphone-ipad/)

### Known gaps (all UNCONFIRMED)
1. The preset zoom percentages offered by the bottom-left readout.
2. Dot-grid spacing and whether it re-scales with zoom.
3. Exact insert placement/animation, and selection-bar appear animation.
4. Any spring/bounce behaviour anywhere in the app.
5. Sticky-note font auto-shrink rule.
6. Whether the drawing palette is literally `PKToolPicker`.
7. The far-right top-bar round button's function.
