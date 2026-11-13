# Goodnotes: settings, gestures and micro-behaviours

Compiled 2026-11-12 from the **official Goodnotes Support Center** (Zendesk help centre, `/hc/en-us`), the product site, and the existing in-repo walkthrough. This is the fine-grained layer that `GOODNOTES-PARITY-PLAN.md` does not cover: exact setting names, defaults, gesture mappings and per-tool quirks.

**Method.** The help centre exposes a public JSON API, so every article in the relevant sections was fetched in full rather than skimmed: `https://support.goodnotes.com/api/v2/help_center/en-us/sections/<id>/articles.json?per_page=100`. 144 articles across 17 sections were pulled; the settings-bearing ones are cited below. Where an article's age matters it is called out inline (the shortcut reference, for instance, was last updated 2026-08-14).

**Citation style.** `[S4]` resolves to a full URL in `## Sources`. Every claim in the tables has a ref. Anything I could not find in a primary source is in `## Unverified` rather than stated as fact.

**Two corroborating sources of a different kind:**

- `[W]` — `research_notes/goodnotes-walkthrough/WALKTHROUGH.md` in this repo: a click-through of the installed **Goodnotes 7.1.34** for Mac made in this project. Used only for settings that exist in the app UI but have no help article.
- `[IMG]` — screenshots downloaded into `images/` from help articles; where an image contradicts the article text, the image is described.

A `⚠` marks a place where the help centre contradicts itself or the live app.

---

## Sources

| Ref | URL | Note |
|---|---|---|
| S0 | https://support.goodnotes.com | Help centre root; confirms the two categories (Goodnotes, GoodNotes 5). |
| S1 | https://support.goodnotes.com/hc/en-us/articles/6554036735631-Zoom-pan-and-scroll-through-pages-in-Goodnotes | Zoom/pan/scroll gestures per input device; keyboard zoom shortcuts; scroll direction path. |
| S2 | https://support.goodnotes.com/hc/en-us/articles/7353756826383-Write-with-the-Zoom-Window | Zoom Window: auto-advance, blue advance area, resize handles, return height in points, iOS-only. |
| S3 | https://support.goodnotes.com/hc/en-us/articles/7353743272719-The-Zoom-Window-is-not-advancing-automatically-when-I-write | Proves the Auto Advance toggle lives in More → Document Editing. |
| S4 | https://support.goodnotes.com/hc/en-us/articles/7353727026959-Configure-palm-rejection-for-comfortable-writing | "Stylus & Palm Rejection" panel; Low/Medium/High; which styluses need it. |
| S5 | https://support.goodnotes.com/hc/en-us/articles/7353756785679-Write-and-customize-ink-with-the-Pen-tool | Pen: 3 types, 4 sliders, solid/dashed/dotted, Draw and Hold. |
| S6 | https://support.goodnotes.com/hc/en-us/articles/7353718215823-Using-the-Highlighter-tool | Highlighter settings; "Draw in Straight Line"; text highlight as a formatting attribute. |
| S7 | https://support.goodnotes.com/hc/en-us/articles/7353718249231-Erase-handwriting-and-page-content-with-the-Eraser-tool | Eraser styles, Erase Filter, Clear Page, Auto-Deselect. |
| S8 | https://support.goodnotes.com/hc/en-us/articles/7353695644175-Select-Move-and-Edit-Content-With-the-Lasso-Tool | Lasso types, Included in Selection, Object Alignment, modifier keys, Disconnect Apple Pencil. |
| S9 | https://support.goodnotes.com/hc/en-us/articles/13682939148943-Draw-shapes-and-build-diagrams-in-Goodnotes | Shape tool, AutoShape, rounded corners default, connectors, Quick Diagramming, Lock Shape. |
| S10 | https://support.goodnotes.com/hc/en-us/articles/9489290046607-Use-the-Tape-Tool-to-hide-and-reveal-content | Tape: reveal with finger, straight tape, remove all tape, slot limits, patterns. |
| S11 | https://support.goodnotes.com/hc/en-us/articles/8254946748687-Draw-Straight-Lines-With-the-Ruler-Tool | Ruler: both edges snap, two-finger rotate, Set Angle/Position, Hide Digits, inches/cm. |
| S12 | https://support.goodnotes.com/hc/en-us/articles/7353727615375-Type-text-with-the-Text-Tool | Text: Pin Text Tool, Save as Default, long-press → Start Typing, full-page limits, shortcut discovery. |
| S13 | https://support.goodnotes.com/hc/en-us/articles/14069931315983-Quick-gestures-for-Undo-and-Redo | 2-finger double-tap undo, 3-finger double-tap redo; no in-app toggle. |
| S14 | https://support.goodnotes.com/hc/en-us/articles/7443501398671-Erase-Handwriting-With-Scribble-to-Erase | Scribble to Erase scope and how to turn it off. |
| S15 | https://support.goodnotes.com/hc/en-us/articles/7443556793103-Select-content-with-the-Circle-to-Lasso-pen-gesture | Circle to Lasso is **on by default**; exact 4-step sequence. |
| S16 | https://support.goodnotes.com/hc/en-us/articles/9756420431759-Preview-Strokes-With-Apple-Pencil-Hover-on-iPad | Hover previews the stroke and tool tooltips; requires the system setting. |
| S17 | https://support.goodnotes.com/hc/en-us/articles/9757771783823-Utilize-the-new-features-of-Apple-Pencil-Pro | Squeeze opens the Palette; barrel roll needs Fountain Pen + React to Pen Rotation. |
| S18 | https://support.goodnotes.com/hc/en-us/articles/8900755183631-Customize-the-toolbar | Toolbar customization rules: what cannot move, resets, undo/redo position, no presets. |
| S19 | https://support.goodnotes.com/hc/en-us/articles/17220521238159-Keyboard-Shortcuts-in-Goodnotes | The authoritative shortcut list (updated 2026-08-14), platform-annotated. |
| S20 | https://support.goodnotes.com/hc/en-us/articles/16536297803535-Organize-content-with-layers | Layers: 5 fixed, no lock/reorder, active layer, global Show Layers toggle, export visible only. |
| S21 | https://support.goodnotes.com/hc/en-us/articles/16348150581647-Add-sticky-notes-to-your-notes | Sticky note collapse/expand and export behaviour. |
| S22 | https://support.goodnotes.com/hc/en-us/articles/7353727577359-Create-Use-and-Share-Elements | Elements/collections, Create Element, GIF offline rules. |
| S23 | https://support.goodnotes.com/hc/en-us/articles/7353757120655-Use-Read-Only-Mode-to-navigate-without-editing | Read Only mode: what still works, why links need it. |
| S24 | https://support.goodnotes.com/hc/en-us/articles/7353695996559-Change-the-scrolling-direction-in-Goodnotes | Per-document vs per-device default path for scrolling direction. |
| S25 | https://support.goodnotes.com/hc/en-us/articles/7353743594127-How-to-Search-Your-Notes | Exactly what is indexed; PDFs without OCR are not searchable. |
| S26 | https://support.goodnotes.com/hc/en-us/articles/7353727932047-Handwriting-Recognition-and-Search-Languages-in-Goodnotes | Supported recognition languages; the real setting name "Default Language for New Documents". |
| S27 | https://support.goodnotes.com/hc/en-us/articles/7353695209743-I-can-t-search-my-notes | "Index PDF and Handwritten Notes" toggle; the language-toggle re-index trick; indexing progress string. |
| S28 | https://support.goodnotes.com/hc/en-us/articles/14500614035471-Spellcheck-your-handwriting | Handwriting spellcheck: red underline, tap for suggestions, AI re-draws in your style, Personal Dictionary. |
| S29 | https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes | Auto Backup: one-way, providers, ~12h cadence, frequency toggle, formats, excluded names. |
| S30 | https://support.goodnotes.com/hc/en-us/articles/7353694866831-Back-up-and-restore-your-library-manually | Manual backup must stay in foreground. |
| S31 | https://support.goodnotes.com/hc/en-us/articles/9585471154447-Lock-notebooks-and-whiteboards-with-Password-Protection | One universal password, Face ID, 2-minute relock, excluded from Auto Backup. |
| S32 | https://support.goodnotes.com/hc/en-us/articles/7353727934223-Present-Goodnotes-on-an-external-screen | Presentation Mode: three mirror options, laser dot/trail. |
| S33 | https://support.goodnotes.com/hc/en-us/articles/7353757107215-Open-Goodnotes-in-multiple-windows-on-iPadOS | Multi-window gestures, dragging lasso selections and pages between windows. |
| S34 | https://support.goodnotes.com/hc/en-us/articles/7353743758991-Change-a-page-template-in-Goodnotes | Per-page template/colour/size/orientation change. |
| S35 | https://support.goodnotes.com/hc/en-us/articles/7353728093199-Import-and-manage-custom-notebook-templates | Manage Notebook Templates; import takes first page only. |
| S36 | https://support.goodnotes.com/hc/en-us/articles/7353756250383-Creating-a-notebook-without-a-cover | Cover off. |
| S37 | https://support.goodnotes.com/hc/en-us/articles/7353727601807-Create-and-Manage-a-QuickNote | QuickNote inherits the last/default template; save/combine/delete on return. |
| S38 | https://support.goodnotes.com/hc/en-us/articles/7353757101071-Create-and-manage-document-outlines | Outline: manual add, 3 nesting levels, AI generation, sort by page number. |
| S39 | https://support.goodnotes.com/hc/en-us/articles/7353727934095-Use-Favorites-and-bookmarks-in-Goodnotes | Favourites vs page bookmarks. |
| S40 | https://support.goodnotes.com/hc/en-us/articles/13682253498767-Improved-User-Interface | Sticky vs non-sticky tools; object menu appears on selection; scale vs resize. |
| S41 | https://support.goodnotes.com/hc/en-us/articles/15303674514191-Organize-folders-and-documents-in-Goodnotes | Folder colour/icon, grid/list, filter, bulk export. |
| S42 | https://support.goodnotes.com/hc/en-us/articles/7353742824975-Export-documents-or-pages | Export formats and scopes; folder export is a zip. |
| S43 | https://support.goodnotes.com/hc/en-us/articles/7353695997199-Convert-handwriting-to-text | Convert via lasso → (…) → Convert → Text. |
| S44 | https://support.goodnotes.com/hc/en-us/articles/7353717662991-Use-Goodnotes-on-macOS | Mac gaps: no Zoom Window, no Word/PPT import, session restore is a macOS setting. |
| S45 | https://support.goodnotes.com/hc/en-us/articles/10012900399887-Use-Time-Keeper-in-Goodnotes-on-iPhone-or-iPad | Time Keeper timer/stopwatch, history, alert on closing. |
| S46 | https://support.goodnotes.com/hc/en-us/articles/7353743265039-Add-and-manage-writing-tool-color-presets | 3 default colour slots, up to 12; palettes do not sync across tools; restore original. |
| S47 | https://support.goodnotes.com/hc/en-us/articles/13590309421327-Can-I-use-my-mouse-to-take-notes | Mouse/trackpad works but has no pressure sensitivity. |
| S48 | https://support.goodnotes.com/hc/en-us/articles/14141163656335-Working-with-Objects | Front/Back ordering; locked objects can still be duplicated. |
| S49 | https://support.goodnotes.com/hc/en-us/articles/5616018181903-Why-is-the-Eraser-automatically-switched-to-when-I-m-writing | The only Goodnotes text on Apple Pencil double-tap: it can silently switch you to the Eraser. |
| S50 | https://support.goodnotes.com/hc/en-us/articles/7353717663887-Use-Scribble-in-Goodnotes | Apple Scribble is separate from Goodnotes recognition; changing one does not change the other. |
| S51 | https://support.goodnotes.com/hc/en-us/articles/13662989983503-What-are-Board-Limits | Whiteboard has a hard content limit despite the infinite canvas. |
| S52 | https://support.goodnotes.com/hc/en-us/articles/7353743248143-Create-external-and-internal-links | Internal links are notebook/whiteboard only; ⌘K. |
| S53 | https://support.goodnotes.com/hc/en-us/articles/9497798035983-Use-the-Sidebar-to-navigate-your-document | Sidebar tabs per document type; Bookmarks Only filter. |
| S54 | https://support.apple.com/guide/ipad/ipad63913965/ipados | Where Apple Pencil double-tap and squeeze sensitivity are actually configured (system Settings). |
| S55 | https://www.goodnotes.com/features | Marketing feature index. Read; contains no setting names, used only for document-type framing. |
| S56 | https://support.goodnotes.com/hc/en-us/articles/13724030806927-What-s-new-for-the-September-launch | September launch release summary: whiteboards, text documents, toolbar redesign. No settings detail — evidence of the *absence* of a changelog. |
| W | research_notes/goodnotes-walkthrough/WALKTHROUGH.md | In-repo click-through of Goodnotes 7.1.34 Mac: settings that exist in the UI with no help article. |

---

## Settings

Goodnotes has **no single Preferences window**. Settings are split across four places, and knowing which is which is most of the design lesson:

1. **Library → Goodnotes menu (top-right) → Settings** — account-wide.
2. **Document → More (…) → Document Editing / Scrolling Direction / Stylus & Palm Rejection** — per-document, but the footer says *"These settings apply to all other documents"* `[W]`.
3. **A tool's own popover** — opened by tapping the *already-selected* tool a second time. This is where pen/eraser/lasso/tape options live.
4. **A slot's own popover** — tap a selected thickness or colour slot a second time.

### Account-wide (Library → Goodnotes menu → Settings)

| Screen/path | Setting (exact name) | Options/default | Effect | Source |
|---|---|---|---|---|
| Settings → Document Editing | **Scrolling Direction** | Horizontal / Vertical; app-observed default Vertical | Default page-scroll axis for documents on iPhone/iPad. Other platforms only get the per-document setting. | [S24], [W] |
| Settings → Document Editing | **Toolbar Customization ▸** | Tools / Accessories tabs | Opens the toolbar editor (see below). | [W], [S18] |
| Settings → Document Editing | **Undo and Redo Position** | Left / Right; observed Left | Which screen edge the undo/redo pair floats on. | [S18], [W] |
| Settings → Document Editing | **Open Documents as New Tabs** | On by default | A second notebook opens as a tab instead of replacing the current one. | [W] |
| Settings → Document Editing | **Automatically Open New Imported Documents** | On (observed) | Import jumps straight into the imported file. | [W] |
| Settings → Document Editing | **Pull to Add Page** | On (observed) | Overscrolling past the last page inserts a page. | [W] |
| Settings → Document Editing | **Show Page Number** | On (observed) | Prints the page number on the page surface itself, not just the HUD. | [W] |
| Settings → Document Editing | **Show Hover Preview** | On (observed) | Apple Pencil hover previews the stroke / shows tool tooltips. | [W], [S16] |
| Settings → Document Editing | **Show Layers** | Off unless Layers rolled out | Global switch for the Layers panel; hiding it also hides layer content. | [S20], [W] |
| Document Language | **Default Language for New Documents** | English (US) | Recognition + search + AI language for new notebooks. List covers ~15 languages. | [S26] |
| Handwriting Recognition | **Index PDF and Handwritten Notes** | Single switch; observed **off** on the walkthrough account | Master switch for search indexing. Off means notebooks are not searchable. | [S27], [W] |
| Writing Aids | **Enable Spellcheck for New Documents** | On by default | Default for new documents only. | [W] |
| Writing Aids | **Advanced Settings** (dictionary) | — | Where the handwriting-spellcheck default for new documents is changed. | [S28] |
| Writing Aids → Custom Words | **Personal Dictionary** | Empty | Words never flagged as misspelt. | [S28], [W] |
| Document Privacy | **Setup / Set up Password Protection** | Off | One case-sensitive password for every locked document; optional Face ID/Touch ID. | [S31] |
| Notification Preferences | one marketing switch | On | Marketing notifications only. | [W] |
| Troubleshooting | **Restore Default Templates** | — | Resets built-in templates; custom templates kept. | [W] |
| Troubleshooting | **Regenerate Missing Thumbnails** | — | Rebuilds the thumbnail cache. | [W] |
| Troubleshooting → Advanced | **Debug Mode** | Off | Diagnostics. | [W] |
| Profile menu → Manage Notebook Templates | **Cover / Paper / Size / Color** | Cover on; A4 portrait; observed Squared | The **default paper for new notebooks** and for QuickNotes. | [S35], [S36], [S37] |
| Profile menu → Cloud & Backup | Cloud Sync, **Manual Backup Documents** | Sync off in walkthrough | Manual `.zip` backup of the library. | [S30], [W] |
| Cloud & Back up Status → Cloud & Backup Settings | **Increase Auto Backup frequency** | Off (≈12 h between runs) | Turns background backup from ~12 h to ~1–2 min. | [S29] |
| Auto Backup dialog | Provider | Google Drive / Dropbox / OneDrive / WebDAV | One-way backup target. No iCloud Drive, no macOS support. | [S29] |
| Auto Backup dialog | **File format** | Goodnotes Document / PDF / PDF and Goodnotes Document | PDF copies are flattened and not re-editable. | [S29] |
| Auto Backup dialog | Destination folder | `Goodnotes` | Subfolders via `/`; Google Drive ignores custom folders; Dropbox limited to `Apps/Goodnotes 6`. | [S29] |
| Auto Backup dialog | **Excluded File Names** | Empty | Any document whose title contains an excluded string is skipped. | [S29] |

### Per-document (Document → More (…))

| Screen/path | Setting (exact name) | Options/default | Effect | Source |
|---|---|---|---|---|
| More (…) | **Scrolling Direction** | Horizontal / Vertical | This document only; footer says the change applies to all other documents too. | [S24], [W] |
| More (…) | **Stylus & Palm Rejection** | Low (recommended) / Medium / High | Rejection sensitivity for finger or capacitive-stylus writing. Also reachable from Library Settings. | [S4] |
| More (…) → Document Editing | **Auto Advance** | On (observed) | Drives the Zoom Window's automatic forward movement. | [S3], [S2] |
| More (…) → Document Editing | **Toolbar Customization ▸** | — | Same editor as the global one. | [S18] |
| More (…) → Document Editing ▸ | **Show Layers** | — | Per-device visibility of the Layers panel. | [S20] |
| More (…) | **Sidebar** | Left / Right | Which edge the page panel docks to. | [W] |
| More (…) | **Align Objects** | On | Snap guides while dragging; dashed = centre alignment, solid = edge alignment. | [S8], [W] |
| More (…) | **Add Lock** | Off | Locks this document with the universal password. | [S31], [W] |
| More (…) | **Show Resolved Comments** | Off | Comment threads display. | [W] |
| More (…) | **Change Template** | Current template | Paper, colour, size (Goodnotes Standard, A3–A7, Letter, Tabloid, Custom), orientation. | [S34], [W] |
| More (…) | **Delete Specific Items ▸** | All kinds on | Clears only chosen kinds from the page: Pen, Pencil, Highlighter, Tape, Text, Elements, Images, Sticky Notes. | [W] |
| More (…) | **Clear Page** | — | Removes content, keeps the page. | [S7], [W] |
| More (…) | **Rotate Page ▸** | — | CW 90°, CCW 90°, 180°. | [W] |
| More (…) | **Go to Page** | Range shown | Number field jump. | [W] |
| More (…) | **Add Page to Outline** | — | Creates an outline entry for this page. | [S38], [W] |
| Nav bar | **Read Only Mode** toggle | Edit | Hides the writing toolbar and turns the nav bar white. | [S23] |

### Pen settings (tap Pen a second time)

| Screen/path | Setting (exact name) | Options/default | Effect | Source |
|---|---|---|---|---|
| Pen → stroke preset | **Solid / Dashed / Dotted** | Solid | Line style per thickness slot. | [S5] |
| Pen → stroke preset | Thickness slider | 0.3 / 0.9 / 1.5 mm presets | Per-slot width; first 3 slots are saved presets. | [W], [S5] |
| Pen | **Fountain Pen / Ball Pen / Brush Pen** | Fountain sense pressure, Ball does not, Brush most | Three pen *types*, not eight styles. | [S5] |
| Pen | **Tip Sharpness** | 50% | Round → sharp stroke ends where supported. | [S5], [W] |
| Pen | **Pressure Sensitivity** | 50% | Width response to pressure. "Min" reduces but never removes it. | [S5] |
| Pen | **Tip Flatness** | Round | Blunt fountain-pen tip on supported Apple devices. | [S5], [W] |
| Pen | **Stroke Stabilization** | 0% | Smooths jitter; costs latency/expressiveness. | [S5], [W] |
| Pen | **Reduce Latency** | On (observed) | Trades prediction for immediacy. | [W] |
| Pen | **React to Pen Rotation** | Off | Barrel-roll dynamic ink for the Fountain Pen only. | [S17] |
| Pen → Pen Settings | **Draw and Hold** | On | Hold at stroke end to snap to a shape; while holding you can adjust scale and angle. | [S5], [S9] |
| Pen → Pen Settings → Draw and Hold | **Snap to Other Shapes** | On | Endpoints connect to nearby shapes/endpoints. | [S5], [W] |
| Pen → Pen Settings → Draw and Hold | **Fill Color** | Off | Fill the recognised shape. | [W] |
| Pen → Pen Gestures | **Scribble to Erase** | On | Pen-only erase by scribbling over ink. | [S14], [W] |
| Pen → Pen Gestures → Scribble to Erase | **Erase Shapes and Highlighter** | Off (observed) | Extends scribble-erase beyond pen strokes. | [W] |
| Pen → Pen Gestures | **Circle to Lasso** | **On by default** | Circle + long-press converts the circle into a lasso selection. | [S15] |
| Pen → Writing Aids | **Check Handwriting Spelling** | On | Per-document handwriting spellcheck. | [S28], [W] |
| Pen → Writing Aids | **Recognition Language** | English (US) | Per-document recognition language. | [W] |
| Pen → Math Assist | **Suggestions** | On | Equation suggestions while writing maths. | [W] |
| Pen → colour slot | Presets / Custom / History tabs | 3 slots, max 12 | Per-tool palettes; they deliberately do **not** sync between tools. | [S46], [W] |
| Pen → colour slot → Settings | **Restore Color Sets to Original** | — | Resets that tool's palette only. | [S46] |

### Other tool settings

| Screen/path | Setting (exact name) | Options/default | Effect | Source |
|---|---|---|---|---|
| Highlighter (tap twice) | **Draw in Straight Line** | Off | Forces every highlighter stroke horizontal-straight regardless of hand wobble. | [S6] |
| Highlighter | **Stroke Stabilization** | — | Same slider as the pen. | [S6] |
| Highlighter | **Reduce Latency** | On | Same as pen. | [W] |
| Eraser (first icon) | **Precision / Standard / Stroke** ⚠ | Precision | Pixel-level / small segment of a continuous stroke / whole continuous stroke. The live app labels the third one **Object**. | [S7], [W] |
| Eraser → **Erase Filter** | Pen, Pencil, Highlighter, Tape + **Select all** | All on | "The eraser ignores marks from any tool that's turned off." | [S7], [IMG] |
| Eraser → Advanced Settings | **Clear Page** | — | Wipes page content. | [S7] |
| Eraser → Advanced Settings | **Auto-Deselect** | **Off** (screenshot) | Returns to the previous tool when the stylus lifts. | [S7], [IMG] |
| Lasso (tap twice) | **Lasso Type** | Freehand (default) / Rectangular | Freehand loop vs drag-frame. | [S8] |
| Lasso → **Included in Selection** | Handwriting, Images, Shapes, Arrows, Text Boxes, Equations, Tape, Sticky Notes | All on | What the lasso is allowed to grab. | [S8], [W] |
| Lasso → Advanced | **Disconnect Apple Pencil** | Off | Lets a finger drive the lasso while the Pencil is connected; writing reconnects it. | [S8] |
| Tape (tap twice) | **Straight Tape** | Off | Forces tape perfectly straight. | [S10] |
| Tape | **Remove All Tape** | — | Clears tape from the current page. | [S10] |
| Tape | colour/pattern slots | 3 slots, min 3 to delete | Patterns sit below solid colours; History tab of recent patterns. | [S10] |
| Text | **Pin Text Tool** | Off | Keeps Text active for consecutive boxes; auto-clears when you switch tools. | [S12], [W] |
| Text → Save as Default | — | — | Saves current formatting as the default for new text boxes. | [S12] |
| Shapes | **Fill Color** toggle | Off | Fill vs stroke-only. | [W] |
| Shapes | Rounded corners | **On by default** for new shapes | Existing shapes keep their old appearance. | [S9] |
| Ruler (tap twice) → Options | **Hide Digits**, **Change to Inches/Centimeters** | Digits on | Unit and label display. | [S11] |
| Ruler (tap twice) | **Set Angle**, **Set Position**, **Hide** | — | Precise ruler placement. | [S11] |
| Zoom Window ⋯ → **Height** | Return height in points, then **Apply** | Per-template default | How far "new line" and auto-advance move down. | [S2] |
| Toolbar Customization | Hide/unhide (red −/green +), reorder, **Reset to Default Toolbar / Writing Tools Layout / Accessories Layout** | Lasso and Audio cannot be moved or hidden | Applies to all notebooks and whiteboards; **no saved presets**. | [S18] |
| Layers panel | visibility toggles, active layer | 5 layers | Cannot lock, reorder or move content between layers. | [S20] |

---

## Gestures

| Input | Gesture | Action | Configurable? | Source |
|---|---|---|---|---|
| 2 fingers | Double-tap anywhere on the page | **Undo** | No in-app toggle | [S13] |
| 3 fingers | Double-tap anywhere on the page | **Redo** | No in-app toggle; conflicts with OS 3-finger gestures on Windows | [S13] |
| 2 fingers | Spread / pinch | Zoom in / out | — | [S1] |
| 1 finger (or double-tap page) | Double-tap the page | Zoom in (cycle) | — | [S1] |
| 1 finger | Drag page | Pan while zoomed | — | [S1] |
| 1 finger | Swipe in the document's scroll axis | Previous / next page | Scrolling Direction | [S1] |
| 1 finger | Drag the right-edge scrollbar | Fast page scrub (horizontal mode only) | — | [S1] |
| 1 finger | **Long-press the page** | Pop-up menu: **Zoom**, **Start Typing**, Paste | — | [S2], [S12] |
| 1 finger | Tap tape | Reveal what is underneath | — | [S10] |
| 1 finger | Double-tap a text box | Edit that box's text (Quick Selection) | — | [S40] |
| 1 finger | Triple-tap text | Select the whole paragraph | — | [S12] |
| 1 finger | Long-press PDF text | Highlight / Strikeout / Define / Speak / Copy | — | [S23] |
| 1 finger | Long-press a PDF text selection → **Highlight** | Yellow highlight stroke (erasable) | Always yellow | [S6] |
| 1 finger | Long-press a thumbnail / tab / document | Lift to drag (reorder, split view, another window) | — | [S33] |
| 2 fingers | On the ruler | Rotate it | — | [S11] |
| 1 finger | On the ruler | Slide the scale along the ruler | — | [S11] |
| Pencil | **Scribble** densely over pen ink | Erase those pen strokes | Pen → Pen Gestures → Scribble to Erase | [S14] |
| Pencil | Draw a **closed circle** around content, lift, then **long-press the circle** | Circle becomes a dotted lasso selection | Pen → Pen Gestures → Circle to Lasso (default on) | [S15] |
| Pencil | **Draw and hold** at the end of a stroke | Snap to line/curve/oval/polygon; keep holding to scale and rotate | Pen Settings → Draw and Hold | [S5], [S9] |
| Pencil | **Hover** (no contact) | Preview the stroke at the tip; tool tooltips | iPad Settings → Apple Pencil → Apple Pencil Hover | [S16] |
| Pencil Pro | **Squeeze** | Opens the floating Palette | Not customizable | [S17], [S18] |
| Pencil Pro | **Barrel roll** | Changes Fountain Pen ink flow | Needs React to Pen Rotation | [S17] |
| Apple Pencil (2nd gen) | **Double-tap** on the barrel | System-assigned action (e.g. switch to eraser) | Configured in iPad Settings, **not** in Goodnotes | [S49], [S54] |
| Pencil (in lasso) | Hold **Option/Alt** while resizing | Scale from the centre | — | [S8] |
| Pencil (in lasso) | Hold **Shift** while resizing a shape/sticky | Keep proportions (images already keep aspect by default) | — | [S8] |
| Finger (with Pencil held) | Any multi-finger gesture | Works while the Pencil rests in the other hand — no need to put it down | — | [S13] |
| Mouse | Drag | Pan / navigate; no pressure sensitivity | — | [S47] |
| Trackpad | 2-finger drag / pinch | Pan / zoom | — | [S1] |
| Keyboard arrows | Arrow keys | Pan a zoomed page | — | [S1] |

---

## Keyboard shortcuts

From the single authoritative article [S19] (updated 2026-08-14). `⌘` on macOS/iPadOS, `Ctrl` on Windows/Web. iPad needs an external keyboard, and tool keys do not fire while a text box has focus.

### File

| Action | Shortcut | Platforms |
|---|---|---|
| New Window | ⌘N | mac, iPad, Win, Web |
| New Notebook | ⌥⌘N | mac, iPad, Win |
| New QuickNote | ⇧⌘N | mac, iPad, Win |
| New Text Document | ⇧⌘T | mac, iPad, Win |
| New Whiteboard | ⇧⌘W | mac, iPad |
| Open | ⌘O | mac, Win |
| Close tab | ⌘W | mac, iPad, Win |
| Close all tabs | ⌥⌘W | **iPad only** |
| Rename | ⌘R | document view only |
| Export | ⇧⌘E | document view |
| Share and Export | ⇧⌘S | document view |
| Print | ⌘P | mac, Win |
| Quit | ⌘Q | mac, iPad, Win |

### Edit

| Action | Shortcut | Notes |
|---|---|---|
| Undo / Redo | ⌘Z / ⇧⌘Z | Ctrl+Y also redoes |
| Cut / Copy / Paste | ⌘X / ⌘C / ⌘V | |
| Paste and Match Style | ⌥⇧⌘V | mac, iPad only |
| Delete | Delete / Backspace | |
| Select All | ⌘A | Also selects in library and thumbnails |
| Duplicate | ⌘D | |
| Find / Find Next / Find Previous | ⌘F / ⌘G / ⇧⌘G | Find Next/Prev mac + Win |
| Dismiss | Esc | Closes search, menus, overlays |

### View and navigation

| Action | Shortcut | Notes |
|---|---|---|
| Full Screen | Fn+F | mac, iPad, Web |
| Zoom In / Out | ⌘+ / ⌘− | Also ⌘ + scroll wheel |
| Actual Size | ⌘0 | |
| Zoom to Fit | ⌘9 | |
| Show/Hide Sidebar | ⌃⌘S | mac; library view |
| Jump to Page | ⌥⌘G | mac, Win |
| Switch tab 1–9 | ⌘1–9 | mac |

### Tools (single key, no modifier)

| Tool | Key | Tool | Key |
|---|---|---|---|
| Pen | P | Shape | S |
| Pencil | **2** | Lasso | V |
| Highlighter | H | Text | T |
| Eraser | E | Image | I |
| Draw Shape (shape pen mode) | D | Elements | M |
| Tape | A | Writing Tools group | W |
| Laser | L | Sticky Notes | N |
| Ruler | R | Timer | K |
| Ask Goodnotes | ⌥⌘A | | |

### Text formatting

| Action | Shortcut |
|---|---|
| Bold / Italic / Underline | ⌘B / ⌘I / ⌘U |
| Strikethrough | ⇧⌘X |
| Add/Edit link | ⌘K |
| Highlight | ⇧⌘H |
| Subscript / Superscript | ⌃⌘, / ⌘. |
| Inline code | ⌘E |
| Block quote | ⇧⌘. |
| Paragraph / H1 / H2 / H3 | ⌥⌘0 / ⌥⌘1 / ⌥⌘2 / ⌥⌘3 |
| Todo / Bulleted / Numbered / Code block | ⌥⌘4 / ⌥⌘5 / ⌥⌘6 / ⌥⌘8 |
| Align left / centre / right | ⌘{ / ⌘\ / ⌘} (Windows) |

The in-app list is discoverable: **long-press the ⌘ key on a hardware keyboard** and the full sheet appears `[S12]`. Text-document-only shortcuts (tables, blocks, word-delete) are listed in [S19].

---

## Tool micro-behaviours

The layer the parity plan misses. Each line is a behaviour you only notice after a week of use.

### Writing tools as a group

- **Sticky vs non-sticky tools.** Sticky (stay active): Lasso, Pen, Pencil, Highlighter, Eraser, Tape, Laser Pointer. Non-sticky (revert to Lasso after one use): Images, Elements, Shapes, Sticky Notes, Textbox — which also enters typing state immediately `[S40]`.
- **Selected tool, tapped again, opens its options.** A second tap on the active tool is the universal "settings" gesture; a third tap on a sub-tool closes the popover and returns to the previous tool `[W]`.
- **The Active Tool Menu is draggable** to any of the four screen edges, and can be docked vertically `[S18]`, and temporarily hidden by tapping Writing Tools in the top bar and tapping again `[S18]`.
- **Every tool keeps its own palettes.** Changing the Tape palette never changes the Pen palette — documented as intentional `[S10]`, [S46].
- **Colour slots: 3 by default, 12 max, per tool**, with a History tab of recently used colours `[S46]`.

### Pen

- Three *types* (Fountain / Ball / Brush) rather than many styles. Depth comes from the four sliders `[S5]`.
- **Pressure Sensitivity at "Min" still varies** — the minimum reduces, never removes, pressure response `[S5]`.
- Draw-and-hold snap is available from Pen, Pencil *and* Highlighter, not only the Shape tool `[S9]`.
- While holding a snapped shape you can still adjust its **scale and angle** before release `[S9]`.
- **Circle to Lasso is on by default**, so a deliberate circle around text followed by a long-press silently turns into a selection `[S15]`.

### Highlighter

- **Highlighter strokes render under pen ink**, and "the highlighter is useful for drawing over words without affecting their visibility" `[S6]`.
- **Text highlight is not a stroke.** Highlighting typed text (text boxes, sticky notes, shapes) is a formatting attribute attached to the characters: it cannot be erased with the Eraser, its opacity cannot be changed, and overlapping colours replace rather than blend `[S6]`.
- Highlighting a **PDF** text selection always produces a yellow stroke, and that one *is* erasable `[S6]`.
- The highlighter can draw shapes with draw-and-hold `[S6]`.

### Eraser

- **Three styles by name, mildly inconsistent:** help says Precision / Standard / Stroke; the 7.1.34 UI says Precision / Standard / **Object** ⚠ `[S7]`, [W].
- **Erase Filter is a per-tool allow-list**, not an "erase highlighter only" checkbox. It is the generalisation that makes selective erase work for pen, pencil, highlighter and tape `[S7]`.
- **Auto-Deselect** returns to the previous tool on stylus lift — the single cheapest "feels native" switch in the app `[S7]`.
- The eraser never touches typed text, PDF text, images or scans; those need the lasso `[S7]`.

### Lasso

- **Freehand is the default**; rectangular exists but is opt-in `[S8]`.
- **The Object Menu appears the moment the loop closes** — no second tap `[S40]`.
- Selecting anything **auto-selects the Lasso tool** in the toolbar, so you can keep selecting without switching tools `[S40]`.
- **Object Alignment** shows dashed guides for centre alignment, solid for edge alignment; it is a single switch in More → Align Objects `[S8]`.
- Images keep their aspect ratio by default; shapes and sticky notes resize freely; Shift constrains them `[S8]`.
- **Disconnect Apple Pencil** lets a finger run the lasso while the Pencil is still paired, and writing reconnects it `[S8]`.

### Shapes

- **New shapes get subtly rounded corners by default**; "existing diagrams may keep their original appearance" `[S9]`.
- **Connectors stay attached** when either shape moves or resizes; control points can be dragged to add bends `[S9]`.
- **Quick Diagramming:** drag from an edge dot of a selected shape to spawn a connected shape `[S9]`.
- Shape frames, not text, take focus after creation on keyboard iPads/Macs — reselect before restyling `[S9]`.

### Zoom Window

- iOS only, and **unavailable on Mac** `[S2]`, [S44].
- Reached from the toolbar *or* by long-pressing the page → Zoom `[S2]`; it is an **Accessory**, so on a default toolbar it lives under the Accessories dropdown and must be added to the toolbar in Toolbar Customization `[IMG]`, [S18].
- **Auto-advance**: crossing the middle of the window reveals a **blue area** on the window's left edge and a matching blue box on the page; writing in the blue area walks the box forward `[S2]`.
- At the page's right edge it **moves down one line** — and the best result is a **ruled template with the window shrunk to one line height and the margin set to match the template** `[S2]`.
- **Resize changes magnification:** smaller box = higher zoom. One handle scales both axes keeping aspect; the other changes height only `[S2]`.
- Return height is a **number in points**, per template, edited from the window's ⋯ menu `[S2]`.
- Auto-advance is a *document* setting (More → Document Editing → Auto Advance), which is why people think the window is broken `[S3]`.

### Text

- **Pin Text Tool** keeps the tool armed for consecutive boxes and clears itself when you switch tools `[S12]`.
- **Long-press anywhere on the page → Start Typing** turns the whole page into one text area `[S12]`.
- Full-page text is Helvetica-only, does not reflow across pages, and exporting is PDF/Goodnotes/JPG only `[S12]`.
- **Save as Default** on the object menu persists formatting for future boxes `[S12]`.
- Large pastes are clipped at the page edge and hidden until the box is resized `[S12]`.

### Tape

- **Reveal with a finger, not the Pencil** — so the writing hand cannot accidentally un-hide an answer `[S10]`.
- Tape is revealable **in Read Only Mode** `[S10]`.
- Tape survives Goodnotes sharing but is **inert in an exported PDF** — it prints as a solid block `[S10]`.
- Patterns are a first-class palette alongside colours; custom patterns can be a 100×100 px image `[S10]`.

### Laser pointer

- Two modes: **Dot** (follows touch) and **Trail** (fading trail) `[S32]`, [W].
- It is a presentation aid, not ink: nothing is written to the page `[S32]`.

### Ruler

- **Both edges snap**, and strokes drawn along either edge come out straight `[S11]`.
- **The scale follows zoom level**, so it measures real millimetres at any magnification `[S11]`.
- It cannot draw on its own; it only constrains Pen/Pencil/Highlighter `[S11]`.
- Two fingers rotate; one finger slides the scale; Set Angle for precision; Hide Digits and inches/cm under Options `[S11]`.

### Elements

- **Any lasso selection can become an Element** (More → Create Element), including handwriting `[S22]`.
- Collections can be renamed, reordered, shared as a file, and appear as tabs in the panel `[S22]`.
- GIPHY GIFs animate on the page and need a connection only to *search*; already-inserted GIFs and saved Elements work offline `[S22]`.

### Sticky notes

- **Collapse** hides the body but keeps a pin; **collapsed notes export as icons**, expanded ones export in full `[S21]`.
- Handwriting can be attached to a note so it moves with it `[S21]`.

### Layers

- **Exactly 5 layers, fixed.** Cannot be locked, reordered, or have content moved between them `[S20]`.
- Drawing, erasing, highlighting and lasso all act **only on the active layer** `[S20]`.
- Editing a hidden layer **auto-unhides it with an alert** `[S20]`.
- **Export includes only currently visible layers** — the documented way to share a "clean" version `[S20]`.

### Search

- Indexes handwriting, typed text, PDF text, scanned text, titles and outlines; **a PDF with no OCR layer stays unsearchable** — Goodnotes does not add OCR `[S25]`.
- There is a visible progress state, "Indexing *x* pages for search…", and results are incomplete until it clears `[S27]`.
- **Re-index trick:** open the document, tap the title, change the recognition language and change it back `[S27]`.
- Recognition language and Apple Scribble are independent systems; changing one does not change the other `[S50]`.

### Spellcheck

- Misspelt **handwriting** gets a red underline; tapping it offers suggestions and the app **re-draws the corrected word in your own handwriting style** using on-device AI `[S28]`.
- Accuracy varies page to page because the style model is built from that page's writing `[S28]`.
- Supported: Dutch, English US/UK, French, German, Italian, Portuguese, Spanish, Turkish `[S28]`.
- Per-document switch is **Check Handwriting Spelling** under the Pen's Writing Aids; the default for new documents lives in Writing Aids → Advanced Settings `[S28]`.

### Documents and locking

- **Read Only Mode hides the whole writing toolbar and turns the nav bar white**; it is the recommended way to tap links "without any risk of writing on the page" `[S23]`.
- Audio recording keeps working in Read Only Mode `[S23]`.
- **Locked documents relock two minutes** after leaving the app or locking the device `[S31]`.
- The password hint appears on the **fourth** wrong attempt (after three failures) `[S31]`.
- Locked documents are **excluded from Auto Backup**, folders cannot be locked, and an exported file loses the lock `[S31]`.

---

## Small things, big impact

Ranked by (daily frequency × annoyance removed) ÷ effort, for a SwiftUI + PencilKit app that currently has no zoom, no highlighter and no settings screen. Effort: **S** ≈ an afternoon, **M** ≈ a day or two, **L** ≈ a week-plus or needs an architectural prerequisite.

| # | Behaviour to copy | Why it matters daily | Effort |
|---|---|---|---|
| 1 | **Two-finger double-tap undo, three-finger double-tap redo** `[S13]` | Removes the reach to a toolbar button on every single mistake. Undo is the most-pressed control in a notes app. | S |
| 2 | **Sticky vs non-sticky tools** `[S40]` | Inserting an image and then being stuck in "image mode" is the classic small-app tell. One enum plus a `toolAfterUse` reset. | S |
| 3 | **Eraser Auto-Deselect** `[S7]` | Erase, then immediately write again with no tool switch. Tiny toggle, disproportionate feel. | S |
| 4 | **Second tap on the active tool opens its options** `[W]` | Gives every tool a settings home without a settings screen or extra toolbar chrome. | S |
| 5 | **Erase Filter (per-tool allow-list)** `[S7]` | "Erase highlighter only" is the single most-requested study behaviour, and it falls out of per-stroke provenance you already have. | S |
| 6 | **Tool category shortcuts P/H/E/V/T/S/D/A/L/M/N/R/K** `[S19]` | Hardware-keyboard iPad and Mac users get muscle memory in a day; the tooltips teach it for free. | S |
| 7 | **Scrolling Direction: per document + per device default** `[S24]` | Horizontal/vertical is a personality trait, not a preference. Costs one enum and one transform. | M |
| 8 | **Long-press on the page → contextual menu** `[S2]` `[S12]` | The discoverability escape hatch for Zoom, Start Typing, Paste — no toolbar space consumed. | S |
| 9 | **Draw-and-hold shape snap** (with live scale/angle while holding) `[S5]` `[S9]` | Turns messy diagrams into presentable ones mid-stroke, and it doubles as the shape tool's tutorial. | M |
| 10 | **Read Only Mode toggle in the nav bar** `[S23]` | Protects notes while reading, and makes PDF links safe to tap. Cheapest "trust" feature in the app. | S |
| 11 | **Circle to Lasso, on by default** `[S15]` | Select-and-move without ever leaving the pen. Needs stroke hit-testing but no new UI. | M |
| 12 | **Scribble to erase** `[S14]` | The pen-native delete. Pairs with the eraser (keep both); also the demo that sells the app. | M |
| 13 | **Per-tool palettes: 3 slots + up to 12 + History tab** `[S46]` | Stops the colour picker from being a modal chore. History alone removes most picker visits. | M |
| 14 | **Palm rejection sensitivity: Low / Medium / High, Low default** `[S4]` | The only lever that fixes finger writers and cheap styli; also the first support question. | M |
| 15 | **Zoom Window with auto-advance and a point-based return height** `[S2]` | The feature that makes small handwriting viable on a 11" page. Needs the zoomable viewport first. | L |
| 16 | **Toolbar Customization with Reset and Undo/Redo Position** `[S18]` | Lets different notebooks need different tools, and the reset button makes the editor safe to explore. | M |
| 17 | **Auto Backup: ~12 h default, "Increase frequency" toggle, excluded names** `[S29]` | Battery-safe default plus an escape hatch. The excluded-name trick is cheaper than a per-document exclude UI. | M |
| 18 | **Password: one universal password, Face ID, 2-minute relock, hint on 4th try** `[S31]` | The relock window and hint timing are what make a lock feel finished rather than bolted on. | M |
| 19 | **Search index toggle + "Indexing x pages…" + language-toggle re-index** `[S27]` | Without the visible progress state, users conclude search is broken. The toggle also buys privacy. | M |
| 20 | **Hover preview + hover tooltips** `[S16]` | Previews the exact stroke footprint before touching down; a few lines of `UIPencilHoverPose`. | S/M |

Runners-up worth doing while nearby: **Pin Text Tool** `[S12]`, **Object Alignment guides (dashed centre / solid edge)** `[S8]`, **Save as Default for text formatting** `[S12]`, **tape reveal by finger only** `[S10]`, **ruler Hide Digits + units** `[S11]`, **Time Keeper** `[S45]`, **Page bookmarks + "Bookmarks Only" filter** `[S39]` `[S53]`.

---

## Images

All downloaded from help-article attachments into `images/` (15 files).

| File | Shows | Source |
|---|---|---|
| `eraser-options-filter.png` | Eraser **Advanced Settings**: Erase Filter switches (Pen/Pencil/Highlighter/Tape), "Select all", Clear Page, **Auto-Deselect shown off**, and the S/M/L eraser sizes | [S7] |
| `eraser-styles-comparison.png` | The same stroke erased by each style: **Precision** clips a small bite (left), **Standard** removes a segment (middle), **Stroke/Object** removes the whole stroke (right) | [S7] |
| `highlighter-settings.png` | The **Writing Tools** capsule with Highlighter active: Pen / Pencil / Highlighter / Tape / Draw Shape icons, then the highlighter's *own* width dots and pale colour slots plus `+` add slot — evidence that palettes are per-tool | [S6] |
| `pen-toolbar-presets.jpg` | Pen toolbar: 3 thickness slots, 3 colour slots, `+` add slot — the per-tool preset row | [S5] |
| `object-scale-rotate-handles.png` | Selection frame with white corner squares (scale) and the protruding circle (rotate) | [S8] |
| `zoom-window-auto-advance.jpg` | Zoom box on the page (blue outline, top) and the Zoom Window below with the **blue auto-advance area** on its left plus prev / new-line / next controls | [S2] |
| `zoom-window-return-height.jpg` | Annotated resize affordances: the zoom box's bottom-right handle on the page (top arrow) and the Zoom Window's height-drag handles along its bottom edge (bottom arrows) — shrinking the box raises magnification | [S2] |
| `ruler-options.png` | The translucent on-canvas ruler in centimetres, with a finger sliding the scale along it — the ruler is a movable overlay, not a saved object | [S11] |
| `tape-pattern-drawing.png` | A patterned tape roll drawn over bilingual text — tape is a drawn strip, and patterns (not only solid colours) are first-class | [S10] |
| `text-tool-formatting.png` | Text active-tool bar: colour, size, font ("Modern"), B/I, alignment, line spacing, highlight, and **Pin Text Tool** boxed — the pin keeps the tool armed for the next box | [S12] |
| `layers-panel.png` | Layers panel: numbered layers with eye toggles and the active layer highlighted — notice there are **no reorder handles and no lock icons**, matching the documented limits | [S20] |
| `accessories-menu.png` | The **Accessories** dropdown: Record & Summarize (pinned, radio dot), Show Recordings, **Zoom Window**, Ruler, Time Keeper, and a **Toolbar Customization** button at the bottom — the opt-in tools live here, not on the main toolbar | [S18] |
| `toolbar-layout-tabs-active-tool-menu.png` | The three-level chrome: document tabs on top, tool row, floating Active Tool Menu below | [S40] |
| `draw-and-hold-rectangle.png` | Draw-and-hold in progress: a hand-drawn rectangle held at the stroke end, at the moment before it snaps to a regular shape | [S9] |
| `read-only-mode.jpg` | The nav-bar cluster: Sidebar, Search, Goodnotes AI, and the **Read Only Mode** icon (document with an eye) — the toggle's actual position in 7.x | [S23] |

---

## Unverified

Things I could not confirm in a primary source, or where sources disagree. Do not treat as build spec.

1. **Apple Pencil double-tap action mapping.** Goodnotes' only article on double-tap is a GN5 troubleshooting note saying an accidental double-tap can silently switch you to the Eraser `[S49]`. Apple documents the mapping as Settings → Apple Pencil `[S54]`. Whether Goodnotes 7 exposes its *own* per-double-tap action picker (e.g. "last tool / eraser / colour") is **unconfirmed**; the 7.1.34 walkthrough did not find one.
2. **Squeeze palette contents and customisation** — documented as opening "the Palette" `[S17]` and explicitly "not customizable" `[S18]`, but no article lists the Palette's exact slots.
3. **Zoom Window "margin" setting.** The article says the best result comes from "setting the margin to fit your Template" `[S2]` but never names that control; the ⋯ menu only documents **Height**. Existence and location unconfirmed.
4. **Eraser's third style name.** Help says **Stroke** `[S7]`; the 7.1.34 UI and its screenshot say **Object** `[W]`, [IMG]. Which is current in 2026 builds is unconfirmed — likely a rename mid-release.
5. **Laser pointer colour and size.** The walkthrough found only Dot / Line `[W]`; no article documents colour or width options. `GOODNOTES-PARITY-PLAN.md` P8.3 assumes colour/size — that assumption is **not** supported by any source read here.
6. **Auto-Deselect factory default.** The help screenshot shows it **off** `[IMG]`, but screenshots can be staged; not stated in text.
7. **Default scrolling direction.** Walkthrough observed Vertical `[W]`; no article states the default.
8. **"Pull to Add Page", "Show Page Number", "Show Hover Preview", "Automatically Open New Imported Documents", "Open Documents as New Tabs", "Undo and Redo Position" defaults.** These six exist in the 7.1.34 Document Editing panel `[W]`, and `Undo and Redo Position` / `Show Hover Preview` are corroborated by `[S18]` / `[S16]`, but **no help article documents the other four** or their default states beyond what the walkthrough observed.
9. **Layers rollout.** Pro-only, "rolling out gradually", one notebook type only `[S20]`. Whether it exists on a free account in Nov 2026 is unknown; the walkthrough account (free) did not see it.
10. **Auto Backup on a fresh device** may re-queue the entire library `[S29]` — behaviour documented as a known quirk, not a setting.
11. **Exact keyboard-shortcut set on iPad without a hardware keyboard.** `[S19]` requires an external keyboard for anything outside text fields; on-screen equivalents are not documented.
12. **Release notes 2024–2026 as a settings source.** The September-launch article `[S56]` and the product features page `[S55]` are marketing summaries that name no settings; no per-version changelog was found on the help centre during this pass. Version-specific default changes could therefore be missed.
13. **Whether "Stylus & Palm Rejection" affects PencilKit-level input or only finger input.** The article scope is finger and capacitive stylus only `[S4]`; no statement on how it interacts with Apple Pencil's own rejection.
