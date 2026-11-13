# Goodnotes live walkthrough

Captured 2026-11-12 by driving the installed **Goodnotes 7.1.34 for Mac** (the iPad app running on Mac) through macOS Accessibility and window screenshots. This is what the app actually shows and does, not what its strings suggest. It complements `GOODNOTES-PARITY-PLAN.md` (which was built from the app bundle only) and corrects it in §10.

Screenshots: `screens/` (numbers below refer to these files).

**Account state:** free plan ("Granth · Free"), three notebooks (Maths, Physics, Chemistry). Every item in the New menu except Folder has a lock badge, so Whiteboard, Text Doc, QuickNote, Study Set and Quick Record could not be created.

**Not exercised:** Apple Pencil-only behaviour (pressure, hover, squeeze, palm rejection), audio recording, AI chat (needs opt-in to on-device indexing; declined to keep notes private), collaboration and sharing, whiteboard, text document.

---

## 1. Library (`01`, `02`, `03`, `04`)

**Sidebar:** Documents, Favorites, Shared, Marketplace ("50+ items for you").

**Header:** upgrade pill, Search, Notifications, profile avatar.

**Content toolbar:**
- **Filter** (`All ▾`): All / Documents / Folders. There are no tags anywhere in the library.
- **+ New** opens a large popover:
  - Tiles: Notebook, Whiteboard, Text Doc / Import, Quick Record
  - List: QuickNote, Study Set, Image, Take Photo
  - Folder
  - Import from Cloud Storage
- **Grid icon** opens a combined menu: Grid ✓ / List / Sort By ▸. Its accessibility label is "Sorting, View Mode, Select", so multi-select lives here too.
- **…** menu and a **cloud-sync status** icon (crossed out, because sync is off).

**Document card:** cover, a ☆ favourite toggle in the cover's top-right corner, title, and a full timestamp ("11 Dec 2025 at 1:12 pm"). Single click selects the card and the title gets a `▾` chevron. Double-click opens it.

**Right-click card** (`03`): the title is editable inline at the top of the menu, then:
- Duplicate
- Move
- Convert to Whiteboard
- Open in New Window
- Export
- Share Link to Collaborate
- Add Lock
- Move to Trash (red)

**Profile menu** (`04`):
- Account row and an upgrade card
- Settings, Manage Notebook Templates, Cloud & Backup, Integrations, Trash Bin
- User Guide, Report an Issue, Rate, About

**Library search** (`05`):
- Empty state shows "Recently Opened Documents" with a Clear button.
- A query returns grouped sections: **Written Notes** (handwriting hits) and **PDFs** (text-layer hits).
- Each result row shows the document cover and name, then a horizontal strip of cropped page snippets with the matched word highlighted and labelled `p.22`, `p.31`, and so on. A row ends in a "6 pages ›" control, and the section has a "Show All Written Notes" link.
- Clicking a snippet (`06`) opens the notebook at that page with the word boxed in orange. A bottom bar shows `Close · [query chip] · 6 matches found · ‹ ›` and the page counter `22 of 55`.

## 2. Editor layout (`07`)

- **Tab bar:** Home button, then one tab per open notebook (`Maths ▾`, `Physics ▾`, each with ×). Opening a second notebook adds a tab, controlled by the setting "Open Documents as New Tabs" (on by default).
- **Left of the toolbar:** Sidebar (pages), Search, Goodnotes AI, Editing Mode (read-only toggle).
- **Centre tools**, each with a single-key shortcut shown in its tooltip:

| Tool | Key | Tool | Key |
|---|---|---|---|
| Lasso | V | Image | I |
| Writing (pen group) | W | Shapes | S |
| Eraser | E | Sticky Note | N |
| Text | T | Laser Pointer | L |
| Element (stickers/GIFs) | M | | |

  After that come **Record & Summarize** and an **Accessories ▾** overflow.
- **Right:** Add Page, Share, More.
- **Page flow:** pages scroll vertically and continuously (direction is a setting). A page counter ("17 of 52") appears bottom-left while scrolling.

**Interaction model:** clicking a tool selects it and shows a floating capsule bar of its options under the toolbar. Clicking the selected tool again, or the selected sub-tool, opens a detail popover. For Shapes, Sticky Note and Element, clicking the active tool a second time switches back to the previous tool.

## 3. Tools in detail

### 3.1 Writing group (`08`–`11`)
The capsule bar contains:
- `[Pen ▾] [Pencil] [Highlighter] [Tape] [Draw Shape]`
- `| 3 thickness presets | 3 colour slots | + Add Slot |`

Each writing tool keeps its own presets: the highlighter bar shows different sizes and five colours.

| Sub-tool | Key | Detail popover |
|---|---|---|
| **Pen** | P | Type: **Fountain / Ball / Brush**. Sliders: **Tip Sharpness** (50%), **Pressure Sensitivity** (50%), **Tip Flatness** (Round), **Stroke Stabilization** (0%). Links to three sub-pages, below |
| **Pencil** | tooltip reads "2" | "Standard Pencil" with a live stroke preview; Reduce Latency; Draw and Hold ▸ |
| **Highlighter** | H | Stroke Stabilization; Reduce Latency; **Draw in Straight Line** |
| **Tape** | A | Preview of "hide content"; **Straight Tape**; **Remove All Tape** (red). Bar: 3 widths, 3 tape colours + slot |
| **Draw Shape** | D | A pen *mode*: strokes become shapes. **Require Hold to Snap**, **Snap to Other Shapes**, **Fill Color** |

Pen sub-pages:
- **Pen Settings:**
  - Adjust Thickness by Speed
  - Reduce Latency
  - **Draw and Hold** ▸: shape snap on hold, with Snap to Other Shapes and Fill Color
  - **Pen Gestures** ▸:
    - **Scribble to Erase** (with "Erase Shapes and Highlighter")
    - **Circle to Lasso**
- **Writing Aids:** Recognition Language (English US); **Check Spelling** ("Enable Spellcheck in this notebook"); Advanced Settings (dictionary).
- **Math Assist:** a "Suggestions" toggle ("Get suggestions and solutions when you're working on math equations").

**Thickness popover** ("Stroke Settings"): line style **Solid / Dashed / Dotted**, plus a Pen Thickness slider in mm (0.3 / 0.9 / 1.5 presets).

**Colour popover** ("Pen Color", `09`): tabs **Presets / Custom / History**; an 8×3 swatch grid plus "+"; an Edit button; and a settings icon.

### 3.2 Eraser (`13`)
The bar shows `[Standard ▾] [⚙] [S M L sizes]`.
- **Eraser Type:** **Precision** (pixel), **Standard** (stroke segment, "efficient erasing without leaving any marks"), **Object**.
- **Advanced Settings:**
  - **Eraser filter** with toggles for Pen / Pencil / Highlighter / Tape and a Select All. "The eraser ignores marks from any tool that's turned off."
  - **Clear Page**
  - **Auto-Deselect** (switches back to the previous tool after erasing)

### 3.3 Lasso (`12`, `16`–`18`)
- **Lasso Type:** Rectangular / Freehand.
- **Included in Selection** toggles: Handwriting, Images, Shapes, Arrows, Text Boxes, Equations, Tape, Sticky Notes.
- **On selection:** a dashed box plus a floating action bar drawn on the canvas (not native controls):
  - AI ✦
  - colour dot
  - **Restyle** (beta, "turn rushed notes into pages that are easier to read")
  - Convert to text
  - Resize
  - Cut, Duplicate, Delete
  - **…**
- **The … menu:**
  - Cut / Copy / Duplicate / Paste / Paste and Match Style
  - Bring to Front / Send to Back
  - Add to Image Playground / Goodnotes AI / Edit Handwriting
  - Resize / Color
  - Take Screenshot / Create Element
  - **Convert ▸ Text, Math**
  - Delete
- **Convert ▸ Text** opens a modal with the recognised text, editable before committing ("xFs)= NSN-cofficient…"), plus **Copy text**, **Auto Detect** (language) and **Convert**.

### 3.4 Other tools (`14`, `15`)
- **Text** (T): the bar has colour, size (24), font ("Modern ▾"), **B** *I*, alignment, line spacing and **Pin Text Tool** (keeps the tool active so you can add several boxes). First-run tip: **long-press anywhere to turn the whole page into one typing area** (full-page typing).
- **Element** (M): a dockable panel with **Stickers / GIFs** tabs and Recents ("After you insert or create an element it appears here"). Any selection can become an Element.
- **Image** (I): a photo-library panel with a camera button.
- **Shapes** (S): bar with a fill toggle, line/connector/elbow, rectangle, circle, triangle, diamond, ellipse, line-weight, and a ▾ for more.
- **Sticky Note** (N): one row of 10 pastel colours.
- **Laser Pointer** (L): **Dot** or **Line** (fading trail).

### 3.5 Accessories (`25`)
- **Show Recordings**
- **Ruler**: a translucent on-canvas ruler marked in cm, draggable and rotatable.
- **Time Keeper**: a floating chip with play, +1 min and a 05:00 timer.
- **Toolbar Customization**

## 4. Page-level menus

- **Add Page** (+):
  - Insert position: **Before / After / Last Page**
  - "Recent templates" ("inherit current page attributes whenever possible") with the current template preselected (Squared Paper)
  - More from Templates…, Image, Take Photo, Import
- **Share and Export:** Collaboration ("Share… Invite, view collaborators"), **Export This Page**, **Export All**, **Print**.
- **More (…)**, headed "Page 31":
  - Remove from Favorites, Copy Page, Rotate Page, **Add Page to Outline**, Change Template, Go to Page
  - Clear or Trash Page: **Delete Specific Items**, Clear Page, Move Page to Trash
  - **Align Objects** (on)
  - Settings: **Add Lock**, Show Resolved Comments, Scrolling Direction (Vertical), Sidebar (Left), Document Editing ▸
- **Editing Mode** (`27`): one click switches the notebook to **Read Only**. All tools disappear and a "Read Only" pill replaces the button.

## 5. Pages sidebar (`19`)
- **Header:** `… Pages ×`.
- **Tabs:** **Pages** (thumbnails) / **Outline** / **Transcripts**.
- **Filter:** **All Pages / Bookmarks Only**.
- **Thumbnail grid:** two columns, each with a page number, a **bookmark ribbon toggle** in the top-right, and a ▾ menu. The current page has a blue border.
- **… menu** (acts on selected pages): Copy, Export, Rotate, Move, Convert to Whiteboard, Mark as Seen, Move to Trash, Show As ▸.
- **Outline tab, empty state:** "Outlines – Maps for your documents: navigate using an imported PDF's Table of Contents, or add your own Outline". Offers **Generate Outline** (AI) plus a menu with Generate New Outline / Select Outlines / Add Page to Outline…

## 6. In-notebook search (`24`)
- A left panel titled "Search Document" with a search field and **Notes / Outlines** tabs.
- Results are listed per page: "Page 12", a text snippet with the match in **bold** (handwriting OCR included), and a cropped thumbnail with the match tinted.
- The query is fuzzy: "force" also matched the misrecognised "forc".
- Every match on the visible canvas gets a light orange highlight.
- The recognition language picker sits at the bottom of the panel (English (US) ▾).

## 7. Templates (`21`, `22`)
- A sheet with **Cover / Paper** tabs, a preview of the chosen paper, **Size** (A4, Portrait ▾) and **Color** (Yellow / White / Dark).
- Paper categories, most with colour-variant dots under each template:
  - **Essentials:** Blank, Dotted, Squared, Ruled Narrow, Ruled Wide
  - **More templates:** creator-made downloads from the Marketplace
  - **Writing Papers:** Cornell, Legal, Single Column Mix, Single Column, Three Column
  - **Planner:** Todos, Monthly Planner
  - **Music:** Music Paper, Guitar Score, Guitar Tablature
- Each category ends with a dashed **+ Import** tile for custom templates.

## 8. Settings
- **Document Editing:** Pull to Add Page, Show Page Number, Scrolling Direction, Show Hover Preview, Toolbar Customization ▸, **Undo and Redo Position** (Left), Automatically Open New Imported Documents, Open Documents as New Tabs.
- **Toolbar Customization:**
  - Tools tab: show/hide and reorder every tool; "at least one tool must be visible"; overflow when space runs out; Reset.
  - **Writing Tools** customisation: show/hide and reorder Pen / Pencil / Highlighter / Tape / Draw Shape.
  - Accessories tab: Record & Summarize is pinned; Show Recordings, Ruler and Time Keeper can be added.
- **Document Privacy:** Setup Password Protection ("one password across all devices").
- **Language:** Handwriting Recognition Language, AI Response Language.
- **Handwriting Recognition:** "Notebooks will be searchable when enabled."
- **Writing Aids:** Spellcheck on by default for new documents; Personal Dictionary with custom words.
- **Other sections:** Notification Preferences, Feedback & Surveys, Troubleshooting.
- **Cloud & Backup:** Goodnotes Cloud sync (off here), **Manual Backup Documents**.
- **Integrations:** Google Calendar and Outlook connectors.

## 8b. More menu and Settings, opened item by item (`28`–`34`)

Second pass on 2026-11-12. Every sub-screen was opened; nothing was changed (template, size, lock and delete dialogs were cancelled).

**Page More menu** (`29`), headed with the page number and a thumbnail:
- **Rotate Page ▸**: Clockwise 90°, Counter Clockwise 90°, 180°.
- **Go to Page**: an inline number field showing the range ("1 – 55"); type a number to jump.
- **Change Template** (`30`): the same Cover / Paper sheet as new notebooks, applied to this page. **Size ▸** has a Portrait / Landscape switch and Goodnotes Standard, A3, A4, A5, A6, A7 (iPhone), Letter, Tabloid, Custom. **Color**: Yellow / White / Dark. **Edit** on Paper Templates manages custom templates.
- **Delete Specific Items ▸** (`28`): one switch per kind (Pen, Pencil, Highlighter, Tape, Text, Elements, Images, Sticky Notes), **Select all**, then **Delete Page Items**. Clears only the chosen kinds from the page.
- **Clear Page** and **Move Page to Trash** (both red).
- **Align Objects** switch (on): objects snap to each other with guides while dragging.
- **Add Lock**: "Lock your documents": one master password for all documents on all devices; Goodnotes can't reset it. Leads to Setup Password Protection.
- Per-document settings: Show Resolved Comments, **Scrolling Direction** (Horizontal / Vertical), **Sidebar** (Left / Right), Document Editing ▸. Footer: "These settings apply to all other documents."

**Toolbar Customization** (`31`): rows with a red remove button and a drag handle (Writing Tools [Customize ›], Eraser, Text, Elements, Images, Shapes, Sticky Notes, Laser Pointer); Tools / Accessories tabs.

**Settings root** (`32`): Document Editing, Document Privacy · Language, Handwriting Recognition, Writing Aids · Notification Preferences, Feedback & Surveys, Troubleshooting.

**Settings sub-pages** (`33`):
- **Document Language**: Handwriting Recognition Language ("used to index, search and understand your handwriting"); AI Response Language.
- **Handwriting Recognition**: one switch, **Index PDF and Handwritten Notes** ("Notebooks will be searchable when enabled"). It was off on this account.
- **Writing Aids**: Enable Spellcheck for New Documents (on); Personal Dictionary → Custom Words.
- **Notification Preferences**: one marketing switch.
- **Troubleshooting**: **Restore Default Templates** (custom templates are kept), **Regenerate Missing Thumbnails**, Restore Lessons, Advanced → Debug Mode.
- **Document Privacy**: Setup Password Protection.

**Profile-menu screens** (`34`):
- **Trash Bin**: a full library grid of deleted notebooks with its own filter, view and sync icons, and an **Empty** button.
- **Manage Notebook Templates**: the default cover and paper for new notebooks (Cover on/off, Size, Color, paper choice).
- **Cloud & Backup**: Cloud Sync (Goodnotes Cloud) and **Manual Backup Documents**.

**Library … menu**: greyed out with nothing selected.

### What NOTEAPP lacks from this pass (checked against the code)
| Goodnotes | NOTEAPP today |
|---|---|
| Settings screen of any kind | none |
| Rotate Page | none (elements rotate, pages don't) |
| Clear Page / Delete Specific Items | none |
| Page size and orientation per page / per notebook | fixed `PageDefaults` size; PDFs keep their own |
| Default template for new notebooks | none |
| Scrolling direction horizontal / vertical | vertical only |
| Show page number on the page | not shown in the editor |
| Spellcheck for typed text | none |
| Troubleshooting: rebuild thumbnails / search index | none (caches are rebuildable but no button) |
| Notebook lock | none |
| Go to Page, Trash Bin, toolbar shortcuts | already have (Go to Page via outline/thumbnails) |

## 9. Patterns worth copying into NOTEAPP

1. **Two-level toolbar.** A stable tool row plus a floating option capsule for the active tool. Clicking the active tool opens its detail popover. Every tool has a one-key shortcut, shown in its tooltip.
2. **Per-tool memory.** Each tool keeps its own three widths and three colour slots, plus an add slot. Colours have a History tab.
3. **Fine pen controls.** Instead of many pen styles: three pen types and four sliders (sharpness, pressure, flatness, stabilisation), plus solid/dashed/dotted lines.
4. **Eraser filter by tool.** Generalises "erase highlighter only". Auto-deselect returns to the previous tool.
5. **Lasso filter by object type.** The selection menu also covers z-order, convert-to-text with an editable preview, and Create Element (reusable stickers).
6. **Gestures.** Scribble to erase, circle to lasso, draw-and-hold to snap a shape.
7. **Search UI.** Cropped snippets with the hit highlighted, grouped by document and by source (handwriting vs PDF). In the notebook: a side panel, highlights on the canvas, and next/previous match.
8. **Read-only toggle in the toolbar.** Cheap to build, and protects notes while reading.
9. **Insert-position control** (Before / After / Last) on Add Page, plus "recent templates" that inherit the current page's size and colour.
10. **Toolbar customisation** with reorder and hide.

## 10. Corrections to `GOODNOTES-PARITY-PLAN.md`

| Plan row | What the live app shows |
|---|---|
| "Eight pen styles" | Goodnotes has **3 pen types** (fountain, ball, brush) plus pencil and highlighter. Its depth comes from the four sliders. NOTEAPP's style count is not the gap; the slider controls are |
| Selective eraser "highlighter/tape only" | It is a general **per-tool eraser filter** (pen, pencil, highlighter, tape) |
| Object eraser | Confirmed: Precision / Standard / Object |
| Shape recognition | Confirmed in two forms: **draw-and-hold** and a dedicated **Draw Shape (D) pen mode**, with snap-to-shapes and fill options |
| Tags "not verified" | **No tags in the UI.** The library filter is All / Documents / Folders only |
| Sort "not verified" | **Confirmed**: Sort By, Grid/List and Select in one menu |
| Multi-select "not verified" | Present: "Select" in the same menu |
| Outline and bookmarks | Confirmed: page bookmark ribbons, a "Bookmarks Only" filter, an Outline tab (PDF table of contents, manual "Add Page to Outline", AI outline) |
| Read-only mode | Confirmed: an "Editing Mode" ⇄ "Read Only" toggle in the toolbar |
| Password protection | Confirmed: per-document **Add Lock** plus a global password in Settings → Document Privacy |
| PDF text search | Confirmed: a separate "PDFs" section in global search |
| Tabs / split view | Tabs confirmed; also **Open in New Window**. Split view was not seen |
| Layers ✅ | **Not exposed** anywhere in the 7.1.34 Mac UI explored (toolbar, More, lasso menu, settings). Downgrade to "not verified" |
| Presentation mode ✅ | Not seen. The laser pointer (dot / line) is present |
| Export | Export This Page / Export All / Print. Formats were not opened |
| Handwriting to text | Confirmed: lasso → Convert → Text (editable preview, language auto-detect) or Math |
| Spellcheck | Confirmed: per notebook, plus a personal dictionary |
| Restyle | Present as **Beta** in the lasso bar |
| Not in plan | Convert to Whiteboard (document and pages), Time Keeper, Pin Text Tool, long-press full-page typing, Undo/Redo position setting, insert position on Add Page, Mark as Seen |
