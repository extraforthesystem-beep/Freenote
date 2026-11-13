# Noteshelf 3 — Feature & Settings Teardown

Competitor research for NOTEAPP (iPad + Mac, SwiftUI + PencilKit).
Focus: the *small* settings, toggles, defaults and micro-interactions that change daily writing.

- Product: **Noteshelf 3** by Fluid Touch Pte. Ltd. (separate app from Noteshelf 1/2; App Store id `6458735203`)
- Platforms: iPadOS/iOS 18+, macOS (Catalyst/native Mac app), watchOS, Android, Windows ([S5])
- Current iOS version at time of research: **8.1.2** ([S5])
- Research date: 2026-11-12
- Method: official site + official Zendesk knowledge base (pulled via its public `/api/v2/help_center` endpoint, 179 articles) + App Store/Play listings. One 2026 third-party review (Paperlike) is used only where the official KB is silent, and is marked **[secondary]**.

---

## Sources

### Official product site
| # | URL | Note |
|---|-----|------|
| S1 | https://noteshelf.net | Home. Positioning, "4 pen styles + 2 highlighter styles", 500+ stickers, 100+ covers, folders/subfolders, filters (photos, tags). |
| S2 | https://noteshelf.net/new/features/ | Features page. Annotate PDFs, record audio, type/convert, draw perfect shapes, customizable toolbar, focus mode, handwriting search, cloud sync. |
| S3 | https://noteshelf.net/new/noteshelf-ai/ | AI page. Audio transcription, Suggested Tags (Apple Intelligence, iOS only), Image Playground (iOS only). |
| S4 | https://noteshelf.net/new/stationery/ | Stationery. Sticky notes (collapsible), stickers, tapes, tabbed notebooks/diaries, digital diaries, kawaii, 200+ templates, 100+ covers. |

### Official store listings
| # | URL | Note |
|---|-----|------|
| S5 | https://apps.apple.com/app/noteshelf-3/id6458735203 | App Store listing + privacy + "What's New" (8.1.2: **Add Space to Your Page**, **per-notebook scrolling style**), free tier limits, 65 search languages, iOS 18+. |
| S69 | https://play.google.com/store/apps/details?id=com.fluidtouch.noteshelf3&hl=en_US | Android listing. Confirms same feature set, "one-time purchase" premium wording, "add blank pages between PDF pages". |

### Official help centre — index / structure
| # | URL | Note |
|---|-----|------|
| S6 | https://noteshelf-support.fluidtouch.biz/hc/en-us | Help centre home; category tree for NS3 iOS, NS2 iOS, Android, Windows. |
| S7 | https://noteshelf-support.fluidtouch.biz/hc/en-us/categories/22023798601881-Noteshelf-3-on-iOS | NS3 iOS category (What's New / FAQ / Announcements / Known issues). |
| S8 | https://noteshelf-support.fluidtouch.biz/hc/en-us/sections/22024780064025-FAQ-s | NS3 iOS FAQ index (10 articles). |
| S9 | https://noteshelf-support.fluidtouch.biz/hc/en-us/sections/360008189193-FAQs | NS2 iOS FAQ index (65 articles) — still the only detailed documentation for many tools that carry over into NS3. |
| S10 | https://noteshelf-support.fluidtouch.biz/api/v2/help_center/en-us/articles.json | Public Zendesk API used to read all 179 article bodies (2 pages). |

### Primary articles (NS3 unless noted)
| # | URL | Note |
|---|-----|------|
| S11 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/23212408206745-How-is-Noteshelf-3-more-advanced-than-Noteshelf-2 | **Best single source.** Full NS3 delta: PDF backups, Content Views, Tags view, sortable categories, Quick Note settings, custom template colours, writable covers, Focus Mode, mini toolbar (8 dock positions), stickers/snippets, lasso multi-options, colour picker, text line spacing, non-uniform image crop, web clips, AI. |
| S12 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/22024757963929-What-s-New-in-Noteshelf-3 | NS3 launch overview: customizable toolbar, 100s of templates, Unsplash covers, mini toolbar, 4-finger focus mode, Content Views, Home section, 60-language handwriting search. |
| S13 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360046855213-6-Features-in-Noteshelf-You-Might-Not-Know-About | Micro-features: swipe pen rack for 14+ colours, custom swatches, date stamp via Get Info, **resizable zoom box (drag bottom-right triangle) + zoom box move handle for palm rejection**, categories, drag-to-group, edge swipes for quick access / bookmarks+TOC. |
| S14 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360060742493-Pen-rack-and-Color-Picker-UI-Enhancements | Pen size slider, 0.1 mm increments, movable favourites toolbar w/ Auto-minimize, COLOURlovers palettes, delete colour. |
| S15 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360060909814-Favorites-Toolbar-How-to-add-rearrange-and-delete-favorites | "Show Favorites Toolbar", add pen/highlighter w/ colour+nib, long-press drag reorder, bin to delete, dock top/bottom/left/right. |
| S16 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/21887313617305-The-All-New-Floating-Mini-Toolbar | Mini toolbar: 3 colours by default, custom colour + **ink dropper**, size presets, long-press swatch → "Edit Color" / "Restore to Default", draggable to 8 positions. |
| S17 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/21890045420313-How-to-use-the-Focus-Mode | Focus Mode via 4-finger tap or slashed-circle icon; audio + image/clipart/sticker editing still work; share/thumbnails/presentation require exiting. |
| S18 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4414988800025-Where-is-the-Zoom-Mode-icon-in-v8-6 | Zoom Box moved to "More" → "Zoom Box" toggle; magnifier icon bottom-right; three-line icon closes it. |
| S19 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4414988378137-How-to-change-page-Scrolling-mode-mode-changed-automatically-in-v8-6 | Scrolling mode: "More" → "View" → horizontal/vertical. **Vertical became default for new installs in v8.6** (bug applied it to existing users, fixed 8.6.1). |
| S20 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4411279536281-How-to-change-palm-rejection-writing-style-setting | Settings → "Handwriting" → **6 writing styles, 3 for left-handers**; UI + palm rejection adjust. |
| S21 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/18175000074521-How-to-use-Bookmarks-in-Noteshelf | Bookmarks: Pages icon → bookmark icon; long-press to change colour + name; filter "Bookmarked"; thumbnail vs list view; clickable chapters. Default colour blue. |
| S22 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/1500000943481-How-to-create-and-edit-the-bookmark-title-and-color-from-the-Finder-menu | Bookmark title/colour editing from Finder; long-tap bookmark → colour + rename → Save. |
| S23 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/18783688583321-Layers-Send-to-back-Bring-to-front | **No layer system** — only per-object "Bring to Front"/"Send to Back" for images, text boxes, strokes/highlights, shapes. |
| S24 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4408484586009-How-to-Create-Custom-pages-Covers | Custom paper: import **PDF or PNG**; exact recommended pixel sizes per iPad; cover ratio 137×170; import path "+ → New Notebook → paper template → Custom". |
| S25 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360058380894-New-Covers-and-Paper-Templates-browser-UI-Enhancements | Change cover via long-press → "Change Cover"; page template via "+ → Page → page from template" or wrench → "change page template"; colour + line height under "Basic" "..."; Free Downloads consolidated. |
| S26 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/22808638737689--v8-0-2-Introducing-The-All-New-Template-Store | Template Store: browse/download to Library, custom templates, orientation, type, colour, rule size, device type; long-press custom → Create Notebook / Delete; cannot create Library/Custom templates from inside a notebook. |
| S27 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360046856973-Digital-diaries-with-custom-term-periods | Digital Diaries with custom term periods; start date < end date; **max 12 months**. |
| S28 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4415033638809-What-s-New-with-the-Shapes-tool-post-v8-6 | Shapes tool independent with own palette + nib slider; "Hold to Convert to Shape" inside Pen & Highlighter menus; tap shapes icon twice for its menu. |
| S29 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/12457630478105--v1-0-21-0-Draw-Straight-Lines-From-Highlighter | Highlighter: double-tap highlighter icon → enable "Draw Straight Lines". |
| S30 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/22746403936793--v8-0-4-All-new-Draw-Straight-Lines-Editable-Shapes | Preset + freeform shapes, editable/rotatable after "Hold to Convert"; "Draw straight lines" appears only in Highlighter rack; edit shape via long-tap. |
| S31 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/22106358861465-Introducing-Preset-Geometrical-Shapes-Editing-of-Shapes | Preset geometrical + custom shapes; edit via lasso context: resize/flip, rotate, move, cut/copy/delete. |
| S32 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360058367054-How-to-Create-Sticky-Notes-in-Noteshelf-iOS | Sticky notes: Text tool → double-tap page → **sticky-note icon top-left of the keyboard** → choose colour → resize. |
| S33 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/21884632746137-How-to-use-Stickers-add-new-ones | Stickers: Add menu → Image Gallery tab → Stickers; long-press object → Delete/Resize/Rotate/Cut/Copy/Paste/**Lock**/Bring to front/Send to back; download packs from Templates. |
| S34 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/30438120078873-Introducing-Snippets-Saved-Clips-Custom-Stickers | Lasso → "Save Clip"; categories; default category "My Clips"; "+ menu → Saved Clips"; rename/delete; long-press clip to add to page. |
| S35 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/1500001623222-How-to-create-and-manage-Audio-Recordings-in-Noteshelf-iOS | Add menu → "Record Audio"; mic icon auto-records; long-press mic → Record/Play/Export/Delete; playback speed; resume recording from player. |
| S36 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360046856373-How-to-search-handwriting-convert-to-text | Lasso → "Convert To Text" → review/edit; search via page-thumbnail search. |
| S37 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360047002434-How-to-use-Handwriting-Recognition | Settings → "Handwriting Recognition" → **download per-language pack** then select; search from double-page icon. |
| S38 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/22809060465561-How-to-Create-Manage-Tags | Tags on pages **and** notebooks; via page long-press → Tag, or Customize toolbar → add Tag; Tags section on shelf; tag search incl. Finder. |
| S39 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/22521828227609-How-to-create-Groups-Sub-groups | Drag notebook onto another to group; nested sub-groups; "+" to create empty group; More Options → Select Notes; cannot group from "Home"; ungroup via "Move". |
| S40 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4409828511257-Subgroups-in-Noteshelf-iOS | Unlimited sub-group levels; long-tap the arrow next to the group name for a breadcrumb jump menu. |
| S41 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/21885120773529-How-to-view-two-notebooks-side-by-side | Side-by-side = **OS Multiple Windows**: drag app beside, or long-press notebook → "Open in new window". No in-app split view. |
| S42 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360061152914-How-to-use-Manual-Sorting-in-Noteshelf-v8-3 | Pull down on shelf → sorting mode → "Custom"; drag to arrange. |
| S43 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360046855313-How-to-Categorize-Shelves-in-Noteshelf | "My Notes" → "Add New Category"; drag notebooks in; rename/edit via "Edit" in the category dropdown. |
| S44 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/19504346634393-How-to-enable-Auto-back-up-in-Noteshelf-iOS | Auto-backup settings: "Auto-Backup notebooks", "Backup on WiFi only", "Notebooks to Backup" count, "Last Back up at", "Storage space used"; per-new-notebook default via New Notebook → More options → "Auto Back-up"; imported PDFs are **not** auto-backed-up/published. |
| S45 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/49110156650137-How-to-Auto-Backup-Noteshelf-3-files-to-the-Cloud-Storage | NS3 path: ⋮ → Settings → Sync & Backup → Auto Backup Notebooks; Drive/Dropbox/OneDrive/WebDAV; **one-way** mirror, not sync; delete = no effect remotely; folder "Noteshelf 3". (Article filed under Android NS3.) |
| S46 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/49370143321497-How-to-Set-Up-WebDAV-for-Backup-in-Noteshelf-3 | WebDAV: Settings → Cloud & Backup → WebDAV → Server URL / Username / Password → "Connect" → pick folder. |
| S47 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360058358394-v8-2-Export-Entire-Database-to-your-Device | Settings → Cloud and Back-up → Export → "Export Data": zip preserving Categories/Groups; offline exports only downloaded books. |
| S48 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360046213114-How-to-enable-Evernote-Auto-Publish-in-Noteshelf | Evernote auto-publish exists (NS2-era article; body empty, feature referenced in S44 notes). |
| S49 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4404466519449-How-to-Lock-your-Notes-on-Noteshelf-iOS | Per-notebook "Password" toggle with Password / Verify / Hint; optional Touch ID; hint shown after repeated wrong entries. |
| S50 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4402353351321-New-Presentation-Mode-in-Noteshelf-iOS | Presentation mode: laser pointer, neon pens, whiteboard, "Hide UI on external display". |
| S51 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4415008371225-Where-is-the-new-ROM-read-only-mode-icon-post-v8-6 | ROM icon is last on the toolbar; tap page to hide toolbar; "Edit" exits; blocks page-level actions incl. delete. |
| S52 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360046216094-Mac-Keyboard-shortcuts-in-Noteshelf | Full Mac shortcut list (⌘N, ⌥⌘N, ⇧⌘P, ⌥⇧⌘P, ⌥⌘B, ⌘→/⌘←, ⌥⌘→/←, ⇧⌘I, ⇧⌘N). |
| S53 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/21713907764505-Introducing-AI-for-Noteshelf-3 | AI: lasso selection or whole page, AI icon/contextual menu, response as handwriting or text; handwriting output only EN/FR/DE/IT/ES; 30 free trials at launch; ChatGPT API. |
| S55 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4415815036569-NS3-for-Apple-Watch-is-here | Apple Watch companion. |
| S56 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360057462514-How-to-Create-Delete-and-Restore-a-page-in-Noteshelf-iOS | Add → "Page"/"Page from template"; drag page left to add; Edit → More → "Move to Trash"; Trash → "Recover Page". |
| S57 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4402386285081-How-to-Move-Copy-paste-pages-from-one-Notebook-to-another-in-Noteshelf-iOS | Pages: Edit → select → More → Move / Copy, then "Paste Below". |
| S58 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360056896934-How-to-import-and-annotate-PDFs-in-Noteshelf-iOS | "+" → "Import Document"; highlight/underline; shapes tool for straight highlighter lines. |
| S59 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360058517153-How-to-import-and-edit-images-in-Noteshelf-iOS | Add → Photo Library → resize by corners → edit: crop, erase, cut → Apply. |
| S60 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4406366150297-How-to-import-stock-photos-from-the-Noteshelf-Media-Library | "Media Library" (Pixabay + Unsplash), Vectors filter for transparent PNGs, lock image to prevent accidental selection. |
| S61 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/900004911606-Copy-Paste-functions-in-Noteshelf-iOS | Lasso → tap outline → Copy; Lasso → Paste; paste images from other apps while in Pen mode. |
| S62 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360058199154-Drag-and-Drop-Functions-in-Noteshelf-iOS | Drag-drop: group notebooks, images, cliparts, PDFs/images/.noteshelf files from Files, reorder pages in Finder. |
| S63 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/900006344343-How-to-export-your-notes-to-the-Printer-in-Noteshelf-iOS | Page Finder → select → Share → PDF or PNG → "Share Now" → Print. |
| S64 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4407181330073-How-to-Rotate-Pages-on-Noteshelf-iOS | Settings → "Rotate Page" → CCW 90 / CW 90 / 180; handwriting rotates with page. |
| S65 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4408483517849-How-to-change-the-default-text-font-in-Noteshelf-iOS | Text tool → double-tap → paintbrush above keyboard → font menu → "Set as default". |
| S66 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4408172242457-How-to-Add-Custom-Fonts-in-Noteshelf-iOS | Install via iFont, then pick from font menu. |
| S67 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360046211214-Sidebar-Pin-notebooks-D-D-multiple-notebooks-Context-Menu-what-s-new-i | v7.0: sidebar replaces dropdown, "Recent" tab, pin notebooks, multi-select drag, context menu with "Open in New Window", custom digital diaries. |
| S70 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/22022928664985-Exciting-new-features-in-our-latest-v8-0 | v8.0: 200+ template store, AI, preset/editable shapes, multi-notebook export, **light/dark mode via in-app Settings**. |
| S71 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360046855153-What-s-New-in-Noteshelf | NS2 relaunch: iCloud sync, pinch-to-zoom on notebooks/PDFs, bullets/numbers/checkboxes, date+name auto-sort, 50+ templates, import PDF into existing notebook, **"When the Apple pencil is connected, use a single finger to swipe. Otherwise, swipe with two fingers."**, date stamp. |
| S72 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360046550814-Whats-New-in-Noteshelf-v7-0-5 | v7.0.5: **page-level undo/redo kept across pages until notebook closes**; new Select Mode with bulk ops. |
| S73 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/14273189697817-How-to-use-Handwriting-to-Text-OCR-Feature | Windows OCR how-to (confirms lasso→convert flow across platforms). |
| S74 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/26001015395097-Introduction-to-Noteshelf-AI-on-Windows | Windows AI parity. |
| S75 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/22808638737689--v8-0-2-Introducing-The-All-New-Template-Store | (same as S26 — template store UI change and Noteshelf Club removal). |
| S76 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360046856173-Mac-How-to-use-a-stylus | Mac has no direct Pencil input; use Sidecar or Wacom tablet. |
| S77 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360046900293-Zoom-Lock-in-Noteshelf-for-Android | Android has "Zoom Lock" (pinch-zoom then lock). Not documented for iOS. |
| S78 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360046855273-How-to-Enable-iCloud-Sync-in-Noteshelf | Settings → "Cloud & Backup" → "Use iCloud". |
| S79 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/4408475811353-How-to-disable-re-enable-iCloud-feature-safely-in-Noteshelf-iOS | Turning "Use iCloud" off prompts "Keep on my device". |
| S80 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360046214954-iCloud-Sync-Issues-Here-s-how-to-troubleshoot | iCloud troubleshooting (cache/eviction behaviour). |
| S81 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360049162614-Notebooks-Graying-out-too-soon-why-they-need-to-be-downloaded-often | Explains greyed-out iCloud notebooks and cache eviction. |
| S82 | https://noteshelf-support.fluidtouch.biz/hc/en-us/articles/360046213054-How-to-change-the-color-of-your-handwritten-content-in-Noteshelf | (Article body empty — cannot verify.) |

### Secondary
| # | URL | Note |
|---|-----|------|
| S68 | https://paperlike.com/blogs/paperlikers-insights/noteshelf-review | **2026 third-party review (32 min, updated Nov 2026).** Only source detailing eraser sub-modes, tape tool options, zoom-box sub-settings, Apple Pencil menu items, export toggles, and the 2026 App Store UI. Marked **[secondary]** throughout. |

---

## Feature list

Legend: **[P]** = primary (official Noteshelf site/help/App Store). **[S]** = secondary (Paperlike 2026 review).

### Notebooks, covers, paper
| Area | Feature | How it works (exact UI names in "quotes") | Source |
|---|---|---|---|
| Notebooks | Everything is a notebook | Imported PDFs, scans, images all become notebooks on the shelf (no separate "document" concept) | [S68] |
| Notebooks | Quick Note | "+ New" → "Quick Note": instant blank notebook, no cover dialog | [S68] |
| Notebooks | Quick Note settings | "Quick Note Settings": size, line height, paper colour, orientation; first launch = blank white page, then **remembers last choice** | [S11] |
| Notebooks | Tabbed notebooks | Notebook with pre-built sections/tabs | [S4] |
| Covers | 100+ covers, full-size & writable | Covers are full-size so you can "write or doodle on them"; custom covers via Unsplash or own photo | [S11][S12][S4] |
| Covers | Change cover | Long-press notebook → "Change Cover"; categories, Free Downloads, or "Custom" import (ratio 137×170) | [S25][S24] |
| Covers | PDFs get covers | Imported PDFs can be given a cover from cover templates | [S71] |
| Paper | Default paper types | "Plain, Ruled, Checked, Dotted & Legal" + "More Templates" | [S26] |
| Paper | Custom paper | Import **PDF or PNG** via "+ → New Notebook → paper template → Custom → +"; per-device pixel sizes documented (e.g. iPad 12.9: 1024×1302 portrait) | [S24] |
| Paper | Template colours & rule size | Under "Basic" tap "..." → colour + line height; template store exposes type, colour, rule size, device type, orientation | [S25][S26] |
| Paper | Template library | Download from Template Store into your own Library; long-press custom → "Create Notebook" / "Delete" | [S26] |
| Paper | Digital diaries | "Digital Diaries" templates with duration wheel; custom term periods; **max 12 months**; start < end date enforced | [S27][S67] |
| Paper | Planners/journals | 200+ templates incl. Cornell notes, daily/weekly/monthly planners, journals, trackers | [S4][S69] |
| Paper | Per-page template | Add → "Page from template" or wrench → "change page template" — changes one page only | [S25] |
| Paper | Add space to page | v8.1.2: "Add Space to Your Page" — expand the canvas to a preferred size mid-note, incl. on PDFs | [S5] |

### Pens, highlighter, eraser
| Area | Feature | How it works | Source |
|---|---|---|---|
| Pens | 4 pen styles | "Ball" (default), "Felt", "Fountain", "Pencil" — all pressure sensitive | [S1][S68] |
| Pens | Line styles | Solid, dotted, dashed per size preset | [S68] |
| Pens | 3 size presets + slider | Three presets on the floating toolbar; tap one then drag slider; **0.1 mm increments**, thinner nibs added | [S14][S68] |
| Pens | Colour swatches | 14 predefined; swipe left on pen rack for more; long-press swatch for custom colour; edit icon to change without losing the original | [S13] |
| Pens | Palette picking | "COLOURlovers" to pick a single colour **or an entire palette**; delete colours via top-right trash | [S14] |
| Pens | Hex input | Long-press colour → enter hex, save to quick-select | [S68] |
| Pens | Ink dropper | Mini Toolbar → custom colour swatch → "Ink Dropper" → pick any colour from the page | [S16][S11] |
| Pens | Favourite pens | "Show Favorites Toolbar" → "Add" → any pen/highlighter + colour + nib; long-press drag to reorder; bin to delete | [S15] |
| Pens | Favourites behaviour | Three-dot icon → "Auto-minimize", "Minimize", "Close"; drag to a corner → collapses to a round icon showing the current pen | [S14] |
| Pens | Floating mini toolbar | Appears on pen/highlighter/shapes tap; 3 colours by default; long-press swatch → "Edit Color", "Restore to Default"; dock to 8 positions incl. horizontally under main toolbar | [S16][S11] |
| Highlighter | 2 styles | "Round" and "Slanted"; 3 size presets + slider | [S1][S68] |
| Highlighter | Opacity behaviour | Translucent so text stays readable; highlighting twice darkens the area | [S68] |
| Highlighter | Draw straight lines | Double-tap highlighter icon → "Draw Straight Lines"; also appears in pen menu post-8.6 | [S29][S30] |
| Highlighter | Erase highlighter only | Dedicated eraser sub-mode (see Eraser) | [S68] |
| Eraser | Sizes + Auto | 3 sizes + "Auto" which resizes to the detected stroke area (caps at largest size) | [S68] |
| Eraser | Sub-modes | "Erase Entire Stroke", "Erase Highlighter Only", "Erase Pencil Only", "Erase Tape Only", "Clear Page" | [S68] |
| Eraser | Auto-select previous tool | Toggle that snaps back to the previous tool after one erase — useful for one-off corrections, annoying for bulk erasing | [S68] |
| Eraser | Pencil double-tap | Apple Pencil double-tap can switch pen↔eraser natively (set in "Double-Tap Action") | [S68] |
| Stylus | "Stylus" toggle (More menu) | In the "More" (⋯) menu, directly under "Zoom Box": row labelled "Stylus" with subtitle "Apple Pencil" and a green toggle | [S18] |
| Stylus | Apple Pencil menu | "Use Apple Pencil", "Pressure Sensitivity", "Double-Tap Action" | [S] only — [S68] |

### Lasso, shapes, straight lines, layers
| Area | Feature | How it works | Source |
|---|---|---|---|
| Lasso | Two selection modes | Pre-defined **boxed selection vs free-hand** | [S11] |
| Lasso | Per-type enable | Independently enable/disable lasso for **handwriting, text boxes, photos, shapes** | [S11] |
| Lasso | Contextual actions | Tap selection → copy, cut, delete, resize, recolour, screenshot, "Convert To Text", "Save Clip", Bring to Front/Send to Back | [S61][S36][S34][S23] |
| Lasso | Resize caveat | Enlarging handwriting can look blurry (vector-but-rasterised) | [S68] |
| Shapes | Preset shapes | Independent Shapes tool with its own palette + nib slider; tap icon twice for its menu | [S28][S31] |
| Shapes | Hold to convert | "Hold to Convert to Shape" inside Pen **and** Highlighter menus — draw a shape with your current pen and hold | [S28][S30] |
| Shapes | Editable after conversion | Long-press shape → drag handles to resize/flip, rotate, move, cut/copy/delete | [S30][S31] |
| Shapes | Auto-straighten limits | Hexagons/octagons often collapse to a circle; curves over-rotate into circles; shapes are not forced proportional | [S68] |
| Layers | **No layer stack** | Only per-object "Bring to Front" / "Send to Back" for images, text boxes, strokes/highlights and shapes | [S23] |

### Navigation, zoom, pages, focus
| Area | Feature | How it works | Source |
|---|---|---|---|
| Zoom | Zoom Box | "More" → "Zoom Box" toggle → magnifier icon bottom-right; box at top, magnified strip below | [S18][S68] |
| Zoom | Resizable zoom box | Drag the **small triangle at the bottom-right corner** to enlarge it | [S13] |
| Zoom | Move handle = palm rest | Top-right icon moves the box; documented as helping palm rejection | [S13] |
| Zoom | Zoom box sub-settings | Margins, line spacing, button placement, **disable auto-advance** | [S] only — [S68] |
| Zoom | Pinch to zoom | Two-finger pinch on notebooks and PDFs | [S71] |
| Zoom | Zoom Lock | Android only: zoom in then lock | [S77] |
| Pages | Page turning | "When the Apple pencil is connected, use a single finger to swipe. Otherwise, swipe with two fingers." | [S71] |
| Pages | Scrolling mode | "More" → "View" → horizontal or vertical; **vertical is the default for new installs** (v8.6) | [S19] |
| Pages | Per-notebook scrolling | v8.1.2: set scrolling independently for each notebook | [S5] |
| Pages | Page Finder | Double-page icon; thumbnails, search, tag filter, bookmark filter, edit/move/copy/trash | [S56][S57] |
| Pages | Add page | Add → "Page" / "Page from template"; or drag a page leftwards to insert | [S56] |
| Pages | Trash | Edit → More → "Move to Trash"; Trash → "Recover Page" | [S56] |
| Pages | Reorder | Drag pages inside the Finder | [S62] |
| Pages | Rotate page | Settings → "Rotate Page" → CCW 90 / CW 90 / 180; handwriting rotates with it | [S64] |
| Pages | Undo across pages | Undo/redo history survives page changes **until you close the notebook** | [S72] |
| Focus | Focus Mode | 4-finger tap or slashed-circle icon; tools vanish; audio + image/sticker editing still allowed | [S17][S12] |
| Focus | Read-only mode (ROM) | Last toolbar icon; tap page to hide toolbar entirely; "Edit" to exit; blocks page edits/deletes | [S51] |
| Navigation | Edge swipes | Swipe from left edge → Quick Access (recent/pinned notebooks); swipe from right → Bookmarks, Tags, page list, PDF table of contents | [S13] |
| Navigation | Sidebar + pinning | Sidebar with categories, "Recent" tab, pinned notebooks; multi-select drag | [S67][S12] |
| Navigation | Side-by-side | iOS Multiple Windows: "Open in new window" — **no in-app split view** | [S41] |

### Text, audio, search, AI
| Area | Feature | How it works | Source |
|---|---|---|---|
| Text | Text boxes | Double-tap page with Text tool; glyph + paragraph formatting; bullets, numbers, checkboxes; line spacing; alignment | [S65][S71][S11] |
| Text | Default font | Paintbrush above keyboard → font menu → "Set as default" | [S65] |
| Text | Custom fonts | Install via iFont etc., then select in the font menu | [S66] |
| Text | Text box colour | Any colour, plus adjustable text line spacing | [S11] |
| Text | Sticky notes | Text tool → double-tap → sticky-note icon top-left of the keyboard → colour; collapses to an icon and can be moved | [S32][S4] |
| Text | Interactive checklists | Real tappable checkboxes (not glyph bullets) | [S68] |
| Audio | Page-attached recording | Add → "Record Audio" → mic icon appears on page and starts recording; long-press mic → Record/Play/Export/Delete; playback speed | [S35] |
| Audio | Re-record onto same icon | Player's Record button appends to the same recording | [S35] |
| Audio | **No stroke-linked playback** | Audio is attached to a page, not to strokes (unlike Notability/GoodNotes) | [S68] |
| Audio | Audio transcription | AI transcribes recordings and summarises key points (iOS 26 / newer builds) | [S3][S68] |
| Search | Global handwriting search | Searches handwriting, typed text and PDFs; **65 languages** per App Store, "60" per launch post | [S5][S12] |
| Search | Language packs | Settings → "Handwriting Recognition" → download the language pack, then select it | [S37] |
| Search | Content Views | Auto-folder views on the shelf for **Photos, Recordings, Bookmarks** across all notebooks | [S11][S12] |
| Search | Scoped search | In-notebook search from the sidebar returns only that notebook's hits | [S68] |
| Search | Tag search | Tags appear as suggestions in global and Finder search | [S38] |
| Text→ | Convert handwriting | Lasso → "Convert To Text" → review/edit dialog; optional font size "Default" resets to the saved text-tool size | [S36][S68] |
| AI | Noteshelf AI | Lasso a region or use whole page → AI icon / contextual "Noteshelf AI" → Summarise, Explain, Generate notes, Translate, Ask anything, Handwrite notes | [S53][S3] |
| AI | Output as ink | Response can be inserted **as handwriting** or as text; handwriting output only EN/FR/DE/IT/ES | [S53] |
| AI | AI tags & images | "Suggested Tags" and "Image Playground" via Apple Intelligence, iOS only | [S3] |
| AI | Privacy | Selected/whole page content is sent to the ChatGPT API | [S53] |

### Organisation, stationery, import/export
| Area | Feature | How it works | Source |
|---|---|---|---|
| Org | Categories (shelves) | "My Notes" → "Add New Category"; rename via "Edit" in the category dropdown; categories can be **reordered/sorted** | [S43][S11] |
| Org | Groups & sub-groups | Drag notebook onto notebook; nested to unlimited depth; long-tap the group arrow for a breadcrumb jump | [S39][S40] |
| Org | No sub-folders in categories | Categories hold notebooks/groups only — groups are the nesting mechanism | [S68] |
| Org | Tags | Page-level **and** notebook-level; toolbar Tag button; shelf "Tags" view; long-press page → "Edit Tags" | [S38] |
| Org | Bookmarks | Named + colour-coded; list view acts as clickable chapters/TOC | [S21][S22] |
| Org | Sorting | "Date Last Opened", "Date Modified", "Name", "Custom" (manual drag) | [S68][S42] |
| Org | View density | List or grid, **and** large vs small notebook thumbnails | [S68] |
| Org | PDF outline | Recognises PDF outlines for navigation; bookmarks substitute when missing | [S68] |
| Stationery | Stickers | Add → Image Gallery → "Stickers"; 500+; downloadable packs | [S33][S1] |
| Stationery | Saved Clips (custom stickers) | Lasso → "Save Clip"; categories; default "My Clips"; reuse any ink/text/image combo | [S34] |
| Stationery | Tape tool | 9 solids + 9 patterns, adjustable width, straight or freehand; "Erase Tape Only"; used for self-testing/revision | [S68][S4] |
| Stationery | Washi/decoration | Tape doubles as washi tape for journals | [S4] |
| Stationery | Sticky notes | See Text — coloured, collapsible | [S32][S4] |
| Stationery | Media library | Built-in Unsplash + Pixabay search; "Vectors" filter for transparent PNGs | [S60] |
| Import | PDF/Word/PPT/images | "+" → "Import Document"; annotate with pen/highlighter; add blank pages between PDF pages (Android listing) | [S58][S69] |
| Import | Scanner | Built-in document scanner with edge detection + manual handles | [S68] |
| Import | Web clips | Save web articles/pages into a notebook, available offline | [S11][S68] |
| Import | Drag & drop | Drop images/PDFs/.noteshelf files from Files, Safari, Photos | [S62] |
| Export | Share options | "Current Page / Select Pages / All Pages" × "Image / PDF / Noteshelf File"; toggles for "Page Template", "Cover Page", "Title & Page No." | [S68] |
| Export | Print | Page Finder → select → Share → PDF/PNG → "Share Now" → Print | [S63] |
| Export | Whole database | Settings → Cloud and Back-up → Export → "Export Data" → zip preserving categories/groups | [S47] |

### Sync, backup, security, presentation, platform
| Area | Feature | How it works | Source |
|---|---|---|---|
| Sync | iCloud sync | Settings → "Cloud & Backup" → "Use iCloud"; same Apple ID required | [S78] |
| Sync | Disable iCloud safely | Toggle off → choose "Keep on my device" | [S79] |
| Sync | Greyed-out notebooks | iCloud cache eviction forces re-download; auto-backup to a third-party drive avoids it | [S81] |
| Backup | Auto-backup targets | Google Drive, Dropbox, OneDrive, **WebDAV** (CloudMe/NextCloud/ownCloud) | [S45][S46] |
| Backup | Backup settings | "Auto-Backup notebooks", "Backup on WiFi only", "Notebooks to Backup" (n/total), "Last Back up at", "Storage space used" | [S44] |
| Backup | Per-notebook default | New Notebook → More options → "Auto Back-up" makes new notebooks auto-back up | [S44] |
| Backup | Backup format | Native **or PDF** ("PDF Format Backups" — readable anywhere) | [S11] |
| Backup | One-way, not sync | Auto-backup mirrors to cloud; deletions don't propagate; not a sync engine | [S45] |
| Backup | Evernote | "Auto Publish" to Evernote existed in NS2; imported PDFs are excluded | [S48][S44] |
| Security | Notebook password | Notebook Options → "Password" toggle → Password / Verify / Hint; hint revealed after repeated failures | [S49] |
| Security | Biometric unlock | Touch ID/Face ID unlock, password still required as fallback | [S49][S5] |
| Presentation | Presentation mode | Projector icon; laser pointer, neon pens, whiteboard; "Hide UI on external display" | [S50] |
| Presentation | Hide UI toggle | Slashed-circle button hides UI from audience | [S68] |
| Platform | Mac shortcuts | ⌘N new notebook, ⌥⌘N quick create, ⇧⌘P new page, ⌥⇧⌘P page from template, ⌥⌘B bookmark, ⌘←/→ page nav, ⌥⌘←/→ first/last, ⇧⌘I import, ⇧⌘N new window | [S52] |
| Platform | Mac stylus | No direct Pencil; use Sidecar mirroring or a Wacom tablet | [S76] |
| Platform | Apple Watch | Companion watch app | [S55] |
| Platform | Siri | "Use this app with Siri" per App Store | [S5] |
| Commercial | Free tier | 3 notebooks, core pens + paper, no HWR/auto-backup; Premium unlocks unlimited notebooks, all templates, HWR, auto-backup, 100 AI credits/month | [S5] |

---

## Settings & toggles

Every documented setting, with exact naming. Defaults are stated **only** where a source states them.

### Settings → Cloud & Backup
| Setting (exact) | Default | What it changes | Why a user cares |
|---|---|---|---|
| "Use iCloud" | Not stated (requires iOS iCloud Drive on) | Device-to-device sync of notebooks (not backup) | Only way to get notes onto iPhone/Mac; off = local only | 
| "Keep on my device" (prompt on disabling iCloud) | — | Keeps notebooks local instead of removing them | Prevents the classic "I turned off iCloud and lost my notes" panic | 
| "Auto-Backup notebooks" | Off (not stated) | Mirrors notebooks to a chosen cloud drive | Safety net that is *not* sync — survives account mistakes | 
| Backup destination | — | Google Drive / Dropbox / OneDrive / **WebDAV** | WebDAV = self-hosted (NextCloud/ownCloud); rare and valuable | 
| "Backup on WiFi only" | Off (not stated) | Restricts uploads to WiFi | Stops cellular data blowups on large notebooks | 
| "Notebooks to Backup" (n of total) | — | Read-out of backup coverage | Instantly shows which notebooks are unprotected | 
| "Last Back up at" | — | Timestamp | Trust check without leaving the app | 
| "Storage space used" | — | Drive quota used/left | Prevents silent backup failure when the drive is full | 
| Backup format (native vs PDF) | Native | PDF backups are human-readable | Notes survive even if the app dies — a real differentiator | 
| "Auto Back-up" (New Notebook → More options) | Off | Makes *new* notebooks auto-back up by default | Set once, every future notebook is protected | 
| "Cloud Logins" | — | Manage/sign out of Drive, Dropbox, OneDrive | Fixes expired-token backup failures | 
| WebDAV "Server URL" / "Username" / "Password" → "Connect" | — | Connects a private cloud; then pick a folder | Self-hosted backup without a vendor | 
| "Export Data" (Cloud & Backup → Export) | — | Zips the whole library preserving categories/groups | Full-fidelity escape hatch / manual archive | 

### Settings → Handwriting
Source: [S20][S68]; exact labels confirmed in the official screenshot `images/06-writing-styles-palm-rejection.png`.

| Setting | Default | What it changes | Why a user cares |
|---|---|---|---|
| "Writing Style" (6 hand icons, 3 left-handed) | Not stated; screenshot shows a right-hand grip selected | Model of how your hand rests; adjusts UI side and palm rejection | Biggest single fix for left-handers and for accidental palm marks | 
| "Handwriting Recognition" (row shows the active language, e.g. "English (UK)") | Device-language dependent | Per-language download, then select | Search/convert works offline; 60–65 languages | 

### Settings → Appearance
| Setting | Default | What it changes | Why a user cares |
|---|---|---|---|
| Theme: Light / Dark / System | Follows system | App chrome and page surroundings | Dark theme at night, light for scanning ([S70][S68]) | 

### Settings → Apple Pencil **[secondary]**
| Setting | Default | What it changes | Why a user cares |
|---|---|---|---|
| "Use Apple Pencil" | Not stated | Whether Pencil is treated as the primary input | Effectively the finger-vs-Pencil arbitration switch | 
| "Pressure Sensitivity" | Not stated | Stroke width from pressure | Pencil-feel tuning per user | 
| "Double-Tap Action" | Not stated | What double-tapping the Pencil side does (e.g. pen↔eraser) | Removes a toolbar trip mid-sentence | 

### In-notebook: "More" (⋯) menu
| Setting | Default | What it changes | Why a user cares |
|---|---|---|---|
| "Customize Toolbar" | Default tool set | Drag tools in/out of the notebook toolbar | You can delete tools you never use — biggest anti-clutter win | 
| "Zoom Box" toggle | Off (shown off in the official screenshot) | Enables the magnifier writing mode | Small handwriting without zooming the whole page | 
| "Stylus" toggle (subtitle "Apple Pencil") | On | Sits directly under "Zoom Box" in the More menu | The closest thing Noteshelf has to a stylus-only / finger-input switch | 
| "View" → horizontal / vertical scrolling | **Vertical** for new installs (8.6+); screenshot shows "Horizontal" as current value | Page flow direction | Vertical for reading/PDFs, horizontal for two-page spreads | 
| "Page Template" | — | Opens the template browser for the current page | Retemplate without leaving the page | 
| "Go To Page" | — | Jump to an arbitrary page number | Faster than scrubbing 200 thumbnails | 
| "Rotate Page" | — | 90° CCW / 90° CW / 180° | Fix landscape scans; ink rotates with the page | 
| "Get Info" | — | Shows notebook metadata incl. **date stamp** | Provenance/versioning without a separate UI | 
| "Password" | Not stated (screenshot shows it present in the More menu) | Per-notebook lock with hint | Shared-iPad privacy, no global vault | 
| "Tag" (toolbar item, added via Customize Toolbar) | Not on toolbar | Tags the current page inline | Tagging without opening the page finder | 

### In-notebook: tool options
| Setting | Default | What it changes | Why a user cares |
|---|---|---|---|
| "Show Favorites Toolbar" | Off | Floating pen rack of saved pens/highlighters | One tap to your 3–6 daily pens | 
| Favourites three-dot menu: "Auto-minimize" / "Minimize" / "Close" | Not stated | Collapse behaviour; Auto-minimize hides it when idle | Keeps the pen rack out of the writing area | 
| "Draw Straight Lines" (highlighter, and pen post-8.6) | Not stated | Snaps a dragged stroke to a straight line | Underlining and highlighting without rulers | 
| "Hold to Convert to Shape" (pen + highlighter) | Not stated | Hold at stroke end to convert to a shape | Circles/arrows without switching tools | 
| Eraser "Auto" | Not stated | Auto-sizes to the stroke under the nib | Fewer size adjustments | 
| "Auto-select previous tool" | Not stated | Snaps back after one erase | Good for single fixes, bad for cleanup | 
| "Erase Entire Stroke" | Not stated | Whole-stroke erase instead of pixel erase | Fast cleanup of mistakes | 
| "Erase Highlighter Only" | Not stated | Erases only highlighter ink | Re-highlight without destroying the pen layer | 
| "Erase Pencil Only" | Not stated | Erases only pencil ink | Keeps pen/highlighter intact | 
| "Erase Tape Only" | Not stated | Erases only tape | Uncover answers without nicking the ink | 
| "Clear Page" | — | Wipes the page | Fast reset for scratch pages | 
| Pen size slider | Per-preset | Continuous nib size in 0.1 mm steps | Matching a specific pen or paper rule | 
| Colour long-press → custom colour / hex | 14 preset swatches | Exact brand/paper colours | Visual consistency, accessibility | 
| "Ink Dropper" | — | Samples any colour already on the page | Match ink to an imported diagram instantly | 
| "Set as default" (text font) | System default | Default font for all future text boxes | Typed notes stop looking generic | 

### Shelf-level
| Setting | Default | What it changes | Why a user cares |
|---|---|---|---|
| Sort: "Date Last Opened" / "Date Modified" / "Name" / "Custom" | Not stated | Shelf order; "Custom" enables drag-arrange | Recently-used ordering is what most people actually want | 
| List vs grid, large vs small thumbnails | Grid | Density of the library | See 40 notebooks at once on a 13" iPad | 
| "Add New Category" | "My Notes" | New shelf category; categories reorderable | Work/Personal/School separation | 
| Tags view (sidebar) | — | Master list of all tags across the app | Cross-notebook retrieval by topic | 
| Content Views | — | Auto-views for Photos / Recordings / Bookmarks | Find a photo or a recording without remembering which notebook | 

### Export sheet
| Setting | Default | What it changes | Why a user cares |
|---|---|---|---|
| Scope: "Current Page" / "Select Pages" / "All Pages" | Current Page | What gets exported | Avoid dumping a whole notebook for one page | 
| Format: Image / PDF / Noteshelf File | PDF | Output type | .noteshelf for handoff, PDF for everyone else | 
| "Page Template" toggle | On | Includes the paper background | Turn off for transparent-background PNGs | 
| "Cover Page" toggle | Off | Prepends the cover | Nice for sharing, noise for printing | 
| "Title & Page No." toggle | Off | Header/footer on export | Submission-ready PDFs | 

---

## Small things, big impact

Ranked by daily-use payoff for a handwriting-first iPad app. Effort is for SwiftUI + PencilKit: **S** ≈ ≤1 day, **M** ≈ 2–5 days, **L** ≈ 1–2 weeks.

1. **Customizable toolbar** ("Customize Toolbar", drag tools in/out). [S11][S68] — Users delete half the default tools and the canvas stops fighting them. **M** (a tool enum + ordered array in `@AppStorage`, edit sheet with drag reorder).
2. **Floating mini toolbar with 3 recent colours + size presets**, dockable to 8 positions, long-press to "Edit Color". [S16][S11] — Colour switching is the single most frequent action ("5 million times a day" per Noteshelf). **M**.
3. **Favourite pen rack with Auto-minimize** — saved pen+colour+nib tuples, collapses to a round current-pen button. [S15][S14] — Turns a 4-tap flow into 1 tap; the collapsed bubble never blocks ink. **M**.
4. **Single-finger page turn only when Pencil is connected, else two fingers.** [S71] — Kills accidental page turns while resting a palm, without a settings trip. **S** (check `UIPencilInteraction`/last-input type).
5. **Writing-style presets incl. 3 left-handed modes**, wired to palm rejection and UI side. [S20][S68] — Lefties are ~10% of users and the most vocal about abandoning apps. **M**.
6. **Eraser sub-modes: "Erase Highlighter Only" / "Erase Pencil Only" / "Erase Entire Stroke" / "Erase Tape Only" + "Clear Page".** [S68] — Turns surgery into one swipe; highlighter-only is the killer one. **S–M** (per-stroke type tags in your model).
7. **Zoom box, resizable by dragging its corner, with a move handle doubling as a palm rest.** [S13][S18] — The only way to write small on 11" glass; the handle trick is a genuinely clever micro-detail. **L**.
8. **Per-notebook scroll direction (horizontal/vertical), default vertical.** [S19][S5] — PDFs and lectures want vertical; notebooks and planners want horizontal. **S**.
9. **"Hold to Convert to Shape" + "Draw Straight Lines" as pen/highlighter toggles.** [S28][S30] — Perfect circles and underlines without a tool switch; also fixes wobbly highlighter. **M**.
10. **Named + colour-coded bookmarks that render as a clickable chapter list.** [S21][S22] — Gives a table of contents to any PDF that lacks one; colour = "exam questions" vs "formulas". **S**.
11. **Read-only mode with tap-to-hide-toolbar.** [S51] — Reviewing a planner with hyperlinks without leaving stray dots; also a defacto present mode. **S**.
12. **4-finger-tap Focus Mode** (audio + sticker editing still allowed). [S17] — Edge-to-edge paper in one gesture, no menu. **S**.
13. **Auto-backup with PDF-format option, "Backup on WiFi only", and a per-notebook default toggle.** [S11][S44] — PDF backups mean notes outlive the app; WiFi-only prevents 200 MB surprises. **M**.
14. **Quick Note that remembers last size/line-height/colour/orientation.** [S11] — Capture speed is the whole point of a quick note; remembering settings removes the setup tax. **S**.
15. **Saved Clips / custom stickers (lasso → "Save Clip", categories, default "My Clips").** [S34] — Reusable diagrams, signatures, lab sketches; a "personal library" with almost no UI. **M**.
16. **Per-page template change + "Page from template" on add.** [S25] — Mixed paper inside one notebook (grid for diagrams, ruled for notes) without a second notebook. **S**.
17. **Page-level undo/redo that survives page changes until the notebook closes.** [S72] — The #1 "I turned the page and lost my undo" complaint. **S–M** (share one `UndoManager` per notebook session).
18. **Tag button on the toolbar + shelf Tags view + tag suggestions in search.** [S38] — Tagging at the moment of writing, not in a cleanup session. **S–M**.
19. **Export sheet toggles: "Page Template" / "Cover Page" / "Title & Page No."** [S68] — One export UI covers transparent PNGs, pretty PDFs and print-ready hand-ins. **S**.
20. **Sticky notes that collapse into a movable icon, with colour choice.** [S32][S4] — Margin commentary that doesn't eat page space; the collapse is the whole trick. **M**.

Runners-up worth stealing: the **"Stylus" toggle living in the page-level More menu rather than a distant settings app** [S18]; date stamp via "Get Info" [S13]; ink dropper [S16]; bookmark colour default blue [S21]; tape patterns for self-testing [S68]; category reordering [S11]; "Add Space to Your Page" canvas growth [S5].

---

## Images

Downloaded to `research_notes/competitors/noteshelf/images/` (15 files).

| File | Caption | Source |
|---|---|---|
| `01-mini-toolbar-pen-colors.jpg` | Mini toolbar docked **vertically at the left edge**: 3 colour dots + custom-palette dot + 3 size dots (official) | https://noteshelf-support.fluidtouch.biz/hc/article_attachments/21887293331609 |
| `03-snippets-saved-clips.jpg` | "Saved Clips" library UI (custom sticker categories) | https://noteshelf-support.fluidtouch.biz/hc/article_attachments/30438532927897 |
| `04-zoom-box-menu.png` | The real **"More" menu**: "Page Template", "Rotate Page", "Go To Page", "View — Horizontal", "Zoom Box" toggle (highlighted), "Stylus / Apple Pencil" toggle, "Password" | https://noteshelf-support.fluidtouch.biz/hc/article_attachments/4415078326553/Untitled_Artwork_34.png |
| `05-scrolling-mode-setting.png` | Same "More" menu with **"View — Horizontal >"** circled, the scrolling-direction setting | https://noteshelf-support.fluidtouch.biz/hc/article_attachments/4415088115993/Untitled_Artwork_35.png |
| `06-writing-styles-palm-rejection.png` | Settings → **"Handwriting"** sheet: "Writing Style" with six hand-grip icons (one selected), "Handwriting Recognition — English (UK) >", "Done"; shelf sidebar visible behind | https://noteshelf-support.fluidtouch.biz/hc/article_attachments/4411296554009/7815C56E-1DE2-4B54-9048-3D5FA624391F.png |
| `07-bookmarks-pages-menu.png` | **"Pages"** side panel: Search + Edit, page thumbnails with numbers, a blue bookmark flag on a page corner | https://noteshelf-support.fluidtouch.biz/hc/article_attachments/18174175276185 |
| `08-auto-backup-cloud.jpg` | Cloud backup **destination** viewed in Google Drive: "My Drive > Noteshelf 3 Android > Uncategorized", one `.nsa` file per notebook + mirrored group folders (official, Android build) | https://noteshelf-support.fluidtouch.biz/hc/article_attachments/49110156647705 |
| `09-favorites-toolbar.png` | Favourites toolbar: pill with drag handle, 5 saved pen/highlighter nibs (blue fountain, red highlighter, purple, orange, black), "+" to add, page dot, "···" menu | https://noteshelf-support.fluidtouch.biz/hc/article_attachments/900008574326/favetoolbar__1_.png |
| `10-presentation-mode.png` | Notebook toolbar with the **projector icon circled** (Presentation Mode entry), next to the slashed-circle (hide-UI / read-only) icon | https://noteshelf-support.fluidtouch.biz/hc/article_attachments/4402353339033/Screenshot_2021-06-15_at_10.54.21_AM.png |
| `11-pen-styles-paperlike.jpg` | Pen menu: Ball / Felt / Fountain / Pencil at three sizes **[secondary]** | https://cdn.shopify.com/s/files/1/1644/5247/files/Noteshelf_3_Review-6.jpg |
| `12-eraser-options-paperlike.jpg` | Eraser sheet: Auto, Auto-select previous tool, Erase Entire Stroke / Highlighter Only / Pencil Only / Tape Only, Clear Page **[secondary]** | https://cdn.shopify.com/s/files/1/1644/5247/files/Noteshelf_3_Review-8.jpg |
| `13-zoom-box-paperlike.jpg` | Zoom Box rectangle on the page with magnified strip below **[secondary]** | https://cdn.shopify.com/s/files/1/1644/5247/files/Noteshelf_3_Review-11.jpg |
| `14-tape-tool-paperlike.jpg` | Tape tool floating toolbar with solids/patterns and width control **[secondary]** | https://cdn.shopify.com/s/files/1/1644/5247/files/Noteshelf_3_Review-13.jpg |
| `15-apple-pencil-settings-paperlike.jpg` | Apple Pencil menu: "Use Apple Pencil", "Pressure Sensitivity", "Double-Tap Action" **[secondary]** | https://cdn.shopify.com/s/files/1/1644/5247/files/Noteshelf_3_Review-18.jpg |
| `16-customize-toolbar-official.webp` | Official "Customize Toolbar" screen with draggable tools | https://noteshelf.net/new/assets/features/row-toolbar-1746.webp |

(File numbering skips `02` — that slot held a low-value focus-mode thumbnail that was removed.)

### Remaining useful image URLs (not downloaded)
| URL | Caption |
|---|---|
| https://noteshelf.net/new/assets/features/row-organize-1888.webp | Library with folders + notebook size options |
| https://noteshelf.net/new/assets/features/row-focus-1636.webp | Focus mode, edge-to-edge paper |
| https://noteshelf.net/new/assets/features/row-search-1888.webp | "Find anything" handwriting search |
| https://noteshelf.net/new/assets/features/ipads-4440.webp | Six iPads showing rendered note styles |
| https://noteshelf.net/new/assets/stationery/aisle-sticky-1890.webp | Sticky notes (kawaii styles) |
| https://noteshelf.net/new/assets/stationery/aisle-tapes-1370.webp | Tape / washi styles |
| https://noteshelf.net/new/assets/stationery/aisle-stickers-1600.webp | Sticker pack art |
| https://noteshelf.net/new/assets/ai/hero-ipad-2100.webp | Noteshelf AI prompt sheet with Explain / Summarize / Generate / Translate / Handwrite |
| https://noteshelf.net/new/assets/ai/tile-tags-1360.webp | "Suggested Tags" (Apple Intelligence) in Note Options |
| https://noteshelf.net/new/assets/ai/tile-audio-1364.webp | Audio transcription + summary beside handwritten notes |
| https://noteshelf-support.fluidtouch.biz/hc/article_attachments/21890052271129 | Focus mode UI (official) |
| https://noteshelf-support.fluidtouch.biz/hc/article_attachments/4411300844441/settings-dark_1x.png | Settings icon location (dark theme) |
| https://noteshelf-support.fluidtouch.biz/hc/article_attachments/18812955833369 | Layers article — "Bring to Front / Send to Back" object menu |
| https://noteshelf-support.fluidtouch.biz/hc/article_attachments/30440356125465 | Saved Clips categories / "Add Clip" |
| https://noteshelf-support.fluidtouch.biz/hc/article_attachments/18174514626073 | Bookmark colour + name dialog |
| https://cdn.shopify.com/s/files/1/1644/5247/files/Noteshelf_3_Review-2.jpg | New-notebook screen: cover + paper template pickers **[secondary]** |
| https://cdn.shopify.com/s/files/1/1644/5247/files/Noteshelf_3_Review-9.jpg | Text box formatting sheet **[secondary]** |
| https://cdn.shopify.com/s/files/1/1644/5247/files/Noteshelf_3_Review-17.jpg | Shelf "More" menu: sort + view options **[secondary]** |

---

## Unverified

Things I could **not** confirm from a primary source — do not treat as fact:

1. **"Stylus-only mode" semantics.** A **"Stylus" toggle (subtitle "Apple Pencil") exists** and is visible in the official v8.6 More-menu screenshot [S18] — so this is primary-confirmed as a control. What it actually does (block finger drawing / prioritise Pencil / switch input device) is not documented anywhere, and its default is not stated. The secondary review separately shows a settings sheet with "Use Apple Pencil" [S68], possibly the same control in a different location.
2. **Eraser sub-mode names and behaviour.** All eraser detail comes from the 2026 Paperlike review [S68]; the official KB has no eraser article for iOS. Names may have shifted in 8.x.
3. **Zoom Box sub-settings** ("margins", "line spacing", "button placement", "auto-advance" toggle) — secondary only [S68]; official docs document only the toggle, the magnifier icon and the resize triangle [S18][S13].
4. **Exact "Auto-select previous tool" default** — not stated anywhere.
5. **Pressure Sensitivity default** — not stated.
6. **Scrolling default today.** v8.6 shipped vertical-by-default for new installs and retroactively changed existing users (called a bug, fixed in 8.6.1) [S19]. Whether 8.1.x still defaults to vertical for new installs is not restated.
7. **Free-tier specifics.** App Store text says 3 notebooks + core pens/paper + 100 AI credits/month [S5]; the 2023 launch article says 30 AI trials [S53]; Paperlike lists iOS subscription prices ($7.99/wk, $9.99/mo, $29.99/yr) [S68] while the Play listing says "one-time purchase" [S69]. Pricing model is genuinely inconsistent across sources/platforms.
8. **WebDAV on iOS.** WebDAV is in the iOS App Store feature list [S5], but the only how-to is filed in the *Android* NS3 category and shows a different settings path ("Sync & Backup" vs "Cloud & Backup") [S45][S46]. iOS menu naming unconfirmed.
10. **Evernote auto-publish in Noteshelf 3.** Documented for NS2 [S48] and implied by the auto-backup article's note [S44], but absent from the NS3 App Store feature list [S5]. Probably legacy-only.
11. **"Add Space to Your Page" mechanics** — only the App Store changelog line exists [S5]; no help article.
12. **Apple Watch app scope** (view-only vs capture) — article exists [S55] but I did not verify its body.
13. **Number of pen styles.** Official marketing says "4 pen styles + 2 highlighter styles" [S1]; this matches the review [S68], but NS2-era articles mention solid/dotted/dashed variants that may not exist in NS3.
14. **Whether NS3 has any true layer stack.** Official docs document only Bring to Front / Send to Back [S23]; I found no evidence of layers in any source. Treated as "no layers", but absence of evidence.
15. **Handwriting language count** — "65 languages" (App Store, 2026) vs "60" (NS3 launch post) [S5][S12].
16. **Whether notes can be merged** — Paperlike says notebooks and pages cannot be merged [S68]; no official statement either way.
