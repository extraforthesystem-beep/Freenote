# Handwriting recognition, ink search and on-device AI

Scope: what the recognisers can do, what search over ink can be, and which AI features are worth building on iPad-only, on-device constraints. Codebase state checked first (see "What this means").

## Key findings

**1. NOTEAPP is already on the state-of-the-art on-device recogniser, and it is a system framework, not a research problem.**
`PKStrokeRecognizer` (iOS/iPadOS/macOS 27) is an `actor` that runs Apple's handwriting engine offline, on every device iOS 27 supports, in 29 languages. It exposes four things: `recognizedText(strokeIDs:)` (one best reading, optionally per stroke subset), `indexableContent` (a string that "may contain multiple concatenated candidate matches" for indexing), `search(_:fullWordsOnly:caseMatchingOnly:)` returning bounds, and `recognitionVersion` to invalidate stale results. — **Strong** (primary API docs + WWDC26 session) [10][11][12].

**2. It is scale-sensitive: Apple's docs say recognition "works best when handwriting is scaled as if drawn on standard US Letter or A4 paper in points".**
This is a real trap for an infinite-canvas whiteboard and for zoom windows: strokes must be normalised to page-point scale before recognition, or accuracy quietly degrades. — **Strong** (docs) [10][11].

**3. `indexableContent` is not a transcript.** It concatenates alternative readings ("101" / "lol"), runs at low priority, and can return `nil` mid-writing; `recognizedText` gives the single best answer. — **Strong** (docs) [10][11]; corroborated by an app developer's field notes — **Weak** (blog) [26].

**4. Recurrent + Bézier input was the jump that made online HWR production-grade; transformers are now marginally ahead.**
Carbune et al. replaced Google's segment-and-decode stack with an LSTM + Bézier-curve input encoding: 20–40% relative error reduction across ~100 languages, up to 10× faster recognition, SOTA on IAM-OnDB. — **Strong** (peer-reviewed, IJDAR) [1]. A 2025 transformer fusing online trajectory and rendered image reports SOTA on IAM-OnDB and VNOn-DB, "exceeding previous bests by up to 1%", i.e. the architecture race is now worth ~1 point. — **Medium-strong** (preprint) [2].

**5. Small models are enough for constrained tasks.** On MathWriting, a 35M-parameter CTC transformer reading raw ink reaches 4.41% / 5.56% CER (valid/test), beating Google Cloud OCR on rendered images (6.50 / 7.17). — **Strong** (KDD'25, table read directly) [3]. Implication: an on-device Core ML model for a narrow domain (math, symbols) is feasible; a general recogniser is not worth building.

**6. Handwritten maths is not solved, and online beats offline by a wide margin.** CROHME 2023 (7th edition) ran online, offline and bimodal tasks on 3,905 newly collected equations. Reported best online expression accuracy in the low 80s vs low 70s offline. — **Medium** (paper abstract confirmed; the specific percentages come from a contestant's write-up, see Unverified) [4].

**7. Search over ink tolerates recognition error, which is why "search, don't transcribe" is the right product bet.**
A pen-input user test measured 1.6% character / 8.8% word error at 10 wpm and still retrieved target documents reliably from the recognised text. — **Medium** (industry user test with numbers, not peer-reviewed) [25].

**8. In-situ ink search is the canonical UX, and it is about not breaking writing flow.**
InkSeine let users lasso existing ink to launch a search, persisted queries as first-class "breadcrumb" objects inside the notes, and treated search as subordinate to inking. Its contribution is design + formative evaluation, not a benchmark. — **Medium** (CHI, qualitative) [5].

**9. Recognition-free word spotting exists, but it is a historical-document technique.**
The word-spotting literature splits query-by-example from query-by-string and exists precisely to avoid full transcription of scanned archives. — **Strong as a survey** (Pattern Recognition) [6]. For live ink, Apple's `search()` already gives recognition-based spotting with bounds, so the recognition-free machinery buys little.

**10. Abstractive summarisation hallucinates at rates that make ungrounded output unusable as a "summary of my notes".**
Human annotation of 2,500 XSum article-summary pairs: 73.1–79.3% of model summaries contained at least one hallucinated span (best model 73.1%, i.e. 26.9% faithful); >90% of extrinsic hallucinations were erroneous; entailment-based measures tracked faithfulness best (ρ≈0.43) while ROUGE/BERTScore barely correlated. — **Strong** (ACL, large human eval) [7].

**11. Long context does not rescue this.** Accuracy is highest when the needed fact is at the start or end of the context and degrades in the middle, even for long-context models — so "just pass the whole notebook" is worse than retrieving the right pages. — **Strong** (TACL) [8].

**12. Lexical search remains a strong baseline; dense retrieval alone often loses zero-shot.**
Across 18 datasets, BM25 was a robust baseline; dense and sparse retrievers "often underperform" it out of domain, while rerankers win at high cost. — **Strong** (NeurIPS D&B) [9]. Semantic search should be additive, not a replacement.

**13. Apple ships usable on-device embeddings, with caveats.** `NLEmbedding.sentenceEmbedding(for:)` since iOS 14, `wordEmbedding` since iOS 13, custom embeddings via CreateML; not every language has one (returns `nil`), and a shared instance must not be used from multiple threads concurrently. — **Strong** (docs) [14].

**14. Apple's on-device LLM is deliberately a small, task-shaped model.** 3B parameters at 2 bits, "optimized for specific tasks like summarization, extraction, and classification, and not suitable for world knowledge or advanced reasoning"; guided generation (`@Generable`) constrains output to a Swift type; context window is fixed and schemas/tools consume tokens; Apple explicitly tells developers to fact-check outputs and to break tasks into small pieces. — **Strong** (WWDC25 + technote) [15][16][17][18].

**15. On-device processing alone does not buy trust.** A CHI 2025 study of on-device vishing detection found users still felt surveilled — the paper's title is a participant quote: "I know my data doesn't leave my phone, but still feel like being wiretapped". Transparency about what is processed matters as much as where. — **Medium** (CHI extended abstract, qualitative) [20]. Local-first principles (offline, ownership, security/privacy by default) frame the same argument. — **Medium** (essay, not a study) [19]. Apple's Private Cloud Compute adds verifiable transparency for server models, but using it means a network round-trip and an entitlement — the wrong trade for personal notes. — **Strong** (Apple security docs) [21].

**16. Diagrams and tables are research-grade, not API-grade.** Flowchart recognition is benchmarked on FC-A/FC-B/FA; DrawnNet improved recognition rate by 2.4/2.3/1.7 points over prior SOTA, i.e. incremental gains on hard benchmarks. — **Medium** [22]. Separating text strokes from shape strokes in a diagram is itself a classifier (~92% correct with an entropy-rate feature). — **Medium** (IJCAI) [23]. Handwritten table work is explicitly thin: "much less work has targeted the detection and recognition of handwritten tables". — **Medium** (TPAMI note) [24].

**17. Vision OCR is the right tool for scanned PDFs, not for ink.** `VNRecognizeTextRequest` runs entirely on device, has fast/accurate paths, per-language models and `customWords`; it reads text *in images*. — **Strong** (docs) [13].

**18. Scribble already gives handwriting→text inside any text field, and must be suppressed around canvases.** `UIScribbleInteraction` / `UIIndirectScribbleInteraction` (iOS 14+) let an app opt fields in or out; Apple warns that text fields near a drawing canvas can steal Pencil events. — **Strong** (docs) [19b].

## What this means for NOTEAPP

- **Do not build a recogniser.** `Packages/SearchKit/Sources/SearchKit/HandwritingRecognizer.swift` already wraps `PKStrokeRecognizer` behind a `HandwritingRecognizing` protocol with `recognitionVersion` invalidation, uses `indexableContent` for the index and `search()` for ink bounds. That is the correct architecture and matches Apple's own guidance. The remaining work is *product surface*, not models.
- **The AI panel is fed the wrong string.** `HandwritingSearch.noteText(for:)` (line 197) calls `recognizer.text(for:)`, which returns `indexableContent` — the multi-candidate index string. Summaries and Q&A are therefore given "101\nlol"-style alternatives as if they were prose. A one-method fix (`recognizedText`) improves answer quality with no new dependency.
- **AI answers are ungrounded in the UI.** `AIKit` computes citations (`CitationExtractor`, `AIResponse.citations`), but `NoteAIPanel` only displays `response.text`; citations are read solely to detect the "not found" sentinel. Given finding 10, citations should be visible and tappable.
- **Everything is page-scoped.** `AISummaryScope` has `.notebook`, but the panel only ever sends `.page` text, and `AIService` caps input at 12,000 UTF-16 units. Notebook-level answers need retrieval first (finding 11), not a bigger prompt.
- **Absent features, confirmed by grep:** no lasso→text, no maths recognition, no diagram/table recognition, no embeddings/`NaturalLanguage` use anywhere, no auto-title, no OCR fallback for scanned PDFs (`SearchIndex.pdfText` returns "" when `pdfPage.string` is nil).
- **Existing strengths to keep:** tolerant prefix matching for misrecognised words, ink-bound marks for hits, `PageTextSource` grouping, and a deterministic offline AI fallback (`DeterministicProvider`) that keeps the panel honest when Apple Intelligence is off.

## Feature ideas

| # | Idea | Evidence | NEW/EXTENDS/DONE | Where in code | Effort | Impact |
|---|---|---|---|---|---|---|
| 1 | Feed AI the single best transcript, not `indexableContent`; keep candidates for the search index only | [10][11][26] | EXTENDS | `SearchKit/HandwritingRecognizer.swift` (add `recognizedText(for:)`), `NoteApp/Search/HandwritingSearch.swift:197` | S | 5 |
| 2 | Show AI citations and tap-to-mark them on the page (highlight the quoted ink/PDF/text) | [7][8] | EXTENDS | `NoteApp/AI/NoteAIPanel.swift` (`response.citations` unused), reuse `HandwritingSearch.pageMarks` + `PageMatchLocator` | M | 5 |
| 3 | Lasso → "Copy as Text" / "Convert to Text box" using `recognizedText(strokeIDs:)` | [10][11] | NEW | `NoteApp/Notebook/EditorToolState.swift` (`.lasso`), `InkKit` selection → new command | S | 4 |
| 4 | Scanned-PDF OCR fallback: run Vision `RecognizeTextRequest` when `pdfPage.string` is empty, store as a `.pdf` segment | [13] | EXTENDS | `SearchKit/SearchIndex.swift:632` (`pdfText`) | M | 4 |
| 5 | Hybrid search: keep substring search, add sentence-embedding re-rank over page text, with a "similar meaning" toggle | [9][14] | NEW | new `SearchKit/SemanticIndex.swift`, `SearchIndex.search` | M | 4 |
| 6 | Grounded notebook-scope Q&A: retrieve top-k pages (lexical + embedding) then ask with only those pages, citing page numbers | [8][9][15] | EXTENDS | `AIKit/AIModels.swift` (`.notebook`), `NoteApp/AI/NoteAIPanel.swift` | M | 4 |
| 7 | Guided generation for flashcards and tags (`@Generable` structs) instead of "Q:/A:" string parsing | [15][16][17][18] | EXTENDS | `AIKit/FoundationModelsProvider.swift:97` (`makePrompt`), `Internal/FlashcardParser.swift` | M | 4 |
| 8 | Auto-title a new notebook from its first page's recognised text, one-tap accept | [15][16] | NEW | `NoteApp/Library/LibraryView.swift` (title edit), `HandwritingSearch.noteText` | S | 3 |
| 9 | Auto-tag suggestions from page text, applied through existing notebook tags | [15][17] + YAKE [27] | EXTENDS | `AppModel.setTags`, `LibraryStore.setTags`, `NoteApp/Library/LibraryView.swift:147` | M | 3 |
| 10 | "Find similar pages" from the current page's text | [9][14] | NEW | `NoteApp/Search/NotebookSearchPanel.swift` | S | 3 |
| 11 | Publish `indexableContent` to Core Spotlight so notes are findable from system search | [11] | NEW | `SearchKit/SearchIndex` after `update(...)` | S | 3 |
| 12 | Page "draft mode": transcribe a whole page to a text document in one pass, with per-block confidence ordering | [1][2][25] | NEW | `TextDocKit` + `HandwritingRecognizer` | M | 3 |
| 13 | Maths block: recognise a lassoed formula to LaTeX (Core ML model; no Apple API) | [3][4] | NEW | new `InkKit`/`MathKit` recogniser, lasso command | L | 3 |
| 14 | Re-run recognition when `recognitionVersion` changes and surface "N pages re-read" | [10][26] | DONE (version stored) / EXTENDS (UI nudge) | `SearchIndex.isFresh`, `HandwritingSearch.indexAll` | S | 2 |
| 15 | Flowchart/diagram recognition on boards (nodes, arrows → structured diagram) | [22][23] | NEW | `Packages/BoardKit` | L | 2 |
| 16 | Handwritten table → structured grid | [24] | NEW | `Packages/BoardKit` / `InkKit` | L | 2 |
| 17 | Make text elements accept Scribble; suppress it near the ink canvas | [19b] | VERIFY (SwiftUI `TextField` gets it free) | `NoteApp/Notebook/PageElementViews.swift` | S | 2 |
| 18 | Per-feature privacy line ("runs on this iPad; no network") + a build-time assertion that no AI code path opens a socket | [19][20][21] | EXTENDS | `NoteApp/AI/NoteAIPanel.swift:95` (copy already claims this) | S | 2 |

## Top 3 to build first

**1. Fix the AI input string, then show citations (rows 1 + 2).** These are the only two changes that address a real defect rather than add surface: the panel is currently summarising a concatenation of alternative readings, and it throws away the citations `AIKit` already computes. The evidence that abstractive output over personal notes is unfaithful in ~73% of cases [7] means an ungrounded summary is worse than no summary; a summary whose sentences you can tap back to the ink is defensible. Both are small, local edits in `HandwritingSearch` and `NoteAIPanel`, and they make every later AI feature safer.

**2. Lasso → text (row 3).** The single most-requested handwriting capability in every competitor, and Apple now hands it over as `recognizedText(strokeIDs:)` [10][11]. NOTEAPP already has a `.lasso` tool and stroke identity, so this is a selection-plus-one-call feature with no model, no index rebuild and no new failure mode. It also unlocks cheap copy-out to other apps, which search alone does not.

**3. Hybrid semantic search, lexical first (row 5, plus row 6 later).** BEIR is the caution: dense retrieval alone often loses to BM25 out of domain [9], so the existing tolerant substring search must stay the primary path and embeddings should only re-rank or answer "find similar". Because `NLEmbedding` is on-device, free, and already in the OS [14], this is the cheapest route to the "search by meaning" behaviour users expect from AI-branded apps — and it is the retrieval step that notebook-scope Q&A (row 6) needs before a 3B on-device model can answer anything beyond one page [8][15].

## Sources

1. Carbune, V., Gonnet, P., Deselaers, T., Rowley, H. A., Daryin, A., Calvo, M., Wang, L.-L., Keysers, D., Feuz, S., & Gervais, P. (2020). Fast multi-language LSTM-based online handwriting recognition. *IJDAR* 23, 89–102. https://doi.org/10.1007/s10032-020-00350-4
2. Lodh, A., Chakraborty, R., Palaiahnakote, S., & Pal, U. (2025). A Transformer Based Handwriting Recognition System Jointly Using Online and Offline Features. arXiv:2506.20255. https://arxiv.org/abs/2506.20255
3. Gervais, P., Fadeeva, A., & Maksai, A. (2025). MathWriting: A Dataset For Handwritten Mathematical Expression Recognition. *KDD '25*, 5459–5469. https://doi.org/10.1145/3711896.3737436
4. Xie, Y., Mouchère, H., Simistira Liwicki, F., Rakesh, S., Saini, R., Nakagawa, M., Nguyen, C. T., & Truong, T.-N. (2023). ICDAR 2023 CROHME: Competition on Recognition of Handwritten Mathematical Expressions. *LNCS* 14188, 553–565. https://doi.org/10.1007/978-3-031-41679-8_33
5. Hinckley, K., Zhao, S., Sarin, R., Baudisch, P., Cutrell, E., Shilman, M., & Tan, D. (2007). InkSeine: In Situ search for active note taking. *CHI '07*, 251–260. https://doi.org/10.1145/1240624.1240666
6. Giotis, A. P., Sfikas, G., Gatos, B., & Nikou, C. (2017). A survey of document image word spotting techniques. *Pattern Recognition*. https://www.cs.uoi.gr/~cnikou/Publications/J36-Web-Giotis-Sfikas-Gatos-Nikou-Pattern-Recognition-2017.pdf
7. Maynez, J., Narayan, S., Bohnet, B., & McDonald, R. (2020). On Faithfulness and Factuality in Abstractive Summarization. *ACL 2020*, 1906–1919. https://doi.org/10.18653/v1/2020.acl-main.173
8. Liu, N. F., Lin, K., Hewitt, J., Paranjape, A., Bevilacqua, M., Petroni, F., & Liang, P. (2024). Lost in the Middle: How Language Models Use Long Contexts. *TACL* 12, 157–173. https://doi.org/10.1162/tacl_a_00638
9. Thakur, N., Reimers, N., Rücklé, A., Srivastava, A., & Gurevych, I. (2021). BEIR: A Heterogenous Benchmark for Zero-shot Evaluation of Information Retrieval Models. *NeurIPS Datasets & Benchmarks*. https://arxiv.org/abs/2104.08663
10. Apple. *PKStrokeRecognizer* (PencilKit). https://developer.apple.com/documentation/pencilkit/pkstrokerecognizer
11. Apple. *Recognizing handwriting and converting it to text* (PencilKit). https://developer.apple.com/documentation/PencilKit/recognizing-handwriting-and-converting-to-text
12. Apple. *Read between the strokes with PencilKit* — WWDC26 session 203. https://developer.apple.com/videos/play/wwdc2026/203
13. Apple. *Recognizing Text in Images* (Vision). https://developer.apple.com/documentation/vision/recognizing-text-in-images
14. Apple. *NLEmbedding* (Natural Language). https://developer.apple.com/documentation/naturallanguage/nlembedding
15. Apple. *Foundation Models*. https://developer.apple.com/documentation/foundationmodels
16. Apple. *Meet the Foundation Models framework* — WWDC25 session 286. https://developer.apple.com/videos/play/wwdc2025/286
17. Apple. *Explore prompt design & safety for on-device foundation models* — WWDC25 session 248. https://developer.apple.com/videos/play/wwdc2025/248
18. Apple. *TN3193: Managing the on-device foundation model's context window*. https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window
19. Kleppmann, M. et al. (2019). Local-first software: You own your data, in spite of the cloud. *Onward! 2019*. https://martin.kleppmann.com/papers/local-first.pdf
19b. Apple. *UIScribbleInteraction* (UIKit). https://developer.apple.com/documentation/uikit/uiscribbleinteraction
20. "I know my data doesn't leave my phone, but still feel like being wiretapped": Understanding (Mis)Perceptions of On-Device AI Vishing Detection Apps. *CHI EA '25*. https://doi.org/10.1145/3706599.3719784 (author list truncated in the page I opened)
21. Apple Security Research. *Private Cloud Compute: A new frontier for AI privacy in the cloud* (2024). https://security.apple.com/blog/private-cloud-compute/
22. Fang, J., Feng, Z., & Cai, B. (2022). DrawnNet: Offline Hand-Drawn Diagram Recognition Based on Keypoint Prediction of Aggregating Geometric Characteristics. *Entropy* 24(3), 425. https://doi.org/10.3390/e24030425
23. Bhat, A., & Hammond, T. (2009). Using Entropy to Distinguish Shape Versus Text in Hand-Drawn Diagrams. *IJCAI 2009*, 1395–1399. https://www.ijcai.org/proceedings/2009/234
24. Lin, Z., He, J., Zhong, Z., Wang, R., & Shum, H.-Y. (2006). Table Detection in Online Ink Notes. *IEEE TPAMI* 28(8), 1341–1346. https://doi.org/10.1109/TPAMI.2006.173
25. Nielsen Norman Group. *Information Retrieval of Imperfectly Recognized Handwriting*. https://www.nngroup.com/articles/handwriting-retrieval/ (author and publication date not shown on the page)
26. "Four lessons from building a handwriting notes app for iPad" (2026). https://dev.to/nsr23588/four-lessons-from-building-a-handwriting-notes-app-for-ipad-1bao — practitioner blog; used only for field behaviour of `indexableContent`.
27. Campos, R., Mangaravite, V., Pasquali, A., Jorge, A., Nunes, C., & Jatowt, A. (2020). YAKE! Keyword extraction from single documents using multiple local features. *Information Sciences* 509, 257–289. https://doi.org/10.1016/j.ins.2019.09.013

## Unverified

- **CROHME 2023 headline accuracies.** A participant write-up states best online 82.34%, offline 70.81%, bimodal 84.12% on the 2023 test set, and 88.24% best on the 2019 test set. I could not open the ICDAR paper itself (Springer and HAL both blocked automated fetches); only the abstract was visible. Treat the exact percentages as unconfirmed.
- **"Handwritten tables are an open problem"** — I saw this stated in TableVLM (ACL 2023, https://aclanthology.org/2023.acl-long.137) but did not open the paper or capture its author list, so I cite [24] instead for the weaker, verified claim that little work targets handwritten tables.
- **Scribble behaviour inside SwiftUI `TextField` on the note page.** Docs describe UIKit `UITextInput` views; whether NOTEAPP's text elements (SwiftUI, `PageElementViews.swift`) already accept Scribble unmodified was not tested on device.
- **Any latency or accuracy figure for `PKStrokeRecognizer` on an A13-class iPad (9th gen).** Apple gives no numbers; the WWDC claim is only "fast". Needs a device measurement before committing to per-stroke or live recognition.
- **Whether `indexableContent`'s concatenated candidates measurably hurt answer quality** is inferred from the API contract, not measured. A quick A/B (both strings through the same prompt) would settle it.
- **Fadeeva et al. (2024), "Representing Online Handwriting for Recognition in Large Vision-Language Models"** — seen only as a citation inside [3]; not opened, so no claim is made from it.
