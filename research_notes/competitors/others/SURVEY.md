# Survey: other handwriting and notes apps — distinctive ideas for NOTEAPP

Scope: apps other than Goodnotes, Notability and Noteshelf. Pages were read on **12 November 2026**. Every app row cites the page it came from; anything I could not confirm is in **Unverified** rather than guessed. "Idea for NOTEAPP" is my synthesis, not a vendor claim.

Bias of this survey: not feature parity, but **small settings and micro-interactions** that change daily writing. Several apps here are much older or much more complex than what we are building; I have tried to separate the idea from the implementation.

---

## Sources

**Primary (vendor docs, help centres, manuals)**

- MyScript Notes (formerly Nebo): https://www.myscript.com/notes/ · https://help.myscript.com/notes/edit-content/pen-gestures-and-interactions/ · https://help.myscript.com/notes/customize-content/settings/ · https://help.myscript.com/notes/edit-content/erase-and-undo-redo/ · https://help.myscript.com/notes/create-content/adjust-zoom-and-space/ · https://help.myscript.com/notes/edit-content/select-copy-and-paste/ · https://help.myscript.com/notes/overview/handwriting/ · https://help.myscript.com/notes/versions/ios/
- Flexcil: https://www.flexcil.com/ · https://support.flexcil.com/hc/en-us/articles/6640732898713-Gesture-features-list · https://support.flexcil.com/hc/en-us/articles/8427582550553-What-is-a-Reference-Link · https://support.flexcil.com/hc/en-us/articles/8131456080025-Pen-mode-and-Gesture-mode · https://support.flexcil.com/hc/en-us/articles/41237047472409-Using-a-masking-pen · https://support.flexcil.com/hc/en-us/articles/40143824842777-Custom-Pen-Toolbar-Guide · https://support.flexcil.com/hc/en-us/articles/8270521456793-How-to-operate-the-pop-up-viewer
- CollaNote: https://collanote.com/ · https://collanote.com/help/free-and-premium · https://collanote.com/help/arc-menu · https://collanote.com/help/eraser-options · https://collanote.com/help/palm-rejection · https://collanote.com/help/audio-recording · https://collanote.com/news/collanote-5-0-new-ui-powerful-rulers-and-global-note-sharing-community · https://apps.apple.com/us/app/collanote-notes-pdf-markup/id1540956268
- ZoomNotes: http://www.zoom-notes.com/ · http://www.zoom-notes.com/Documents/ZoomNotes7.5.pdf (81-page manual) · https://beingpaperless.com/12-features-that-make-zoomnotes-the-ultimate-note-taking-app/
- Notewise: https://notewise.dev/post/notewise-4.0-frontline-features · https://apps.apple.com/us/app/notewise-ai-notes-pdf-docs/id6480045936
- Penbook: https://penbook.app/ · https://apps.apple.com/us/app/penbook-paper-planner-notes/id1473064295
- Microsoft OneNote (iPad): https://support.microsoft.com/en-us/onenote/onenote-for-ipad-or-iphone-help-and-learning/handwrite-draw-and-sketch-in-onenote-for-ipad-or-iphone · https://support.microsoft.com/en-us/onenote/onenote-for-ipad-or-iphone-help-and-learning/select-a-drawing-mode-in-onenote-for-ipad-or-iphone · https://support.microsoft.com/en-us/onenote/onenote-help-and-learning/ink-faster-with-gestures-for-creating-shapes-deleting-ink-and-more · https://support.microsoft.com/en-us/topic/62d3516d-ce5e-4d97-bc3d-5569810161d0 (Ink Replay) · https://support.microsoft.com/en-us/onenote/onenote-help-and-learning/draw-and-sketch-notes-in-onenote
- Apple Notes, Freeform, Apple Pencil (iPad User Guide, iPadOS 27): https://support.apple.com/en-lk/guide/ipad/ipada87a6078/ipados (drawings and handwriting in Notes) · https://support.apple.com/en-lk/guide/ipad/ipad10f28bec/ipados (Math Notes) · https://support.apple.com/en-lk/guide/ipad/ipadf825a0bd/ipados (Freeform draw) · https://support.apple.com/en-lk/guide/ipad/ipadcb84e16e/ipados (Freeform settings) · https://support.apple.com/en-lk/guide/ipad/ipad9c7aadac/ipados (Freeform scenes) · https://support.apple.com/en-lk/guide/ipad/ipad6350b8dc/ipados (Markup tools) · https://support.apple.com/en-lk/guide/ipad/ipadc55b6c7a/ipados (Draw with Apple Pencil)
- Samsung Notes: https://www.samsung.com/us/support/answer/ANS10003634/
- reMarkable: https://support.remarkable.com/articles/Knowledge/Toolbar · https://support.remarkable.com/s/article/Writing-tools

**Secondary (reviews and hands-on)**

- Paperlike, "Best Note-Taking Apps for iPad in 2027", first published 1 Jul 2026, updated 4 Nov 2026: https://paperlike.com/blogs/paperlikers-insights/best-note-taking-apps-ipad
- MacStories, "iPadOS 18's Smart Script: A Promising Start…" (John Voorhees): https://www.macstories.net/stories/ipados-18s-smart-script-a-promising-start-but-dont-toss-your-keyboard-out-yet/
- Paperless X, "12 features that make ZoomNotes the best note-taking app": https://beingpaperless.com/12-features-that-make-zoomnotes-the-ultimate-note-taking-app/

---

## MyScript Notes (Nebo)

Formerly Nebo on iOS/Android; renamed September 2025. The pitch is Interactive Ink: handwriting stays editable and convertible, with gestures instead of tool switching. https://help.myscript.com/notes/versions/ios/

| Feature/setting | How it works | Idea for NOTEAPP | Source |
|---|---|---|---|
| Four note formats | Notebook (fixed-size pages, covers, paper colour/pattern), Document (reflowing content), Board (expandable canvas), PDF import/annotation. | Do not make every note one canvas type. Offer a page notebook and an expandable board, and make conversion to text a per-format capability. | https://www.myscript.com/notes/ |
| Pen gesture vocabulary | Scratch out to erase; draw an upward line to join words/lines; downward line to break; single or double underline; strike through; frame text to highlight. | Ship joins/splits as gestures on a text-line level, not as a separate "handwriting edit" mode. | https://help.myscript.com/notes/edit-content/pen-gestures-and-interactions/ |
| Gesture behaviour is configurable per note format | Settings > Interactions: for board, document and PDF separately, strike-through can display a strike, erase content, or do nothing; underline can display underlined, bold, or nothing. | Expose per-surface gesture semantics. Users hate a gesture that "does the wrong thing" in PDFs specifically. | https://help.myscript.com/notes/customize-content/settings/ |
| Conversion preview | Documents show how handwriting will convert; if wrong, tap the preview and pick another reading. Can be disabled in Settings > Writing. | A non-modal "I read this as…" strip is cheaper than a full convert-and-undo cycle. | https://help.myscript.com/notes/customize-content/settings/ |
| Learn word | Select a word, tap Learn to add it to the personal dictionary so future recognition gets it right. | Put "Add to dictionary" in the selection dock. It turns a repeated annoyance into one tap. | https://help.myscript.com/notes/versions/ios/ · https://help.myscript.com/notes/customize-content/user-dictionary/ |
| Writing position | Settings > Pen > Writing position: choose the posture that resembles yours (used to tune recognition). | A cheap calibration screen. Also useful later for palm rejection and stroke prediction. | https://help.myscript.com/notes/customize-content/settings/ |
| Active vs passive pen | Settings > Pen > Use active pen. Finger input works; active pen recommended. | Keep an explicit "finger draws" switch rather than silently accepting every touch. | https://help.myscript.com/notes/customize-content/settings/ |
| Two-finger undo, three-finger redo | On iOS, two fingers tap the note to undo, three to redo, alongside toolbar arrows. | Add the system-standard multi-finger undo/redo and make it work while the Pencil is down. | https://help.myscript.com/notes/edit-content/erase-and-undo-redo/ |
| Eraser types | Double-tap eraser icon: Stroke or Precise, then set width. | Two eraser semantics only. "Precise" means area erasing that leaves neighbouring ink, not a smaller circle. | https://help.myscript.com/notes/edit-content/erase-and-undo-redo/ |
| Lasso options | Double-tap lasso: Freehand or Rectangle. Single tap selects converted content; `Copy as…` gives text, math or diagram. | Rectangle lasso is the fast path for text blocks; freehand for drawings. Do not make users choose in settings. | https://help.myscript.com/notes/edit-content/select-copy-and-paste/ |
| Zoom chip | Zoom level always visible (bottom-left for right-handed, bottom-right for left-handed); tap resets to 100%; lock icon locks the level; zoom saved for 30 days of inactivity. | Copy this exactly. It is a one-line affordance with outsized confidence benefit. | https://help.myscript.com/notes/create-content/adjust-zoom-and-space/ · https://help.myscript.com/notes/versions/ios/ |
| Adjust space | Two-finger long press between elements shows a blue line; drag down to add space, up to remove. Long press empty area > Adjust space. | Needed for any page-based notebook where inserts push handwriting down. Hard part is reflowing strokes and PDFs. | https://help.myscript.com/notes/create-content/adjust-zoom-and-space/ |
| Highlighter modes | "Freehand" keeps a hand-drawn stroke; "smart" auto-aligns with text; a "No fill" colour removes existing smart highlights; eraser removes freehand highlights. | Smart align for text, freehand for drawings, and a visible way to remove a highlight without erasing ink. | https://help.myscript.com/notes/versions/ios/ |
| Pencil palette and input | Version 6.1: squeeze or double-tap Pencil to open a palette for tool, thickness and colour. Version 6.5: haptic feedback, hover and pressure sensitivity. | The palette should open where the Pencil is, then close on first stroke. | https://help.myscript.com/notes/versions/ios/ |
| Ruler and laser | Ruler (7.2) drags, rotates and snaps into place, at any angle; units cm/inches. Laser pointer (7.1) leaves no marks. | Ruler with rotate-and-snap is table stakes for diagrams; laser is a presentation-only tool. | https://help.myscript.com/notes/versions/ios/ · https://help.myscript.com/notes/customize-content/settings/ |
| Selection action dock | App Store screenshot shows a horizontal dock under the selection: Cut, Copy, Copy as…, Delete, AI, Convert, Resize. | Anchored, text-labelled actions beat icon-only toolbars for first-time users. | https://apps.apple.com/us/app/nebo-notes-pdf-annotations/id1119601770 |

---

## Flexcil

A PDF-first study app. The core idea is a **gesture mode** that turns the Pencil into a markup device without a toolbar, plus links from notes back to the source page.

| Feature/setting | How it works | Idea for NOTEAPP | Source |
|---|---|---|---|
| Pen mode vs Gesture mode | The far-left icon of the pen toolbar toggles between pen/highlighter markup and gesture-driven selection. | A single, always-visible mode switch is clearer than overloading every gesture in one mode. | https://support.flexcil.com/hc/en-us/articles/8131456080025-Pen-mode-and-Gesture-mode |
| Gesture vocabulary | Underline selects text; parentheses select a range; small and large circles select words/phrases; long-press drag selects; L and square capture document regions; there is a dedicated eraser gesture. | Underline-to-select on PDFs is the standout: it matches how people already mark text. | https://support.flexcil.com/hc/en-us/articles/6640732898713-Gesture-features-list |
| Reference links | Drag a selected document region or text into a note; the pasted copy gets a link icon that jumps back to the source location. | Excerpts should carry provenance. A note assembled from three PDFs should be able to show where each block came from. | https://support.flexcil.com/hc/en-us/articles/8427582550553-What-is-a-Reference-Link |
| Pop-up viewer | Swipe up with three fingers (or toolbar icon) to open a second document over the current one; swipe down to close; three-finger pinch resizes if enabled in Document Viewer settings; drag a tab between viewers. | A floating second page is better than splitting the screen for quick look-ups. The three-finger vocabulary is discoverable once taught. | https://support.flexcil.com/hc/en-us/articles/8270521456793-How-to-operate-the-pop-up-viewer |
| Masking pen | Drag tape over answers to hide them. Tapping the tape opens a correct/incorrect pop-up; answers can be sorted by accuracy or page order; masking can be hidden with a T icon. | A "study mode" layer that hides chosen regions and records recall results, without turning the notebook into flashcards. | https://support.flexcil.com/hc/en-us/articles/41237047472409-Using-a-masking-pen |
| Masking via gestures | Underline or parenthesis gestures can create masking; holding the masking pen converts the drag into a straight line. | Reuse selection gestures to create study material; do not require a separate tool for every action. | https://support.flexcil.com/hc/en-us/articles/41237047472409-Using-a-masking-pen |
| Custom pen toolbar | Hide or show tools, drag to reorder, and set Pen Count up to 50 pens. | Power users want a wall of numbered pens; everyone else wants five. Make the count a preference. | https://support.flexcil.com/hc/en-us/articles/40143824842777-Custom-Pen-Toolbar-Guide |
| Multi-page and audio | Single, 2-page or 4-page view; audio recording syncs with handwriting; vector ink; squared/round highlighter; dotted, straight-line and fountain pens. | 2-page view for PDF study is a reading feature, not a writing feature; keep it separate from the notebook canvas. | https://www.flexcil.com/ |
| PDF structure editing | Merge PDFs; add, move, delete pages; outlines and bookmarks. | Import should not be a dead end: page management belongs in the document, not a separate app. | https://www.flexcil.com/ |

---

## CollaNote

Free, Apple-only, student-oriented, with unusually deep pen/tool customisation and a radial menu. This is the best source of "small settings" in the survey.

| Feature/setting | How it works | Idea for NOTEAPP | Source |
|---|---|---|---|
| Arc Menu | A round menu with tools, undo/redo, and the current tool's size and colour. Apple Pencil Pro: squeeze, and it opens where the tip points; squeeze again to close. Pencil 2: set Menu > Gestures > Apple Pencil Double Tap to Arc Menu; it opens mid-screen. Closes on writing, tapping the page or scrolling. | This is the single best Pencil micro-interaction in the survey. It removes the trip to the toolbar without hiding tools. | https://collanote.com/help/arc-menu |
| Eraser options | Tap Eraser twice: Whole stroke vs Partial; size 1–70; "Auto switch back to last tool"; "Scribble out to erase" with pen or pencil. | Auto-return plus scribble-out covers most erasing without a tool change. Make both independently switchable. | https://collanote.com/help/eraser-options |
| Pencil double-tap action | Menu > Gestures > Apple Pencil Double Tap can be "Switch Tool" (pen/eraser) or "Arc Menu". | Offer the two or three actions people actually use; do not ship a long list. | https://collanote.com/help/eraser-options · https://collanote.com/help/arc-menu |
| Palm rejection strength | Menu > Gestures > Palm Rejection: High, Normal, Low. Normal default; High if the hand still marks. Separately, the Hand/Stylus Toggle makes the finger scroll instead of draw. | A three-level palm setting is more honest than a binary. Pair it with a visible finger-mode toggle. | https://collanote.com/help/palm-rejection |
| Ruler family | CollaNote 5.0 added Circular Ruler, Triangle Ruler and Protractor alongside the straight ruler, for circles, triangles and measuring angles. | A protractor is cheap to add and makes the app credible for geometry students. | https://collanote.com/news/collanote-5-0-new-ui-powerful-rulers-and-global-note-sharing-community |
| Tool breadth | 50+ pens and brushes on the site; App Store says 25+; includes smart shape/diagram recognition, stabilizer, writing sounds. | Tool breadth is marketing; a stabilizer and 6 good pens are what people feel. | https://collanote.com/ · https://collanote.com/help/free-and-premium |
| Audio that follows handwriting | Record while writing; tap a word afterwards and playback jumps to the moment you wrote it, "karaoke-style"; AI transcript. Long recordings are saved in parts and joined automatically. | Audio sync should be word-level, not page-level. Word-level requires timestamped stroke groups. | https://collanote.com/ · https://collanote.com/help/audio-recording |
| Translation in the margin | Select a phrase to translate into 90+ languages in the margin; audio pronunciation without leaving the app. | Margin results keep the page intact. Avoid full-screen translation modals. | https://collanote.com/ |
| Premium writing extras | Stabilizer, writing sounds, note lock, paper colours, Curve Tool, Fill Tool, Write Beside Your PDFs, Reading Mode, Presentation Mode. | "Write beside your PDFs" is a strong differentiator for students: a pinned note pane next to the page. | https://collanote.com/help/free-and-premium |
| Mini Map and Book Reading Mode | 5.1 added a Mini Map for jumping around the canvas, and a two-page reading mode with physics-based page-turn animation (iPhone Duo). | A minimap is only needed once the canvas is large; do not add it to page notebooks. | https://apps.apple.com/us/app/collanote-notes-pdf-markup/id1540956268 |
| Community and study extras | Public rooms, shared notes on a map, flashcard decks, hyperlinked planners. | Out of scope for v1, but shared decks are a cheap content moat later. | https://collanote.com/ |

---

## ZoomNotes

The "everything app": older UI, extraordinary depth. I read the 81-page official manual, which documents behaviour in more detail than the App Store page.

| Feature/setting | How it works | Idea for NOTEAPP | Source |
|---|---|---|---|
| Infinite whiteboard mode | A per-document switch makes the page near-infinite and a single colour; page size is then only used for printing/PDF. | The reverse of our default: let a document opt into infinite, rather than making the whiteboard a separate document type. | http://www.zoom-notes.com/Documents/ZoomNotes7.5.pdf |
| Sub-documents | A page can contain a whole sequence of pages as an object: preview it, move/resize/rotate it, double-tap to zoom in; sub-documents can be bookmarked. | "Pages within pages" solves detail without a new notebook. Very strong for diagrams and appendices, but expensive. | http://www.zoom-notes.com/Documents/ZoomNotes7.5.pdf |
| Bookmarks as camera views | A bookmark stores pan/zoom/rotation plus per-bookmark transition time, group animation, and layer visibility; play them as a presentation, or export to video. | Separate "bookmark = page link" from "bookmark = saved view". Our outline can stay simple; scenes can be the presentation layer. | http://www.zoom-notes.com/Documents/ZoomNotes7.5.pdf |
| Magnification window | A magnified region at the bottom of the screen; a red box shows which page area is magnified; "Auto-advance" moves the region along the line and down to the next line when you reach the edge; margins are adjustable. | This is better than a plain zoom for small handwriting on a 13" iPad. Auto-advance is the magic. | http://www.zoom-notes.com/Documents/ZoomNotes7.5.pdf |
| Rubout with speed-scaled area | Drag to rub out; a circle shows the affected region; faster movement makes the eraser area larger. | Speed-scaled erasing feels natural but is risky; keep the indicator visible. | http://www.zoom-notes.com/Documents/ZoomNotes7.5.pdf |
| Quick zoom while drawing | Two-finger pinch during a line temporarily switches to zoom, then returns to the previous tool. | Never make users hunt for the zoom tool mid-stroke. | http://www.zoom-notes.com/Documents/ZoomNotes7.5.pdf |
| View rewind | Every view change (zoom, pan, page, bookmark) is logged; rewind and forward restore previous camera positions. | Cheap, delightful, and useful after an accidental pinch. | http://www.zoom-notes.com/Documents/ZoomNotes7.5.pdf |
| Favourite pens and custom toolbars | Save the current pen as a favourite; Side Tool Bar for pen type/colour/width; toolbar can be top or bottom, icons resized/recoloured, tools hidden. | Saved pen presets are a better answer than a colour grid for people who use the same three pens. | http://www.zoom-notes.com/Documents/ZoomNotes7.5.pdf · https://beingpaperless.com/12-features-that-make-zoomnotes-the-ultimate-note-taking-app/ |
| Per-page size and style | Every page can have its own size, orientation, background (none, lines, squares, music, isometric), colour, line spacing and margins. | Mixed page sizes in one notebook is unusual and useful for pasting handouts. | http://www.zoom-notes.com/Documents/ZoomNotes7.5.pdf |
| Tags | Documents and individual pages can be tagged with named, coloured tags; tag search filters documents/pages; tags show as coloured squares on previews. | Page-level tags are more useful than document tags for a notebook app. | http://www.zoom-notes.com/Documents/ZoomNotes7.5.pdf |
| Split view | Two documents side by side or above/below, vertical or horizontal. | Provide a true two-document pane, not just iPadOS multitasking. | http://www.zoom-notes.com/ · https://beingpaperless.com/12-features-that-make-zoomnotes-the-ultimate-note-taking-app/ |
| Highlighter behind ink | Highlighter can be drawn behind handwriting instead of over it. | A "highlight behind ink" option is a small toggle with a big visual difference. | https://beingpaperless.com/12-features-that-make-zoomnotes-the-ultimate-note-taking-app/ |
| Auto outline | The app generates an outline of pages while writing; pages can be labelled in the outline. | Auto-create an outline from page labels, rather than asking users to build one. | https://beingpaperless.com/12-features-that-make-zoomnotes-the-ultimate-note-taking-app/ |
| Pen button mapping | Wacom pen buttons can be assigned to undo, show/hide sidebar, next/previous bookmark, toggle zoom, undo zoom. | Map hardware buttons to camera and undo, not to obscure tools. | http://www.zoom-notes.com/Documents/ZoomNotes7.5.pdf |
| Calendar on planner pages | Planner pages automatically show events from the Calendar app on month/week/day pages; links can be added between pages and documents. | Live-data stationery is more compelling than static PDF planners. | http://www.zoom-notes.com/ |

---

## Notewise

AI-first, page/canvas hybrid. Less useful for writing feel, more useful for **toolbar and canvas structure** ideas. Notewise 4.0 shipped in 2026. https://notewise.dev/post/notewise-4.0-frontline-features

| Feature/setting | How it works | Idea for NOTEAPP | Source |
|---|---|---|---|
| Customisable toolbar | Choose what appears, hide what you do not use; more colours in Quick Control. | Same lesson as Flexcil: the toolbar is a user-owned surface. | https://notewise.dev/post/notewise-4.0-frontline-features |
| Connector | Link any two elements on the canvas to build diagrams and show relationships. | For the whiteboard, connectors between objects (not just strokes) are the difference between drawing and diagramming. | https://notewise.dev/post/notewise-4.0-frontline-features |
| Custom tabs over the same content | The same note can be viewed as action items, meeting minutes, decision log, Cornell notes and 20+ formats; editing a tab does not change the underlying content. | A "view" layer over notes is powerful but heavy. A lightweight version: page templates that re-present blocks, not duplicate them. | https://notewise.dev/post/notewise-4.0-frontline-features |
| AI note follows edits | A living note is generated from captures; editing source updates the note, or "suggest changes" requires approval per update. | The approval mode is the important idea: AI should propose, not silently rewrite. | https://notewise.dev/post/notewise-4.0-frontline-features |
| Media on canvas | Import docs, slides and videos; write over a video while it plays. | For lecture capture, a video object on the page with ink above it is a real workflow. | https://notewise.dev/post/notewise-4.0-frontline-features |
| Typography | 2000+ Google Fonts. | Not a priority for handwriting, but a signal that typed annotations should not be stuck with one font. | https://notewise.dev/post/notewise-4.0-frontline-features |
| Magic Select | AI selection tool included in the Starter plan. | Keep an eye on it; the interaction (select an area, ask a question) is likely to become standard. | https://notewise.dev/post/notewise-4.0-frontline-features |

---

## Penbook

A paper-planner simulator. Its distinctive idea is **Live Paper**: stationery that is generated from data rather than a static PDF.

| Feature/setting | How it works | Idea for NOTEAPP | Source |
|---|---|---|---|
| Hundreds of stationery designs | Hundreds of hand-designed notebooks, planners and layouts included; can customise density and opacity of stationery elements. | Density/opacity sliders for ruled lines and grids are cheap and make templates feel designed rather than imposed. | https://penbook.app/ · https://apps.apple.com/us/app/penbook-paper-planner-notes/id1473064295 |
| Live Paper daily planner | Pages update with the information you need as you use them; the Daily Planner lets you write on top of the day's meetings and errands. | A daily page that pulls Calendar events into the paper layout, with ink on top, is a strong "why digital" moment. | https://penbook.app/ |
| Live weekly and yearly planners | Weekly pages show connected calendars inside the page; yearly pages block out vacation days, school holidays and family visits. | Live data should be per-page-type, not one global calendar widget. | https://penbook.app/ |
| Screen-size-aware stationery | Layouts automatically adjust to the iPad or iPhone screen size. | Templates should be responsive to page size and orientation, not fixed PDFs. | https://penbook.app/ |
| Colour palettes for writing | Palettes made for writing, plus cover and stationery browsing/download inside the app. | Curated pen palettes are a better default than an infinite colour wheel. | https://penbook.app/ |

---

## Microsoft OneNote (iPad)

OneNote is a freeform page, not a sheet of paper: text boxes, images and ink can sit anywhere. On iPad, Microsoft documents a limited ink feature set; that limitation is itself instructive.

| Feature/setting | How it works | Idea for NOTEAPP | Source |
|---|---|---|---|
| Free canvas | Text, images, ink and media can be placed anywhere and layered; every page behaves like a whiteboard. | Our whiteboard covers this, but OneNote shows the value of a page that is not a fixed rectangle. | https://paperlike.com/blogs/paperlikers-insights/best-note-taking-apps-ipad · https://support.microsoft.com/en-us/onenote/onenote-help-and-learning/draw-and-sketch-notes-in-onenote |
| Custom pen toolbox | Add or remove pens/highlighters on the Draw tab; custom pens are portable to Word, Excel, Visio and PowerPoint. | Pen presets that travel with the user, not the document. | https://support.microsoft.com/en-us/onenote/onenote-for-ipad-or-iphone-help-and-learning/handwrite-draw-and-sketch-in-onenote-for-ipad-or-iphone |
| Pen thickness and colour | Five thickness presets from .25 mm to 3.5 mm, tappable dots between − and +; "More Ink Colors" with colour plus brightness and Apply. | Brightness as a separate axis from hue is a good colour picker for ink, especially on dark paper. | https://support.microsoft.com/en-us/onenote/onenote-for-ipad-or-iphone-help-and-learning/handwrite-draw-and-sketch-in-onenote-for-ipad-or-iphone |
| Draw with Touch | Drawing Mode > Draw with Touch: when off, a finger pans instead of drawing. | Same idea as CollaNote's Hand/Stylus toggle; make the default explicit on first run. | https://support.microsoft.com/en-us/onenote/onenote-for-ipad-or-iphone-help-and-learning/select-a-drawing-mode-in-onenote-for-ipad-or-iphone |
| Stylus Orientation | Set how you hold the stylus so OneNote can ignore palm input. | A posture picker is a cheap palm-rejection aid and can feed stroke prediction. | https://support.microsoft.com/en-us/onenote/onenote-for-ipad-or-iphone-help-and-learning/select-a-drawing-mode-in-onenote-for-ipad-or-iphone |
| Draw and Hold | Draw a line/circle/triangle/arrow in one stroke, hold before lifting; it converts to a neat shape; while holding, drag to resize or rotate. | The "keep holding" continuation is the good part: convert and transform in one gesture. | https://support.microsoft.com/en-us/onenote/onenote-help-and-learning/ink-faster-with-gestures-for-creating-shapes-deleting-ink-and-more |
| Scratch out to erase | Scribble a loopy or zigzag stroke over ink to delete it; undo restores both ink and scribble. Can be disabled in File > Options > Advanced > Pen. | Provide an off switch. Power scribblers will trigger it accidentally. | https://support.microsoft.com/en-us/onenote/onenote-help-and-learning/ink-faster-with-gestures-for-creating-shapes-deleting-ink-and-more |
| Lasso selection | Lasso selects ink; cut, copy, delete, move, rotate. | Basic, but rotation of an ink selection is often missing in simpler apps. | https://support.microsoft.com/en-us/onenote/onenote-for-ipad-or-iphone-help-and-learning/handwrite-draw-and-sketch-in-onenote-for-ipad-or-iphone |
| Ink Replay | Replays strokes in the order they were drawn. Documented as Windows-only in OneNote/Word/Excel/PowerPoint. | Replay is a wonderful "how did I get here" feature, but not an iPad v1 feature. | https://support.microsoft.com/en-us/topic/62d3516d-ce5e-4d97-bc3d-5569810161d0 |
| Transcription + ink | On Windows, ink plays back in lockstep with a recording; tap an annotation to jump to that moment. | This is the end-state of audio sync; CollaNote's word-level jump is the mobile-scale version. | https://support.microsoft.com/en-us/topic/62d3516d-ce5e-4d97-bc3d-5569810161d0 |
| No handwriting-to-text on iPad | The iPad help page states plainly: "OneNote for iPad does not currently support converting handwriting to text." | A documented gap we can beat. But do not assume it is permanent; see Unverified. | https://support.microsoft.com/en-us/onenote/onenote-for-ipad-or-iphone-help-and-learning/handwrite-draw-and-sketch-in-onenote-for-ipad-or-iphone |
| Ink colours | The Ink Color Selector includes effects such as galaxy, marble and glitter. | Fun, low-cost differentiation for a personal app; not a core workflow. | https://paperlike.com/blogs/paperlikers-insights/best-note-taking-apps-ipad |
| Hierarchy and tags | Notebooks > sections > pages, with subpages; tags for notes. | OneNote's hierarchy is the counter-example to Apple Notes' flat tags: both are valid, but pick one and be consistent. | https://support.microsoft.com/en-us/onenote/onenote-for-ipad-or-iphone-help-and-learning/create-a-subpage-in-onenote-for-ipad-or-iphone · https://support.microsoft.com/en-us/onenote/onenote-for-ipad-or-iphone-help-and-learning/tag-notes-in-microsoft-onenote-in-onenote-for-ipad-or-iphone |

---

## Apple Notes and Freeform

These are the platform conventions our users already know. The iPad User Guide content below was read from the **iPadOS 27** guide.

### Apple Notes

| Feature/setting | How it works | Idea for NOTEAPP | Source |
|---|---|---|---|
| Smart Script refine | Select handwriting and tap Refine to make it smoother, straighter and more legible; or enable Auto-refine Handwriting from the tool menu's gear. The result keeps the look of the user's writing. | Refinement must preserve character, not replace it with a font. Offer it as a toggle, not a default surprise. | https://support.apple.com/en-lk/guide/ipad/ipada87a6078/ipados |
| Auto-refine is per-line and animated | MacStories observed refinement kicking in after a line or two, animating to improve the writing; it briefly stops accepting input while refining. | Do refinement off the input path. Any pause during writing is a bug users will feel. | https://www.macstories.net/stories/ipados-18s-smart-script-a-promising-start-but-dont-toss-your-keyboard-out-yet/ |
| Straighten | A separate action makes selected writing more level. | "Straighten" should be a one-shot selection action, not a global page setting. | https://support.apple.com/en-lk/guide/ipad/ipada87a6078/ipados |
| Handwriting area resize handle | Drag the handle on the left up or down to change the handwriting area. | A visible resize affordance is a quiet way to handle "I ran out of room" without a mode. | https://support.apple.com/en-lk/guide/ipad/ipada87a6078/ipados |
| Smart Selection | Select handwriting with typed-text gestures: double-tap a word, triple-tap a sentence, touch and hold then drag for a paragraph; handles adjust the range. | Meet the text-editing gestures users already have. This is more important than a custom lasso for most people. | https://support.apple.com/en-lk/guide/ipad/ipada87a6078/ipados |
| Scratch out then hold | Scratch out writing, then hold the Pencil/finger down to erase; supported with Pen, Mono line or Marker. | The hold-to-confirm is a good guard against accidental deletion during fast writing. | https://support.apple.com/en-lk/guide/ipad/ipada87a6078/ipados |
| Spelling in your own hand | Misspelled words get a dotted underline; tapping offers corrections; the fix is rendered in the user's writing style. | If we do handwriting recognition at all, corrections must preserve the hand. | https://support.apple.com/en-lk/guide/ipad/ipada87a6078/ipados |
| Convert text to handwriting | Select a text object, then Convert to Handwriting. Requires previously saved notes with at least 10 unique lowercase characters. | A "make this look handwritten" action is a gimmick until it is good; Apple gates it on a learned style sample. | https://support.apple.com/en-lk/guide/ipad/ipada87a6078/ipados |
| Paste typed text as handwriting | Paste copied text into a handwriting area; it appears in the user's handwriting. MacStories notes it only works when pasting into existing handwriting, and looks "a little too perfect". | Useful for pasting a quote into a handwritten page. The limitation (must paste into existing ink) is worth avoiding. | https://support.apple.com/en-lk/guide/ipad/ipada87a6078/ipados · https://www.macstories.net/stories/ipados-18s-smart-script-a-promising-start-but-dont-toss-your-keyboard-out-yet/ |
| Math Notes | Write or type an expression with `=`; it solves inline. Tap the `=` to see what Notes understood; red dotted lines mean unsolvable, blue dotted mean ambiguous. Graphs insert from an equation; add another equation to the same graph. | Tap-the-result-to-debug-the-parse is the best math UX in this survey. It turns a wrong answer into a fixable misunderstanding. | https://support.apple.com/en-lk/guide/ipad/ipad10f28bec/ipados |
| Scribble and search | Tap the Scribble tool to transcribe handwriting as you write; handwritten text is searchable; the first handwritten line becomes the suggested title. | Auto-title from the first handwritten line is a tiny, high-value library feature. | https://support.apple.com/en-lk/guide/ipad/ipada87a6078/ipados |
| Markup tool palette | Pen, marker, pencil; tap the selected tool again for weight/opacity; colour via Grid, Spectrum or Sliders; ruler drags and rotates with two fingers; lasso sits between eraser and ruler; toolbar can be moved to any edge and auto-minimized. | The tool order and "tap again for options" are conventions worth copying exactly. | https://support.apple.com/en-lk/guide/ipad/ipad6350b8dc/ipados |
| Pencil Pro squeeze and double-tap | Settings > Apple Pencil > Squeeze and Double Tap choose the action (for example undo or show tool palette). Haptics can be turned off in Settings > Apple Pencil. | Let the user map squeeze to undo or palette; do not decide for them. | https://support.apple.com/en-lk/guide/ipad/ipadc55b6c7a/ipados |
| Barrel roll | Rotating the barrel previews the angle of the highlighter and fountain pen in Notes, Freeform and Markup; third-party support is per-app. | If we ship a chisel highlighter or fountain pen, barrel roll is expected on Pencil Pro. | https://support.apple.com/en-lk/guide/ipad/ipadc55b6c7a/ipados |
| Hover preview | Hold Pencil up to 12 mm above the display to explore the tool palette, preview colour/thickness/opacity (highlighter in Notes), and preview eraser size/effect. Hover can be disabled in Settings > Apple Pencil. | Hover should preview the mark and the eraser footprint, not just highlight a button. | https://support.apple.com/en-lk/guide/ipad/ipadc55b6c7a/ipados |
| Smart Folders and Quick Notes | Hashtags create Smart Folders; Quick Notes capture from anywhere. | Tags + saved queries are a better library model than deep folder trees for a personal app. | https://paperlike.com/blogs/paperlikers-insights/best-note-taking-apps-ipad |

### Freeform

| Feature/setting | How it works | Idea for NOTEAPP | Source |
|---|---|---|---|
| Infinite canvas with grouped strokes | Strokes are grouped into a drawing; you can separate or merge strokes, delete, resize or straighten parts. | Grouping is what makes an infinite canvas editable. Without it, every selection is a rectangle of pixels. | https://support.apple.com/en-lk/guide/ipad/ipadf825a0bd/ipados |
| Draw with Finger | A toggle inside the drawing tools lets Pencil users also draw with a finger; by default Pencil draws and finger selects/scrolls. | The default should depend on whether a Pencil is paired; expose the override in the tool options, not app settings. | https://support.apple.com/en-lk/guide/ipad/ipadf825a0bd/ipados |
| Hold still to smooth/straighten | Finish a drawing and hold the finger/Pencil still for a moment to smooth or straighten its shape. | A hold-at-end gesture is more discoverable than a "shape recognition" toggle. | https://support.apple.com/en-lk/guide/ipad/ipadf825a0bd/ipados |
| Snap to Shapes | A selection option that smooths or straightens hand-drawn lines. | Offer "snap this selection" as a repair action, not only as a live behaviour. | https://support.apple.com/en-lk/guide/ipad/ipadf825a0bd/ipados |
| Tool row and second-tap options | Tools include Fill, Crayon, Fountain Pen, Reed Pen, Watercolour Brush; tap a tool a second time to change angle, thickness, opacity; swipe the tool row for more. | Second-tap options again. It is the dominant convention across the apps in this survey. | https://support.apple.com/en-lk/guide/ipad/ipadf825a0bd/ipados |
| Ruler rotation | Tap Ruler, drag with one finger, rotate by placing two fingers on it and turning. | Two-finger rotation of the ruler is the correct gesture; a rotation slider is not. | https://support.apple.com/en-lk/guide/ipad/ipadf825a0bd/ipados |
| Scenes | Save the current view as a named scene; reorder scenes; present, print or export all scenes, or a single scene; scenes are shared with collaborators. | This is the cleanest presentation model for a whiteboard: named camera views, not pages. | https://support.apple.com/en-lk/guide/ipad/ipad9c7aadac/ipados |
| Alignment guides | Settings > Apps > Freeform: Snap to Grid, Center Guides, Edge Guides, Spacing Guides (when three or more items are equally spaced). | Spacing guides are the one nobody ships and everybody needs when laying out a page. | https://support.apple.com/en-lk/guide/ipad/ipadcb84e16e/ipados |
| Handwriting as text | Handwriting is recognised as words; select, copy/paste as text, straighten, translate; searchable like typed text. | Recognition should be continuous and invisible, feeding search and selection, not a modal conversion. | https://support.apple.com/en-lk/guide/ipad/ipadf825a0bd/ipados |
| Math Results modes | Choose Insert Results (solve automatically), Suggest Results (show a Solve button), or Off; answers appear in the user's writing. | "Suggest" is the right default for a writing app; automatic insertion can feel like the app is editing your notes. | https://support.apple.com/en-lk/guide/ipad/ipadf825a0bd/ipados |
| Dark canvas and dot grid | Boards can use a dark canvas with dark controls; dot grid can be toggled in full screen or via View Options. | A dot-grid toggle belongs in the canvas controls, not deep settings. | https://support.apple.com/en-lk/guide/ipad/ipadcb84e16e/ipados |

---

## Samsung Notes (UX reference)

Not an iPad app; included because its S Pen writing settings are unusually explicit about handwriting repair.

| Feature/setting | How it works | Idea for NOTEAPP | Source |
|---|---|---|---|
| Align handwriting | Clean up handwriting > Align handwriting, then confirm; useful when a line drifts off the baseline. | One-tap baseline alignment for a selected block is more useful than global straightening. | https://www.samsung.com/us/support/answer/ANS10003634/ |
| Handwriting help | Assists S Pen writing with guidelines, correcting letter shapes and aligning letters; language selectable; Pen mode only. | Optional writing guides that appear only while writing, then fade, are a good training-wheels pattern. | https://www.samsung.com/us/support/answer/ANS10003634/ |
| Eraser types | Stroke eraser, Area eraser with size slider, and "Erase highlighter only". | "Erase highlighter only" is an excellent selective eraser and cheap to implement if strokes carry a type flag. | https://www.samsung.com/us/support/answer/ANS10003634/ |
| S Pen button as temporary eraser | Press and hold the S Pen button while hovering to erase; release to return to the previous tool. | A hardware-button momentary eraser is faster than any toolbar. On iPad, the equivalent is squeeze/double-tap. | https://www.samsung.com/us/support/answer/ANS10003634/ |
| Selection modes | Double-tap Selection mode to choose Lasso or Rectangle; a switch controls "Include partially selected objects". | The partial-selection toggle is a small setting with a big effect on lasso frustration. | https://www.samsung.com/us/support/answer/ANS10003634/ |
| Ink stack order | Selected handwriting can be moved forward or backward. | Needed once highlights and images share a page; otherwise erasing order is unpredictable. | https://www.samsung.com/us/support/answer/ANS10003634/ |
| Handwriting language and reconnection | Settings > Handwriting language; after a bad conversion, "Handwriting reconnection language" re-runs recognition with another language. | Let users re-run recognition with a different language instead of retyping. | https://www.samsung.com/us/support/answer/ANS10003634/ |

---

## reMarkable (UX reference)

An e-ink tablet, not an iPad app. Relevant for its restraint and its physical-button/toolbar model.

| Feature/setting | How it works | Idea for NOTEAPP | Source |
|---|---|---|---|
| Left/right-handed mode | A setting switches the UI for left- or right-handed writing. | Handedness should move controls, not just flip an icon. We already need this for the zoom chip. | https://support.remarkable.com/articles/Knowledge/Toolbar |
| Toolbar position | The toolbar can be shown/hidden and positioned. | A hideable toolbar with a remembered position is better than a fixed bar that eats canvas. | https://support.remarkable.com/articles/Knowledge/Toolbar |
| Two pens in the toolbar | Two writing tools are exposed for quick switching; release notes for 2.8 say the device remembers the favourite pen. | Two pen slots plus one eraser is the minimum viable fast-switching set. | https://support.remarkable.com/articles/Knowledge/Toolbar · https://support.remarkable.com/s/article/Software-release-2-8-June-2021 |
| Layers | Add, hide, delete and reorder layers; templates are reached through the layers icon. | Layers are a power feature, but "hide this layer" is the useful daily action. | https://support.remarkable.com/articles/Knowledge/Toolbar |
| Page overview and document settings | Page overview for navigation; document settings for page-level options. | A page overview with large thumbnails is still the fastest way to navigate a 100-page notebook. | https://support.remarkable.com/articles/Knowledge/Toolbar |
| Writing tools | Ballpoint, fineliner, marker, pencil, mechanical pencil, highlighter, calligraphy pen, shader (colour blending). List is from the search preview; the article body is JavaScript-gated, so treat the exact set as unconfirmed. | The shader idea (blend and layer colours) is a nice differentiator for a colour iPad app, not for v1. | https://support.remarkable.com/s/article/Writing-tools |

---

## Cross-app small things, big impact

Ranked by expected daily benefit per unit of SwiftUI/PencilKit effort. Effort: **S** ≈ up to 3 days, **M** ≈ 1–2 weeks, **L** ≈ multi-week.

| # | Idea | Seen in | User benefit | Effort |
|---|---|---|---|---|
| 1 | **Tap the selected tool again for its options** (size, opacity, colour) instead of opening a separate settings sheet. | Apple Markup, Freeform, OneNote, CollaNote | The most repeated action in the app becomes one tap, in one small popover instead of a settings sheet. | S |
| 2 | **Eraser auto-returns to the previous tool**, with an independent "double-tap to toggle eraser" action. | CollaNote, Samsung Notes | Removes the second tool change after every erase, without forcing a mode. | S |
| 3 | **Scratch-out to erase, with undo and an off switch.** | MyScript Notes, Apple Notes, OneNote | Erase without leaving the pen. The off switch is essential for fast writers. | M |
| 4 | **Selection action dock anchored to the selection** (Cut, Copy, Convert, Delete, Resize, more). | MyScript Notes | Actions appear where the eyes are. Text labels beat icon-only bars for discoverability. | S |
| 5 | **Zoom chip: always visible, tap to reset 100%, tap the lock icon to lock the level.** | MyScript Notes | Recovers from an accidental pinch instantly and gives confidence about scale. | S |
| 6 | **Handedness-aware placement** of zoom chip and floating controls (left for right-handed, right for left-handed). | MyScript Notes, reMarkable | Left-handed users stop covering the controls. Cheap to do once, painful to retrofit. | S |
| 7 | **Two-finger undo, three-finger redo.** | MyScript Notes | Undo without moving the Pencil to a toolbar. Matches the system gesture users know. | S |
| 8 | **Palm rejection strength (Low/Normal/High) plus a finger-draws vs finger-scrolls toggle.** | CollaNote, OneNote, Freeform | Fixes the two most common "the app is broken" reports without a support conversation. | S |
| 9 | **Smart highlighter that aligns with text and can sit behind ink**, plus freehand highlight and "erase highlighter only". | MyScript Notes, Samsung Notes, ZoomNotes | Highlights stop looking drunk, and clearing highlights stops destroying ink. | M |
| 10 | **Pencil squeeze radial menu at the nib** with tools, undo/redo, size and colour; closes on the first stroke. | CollaNote | Biggest reduction in travel to the toolbar, and it feels native to Pencil Pro. | M |
| 11 | **Configurable squeeze and double-tap actions, plus a haptics toggle.** | Apple, CollaNote | Users map the hardware to undo or palette, whichever they use. Haptics off is a real accessibility need. | S |
| 12 | **Hover preview of the tool footprint and eraser area**, not just a highlighted button. | Apple | Fewer wrong-size strokes and fewer accidental erases before touching the screen. | M |
| 13 | **Custom toolbar: hide, reorder, and choose pen count (up to 50).** | Flexcil, ZoomNotes, Notewise | Power users get their 12 pens; everyone else gets a clean bar. | S |
| 14 | **Saved pen presets ("favourite pens")** with name, colour, width and tool. | ZoomNotes, Flexcil | Switch between "lecture pen" and "diagram pen" in one tap instead of re-picking a colour. | S |
| 15 | **Handwriting refinement as an opt-in toggle + a one-shot Straighten on selection.** | Apple Notes | Neater notes without changing the user's hand; no surprise reflow. | L |
| 16 | **Conversion preview strip** above handwriting ("I read this as…"), tap to choose another reading. | MyScript Notes | Catches recognition errors before conversion, when they are cheap to fix. | M |
| 17 | **"Learn word" in the selection dock** to add a word or abbreviation to the recognition dictionary. | MyScript Notes | Names, jargon and drug names stop being misread forever. | M |
| 18 | **Math that solves on `=`, with tap-to-inspect parse errors** (red = unsolvable, blue = ambiguous) and insert graph. | Apple Notes | Turns a wrong answer into a learning moment, not a mystery. | L |
| 19 | **Adjust-space blue line** to insert or remove vertical room between elements. | MyScript Notes | The "I need two more lines here" problem, solved without cut-and-paste. | L |
| 20 | **Saved views / scenes**: name a camera view, reorder, present, export or print each scene. | Freeform, ZoomNotes | Makes a whiteboard presentable without turning it into slides. | M |
| 21 | **Reference link from a pasted excerpt back to its source page and rectangle.** | Flexcil | Notes assembled from PDFs keep their provenance; reviewing is one tap. | M |
| 22 | **Masking tape for self-testing**, tap to reveal, record correct/incorrect, sort by accuracy. | Flexcil | A study workflow that does not require a separate flashcard app. | M |
| 23 | **Pop-up second document** over the page, resizable with a three-finger pinch. | Flexcil | Look things up without leaving the page or splitting the screen. | M |
| 24 | **Magnifier with auto-advance and margins**, for writing small on a large page. | ZoomNotes | Makes small handwriting comfortable on a 13" iPad, and keeps the hand out of the way. | M |
| 25 | **View rewind / forward** (undo camera moves independently of content undo). | ZoomNotes | One tap to recover from a bad pinch, without undoing a stroke. | S |

Deliberately left out of the 25 because they are either large or situational: live-data stationery (Penbook), hold-still shape smoothing (Freeform), ink stack order and highlight-behind-ink (Samsung Notes, ZoomNotes), page-level tags (ZoomNotes), and auto-outline from page labels (ZoomNotes). They are documented in the app sections above if we want them later.

---

## Images

Downloaded with `curl` into `research_notes/competitors/others/images/`. App Store screenshots are marketing frames with a device mock-up, not raw captures; ZoomNotes' is a legacy UI. Use them for layout and feature evidence, not pixel-accurate current UI.

| File | What it shows | Source URL |
|---|---|---|
| `myscript-appstore-1.png` | MyScript Notes iPad; selection dock with Cut/Copy/Copy as/Delete/AI/Convert/Resize; PDF thumbnails; inline highlight. | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/f0/c0/ce/f0c0ce7c-6aaf-4fa4-e8cf-ce372e0e737e/MSNotes-iOS-ipadPro130-01-EN.jpg/1200x1600bb.png |
| `myscript-pdf-hero.png` | MyScript Notes PDF annotation hero (marked-up page). | https://www.myscript.com/_ipx/q_80&s_488x706/notes/hero/pdf-hero-img.png |
| `flexcil-appstore-1.png` | Flexcil iPad App Store frame. | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource116/v4/b6/2d/14/b62d147e-0e1a-2b79-0767-8f7ead324d40/20ff5ded-d98f-4447-90dd-532bc8d8ba3f__U110b_U1167_U11bc_U110b_U1165.jpg/1200x1600bb.png |
| `flexcil-appstore-2.png` | Flexcil PDF page with floating numbered pen bar (1.5, 1.0, 0.4…), highlight/underline annotations. | https://is1-ssl.mzstatic.com/image/thumb/Purple126/v4/08/bf/c8/08bfc88f-ba39-d9d0-8b12-9f6cec043eff/096aacfa-bd72-4e0e-bf92-fce44467fd79_1.png/1200x1600bb.png |
| `flexcil-custom-pen-toolbar.png` | Flexcil custom pen toolbar guide screenshot (show/hide/order, pen count). | https://support.flexcil.com/hc/article_attachments/41230333190297 |
| `flexcil-masking-pen-list.png` | Flexcil masking pen picker (rightmost pen, colour choices). | https://support.flexcil.com/hc/article_attachments/41237026376345 |
| `flexcil-masking-answer-popup.png` | Flexcil masking area with correct/incorrect answer pop-up. | https://support.flexcil.com/hc/article_attachments/41237047450393 |
| `collanote-appstore-1.png` | CollaNote iPad App Store frame. | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/51/d3/23/51d323b5-e4c4-fc27-9901-008002fab774/4349c0c8-0000-44a2-818c-db612236bb0c_1_-_Beautiful_Note.png/1200x1600bb.png |
| `collanote-appstore-2.png` | CollaNote "Ink & Audio in perfect sync" frame; audio player with rewind/play. | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/65/8c/0b/658c0b31-c5c3-0936-0121-fd111c057604/286adbbc-7697-4f4e-8623-b47ac8d54f36_2_-_Ink_And_Audio.png/1200x1600bb.png |
| `collanote-pen-tools.png` | CollaNote pen/brush shelf (50+ tools). | https://collanote.com/images/home/hero-pen-tools-v4.webp |
| `collanote-rulers.png` | CollaNote 5.0 ruler tools, including circular ruler, triangle ruler and protractor. | https://collanote.com/uploads/034664768f63501cafa4.webp |
| `zoomnotes-appstore-1.png` | Legacy ZoomNotes App Store frame; lists sub-documents, layers, bookmarks, infinite zoom; shows page-within-page. | https://is1-ssl.mzstatic.com/image/thumb/Purple122/v4/51/16/73/511673eb-c149-2bd5-ae79-1b292f087626/mzl.pxgyfnil.png/1200x1600bb.png |
| `notewise-appstore-1.png` | Notewise frame showing connector between text blocks, floating tool pill, AI quiz/meeting transcript. | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/57/91/ae/5791aee7-8eda-d101-e88a-93be6e36489e/iPad_38.jpg/1200x1600bb.png |
| `penbook-appstore-1.png` | Penbook iPad App Store frame. | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/f5/a7/5d/f5a75d56-e4dd-d80b-b117-ae0572a1c10d/ipad-01.png/1200x1600bb.png |
| `penbook-appstore-2.png` | Penbook iPad App Store frame. | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/e3/d6/2c/e3d62c3f-7cea-ba20-b766-4d5fe8500982/ipad-06.png/1200x1600bb.png |
| `penbook-templates.png` | Penbook template previews: planners, grids, chemistry, storyboard, maths layouts. | https://storage.ghost.io/c/bc/29/bc29c733-11e0-43d7-a672-1ca265b5a4d7/content/images/2025/10/template-previews-3.png |
| `onenote-appstore-1.png` | OneNote iPad frame: floating top toolbar over a free canvas, handwriting and typed text on one page. | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource122/v4/89/26/99/892699ef-2b64-0ed2-4368-3886d2fa3264/2d766ea1-de77-4f2b-bb65-502d39aa234b_iOS_AS_iPad_Hero.png/1600x1200bb.png |
| `samsung-eraser-options.png` | Samsung Notes eraser settings: stroke eraser, area eraser, erase highlighter only, size slider. | https://image-us.samsung.com/SamsungUS/support/solutions/mobile/phones/galaxy-s/s25/MOB_PH_GS_S25_Erase-handwriting-4.jpg |

Not collected: Apple Notes/Freeform in-app screenshots (Apple's guide images are not exposed as stable direct URLs), current ZoomNotes UI (site uses legacy captures), and reMarkable UI (official pages are location-gated). App Store screenshots for Apple Notes/Freeform and reMarkable would need a device or a different storefront.

---

## Unverified

- **OneNote iPad ruler.** The iPad handwrite article lists pen, highlighter, eraser and lasso but not the ruler; the "Rotate Ink Ruler" article is written for Windows. I did not confirm a ruler on the iPad Draw tab. https://support.microsoft.com/en-us/onenote/onenote-for-ipad-or-iphone-help-and-learning/handwrite-draw-and-sketch-in-onenote-for-ipad-or-iphone
- **OneNote iPad ink-to-text.** Microsoft's iPad page says it is not supported, but forum posts and 2026 videos disagree, possibly because of Insider builds or the separate "Ink to Text Pen" on Windows. Treat "unsupported" as the documented state, not a permanent guarantee. https://support.microsoft.com/en-us/onenote/onenote-for-ipad-or-iphone-help-and-learning/handwrite-draw-and-sketch-in-onenote-for-ipad-or-iphone · https://learn.microsoft.com/en-us/answers/questions/4890969/ink-to-text-tool-in-onenote-for-ipad
- **ZoomNotes current UI vs manual.** The 7.5 manual and the App Store screenshots I could download are legacy (old toolbar, old icons). Behaviour names are documented, but current placement may differ. http://www.zoom-notes.com/Documents/ZoomNotes7.5.pdf
- **ZoomNotes "infinite whiteboard" exact limits.** The manual says "near infinite" and that page size is only used for print/PDF; the practical maximum zoom and memory behaviour are not documented. http://www.zoom-notes.com/Documents/ZoomNotes7.5.pdf
- **Nebo/MyScript "smart" highlighter scope.** The release note says smart highlights auto-align with text, but does not state which note formats or whether PDF text and handwriting both qualify. https://help.myscript.com/notes/versions/ios/
- **CollaNote pen count.** The website says "50+ pens and brushes", the App Store description says "25+", and Paperlike says "25 or so". The count is marketing, not a spec; the underlying customisation is real. https://collanote.com/ · https://apps.apple.com/us/app/collanote-notes-pdf-markup/id1540956268
- **Notewise infinite canvas.** A developer reply in App Store reviews says infinite canvas is not currently supported, while the 4.0 post uses "canvas" loosely. I did not verify whether 4.0 changed this. https://apps.apple.com/ph/app/6480045936?see-all=reviews&platform=iphone · https://notewise.dev/post/notewise-4.0-frontline-features
- **Penbook smart folders.** Nothing on the Penbook site documents tag-based smart folders; that idea comes from Apple Notes. Do not attribute it to Penbook.
- **Samsung "Handwriting help" availability.** The support page is written for Galaxy S25 phones; tablet availability, language coverage and whether it works with third-party keyboards are not stated. https://www.samsung.com/us/support/answer/ANS10003634/
- **reMarkable writing-tool details.** The "Writing tools" article is JavaScript-gated; the tool list (ballpoint, fineliner, marker, pencil, mechanical pencil, highlighter, calligraphy, shader) comes from the search preview, not the rendered page. https://support.remarkable.com/s/article/Writing-tools
- **reMarkable "remembers your favourite pen".** This is from release notes 2.8 (2021); I did not confirm it still behaves that way on current firmware. https://support.remarkable.com/s/article/Software-release-2-8-June-2021
- **Apple Notes behaviour by OS version.** The guide I read is iPadOS 27 (November 2026). Auto-refine, Straighten, Convert to Handwriting and paste-as-handwriting may be unavailable or different on iPadOS 18–26, and Smart Script has a device list. Smart Script's "briefly stops accepting input" observation is from MacStories' iPadOS 18 beta test, not from the shipping OS.
- **Pencil hover tool-palette preview.** Apple documents hover preview in supported apps; third-party support is not guaranteed by the OS. Our implementation would need to test on M4/M5 iPads with Pencil Pro.
- **"Squeeze to open palette at the nib" on Pencil Pro.** CollaNote documents this; the OS exposes squeeze but the at-nib placement is app-drawn. Confirm the coordinate behaviour on device before committing to the interaction.
- **Paperlike statements.** Prices, plan names and feature comparisons are secondary and change frequently; use them for behaviour descriptions (for example MyScript highlighter snapping, OneNote ink colours), not for pricing.
