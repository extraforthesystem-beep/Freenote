# 05 — PDF import/export and page-rendering pipeline

Scope: `NoteApp/Import/*`, `Export/*`, `Notebook/PageBackground.swift`, `PDFLinkHandler.swift`, library covers, `Packages/InkKit` (`PDFImportConversion`, `VectorPDFExport`, `VectorPageRenderer`, `TemplateRenderer`). Read-only; line numbers are the working tree on 2026-11-13. Intent per `.memory/decisions/2026-11-12-pdf-vector-export-and-import.md`. Verified by code reading plus one runtime PDFKit probe (`/Rotate`, `bounds(for:)`) on a 612×792 page. Unproven claims are marked **UNVERIFIED**.

**Correction to the brief:** import loads no whole document per page — `PDFDocument(url:)` is lazy. Real costs: the file read whole into `Data`, the file reopened per render, uncapped bitmap area.

---

## 1. Findings

### Critical

**C1. Rotated PDF pages are imported at the wrong page size, so content is shrunk and letterboxed.**
`PDFImporter.swift:254-260` sizes the notebook page from `pdfPage.bounds(for: .mediaBox)`, which is *unrotated* (probe: `/Rotate 90` still reports 612×792). `PageElementRenderer.swift:151-162` draws with `getDrawingTransform(.mediaBox, …)`, which *does* apply `/Rotate` and aspect-fits 792×612 into 612×792 → 0.773 scale, ~90 pt white bands. Imported ink uses the same transform, so it stays aligned and hides the bug; the page shape is wrong in editor, thumbnails, covers and export (`VectorPDFExport.swift:43-45` reuses `page.width/height`).
**Impact:** phone-scan apps write `/Rotate 90`; a large share of imported PDFs comes in 23% undersized — the first thing a GoodNotes user notices.
**Fix:** page size from the rotated box (swap w/h for `rotation % 180 == 90`, keep origin), with a fixture. The existing `rotatedPage` test (`PDFImportConversionTests.swift:181`) only asserts centre→centre and passes with the bug.

**C2. Import has no size or page-count bound.**
`PDFImporter.swift:306-312` reads the whole PDF into `Data`; `:296-303` builds a `PDFDocument` over it; for encrypted or inked files `:270-283` copies *every* page into a fresh document (`PDFImportConversion.swift:305-309`) and serialises it (`:318`). A 300 MB/500-page scan peaks near 2–3× file size, on top of one notebook page per PDF page. `PDFPageSelection.all` (`PDFImporter.swift:43-44`) accepts 5,000 pages; progress bar appears only above 20 (`:79`).
**Impact:** jetsam kill mid-import; the cleanup (`:158-165`) at least avoids a half notebook.
**Fix:** size/page-count/longest-side precheck with a confirm sheet; read via `PDFDocument(url:)`; rewrite page-by-page into a `CGContext` writer under `autoreleasepool`.

### High

**H1. Every render reopens the asset; no shared document cache.**
`PageElementRenderer.swift:142-146` runs `PDFDocument(url:)` inside `drawPDFPage` — once per render, twice per page display (base + sharp, `PageBackground.swift:262-317`), and again for page images (`ContinuousPagesView.swift:649-656`), thumbnails (`PageThumbnailStrip.swift:182-190`), covers (`LibraryCovers.swift:53-77`), search indexing (`SearchIndex.swift:640`, per page), search marks (`PageMatchLocator.swift:55`), links (`PDFLinkHandler.swift:99`) and export. A 500-page notebook re-parses the same xref dozens of times, concurrently, unsynchronised.
**Impact:** scroll/page-turn latency on large assets; the repo's own note (`PDFLinkHandler.swift:16-18`) puts a 1,000-page open above a millisecond and only tolerates it via a cache.
**Fix:** process-wide LRU `PDFAssetCache` keyed by asset URL, bounded by count and bytes, invalidated on asset write. Fold `PDFLinkHandler.lastDocument` (`:19`, `:94-102`) into it.

**H2. Bitmaps are capped by zoom scale only — never by pixels or page points.**
`PageBackgroundCache.maximumScale = 4` (`PageBackground.swift:337`, `:347-351`); inactive pages quantised to 1…3 (`ContinuousPagesView.swift:304-305`); import accepts any box larger than 1 pt (`PDFImporter.swift:255`). Cost is accounted after allocation (`PageBackground.swift:395-398`). A 2000×2800 pt plan page at 4× is 8000×11200 px ≈ 358 MB for one page; three exceed all caches combined (128+128+64+48 MB, `MemoryPressure.swift:6-7`).
**Impact:** single-page OOM reachable simply by opening a file.
**Fix:** clamp pixel area (~16 MP) and page points (~20,000) at import; derive scale from the viewport, not page points × zoom.

**H3. No tiled rendering; vector PDF becomes one bitmap per page.**
No `CATiledLayer`/tile/async-layer draw anywhere (repo grep). Zoom reaches `fit * 8` (`ContinuousPagesView.swift:736`, `:850`) while the paper bucket stops at 4 (`PageBackground.swift:337`), so at high zoom PDF text is a 4 px/pt bitmap upsampled.
**Impact:** blurry text exactly where users zoom to read; ink is already vector-sharp via the sharp-ink ADR.
**Fix:** draw `pdfPage` elements per tile from `pageRef` at settled zoom — resolution-independent, cheap, and fixes H2 plus most of C1's visual damage. Bitmaps only for `.image`.

**H4. Import rewrites the manifest once per page → O(n²).**
`PDFImporter.swift:141-146` loops `store.savePage`; `LibraryStore.swift:365-373` decodes and re-encodes the manifest each call. 500 pages = 500 encodes of a 500-entry `pageOrder` plus 500 atomic writes.
**Impact:** minutes-long import that reads as a hang, with Cancel disabled (`PDFImportFlow.swift:59-65`).
**Fix:** `savePages([Page], in:)` — page files first, one manifest write (ordering already exists in the catch path).

### Medium

**M1. Rotation-blind hit tests.** `PDFLinkHandler.swift:44-63` and `PageMatchLocator.swift:60-79` reverse the aspect-fit from unrotated `bounds` with a y-flip only, so on `/Rotate 90` pages taps transpose and highlights sit a quarter-turn off. Same root as C1; fix once.

**M2. `CropBox` never used.** Zero `cropBox` references: sizing (`PDFImporter.swift:254`), drawing (`PageElementRenderer.swift:152-159`), links (`:44`), search (`:60`). Print-workflow PDFs show bleed and trim marks, framed differently from Preview. Use `cropBox`, falling back to `mediaBox`.

**M3. Background cache keys churn on every element edit.** `baseKey` hashes each element's `updatedAt` (`PageBackground.swift:400-405`), bumped on every change (`NotebookSession.swift:660,677,686,782`). Each drag settle adds a 31 MB (4×) page bitmap while the old one is still cost-accounted, and re-rasterises the PDF (~77 ms at 2×, `PageBackground.swift:361-363`). Fix: paper+PDF keyed by page identity; elements on their own layer.

**M4. Each insert range stores another full copy of the PDF.** `PDFImportConversion.data` copies all pages (`:305-309`) and `addAsset` dedupes by SHA-256 of bytes (`LibraryStore.swift:461-470`), so 1–50 then 51–100 of one inked PDF stores two full files. Fix: one canonical asset, converted-ink state per page.

**M5. Export buffers the whole output, twice when editable.** `PDFExport.swift:232-234` returns `Data(contentsOf:)`; the editable path reopens the file, annotates every page, then `dataRepresentation()` (`:236-270`), wrapped again in `PDFExportDocument(data:)` (`:15-31`). For 500 inked pages: full PDF + object graph + second full PDF live together. Fix: hand the temp file URL to the exporter; annotate into a destination writer.

**M6. Export drops interactive/document-level content.** `VectorPDFWriter` writes media box + outline only (`VectorPDFExport.swift:36-78`); links and widgets are in neither the draw path (`PageElementRenderer.swift:151-166`) nor the annotation whitelist (`:179-185`), so imported forms become inert pixels and links vanish (links are intended; forms are not). Rewritten imports lose the original outline; import compensates by reading it first (`PDFImporter.swift:265-267`). **UNVERIFIED:** link annots cannot pass the writer (no fixture built).

### Low

- **L1.** Converted ink flattens to one median width with `force: 1` and duplicates dots (`PDFImportConversion.swift:211-249`).
- **L2.** Three opens per import (`PDFImporter.swift:87-101`, `:245`); `PDFLinkHandler.lastDocument` pins one document for process life (`:19`).
- **L3.** No per-page `autoreleasepool` in scan/export loops (`PDFImporter.swift:252-262`, `PDFExport.swift:201-228`). **UNVERIFIED** (no Instruments run).
- **L4.** Dark Paper renders three full-page bitmaps (`PageBackground.swift:81-106`): 93 MB transient at 4×.
- **L5.** "Background to all pages" loops load+save per page (`NotebookSession.swift:430-439`), same O(n²) churn as H4.

**Do not regress:** asset dedupe (`LibraryStore.swift:461-470`), password never stored (`PDFImporter.swift:270-283`), real text in vector export (`VectorPDFExportTests.swift:109-127`), light-forced export ink (`PageRenderer.swift:96-104`), memory purge (`MemoryPressure.swift:29-35`).

---

## 2. Pipeline architecture limits

1. **The page is the only unit of work.** Import, render, cache, export and search all work at whole-page resolution and identity, so every cost scales with page size and count.
2. **PDF is treated as an image format.** The pipeline's only interface is "rasterise this page" (`PageElementRenderer.drawPDFPage` inside `PageRenderer.image`); resolution independence is discarded on import and recovered only on export. Hence H2, H3.
3. **No document-level object.** Nothing owns the asset; each consumer opens the file itself, so caches, lifetimes and errors are per-consumer (H1).
4. **Geometry duplicated four times, rotation-aware once.** Importer, renderer, links, search each recompute box/rotation/fit; three get `/Rotate` wrong (C1, M1), all four ignore `CropBox` (M2).
5. **Persistence is O(manifest) per page.** `savePage` reloads and rewrites the manifest (`LibraryStore.swift:365-373`); bulk paths inherit it (H4, L5).
6. **Import is a whole-buffer rewrite, not a stream** (C2, M4).

---

## 3. Prioritised foundation changes

**P0 — correctness (days, ship-blocking):**
1. **One `PDFPageGeometry`** (crop box + `/Rotate` + aspect fit → page rect) shared by importer, renderer, link handler, search. Fixes C1, M1, M2 and deletes three hand-rolled copies. Fixtures: `/Rotate 90` page, crop box < media box, asserted through `makePage`.
2. **Batched `savePages`** used by `importPDF`/`insertPages`. Fixes H4, L5.
3. **Import precheck**: file size, page count, longest side, hard page-point clamp. Bounds C2 and H2's worst case.

**P1 — the render foundation:**
4. **`PDFAssetCache`**: LRU of open documents keyed by asset URL, bounded by count and bytes, invalidated on write; every consumer routes through it (H1, L2). Prerequisite for 5.
5. **Tiled PDF layer** for `pdfPage` elements — draw `CGPDFPage` per tile at settled zoom, not one page bitmap. Removes the memory ceiling (H2), makes deep zoom sharp (H3), frees the paper cache to hold templates. Highest-leverage change; design it as the retirement path for `PageBackgroundCache`/`PageImageCache`.
6. **Split paper keys from element keys** (M3) so element edits never re-rasterise the PDF page.

**P2 — storage and export hygiene:**
7. **One canonical asset per source PDF**, converted-ink state per page instead of file rewrites (M4).
8. **Stream export** — file URL to the exporter, annotations into a destination writer (M5); carry link annotations or state the loss in the export UI (M6).
9. **`autoreleasepool` per page** in scan/render/export loops (L3), plus a 500-page render benchmark in `RenderBenchmarks.swift` so these numbers stop drifting.

*Sequencing:* 1–3 fix user-visible lies. Do 4–6 before any PDF-rendering feature (annotation editing, split view), or each re-implements the broken geometry.
