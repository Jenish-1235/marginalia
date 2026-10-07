# Marginalia — a reading, annotating & learning app for iPad

> One place for books, papers and blogs. Read beautifully, mark up with Apple Pencil
> as naturally as paper, and turn what you read into knowledge you keep.

Target hardware: iPad (A16, 11th gen) + Apple Pencil (USB-C / 1st gen), MacBook Pro M5 Pro.
Personal app, sideloaded via Xcode. Native Swift / SwiftUI / UIKit where it matters.

---

## 1. Principles

1. **Pencil writes, finger navigates.** No mode switching to scroll vs draw. The Pencil is always
   an annotation instrument; fingers scroll, zoom, select text and open menus.
2. **Every mark is knowledge.** Highlights, ink and notes are not decorations on a file — they are
   indexed, searchable, linkable records that flow into notes and review.
3. **Originals are sacred.** Source PDFs are never modified. Annotations live in the database and
   are flattened into a copy only on export. No corrupted books, unlimited undo.
4. **Capture must be one tap.** Safari → Share → done. Paste an arXiv link → the paper appears.
5. **Fast and offline.** Everything works on a plane. AI and sync are additive, never required.
6. **Monochrome.** The entire UI is matte black / charcoal surfaces with white ink — no hues.
   Pages stay paper-white (or inverted in night mode); meaning is carried by shape and weight,
   never by colour.

## 2. Feature pillars

### 2.1 Library
- Import: Files picker, drag & drop (Split View / Stage Manager), "Open in…", share sheet.
- Kinds: **Book**, **Paper**, **Article** (captured web page). Auto-detected, editable.
- Metadata: title, authors, year, source URL, DOI/arXiv id, page count, progress, last opened.
- Papers: detect DOI / arXiv id from first pages → fetch clean metadata (Crossref / arXiv API).
- Organisation: collections (manual), tags, smart shelves (*Reading now*, *Unread*, *Recently added*,
  *Finished*, *Has notes*).
- Grid (covers) and list views; sort by recent / title / added / progress.

### 2.2 Capture (web → PDF)
- In-app browser (persistent cookies → log into Medium/Substack once) with a **Save** button.
- **Safari Share Extension** "Save to Marginalia": enqueues URL into the shared App Group; the main
  app renders it (extensions have tight memory limits — rendering there crashes).
- Pipeline:
  1. URL is already a PDF (or arXiv `abs/` → `pdf/`) → download directly.
  2. Load in off-screen `WKWebView`, de-lazy images, wait for network idle + MathJax/KaTeX.
  3. Run **Mozilla Readability.js** → article title, byline, site, clean content.
  4. Render into our typographic template (serif body, wrapped code, figures, captions).
  5. Paginate via `UIPrintPageRenderer` at an **iPad-shaped page** (aspect of the 11" screen) so
     articles read like book pages. Fallback: print the page as-is if Readability fails.
  6. Store source URL, byline, site, date and the clean HTML (re-render later if template changes).

### 2.3 Reader
- PDFKit `PDFView`: vertical continuous scroll, single page or two-up (landscape).
- Resume exactly where you left off (page + scroll offset), reading progress per doc.
- Outline (TOC), page thumbnails strip, in-document search with result list.
- **Reference peek**: tapping an internal link (citation `[12]`, `Fig. 3`, `Eq. 4`) shows a floating
  preview of the destination instead of jumping away. Long-press to jump. Huge for papers.
- Back/forward history for jumps.
- Appearance: paper (white pages on matte black) / night (inverted pages, images kept natural).
- Multi-window: two documents side by side, or document + its notebook.
- Focus mode: hide all chrome.

### 2.4 Annotation (the core experience)

**Pencil tools** (floating, compact, draggable toolbar; remembers last tool per document):

| Tool | Behaviour |
|---|---|
| **Smart highlighter** | Stroke over text → snaps into a real *text highlight* (selectable, searchable, exported to notes). Stroke over a figure/whitespace → stays a translucent ink stroke. |
| Pen | Pressure-independent fine pen (USB-C Pencil has no pressure), 3 widths, graphite / black ink. |
| Smart underline | Like the highlighter but produces a text underline. |
| Eraser | Stroke eraser for ink; tapping a text highlight with the eraser deletes it. |
| Lasso | Select ink to move, recolour, delete, or **convert handwriting to a text note**. |

**Finger / text selection menu:** Highlight · Underline · Strikethrough · Bracket · Add note ·
Copy · **Explain** (AI) · **Make flashcard** · Search in document.

**Notes on the page:**
- Anchored notes: tap a highlight → attach a typed note; a small marker appears in the margin.
- Free notes: tap anywhere with the note tool → sticky note (typed or handwritten).
- **Margin space**: per-page "expand margin" that grows a writable canvas beside the page.
- **Insert blank page** (plain / lined / grid) after any page for derivations and diagrams.

**Ergonomics:** two-finger tap = undo, three-finger tap = redo, Pencil double-tap (1st gen) /
toolbar toggles eraser, palm rejection, ink rendered on a per-page PencilKit canvas so zooming stays
crisp.

### 2.5 Notebook & learning
- **Per-document notebook** shown side-by-side with the PDF: every highlight appears automatically
  (with page, colour, your note). Free-form markdown notes between them. Tap any quote → jump to it.
- **Mark styles have meaning** (monochrome, configurable): graphite highlight = key idea,
  underline = definition/detail, margin bracket = important passage, `?` marker = question /
  confusion, `→` marker = to look up. Notebook filters by style; `?` items become an
  "open questions" list.
- **Flashcards + spaced repetition** (FSRS scheduler): make a card from any highlight (cloze) or
  write Q/A. Daily review queue; each card links back to its page.
- **Daily resurfacing**: a short feed of past highlights to keep ideas alive (Readwise-style).
- **AI study companion** (Claude API, your own key in Keychain — the A16 iPad doesn't support Apple
  Intelligence, so on-device models aren't an option):
  - Explain selection (with surrounding page context), define term, explain equation.
  - Summarise page / section / whole document into the notebook.
  - Ask questions about the document ("chat with this paper"), answers cite pages.
  - Generate flashcards from a section or from your highlights.
- **Global search** across full text, highlights, notes and cards.
- **Export**: annotated PDF (flattened copy), notebook as Markdown (Obsidian-friendly).

### 2.6 Sync (later)
- Files in iCloud Drive container, metadata + annotations via CloudKit (`CKSyncEngine`).
- Same app runs on the M5 Mac (iPad app on Apple Silicon / Catalyst) — read & review on the Mac.
- Requires the paid Apple Developer Program (also makes sideloaded installs last 1 year, not 7 days).

## 3. Architecture

```
Marginalia (iPad app, SwiftUI shell + UIKit reader)
├─ App/        app entry, routing, environment, settings
├─ Store/      GRDB database (SQLite + FTS5), records, migrations, FileStore (PDFs, thumbnails)
├─ Library/    library UI, import pipeline, metadata extraction, indexing
├─ Reader/     PDFView host, tool state, Pencil overlay, smart highlighter, menus, reference peek
├─ Notebook/   per-document notes, highlight list, markdown editor
├─ Learning/   flashcards, FSRS scheduler, review UI, resurfacing
├─ Capture/    web capture (WKWebView + Readability.js), browser, capture queue
├─ AI/         Claude client, prompts, key storage
└─ ShareExtension/  enqueues URLs/PDFs into the App Group
```

Key technical choices:
- **GRDB** over SwiftData: real SQLite, FTS5 full-text search, explicit migrations, observable
  queries, and works with `CKSyncEngine` later.
- **PDFKit + `PDFPageOverlayViewProvider`** gives one `PKCanvasView` per page that scrolls and zooms
  with the page — Apple's sanctioned PDFKit × PencilKit integration.
- **Smart highlighter**: on stroke end, take the stroke's start/end points in page space, build a
  `PDFSelection` between them, and accept it as a text highlight if the stroke is line-like and the
  selection's line rects cover most of the stroke. Otherwise keep the ink.
- Annotations rendered as non-persisted `PDFAnnotation`s on load (text markup) + `PKDrawing` per
  page (ink). Export flattens both into a copy.
- Text extraction + indexing runs in background tasks; UI never blocks on large books.

### Data model

```
document(id, kind, title, authors, year, sourceURL, doi, arxivID, fileName, pageCount,
         addedAt, openedAt, lastPage, progress, status, coverColor)
collection(id, name, sortIndex)            document_collection(documentID, collectionID)
tag(id, name)                              document_tag(documentID, tagID)
highlight(id, documentID, page, style, rects(json), text, note, createdAt, updatedAt)
ink(documentID, page, drawing(blob), updatedAt)
note(id, documentID, page?, anchorX?, anchorY?, body, createdAt, updatedAt)
card(id, documentID?, highlightID?, front, back, fsrs state..., due)
review_log(id, cardID, rating, reviewedAt)
page_text FTS5(documentID, page, text)     annotation_search FTS5(kind, refID, text)
capture_queue(id, url, status, error, createdAt)   (App Group)
```

## 4. Milestones

| # | Milestone | Outcome |
|---|---|---|
| M1 | Foundation | Project, database, import, library grid, PDF reader with resume. **Daily usable.** |
| M2 | Annotation core | Text highlights/underline/strike + notes via selection menu; Pencil ink overlay; tool palette; undo. |
| M3 | Smart Pencil | Smart highlighter/underline, lasso, eraser on highlights, blank pages, margin canvas. |
| M4 | Notebook | Side-by-side notebook, colour semantics, markdown notes, export Markdown + annotated PDF. |
| M5 | Capture | Web → PDF pipeline, in-app browser, Safari share extension, arXiv/DOI smart import. |
| M6 | Search & organise | Global FTS search, collections, tags, smart shelves, paper metadata fetch. |
| M7 | Learn | Flashcards, FSRS review, daily resurfacing. |
| M8 | AI companion | Explain / summarise / ask / generate cards with Claude. |
| M9 | Polish | Reference peek, themes, multi-window, focus mode, performance on 1000-page books. |
| M10 | Sync | iCloud files + CloudKit records; run on Mac. |

## 5. Defaults decided

- App name **Marginalia** (rename freely). Bundle prefix `com.jenish`.
- iPadOS 18.0 minimum (runs on current iPadOS on the A16 iPad).
- Article pages iPad-shaped; annotations stored outside the PDF with export to a flattened copy.
- Sync designed-for from day one (UUID string ids, `updatedAt` everywhere), implemented in M10.
