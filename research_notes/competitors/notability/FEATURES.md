# Notability (Ginger Labs) — Feature & Settings Teardown

Research for NOTEAPP (iPad + Mac, SwiftUI + PencilKit). Focus: the *small* settings, toggles, defaults and micro-interactions that change the daily writing feel.

App version referenced: **16.13.5** (App Store, released 2026-11-09). Rating 4.76 / 458,779 ratings (US).

---

## Sources

### Primary — marketing / store
| URL | Note |
|---|---|
| https://notability.com | Home. Positioning: "Notes that help you think"; AI tab list (quizzes, summaries, chat, action items, YouTube link-to-note). |
| https://notability.com/students | Student workflow (record → annotate → quiz), plan tiers, quiz session lengths 15/20/25 min. |
| https://notability.com/pricing/compare | Full plan matrix: Starter / Lite / Classic / Plus / Pro, storage, version history (7/30/90 days), backup. |
| https://apps.apple.com/us/app/notability-ai-notes-pdf/id360593530 | App Store listing + current release notes (16.13.5). |
| https://itunes.apple.com/lookup?id=360593530&country=us | Store metadata (version, date, rating count) used above. |

### Primary — Help Center (`support.gingerlabs.com/en-us/articles/...`)
All fetched as the Help Center's own "Copy for LLM" markdown variant (`<url>.md`) where available.

| URL | Note |
|---|---|
| https://support.gingerlabs.com/en-us | Help Center index; 8 collections, "Features" has 64 articles. |
| https://support.gingerlabs.com/sitemap.xml | Full article inventory (158 URLs) — used to make sure nothing big was missed. |
| https://support.gingerlabs.com/en-us/articles/16300218-settings-appearances-tools-gestures | **The settings master list** (Appearance, Note Editor, Gestures, Media, Transcription, Status Bar). |
| https://support.gingerlabs.com/en-us/articles/16300185-note-view-settings | Seamless / Single Page / Presentation Mode / Content Matches Theme / Status Bar. |
| https://support.gingerlabs.com/en-us/articles/16300208-settings-account-subscription-help | Account, Subscription, AI Customization, About/Help tabs, Recently Deleted. |
| https://support.gingerlabs.com/en-us/articles/16300227-settings-connected-services | iCloud Syncing + Third-Party Backup tab. |
| https://support.gingerlabs.com/en-us/articles/16300068-customize-your-toolbox | Toolbox reorder / duplicate / hide ("Hidden Tools"). |
| https://support.gingerlabs.com/en-us/articles/16300131-pencil | Pencil tool: pressure, tilt-shading, 8 custom colors. |
| https://support.gingerlabs.com/en-us/articles/16300204-writing-with-apple-pencil | Pressure, dashed/dotted, Mirror Ink, double-tap options, auto-deselect, palm detection, one-finger scrolling, haptics, hover. |
| https://support.gingerlabs.com/en-us/articles/16300189-eraser | Partial vs Whole eraser; eraser can draw perfect shapes. |
| https://support.gingerlabs.com/en-us/articles/16300200-highlighter | Highlighter styles, Smart Highlighter (snaps to PDF/typed text), Straight Line Highlighter. |
| https://support.gingerlabs.com/en-us/articles/16300159-creating-and-styling-perfect-shapes | Shape detection, snapping guides, Stroke/Fill, Ink Fill, Locked Shapes. |
| https://support.gingerlabs.com/en-us/articles/16300180-zoom-view | Zoom View: target box, auto-scroll, width handle, tap-to-move box. |
| https://support.gingerlabs.com/en-us/articles/16300179-custom-templates-and-note-background | Templates: size, orientation, paper color, categories, spacing, "Letter (Optimized)". |
| https://support.gingerlabs.com/en-us/articles/16300018-pdf-outlines | PDF outline/TOC navigation inside Content Manager. |
| https://support.gingerlabs.com/en-us/articles/16300170-search | Global search, folder filter, in-note search. |
| https://support.gingerlabs.com/en-us/articles/16300122-recording-and-playing-audio | Recording, note-replay sync, playback speeds, trim/split/merge, Voice Boost. |
| https://support.gingerlabs.com/en-us/articles/16300075-audio-transcripts | Transcripts, Copy All Transcripts, language list, privacy. |
| https://support.gingerlabs.com/en-us/articles/16300114-handwriting-and-math-conversion | Handwriting→text, math→LaTeX image, Select/Group/Stickers, per-note language. |
| https://support.gingerlabs.com/en-us/articles/16300213-multi-note-and-note-switcher | Multi-Note split, Note Switcher edge swipe setting. |
| https://support.gingerlabs.com/en-us/articles/16300117-auto-backup-third-party-backup-guide | Auto-Backup: services, destination, folder selection, file formats, timing. |
| https://support.gingerlabs.com/en-us/articles/16300164-backing-up-notes-outside-of-notability-cloud | Third-Party Backup (Notability Cloud naming), NTB/PDF/PDF+Recording. |
| https://support.gingerlabs.com/en-us/articles/16300142-importing-files | Import, Bulk Import, "Add space" to PDFs. |
| https://support.gingerlabs.com/en-us/articles/16300163-sharing-notes | Export formats PDF/Note/JPEG/PNG/NTB, Share Settings, Publish to Gallery. |
| https://support.gingerlabs.com/en-us/articles/16300139-keyboard-shortcuts | Full shortcut list incl. toolbox ⌘1–9, color ⌥⌘1–8, size ⌃⌥1–3. |
| https://support.gingerlabs.com/en-us/articles/16300226-content-manager-and-bulk-actions | Content Manager: All Pages / Bookmarks / Notes, page actions, bulk page ops. |
| https://support.gingerlabs.com/en-us/articles/16300085-options-menu | In-note Options menu + Note Info fields (page size, languages, word count, version history). |
| https://support.gingerlabs.com/en-us/articles/16300162-viewing-your-notes | List/Grid, All/Recents/Favorites/Unfiled/Shared, sorting. |
| https://support.gingerlabs.com/en-us/articles/16300260-text-and-text-boxes | Text boxes, Quick Text Boxes, Scribble, keyboard toolbar, favourite fonts, TTS, quote/code blocks. |
| https://support.gingerlabs.com/en-us/articles/16300229-ruler | Ruler gestures (45°/90° snap, stamp line), Ruler Units, angle measurement. |
| https://support.gingerlabs.com/en-us/articles/16300236-laser-pointer | Laser pointer for presentation, Tail/No Tail, 64 color slots. |
| https://support.gingerlabs.com/en-us/articles/16300041-latest-ios-app-updates | Release notes 16.10 → 16.13.5. |
| https://support.gingerlabs.com/en-us/articles/16300003-notability-home-screen | Home screen: notification center, Events, Up next to learn, Record a Lecture. |
| https://support.gingerlabs.com/en-us/articles/16300005-focus-mode | Focus Mode (4-finger tap / ⌘⇧F), single movable tool. |
| https://support.gingerlabs.com/en-us/articles/16300017-study-timer | Study session timer, breaks, goals. |
| https://support.gingerlabs.com/en-us/articles/16300155-custom-colors | 64 slots, 8 "fast" colors, HEX, dropper. |
| https://support.gingerlabs.com/en-us/articles/16300046-notability-learn | Learn panel: summaries, quizzes, flashcards, action items; 250–20k word limits. |
| https://support.gingerlabs.com/en-us/articles/16300036-smart-notes-pro | Smart Notes (real-time structured notes from recording). |
| https://support.gingerlabs.com/en-us/articles/16300038-chat-with-your-notes-pro | Chat with note / library, image attach via lasso. |
| https://support.gingerlabs.com/en-us/articles/16300039-live-transcripts-pro | Live transcripts in Learn panel. |
| https://support.gingerlabs.com/en-us/articles/16300052-squeeze-gestures-with-apple-pencil-pro | Pencil Pro squeeze: erase, last tool, palette, arc menu. |
| https://support.gingerlabs.com/en-us/articles/16696325-tape | Tape study cover: 12 sizes, 9 patterns, hide-all. |
| https://support.gingerlabs.com/en-us/articles/17440617-measurement-tool | Ruler modes: straight edge / calculate length / calculate area, per-note scale. |
| https://support.gingerlabs.com/en-us/articles/17737566-graphs | Type or handwrite a function → plot; +Graph. |
| https://support.gingerlabs.com/en-us/articles/18321210-ink-smoothing | Ink Smoothing / "Stabilization" Low/Medium/High, per tool + default. |
| https://support.gingerlabs.com/en-us/articles/16764640-calligraphy-pen | Calligraphy pen, nib angle, barrel-roll angle, Lock angle. |
| https://support.gingerlabs.com/en-us/articles/16299996-note-covers | Note covers as library thumbnails. |
| https://support.gingerlabs.com/en-us/articles/16300151-content-matches-theme | Content Matches Theme; night-mode image inversion rules. |
| https://support.gingerlabs.com/en-us/articles/16300020-organize-notes-with-folders | Folders (6 levels), folder color, emoji, lock, sort. |
| https://support.gingerlabs.com/en-us/articles/16300177-note-security-locked-folders | Locked folders + Face ID/Touch ID/passcode override. |
| https://support.gingerlabs.com/en-us/articles/16810358-flashcards-import | Flashcard import (Anki TXT/CSV/APKG), spaced repetition ratings. |
| https://support.gingerlabs.com/en-us/articles/16300120-add-and-edit-media | Media: photo/scan/GIF/sticker/sticky, crop, lock, forward/back, rounded/sharp corners. |
| https://support.gingerlabs.com/en-us/articles/16300250-importing-external-planners-into-notability | Import planner PDF → "Create Template". |
| https://support.gingerlabs.com/en-us/articles/16300253-note-reminders-with-siri | "Remind me of this" → reminder opens the note. |
| https://support.gingerlabs.com/en-us/articles/16300127-widgets | Widgets: new note, specific note/folder, recents, start recording. |

### Secondary
| URL | Note |
|---|---|
| — | No third-party review was needed: every claim below is sourced from Ginger Labs' own docs. Where a behaviour is only implied, it is listed under **Unverified**. |

---

## Feature list

### Notes, documents & library
| Area | Feature | How it works (gesture/setting, exact UI names in quotes) | Source |
|---|---|---|---|
| Library | Home screen | "Home" sidebar item: "Record a lecture", "Import a file", "Find a template", "Today" events, "Up next to learn", "Favorite notes". | https://support.gingerlabs.com/en-us/articles/16300003-notability-home-screen |
| Library | Note types | Single note type; a note's character comes from its background: blank paper, template, or imported PDF/scan. No separate "notebook" object. | https://support.gingerlabs.com/en-us/articles/16300179-custom-templates-and-note-background |
| Library | List / Grid | Toggle "List or Grid" in the upper-right of the Library next to "+New". | https://support.gingerlabs.com/en-us/articles/16300162-viewing-your-notes |
| Library | Filters | "All Notes", "Recents" (last ten opened), "Favorites", "Unfiled Notes", "Shared Notes". | https://support.gingerlabs.com/en-us/articles/16300162-viewing-your-notes |
| Library | Sorting | Sort by "Name", "Modified Date", "Created Date" (also per-folder "Sort Folders"). | https://support.gingerlabs.com/en-us/articles/16300162-viewing-your-notes |
| Library | Folders | Up to six levels of nesting; folder color, emoji (Cloud), "Lock Folder" (iCloud only); duplicate folder names allowed. | https://support.gingerlabs.com/en-us/articles/16300020-organize-notes-with-folders |
| Library | Note covers | "Add note cover" from long-press or Content Manager → preset covers become the library thumbnail (Cloud only). | https://support.gingerlabs.com/en-us/articles/16299996-note-covers |
| Library | Recently Deleted | Notes recoverable for 30 days: Settings → "Recently Deleted". | https://support.gingerlabs.com/en-us/articles/16300208-settings-account-subscription-help |
| Library | Delete gesture | Swipe left-to-right on a note name to delete (unusual direction, deliberate). | https://support.gingerlabs.com/en-us/articles/16300118-create-and-edit-notes |
| Note | Page defaults per note | Content Manager shows "All Pages", "Bookmarks", "Notes" (= annotated pages only), grid view toggle. | https://support.gingerlabs.com/en-us/articles/16300226-content-manager-and-bulk-actions |
| Note | Page actions | "Add Page", "Cut", "Copy", "Create Template", "Clear Page", "Delete Page"; PDF pages add "Rotate" and "Copy Background". | https://support.gingerlabs.com/en-us/articles/16300226-content-manager-and-bulk-actions |
| Note | Bulk page ops | "Select" → pick pages → Copy / Duplicate / Delete; paste pages into another note. | https://support.gingerlabs.com/en-us/articles/16300226-content-manager-and-bulk-actions |

### Paper, templates & page layout
| Area | Feature | How it works | Source |
|---|---|---|---|
| Templates | Backgrounds | New note bottom bar: "Rule", "Grid", "Dot" plus "Import" and "Scan". | https://support.gingerlabs.com/en-us/articles/16300179-custom-templates-and-note-background |
| Templates | Custom template axes | "Template Size", "Landscape or Portrait", "Paper Color", "Type" (Basic, Education, Creative…). | https://support.gingerlabs.com/en-us/articles/16300179-custom-templates-and-note-background |
| Templates | Paper sizes | Letter, Legal, Tabloid, A3, A4, A5, A6, A7 + **"Letter (Optimized)"** (rescales text-only notes across devices). | https://support.gingerlabs.com/en-us/articles/16300179-custom-templates-and-note-background |
| Templates | Line spacing | Basic template → three blue dots → slider; 10 discrete spacings mapped to physical inches/cm (1/2", 1/4", 1"…). | https://support.gingerlabs.com/en-us/articles/16300179-custom-templates-and-note-background |
| Templates | Make template from a page | Content Manager → page ⋯ → "Create Template" (saved to "My Templates" → "Custom Templates"). | https://support.gingerlabs.com/en-us/articles/16300179-custom-templates-and-note-background |
| Templates | Planners | Long-press "+New" → planners & worksheets download list (also imports external planner PDFs → Create Template). | https://support.gingerlabs.com/en-us/articles/16300179-custom-templates-and-note-background · https://support.gingerlabs.com/en-us/articles/16300250-importing-external-planners-into-notability |
| Layout | View modes | In-note "View settings" → **"Seamless"** (vertical scroll, title at top) or **"Single Page"** (horizontal page-at-a-time). | https://support.gingerlabs.com/en-us/articles/16300185-note-view-settings |
| Layout | Default view | Settings → Note Editor → Document Defaults → "Default note view": Seamless or Single page. | https://support.gingerlabs.com/en-us/articles/16300218-settings-appearances-tools-gestures |
| Layout | Narrow margins | "Narrow Margins" for new notes (smaller text side margins). | https://support.gingerlabs.com/en-us/articles/16300218-settings-appearances-tools-gestures |
| Layout | Status bar | Per-note toggle "Status Bar" (View settings) + global toggle in Settings. | https://support.gingerlabs.com/en-us/articles/16300185-note-view-settings |
| Layout | Dark mode content | "Content Matches Theme" per note; imported images and non-custom stickers are *not* inverted, PDF images *are*. | https://support.gingerlabs.com/en-us/articles/16300151-content-matches-theme |
| PDF | Import with margins | Import dialog "Add space": None / Left / Right / Both — blank gutter per page to write in. | https://support.gingerlabs.com/en-us/articles/16300142-importing-files |
| PDF | Outlines | Auto-detects PDF TOC; Content Manager dropdown → "Outlines"; tap heading to jump, arrows to expand. | https://support.gingerlabs.com/en-us/articles/16300018-pdf-outlines |
| Scan | Scan to PDF | "Scan" creates a PDF background; scanned doc can also "Insert as… Ink". | https://support.gingerlabs.com/en-us/articles/16300179-custom-templates-and-note-background · https://support.gingerlabs.com/en-us/articles/16300105-image-to-ink-conversion |

### Ink tools
| Area | Feature | How it works | Source |
|---|---|---|---|
| Pen | Pressure & tilt | Pressure = width; tilt Pencil sideways to shade (thicker). Apple Pencil (USB-C) has no pressure sensitivity. | https://support.gingerlabs.com/en-us/articles/16300131-pencil |
| Pen | Line styles | Normal, **dashed**, **dotted**; "Mirror horizontally / vertically" for selected ink. | https://support.gingerlabs.com/en-us/articles/16300204-writing-with-apple-pencil |
| Pen | Ink smoothing | "Stabilization" slider **Low / Medium / High**, default **Low**; per-tool level + a global default that offers to reset per-tool overrides. | https://support.gingerlabs.com/en-us/articles/18321210-ink-smoothing |
| Pen | Calligraphy pen | Flat-nib pen; nib "angle" slider 0/30/45°, negative for left-handers; Apple Pencil Pro barrel roll sets angle live; "Lock angle" ignores roll. | https://support.gingerlabs.com/en-us/articles/16764640-calligraphy-pen |
| Pen | Widths | 1.5 and 2.5 width steps added for pen, highlighter, calligraphy (16.12.5). | https://support.gingerlabs.com/en-us/articles/16300041-latest-ios-app-updates |
| Highlighter | Styles | Translucent ink; brush styles; pressure-sensitive highlighter, dashed/dotted. | https://support.gingerlabs.com/en-us/articles/16300200-highlighter |
| Highlighter | Smart Highlighter | Long-press PDF/typed text to snap, then drag word-by-word — highlight follows text, not your hand. Not for handwriting. | https://support.gingerlabs.com/en-us/articles/16300200-highlighter |
| Highlighter | Straight-line highlighter | Draw over text then hold → snaps to a straight highlight. | https://support.gingerlabs.com/en-us/articles/16300200-highlighter |
| Eraser | Two modes | Tap eraser icon again → "Partial Eraser" or "Whole Eraser" + size. Partial erases segments that stay editable (colour/width per segment). | https://support.gingerlabs.com/en-us/articles/16300189-eraser |
| Eraser | Auto-deselect | "Auto-Deselect Eraser": after erasing, snap back to the last used tool. Greyed out while squeezing Pencil Pro (squeeze can't erase multiple marks). | https://support.gingerlabs.com/en-us/articles/16300218-settings-appearances-tools-gestures · https://support.gingerlabs.com/en-us/articles/16300052-squeeze-gestures-with-apple-pencil-pro |
| Eraser | Shape trick | With Partial Eraser, draw a shape and hold → becomes a Perfect Shape. | https://support.gingerlabs.com/en-us/articles/16300189-eraser |
| Shapes | Perfect Shapes | Draw then hold → snaps to circle/ellipse/triangle/square/rect/pentagon/hexagon/arrow; red snapping guides align to grid and other shapes. | https://support.gingerlabs.com/en-us/articles/16300159-creating-and-styling-perfect-shapes |
| Shapes | Stroke / Fill | Selected shape → style menu → "Stroke" and "Fill"; "Ink Fill" = press and hold inside a closed shape to flood it with the current colour. | https://support.gingerlabs.com/en-us/articles/16300159-creating-and-styling-perfect-shapes |
| Shapes | Lock | "Lock" a shape so it can't be nudged (tap → Lock / Unlock). | https://support.gingerlabs.com/en-us/articles/16300159-creating-and-styling-perfect-shapes |
| Select | Selection model | "Select" (lasso) → circle ink → tap inside → Convert / Group / Save as Sticker / Style / cut-copy-delete; two-finger pinch to resize, rotate to rotate. | https://support.gingerlabs.com/en-us/articles/16300114-handwriting-and-math-conversion |
| Select | Group & stickers | "Group" makes ink one object; "Save" → "My Stickers", reusable in every note. | https://support.gingerlabs.com/en-us/articles/16300053-group-content-and-make-custom-stickers |
| Colours | Custom palette | 8 "fast" custom colours in the tray + 64-slot popover; colour wheel, HEX entry, **eyedropper** to grab a colour already on the page. | https://support.gingerlabs.com/en-us/articles/16300155-custom-colors |
| Toolbox | Customisation | Swipe toolbox left → edit; drag to reorder, duplicate Pen/Pencil/Highlighter/Eraser (each duplicate keeps its own style/colour), hide into "Hidden Tools". | https://support.gingerlabs.com/en-us/articles/16300068-customize-your-toolbox |
| Zoom | Zoom View | Tap zoom icon → zoom window at bottom + target box on page; tap anywhere to move target; two-finger pinch to resize; drag bottom-right corner on iPad. | https://support.gingerlabs.com/en-us/articles/16300180-zoom-view |
| Zoom | Auto-scroll writing | Zoom window auto-advances right as you fill the highlighted area, then wraps to a new line; blue corner arrow adjusts the active width; buttons advance right/left/down. | https://support.gingerlabs.com/en-us/articles/16300180-zoom-view |
| Zoom | Enter by gesture | "Tap and Hold to Enter Zoom View while handwriting" (Settings → Note Editor → Gestures). | https://support.gingerlabs.com/en-us/articles/16300218-settings-appearances-tools-gestures |
| Ruler | Straight edge | Drag with one finger; tap compass → nearest 45°; double-tap compass → +90°; slide compass vertically to rotate freely. | https://support.gingerlabs.com/en-us/articles/16300229-ruler |
| Ruler | Stamp line | One-finger double-tap = stamp a line; tap-and-hold a triangle to preview the target line first. Line detection snaps to ruler even if you start away from it. | https://support.gingerlabs.com/en-us/articles/16300229-ruler |
| Ruler | Dismiss | Tap ruler icon again, or two-finger long press / two-finger pinch. | https://support.gingerlabs.com/en-us/articles/16300229-ruler |
| Ruler | Measurement | Modes "Straight edge", "Calculate length", "Calculate area"; calibrate one scale per note against a known length; units mm–miles; "Reset scale". | https://support.gingerlabs.com/en-us/articles/17440617-measurement-tool |
| Tape | Study cover | Draw over content to hide it; 12 sizes, 9 patterns, 4 colours + custom; tap to reveal, tap inside outline to re-cover; "hide all / show all" toggle. Tape does not export. | https://support.gingerlabs.com/en-us/articles/16696325-tape |

### Text, media & elements
| Area | Feature | How it works | Source |
|---|---|---|---|
| Text | Tap-anywhere typing | Text tool → tap anywhere to type; or press-and-hold → "+Text Box". | https://support.gingerlabs.com/en-us/articles/16300260-text-and-text-boxes |
| Text | Quick Text Boxes | Text tool icon twice → settings → "Quick Text Boxes" → "Draw Text Boxes" or "Scribble". | https://support.gingerlabs.com/en-us/articles/16300260-text-and-text-boxes |
| Text | Font presets | Up to three favourite styles pinned to the keyboard toolbar via the Heart icon. | https://support.gingerlabs.com/en-us/articles/16300260-text-and-text-boxes |
| Text | TTS | Text-to-Speech with automatic language detection; speed slider in Settings. | https://support.gingerlabs.com/en-us/articles/16300260-text-and-text-boxes |
| Text | Quote / code blocks | ">" + space inserts a quote block; code blocks preserve spacing/font. | https://support.gingerlabs.com/en-us/articles/16300260-text-and-text-boxes |
| Media | Add media | Photos, Camera, GIFs, Stickers, Sticky Notes, Image Playground; object menu: "Crop, Duplicate, Cut, Copy, Locked Objects, Send Forward, Send Backward, Delete". | https://support.gingerlabs.com/en-us/articles/16300120-add-and-edit-media |
| Media | Format options | "Format": captions on/off, "Round or Sharp Corners", "Text Wrap". | https://support.gingerlabs.com/en-us/articles/16300120-add-and-edit-media |
| Media | Lock objects | Lock stickers/images/stickies/GIFs in place to stop accidental drags. | https://support.gingerlabs.com/en-us/articles/16300120-add-and-edit-media |
| Media | Image → Ink | Select image → "Convert to Ink" (needs A12+). | https://support.gingerlabs.com/en-us/articles/16300105-image-to-ink-conversion |
| Media | Web Clip | Drag a link in, or type a URL → "Create Web Clip" → static preview card; "Edit Web Clip" to re-crop. | https://support.gingerlabs.com/en-us/articles/16300050-web-clip |
| Media | Graphs | Text tool → "+Graph", type f(x), live preview, place on page; up to 2 functions, min/max, intersections, custom ranges. | https://support.gingerlabs.com/en-us/articles/17737566-graphs |

### Audio, search, AI, study
| Area | Feature | How it works | Source |
|---|---|---|---|
| Audio | Note Replay | Tap anything (word, sketch, photo) during playback to hear what was said then; new ink during playback gets timestamped. | https://support.gingerlabs.com/en-us/articles/16300122-recording-and-playing-audio |
| Audio | Playback settings | 0.7x / Normal / 1.25x / 1.5x / 2x; ±10s skip; "Tuning" → frequency + **"Voice Boost"** slider for distant lecturers. | https://support.gingerlabs.com/en-us/articles/16300122-recording-and-playing-audio |
| Audio | Clip editing | Recording list → "Edit" → "Edit Clip": drag black bars to trim, "Split", rename, "Merge". | https://support.gingerlabs.com/en-us/articles/16300122-recording-and-playing-audio |
| Audio | Auto-split warning | Docs recommend starting a new recording after 1 hour because long recordings may split into segments. | https://support.gingerlabs.com/en-us/articles/16300122-recording-and-playing-audio |
| Audio | Record from library | Record button creates a note *and* starts recording in one tap ("Record a lecture" on Home). | https://support.gingerlabs.com/en-us/articles/16300122-recording-and-playing-audio |
| Transcripts | Auto transcription | Settings toggle "Transcription"; per-note transcripts in Learn panel; "Copy All Transcripts" pastes into notes. | https://support.gingerlabs.com/en-us/articles/16300075-audio-transcripts |
| Search | Three levels | Global library search; per-folder via "Filter"; in-note search inside Content Manager. | https://support.gingerlabs.com/en-us/articles/16300170-search |
| Search | Handwriting search | Handwriting recognition language per library + per note ("Handwriting Language" in Note Info). | https://support.gingerlabs.com/en-us/articles/16300114-handwriting-and-math-conversion |
| Convert | Handwriting → text | Select → circle ink → tap inside → "Convert" → "Text". | https://support.gingerlabs.com/en-us/articles/16300114-handwriting-and-math-conversion |
| Convert | Math → LaTeX image | "Convert" → "Math" gives a hi-res scalable image with an editable LaTeX source. | https://support.gingerlabs.com/en-us/articles/16300114-handwriting-and-math-conversion |
| Convert | Handwriting → graph | Circle a function → "Convert" → "Graph". | https://support.gingerlabs.com/en-us/articles/17737566-graphs |
| Learn | Panel | Learn icon → summary, plus cards for quizzes / flashcards / fill-in-the-blank; "Copy All" into note. Requires 250–20,000 words. | https://support.gingerlabs.com/en-us/articles/16300046-notability-learn |
| Learn | Smart Notes | Live structured notes from a recording, refreshed with ink/text/PDF after you stop. | https://support.gingerlabs.com/en-us/articles/16300036-smart-notes-pro |
| Learn | Chat | Chat with a note or the whole library; lasso ink → "Chat" to attach a drawing as context. | https://support.gingerlabs.com/en-us/articles/16300038-chat-with-your-notes-pro |
| Learn | Flashcards | Import TXT/CSV/APKG from Anki; rate "Again / Hard / Good / Easy" for spaced repetition. | https://support.gingerlabs.com/en-us/articles/16810358-flashcards-import |
| Learn | Study timer | Options → "Start Study Session": study time, break duration, goal, number of sessions; break screen counts down. | https://support.gingerlabs.com/en-us/articles/16300017-study-timer |

### Presentation, multitasking, input
| Area | Feature | How it works | Source |
|---|---|---|---|
| Present | Presentation Mode | Full screen, no toolbars; UI actions (library, Content Manager, magnifier) are hidden from the audience; AirPlay/HDMI. Single Page view makes pages behave like slides. | https://support.gingerlabs.com/en-us/articles/16300185-note-view-settings |
| Present | Laser pointer | Tool + colour (64 slots) + size + "Tail / No Tail"; leaves no marks. | https://support.gingerlabs.com/en-us/articles/16300236-laser-pointer |
| Present | Private second note | Multi-Note while presenting stays hidden; "Mirror" → Left/Right to share it deliberately. | https://support.gingerlabs.com/en-us/articles/16300213-multi-note-and-note-switcher |
| Multi-note | Split view | Swipe from left edge → "Note Switcher" → long-press thumbnail → "Open On Right" / "Open On Bottom"; drag-and-drop also works. | https://support.gingerlabs.com/en-us/articles/16300213-multi-note-and-note-switcher |
| Multi-note | Swap / rotate | Long-press thumbnail → "Switch Notes" / "Switch Orientation". | https://support.gingerlabs.com/en-us/articles/16300213-multi-note-and-note-switcher |
| Pencil | Double-tap | Configured in iPad Settings → Apple Pencil → Actions: switch tool↔eraser, tool↔last used, colour palette, ink attributes, off. | https://support.gingerlabs.com/en-us/articles/16300204-writing-with-apple-pencil |
| Pencil | Squeeze | Erase (hold), last tool (hold = temporary, quick = persistent), colour palette, or **arc menu** (draw while it's open). | https://support.gingerlabs.com/en-us/articles/16300052-squeeze-gestures-with-apple-pencil-pro |
| Pencil | Hover | Previews tool and stroke footprint; toggle "Apple Pencil hover". | https://support.gingerlabs.com/en-us/articles/16300204-writing-with-apple-pencil |
| Pencil | Haptics | Vibration on shape recognition, snapping and tool change; toggle "Apple Pencil haptics"; Pencil Pro + iPad Pro + iOS 18+. | https://support.gingerlabs.com/en-us/articles/16300218-settings-appearances-tools-gestures |
| Finger | Finger scrolls, Pencil writes | With a Pencil connected, one finger scrolls; tap "Apple Pencil" in Options → "disconnect" to draw with a finger; resuming with the Pencil reconnects automatically. | https://support.gingerlabs.com/en-us/articles/16300204-writing-with-apple-pencil |
| Keyboard | Shortcuts | ⌘1–9 tools by toolbox position; ⌥⌘1–8 colours; ⌃⌥1–3 sizes; ⌘⇧S Note Switcher; ⌥⌘P Content Manager; ⌘⇧F Focus Mode; Space/⇧Space page forward/back; ⌘↑/⌘↓ top/bottom. | https://support.gingerlabs.com/en-us/articles/16300139-keyboard-shortcuts |
| Keyboard | Shortcut discovery | Hold ⌘ to show the shortcut menu (only when a keyboard is attached). | https://support.gingerlabs.com/en-us/articles/16300139-keyboard-shortcuts |

### Organisation, import/export, sync
| Area | Feature | How it works | Source |
|---|---|---|---|
| Import | Import | Long-press "+New" → "Import" (Files, Dropbox, Google Drive, OneDrive, Box, WebDAV); in-note "Import" appends. | https://support.gingerlabs.com/en-us/articles/16300142-importing-files |
| Import | Bulk Import | Long-press "+New" → "Bulk Import" → pick a folder → imports subfolders too. | https://support.gingerlabs.com/en-us/articles/16300142-importing-files |
| Export | Formats | PDF, "Note" (.ntb, keeps audio + editability), JPEG, PNG; per-format "More options". | https://support.gingerlabs.com/en-us/articles/16300163-sharing-notes |
| Export | Share from note | Options → "Quick Share" (share sheet), "Export Options", "Publish to Gallery", "Share Settings" (collaboration). | https://support.gingerlabs.com/en-us/articles/16300085-options-menu |
| Backup | Third-Party Backup | One-way; Box/Dropbox/Google Drive/OneDrive/WebDAV; "Destination" folder, "Folders to Back Up", "File Format" (Note/NTB, PDF + "Paper" toggle, PDF+Recording zip, RTF, RTF+Recording). | https://support.gingerlabs.com/en-us/articles/16300117-auto-backup-third-party-backup-guide |
| Backup | When it runs | After enabling/changing settings all notes back up; otherwise a note backs up when you edit it and return to the Library. | https://support.gingerlabs.com/en-us/articles/16300117-auto-backup-third-party-backup-guide |
| Backup | Locked notes | Password-protected notes are **not** backed up by default; opt in per folder (needs the folder password). | https://support.gingerlabs.com/en-us/articles/16300117-auto-backup-third-party-backup-guide |
| Sync | iCloud vs Cloud | "iCloud Syncing" (two-way, per-device) or "Notability Cloud" (account-based); iCloud sync is unavailable in Cloud, and backup-to-iCloud is impossible by design. | https://support.gingerlabs.com/en-us/articles/16300227-settings-connected-services |
| Versioning | Version history | "Version History" / "iCloud Version History" in Note Info; 7 / 30 / 90 days by plan. Renaming a note clears saved iCloud versions. | https://support.gingerlabs.com/en-us/articles/16300085-options-menu · https://notability.com/pricing/compare |
| Security | Locked folders | Folder password, synced iOS↔Mac even without note sync; Face ID/Touch ID/passcode override; no per-note or whole-app lock. | https://support.gingerlabs.com/en-us/articles/16300177-note-security-locked-folders |
| Share | Link sharing | "Create Link" gives a browser-viewable link (not for Cloud-stored notes). | https://support.gingerlabs.com/en-us/articles/16300085-options-menu |
| Automation | Siri / Shortcuts | "Remind me of this" → reminder opens the note; Shortcuts can create/rename/move notes or add text (16.13.5). | https://support.gingerlabs.com/en-us/articles/16300253-note-reminders-with-siri · https://support.gingerlabs.com/en-us/articles/16300041-latest-ios-app-updates |
| Automation | Widgets | New note, specific note, specific folder, Recents, "start recording" (tapping creates a note and records). | https://support.gingerlabs.com/en-us/articles/16300127-widgets |

---

## Settings & toggles

### App Settings → Appearance
| Setting | Default | What it changes | Why a user cares |
|---|---|---|---|
| "Match Theme to iOS Appearance" | — | Follows system light/dark. | Set-and-forget dark mode; remembers your preferred dark theme. |
| "Night Mode" | — | Darker app + note appearance; inverts PDF images, not imported images/stickers. | Night writing without blinding white paper. |
| "Colorful Folders" | — | Folder rows get a colour border; off = bullet points. | Scan the sidebar by colour, not text. |
| "Keep iPad Awake" | — | Prevents screen sleep. | Long lectures/meetings without constant taps. |
| "Themes" | — | Light, Dark, Dark Blue, Jet Black and more. | Personality without changing layout. |

### App Settings → Note Editor → Document Defaults
| Setting | Default | What it changes | Why a user cares |
|---|---|---|---|
| "Default Note Title" (+ include date and/or time) | — | Auto-fills the title of every new note. | Instant, sortable, searchable titles — no naming friction. |
| "Default Template" | Plain/Rule/Grid/Dot (default value undocumented) | Paper for every new note. | Most users write on ruled paper every day. |
| "Default Text Box Paper" | — | Paper, grid space and colour behind text boxes. | Text boxes stop looking like blank white patches. |
| "Default note view" | Seamless or Single page | Vertical scroll vs horizontal page flip. | Individuals pick the one that matches their brain. |
| "Narrow Margins" | — | Narrower side margins for new notes. | More usable width on 11"/13" iPads. |
| "Template" size | Letter (Optimized) recommended | Cross-device text scaling. | Notes look identical on iPad and Mac. |

### App Settings → Note Editor → Typing
| Setting | Default | What it changes | Why a user cares |
|---|---|---|---|
| "Default Font Style" | — | Font, size, colour for typed text. | Consistent notes without restyling. |
| "Check Spelling" | — | Red squiggles. | Off for bilingual notes. |
| "Data detection" | — | Makes links, phone numbers, dates, addresses tappable (manually added links unaffected). | Phone numbers in meeting notes become actionable. |
| "Tap anywhere to start typing" | — | Tap = place cursor/typing anywhere on the page. | Removes the "insert text box first" step. |
| Text-to-Speech speed slider | — | Reading speed. | Proofreading at 1.5x. |

### App Settings → Note Editor → Handwriting & Drawing
| Setting | Default | What it changes | Why a user cares |
|---|---|---|---|
| "Language" (handwriting) | — | Recognition + search language for new notes. | Mixed-language users need per-note control (Note Info → "Handwriting Language"). |
| "Math Conversion" | — | Enables math → LaTeX images. | STEM notes. |
| "Straight Lines" | — | Draw a line and **hold** → auto-straighten. | Underlines, dividers, tables without the ruler. |
| "Shapes Detection" | — | Draw a shape, **hold** → perfect shape. | Diagrams in 3 seconds. |
| "Palm Detection" | on (implied) | Lets the palm rest anywhere while writing. | The single biggest "does it feel like paper" factor. |
| "Auto-Deselect Eraser" | on | Returns to the last tool after erasing. | The classic death-by-a-thousand-taps fix. |
| "Apple Pencil haptics" | — | Buzz on shape recognition, snapping, tool change. | Confirms the snap without looking. |
| "Apple Pencil hover" | — | Preview tool/stroke before contact. | Aim before inking; can be turned off if distracting. |
| "Ruler Units" | — | Metric / Imperial. | Measurement tool output. |
| "Ink Fill" | — | Press-and-hold inside a closed shape to flood-fill. | Fast shading without the highlighter. |
| "Stabilization" (Ink Smoothing) | **Low** | Low/Medium/High smoothing; per-tool override. | Removes hand tremor without making writing mushy. |

### App Settings → Note Editor → Gestures
| Setting | Default | What it changes | Why a user cares |
|---|---|---|---|
| "Tap and Hold to Enter Zoom View while handwriting" | — | Hold on the page → magnifier. | No reaching for the toolbar. |
| "Undo Redo Gestures" | — | "2 Finger Tap" (undo) + "3 Finger Tap" (redo) **or** "3 Finger Swipe" left/right. | Undo without breaking writing posture. |
| "Enter and Exit Focus Mode" | — | "4 finger tap" or "None". | Full-screen writing, zero chrome. |
| "Note Switcher" | "Swipe from Left Edge" | Or "None"; with None, the same swipe returns to the Library. | Stops accidental library exits from edge swipes. |

### App Settings → other tabs
| Setting | Default | What it changes | Why a user cares |
|---|---|---|---|
| "Default Media Options" | — | "Rounded corners" or "Sharp corners" for inserted media. | Visual consistency in one toggle. |
| "Transcription" | — | Audio → text. | Searchable lectures. |
| "AI" / "Learn" / "Transcription" / "Default Language" (AI Customization tab) | on | Master switches for AI features, study features, transcription, and Learn language. | Privacy-conscious users can kill AI entirely. |
| "Status Bar" | — | Show/hide status bar in notes. | One less distraction. |
| "iCloud Syncing" + "Last iCloud Sync" | — | Two-way device sync, with a visible last-sync timestamp. | Trust signal that notes are safe. |
| "Third-Party Backup" | off | Service + "Destination" + "Folders to Back Up" + "File Format". | Off-app insurance policy. |
| "Locked Folders" (Account) | — | Password + Face ID/Touch ID/passcode override. | Shared iPad privacy. |
| "Recently Deleted" | 30 days | Undo for deletions. | Recover the note you swiped away. |

### Per-note / in-note controls
| Setting | Where | What it changes | Why a user cares |
|---|---|---|---|
| "Seamless" / "Single Page" | View settings | Scroll model for *this* note. | Slides/PDFs read better single-page. |
| "Content Matches Theme" | View settings | Note background follows light/dark. | No white flash at night. |
| "Presentation Mode" | View settings | Hides chrome from audience view. | Presenting from the same app you wrote in. |
| "Template settings" | Options menu | Per-note paper swap. | Imported PDF pages vs blank pages in one note. |
| "Note Info" | Tap title | Rename, move folder, page size, "Handwriting Language", "Study Material Language", **Word Count**, version history, Note ID. | Per-note corrections without global changes. |
| "Auto-Deselect" + Pro Pencil squeeze | Settings × Pencil | Auto-deselect **disables** squeeze functions. | A real trap: two good features that cancel each other. |
| Playback speed / "Voice Boost" | Audio "Playback Settings" / "Tuning" | 0.7x–2x; amplify distant voices. | Lecture recorded from the back row is still usable. |

---

## Small things, big impact

Ranked by (daily frequency × annoyance removed) ÷ effort. Effort is for an iPad SwiftUI + PencilKit app.

| # | Micro-feature / setting | Why it matters | Effort |
|---|---|---|---|
| 1 | **Auto-deselect eraser** — snap back to the last pen after erasing (with a "not while squeezing" carve-out) | Removes the most repeated 2-tap sequence in the app; erasing becomes a gesture, not a mode. Design the carve-out up front so Pencil squeeze still works. | S |
| 2 | **Hold-to-straighten line** and **hold-to-perfect-shape**, with red snap guides | Users get clean rules, tables and boxes with zero tool switching. Huge perceived "smartness" per line of code. | S |
| 3 | **Finger scrolls while Pencil writes** + "disconnect Apple Pencil" to finger-draw | The correct iPadOS contract: Pencil = ink, finger = navigate. The explicit disconnect toggle covers the 5% who want finger ink. | M |
| 4 | **Zoom View with auto-advancing writing box** (auto-wrap to next line, resizable active width) | The single biggest comfort feature for small handwriting on a 11" screen; also the strongest GoodNotes/Notability parity item. | M–L |
| 5 | **Per-tool ink smoothing preset** (Low default, Medium/High, per-tool override) | Makes cheap styli and tired hands feel good without softening deliberate strokes; per-tool because pencils and pens want different values. | M |
| 6 | **Default template + default note view + narrow margins** in one "Document Defaults" pane | Every new note starts correct — the compounding win of the whole settings screen. | S |
| 7 | **Seamless vs Single Page per note** (not just global) | PDFs/slides want pagination; long notes want scroll. One toggle, two audiences. | S |
| 8 | **Configurable undo/redo gestures** (2-finger tap / 3-finger swipe) | Undo mid-sentence without moving the Pencil hand to a button. Also a discoverability win: gestures are listed in Settings. | S |
| 9 | **Smart Highlighter that snaps to PDF/typed text** (long-press first word, drag) | Highlights land *under* the words instead of across them; makes PDF annotation look professional. | L |
| 10 | **8 "fast" colours + 64-slot palette + eyedropper** | Daily colours one tap away; the eyedropper quietly becomes the most-used colour picker ("match that diagram"). | S–M |
| 11 | **Zoom-free "tap anywhere to start typing"** for text | Removes the "insert text box" detour for labels and titles. | S |
| 12 | **Content Manager page filters**: "Bookmarks" and "Notes" (annotated-only) | Navigation in a 200-page PDF becomes a jump list, not a scroll marathon. | M |
| 13 | **Audio: tap any word/ink to replay that moment**, plus 0.7x–2x and Voice Boost | The core "why Notability" feature; replay-by-tap is what users show other people. | L |
| 14 | **Ruler with 45°/90° compass snapping and double-tap "stamp line"** | Precise underlines and tables without a straight-edge tool mindset; stamping is the sleeper feature. | M |
| 15 | **Tape** (12 sizes, 9 patterns, tap-to-reveal, hide-all) | Turns any note into a flashcard in two strokes; cheap to build on top of an element/annotation model. | M |
| 16 | **One-tap "Record a lecture"** that creates the note and starts recording; matching widget | Removes the "new note → name → find record button" sequence at the exact moment the lecture starts. | S |
| 17 | **Auto-backup that fires on returning to the Library**, per folder, with a format choice | Invisible safety; the "on library return" trigger is what makes it feel free rather than scheduled. | M |
| 18 | **Study session timer with breaks and a goal** (Pomodoro inside the note) | Cheap retention feature; keeps the app open during study instead of a separate timer app. | S–M |
| 19 | **Default note title with date/time** | Library becomes self-sorting; zero typing. | S |
| 20 | **Focus Mode** (4-finger tap / ⌘⇧F) that reduces UI to one draggable tool | Instant "distraction-free" without a separate mode screen; makes demos and deep work feel premium. | S–M |

Bonus candidates if a slot opens: **note covers** (library looks designed, S), **toolbox duplicates** (two pen presets, S), **"Add space" on PDF import** (S), **"Narrow Margins"** (S).

---

## Images

Downloaded to `research_notes/competitors/notability/images/`:

| File | Caption | Source article |
|---|---|---|
| `home-screen.png` | Redesigned Home: sidebar with colour-dot folders, "Record a lecture / Import a file / Find a template" cards, "Up next to learn", favourite notes. | /articles/16300003-notability-home-screen |
| `template-settings.png` | Templates sheet: gallery row, "Size: Letter (Optimized)" dropdown, Basic Templates (Plain/Rule/Grid/Dot) with "CURRENT" badge, paper colour swatches, Education section. | /articles/16300179-custom-templates-and-note-background |
| `template-customize.png` | Second templates view (custom template axes / paper choices). | /articles/16300179-custom-templates-and-note-background |
| `tape.png` | Toolbar close-up: pen, pencil, Tt, highlighter, eraser, hand, select, add, ruler, tape + the 9 tape patterns. | /articles/16696325-tape |
| `ink-smoothing.png` | Tool style tray: line styles (solid/tapered/dashed/dotted) and "Stabilization — Medium" slider. | /articles/18321210-ink-smoothing |
| `squeeze-menu.png` | Apple Pencil Pro squeeze **arc menu**: pen, pencil, highlighter, eraser, select, undo + two colour wells. | /articles/16300052-squeeze-gestures-with-apple-pencil-pro |
| `study-timer.png` | "Break Time" 4:15 full-screen break with "Stretch, breathe, or grab some water." | /articles/16300017-study-timer |
| `widgets.png` | Home-screen widget picker with Notability widgets (new note, folder, recents, record). | /articles/16300127-widgets |
| `flashcard-import.png` | Flashcard import flow (Anki TXT/CSV/APKG), spaced-repetition ratings. | /articles/16810358-flashcards-import |
| `digital-planner-note.png` | Hyperlinked digital planner page: month tab index, "Tap 2x – Monthly Page", folded-magazine layout tutorial. | /articles/16300278-how-to-use-digital-planners |
| `smart-notes-pro.jpg` | Smart Notes panel generating structured notes live during a recording. | /articles/16300036-smart-notes-pro |
| `chat-with-note.jpg` | "Chat with your notes" UI inside a note. | /articles/16300038-chat-with-your-notes-pro |
| `live-transcripts.jpg` | Live Transcripts panel while recording. | /articles/16300039-live-transcripts-pro |

Remaining useful image URLs (not downloaded — marketing art / lower value):

| URL | Caption |
|---|---|
| https://notability.com/static/features/ai/featuregraphic-AI-flashcards-wide.webp | AI flashcards feature graphic (wide). |
| https://notability.com/static/features/ai/featuregraphic-AI-smartnotes-narrow.webp | Smart Notes feature graphic (narrow). |
| https://notability.com/static/features/ai/featuregraphic-AI-chat-wide.webp | Chat with notes graphic. |
| https://notability.com/static/features/ai/featuregraphic-AI-actionitems-narrow.webp | Auto-generated action items graphic. |
| https://notability.com/static/features/ai/featuregraphic-AI-youtube-wide.webp | YouTube link-to-note graphic. |
| https://notability.com/static/students/Tablet-Students.webp | Student hero (tablet). |
| https://downloads.intercomcdn.com/i/o/qft13i0t/2599190421/54aff6564b11a7866f583fd3a79d/upload_13416423750758654630.png | Note covers picker. |
| https://downloads.intercomcdn.com/i/o/qft13i0t/2599191911/8d3650496b457c1d9aa0d232c2b7/upload_13478659062564958162.png | PDF Outlines in Content Manager. |
| https://downloads.intercomcdn.com/i/o/qft13i0t/2629037743/bd81e3bd100a038a21a6dbe99bcb/menus-options-outline.png | In-note Options menu icon reference (View settings / Template settings entry point). |

Note: Intercom CDN URLs are signed and expire; the article URLs above are the durable reference.

---

## Unverified

These are plausible or commonly assumed, but I could **not** confirm them in Ginger Labs' documentation — do not implement from this list without checking the app.

1. **"Auto-advance to next page"** — no such setting exists in any documented settings screen, note view settings, or release note. Notability's answer to running out of room is *zoom auto-scroll* and *add page*, not page auto-advance. If we build auto-advance, it is a differentiator vs Notability (GoodNotes has it).
2. **Page scroll direction as a user setting** — not documented. The only control is "Seamless" (vertical) vs "Single Page" (horizontal). No "reverse scroll" or per-axis choice.
3. **Palm Detection as an on/off switch** — listed as a bullet under Handwriting & Drawing, but I could not confirm whether it is a toggle or always-on. Treat as on-by-default and non-toggleable until verified in-app.
4. **Default values** for: "Default Template", "Default note view", "Tap anywhere to start typing", "Check Spelling", "Data detection", "Colorful Folders", "Keep iPad Awake", "Straight Lines", "Shapes Detection", "Apple Pencil hover". Only **Ink Smoothing = Low** is explicitly documented as a default.
5. **Undo/redo gesture default** — the docs describe both "2 Finger Tap / 3 Finger Tap" and "3 Finger Swipe" as options but do not say which ships enabled.
6. **Whether "Auto-Deselect Eraser" is default-on** — the docs describe the behaviour and how to disable it ("This can be disabled in…"), which strongly implies on, but it is not stated.
7. **Lasso naming** — Notability's UI calls it the **"Select"** tool, not "Lasso". I could not confirm a lasso-vs-rectangle selection mode choice; only freehand circling is documented.
8. **Layer support** — no layers feature found in any documentation or release note. Elements are ordered with "Send Forward / Send Backward" only, plus "Lock".
9. **Whiteboard / infinite canvas** — not documented; every note has a page size (Letter/A4/…). No infinite canvas found.
10. **Outline/bookmarks beyond PDF** — "Bookmarks" exist as a Content Manager page filter (star a page), but there is no documented user-authored outline/table-of-contents for non-PDF notes.
11. **Handwriting-to-text for entire note at once** — only per-selection "Convert → Text" is documented.
12. **"Palm rejection modes" (multiple modes)** — no modal choice is documented; only a single "Palm Detection" behaviour.
13. **Auto-backup to iCloud** — explicitly *not* possible; backups go to Box/Dropbox/Google Drive/OneDrive/WebDAV only.
14. **Per-note password** — explicitly unavailable; only folders can be locked.
