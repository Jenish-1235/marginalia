import Foundation
import GRDB
import Observation
import PDFKit
import PencilKit

/// State and commands for one open document. The UIKit canvas reports into it;
/// SwiftUI chrome reads from it and sends commands through it.
@Observable
final class ReaderModel {
    let document: Document
    let pdf: PDFDocument
    private let database: AppDatabase
    private let annotationStore: AnnotationStore

    private(set) var pageIndex: Int
    var chromeVisible = true
    var layout: ReaderLayout = .continuous {
        didSet { canvas?.apply(layout: layout) }
    }

    var tools = ToolSettings.load() {
        didSet {
            tools.save()
            canvas?.inkLayer.apply(tools)
        }
    }

    /// All text marks in the document, by id.
    private(set) var highlights: [String: Highlight] = [:]
    /// The mark whose note is being edited (drives the note sheet).
    var editingHighlight: Highlight?

    var showingNotebook = false
    /// Free-form notes for the whole document.
    var notebookBody = "" {
        didSet { scheduleNotebookSave() }
    }

    /// Marks in reading order.
    var orderedMarks: [Highlight] {
        highlights.values.sorted { a, b in
            if a.page != b.page { return a.page < b.page }
            // Page space is y-up: higher on the page means larger maxY.
            return (a.rects.first?.maxY ?? 0) > (b.rects.first?.maxY ?? 0)
        }
    }

    @ObservationIgnored weak var canvas: ReaderCanvasController?
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    @ObservationIgnored private var notebookSaveTask: Task<Void, Never>?
    @ObservationIgnored private var isLoading = true
    @ObservationIgnored private var inkByPage: [Int: Data] = [:]
    @ObservationIgnored let undoManager = UndoManager()

    var pageCount: Int { pdf.pageCount }
    var pageLabel: String {
        let label = pdf.page(at: pageIndex)?.label
        let number = label.flatMap { $0.isEmpty ? nil : $0 } ?? "\(pageIndex + 1)"
        return "\(number) of \(pageCount)"
    }

    init?(document: Document, database: AppDatabase) {
        guard let pdf = PDFDocument(url: FileStore.fileURL(for: document)) else { return nil }
        if pdf.isLocked { _ = pdf.unlock(withPassword: "") }
        self.document = document
        self.pdf = pdf
        self.database = database
        self.annotationStore = AnnotationStore(database: database)
        self.pageIndex = min(document.lastPage, max(pdf.pageCount - 1, 0))
        do {
            highlights = Dictionary(uniqueKeysWithValues: try annotationStore.highlights(for: document.id).map { ($0.id, $0) })
            inkByPage = try annotationStore.inkPages(for: document.id)
            notebookBody = try annotationStore.documentNote(for: document.id)
        } catch {
            print("Failed to load annotations: \(error)")
        }
        isLoading = false
        markOpened()
    }

    /// Where reading should resume: page index plus vertical position in page space.
    var resumeDestination: (page: Int, y: Double?) {
        (min(document.lastPage, max(pageCount - 1, 0)), document.lastPageY)
    }

    // MARK: Commands

    func go(toPage index: Int) {
        canvas?.go(toPage: index)
    }

    func go(to destination: PDFDestination) {
        canvas?.go(to: destination)
    }

    func toggleChrome() {
        chromeVisible.toggle()
    }

    // MARK: Events from the canvas

    func canvasDidChangePage(to index: Int) {
        guard index != pageIndex else { return }
        pageIndex = index
        schedulePersist()
    }

    // MARK: Text marks

    /// Creates marks for a selection, one per page it spans.
    @discardableResult
    func addMark(from selection: PDFSelection, style: MarkStyle, flag: MarkFlag? = nil) -> [Highlight] {
        let now = Date()
        var created: [Highlight] = []
        for page in selection.pages {
            let lines = selection.selectionsByLine().filter { $0.pages.contains(page) }
            let rects = lines.map { $0.bounds(for: page) }.filter { !$0.isEmpty }
            guard !rects.isEmpty else { continue }
            let text = lines.compactMap(\.string).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            created.append(Highlight(
                id: UUID().uuidString, documentID: document.id, page: pdf.index(for: page),
                style: style, flag: flag, rects: rects, text: text, note: nil,
                createdAt: now, updatedAt: now))
        }
        guard !created.isEmpty else { return [] }
        insert(created)
        undoManager.setActionName(style.title)
        return created
    }

    func update(_ highlight: Highlight) {
        guard let previous = highlights[highlight.id] else { return }
        var updated = highlight
        updated.updatedAt = Date()
        highlights[updated.id] = updated
        canvas?.render(updated)
        save([updated])
        undoManager.registerUndo(withTarget: self) { model in model.update(previous) }
    }

    func deleteMark(id: String) {
        guard let removed = highlights.removeValue(forKey: id) else { return }
        canvas?.removeMark(id: id)
        do { try annotationStore.deleteHighlight(id: id) }
        catch { print("Failed to delete mark: \(error)") }
        undoManager.registerUndo(withTarget: self) { model in model.insert([removed]) }
        undoManager.setActionName("Delete")
    }

    private func insert(_ marks: [Highlight]) {
        for mark in marks {
            highlights[mark.id] = mark
            canvas?.render(mark)
        }
        save(marks)
        let ids = marks.map(\.id)
        undoManager.registerUndo(withTarget: self) { model in ids.forEach(model.deleteMark(id:)) }
    }

    private func save(_ marks: [Highlight]) {
        do { try annotationStore.save(marks) }
        catch { print("Failed to save marks: \(error)") }
    }

    /// Scrolls so the mark sits near the top of the screen.
    func reveal(_ mark: Highlight) {
        guard let page = pdf.page(at: mark.page), let rect = mark.rects.first else { return }
        go(to: PDFDestination(page: page, at: CGPoint(x: rect.minX, y: rect.maxY + 60)))
    }

    // MARK: Notebook

    private func scheduleNotebookSave() {
        guard !isLoading else { return }
        notebookSaveTask?.cancel()
        notebookSaveTask = Task {
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            saveNotebook()
        }
    }

    func saveNotebook() {
        notebookSaveTask?.cancel()
        do { try annotationStore.saveDocumentNote(notebookBody, documentID: document.id) }
        catch { print("Failed to save notebook: \(error)") }
    }

    /// Writes the notebook as Markdown to a temporary file for sharing.
    func exportMarkdown() -> URL? {
        let markdown = NotebookExporter.markdown(document: document, body: notebookBody, marks: orderedMarks)
        let safeTitle = document.title.replacingOccurrences(of: "/", with: "-").prefix(80)
        let url = URL.temporaryDirectory.appending(path: "\(safeTitle) — Notes.md")
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Ink

    func inkDrawing(for page: Int) -> PKDrawing {
        guard let data = inkByPage[page], let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    func saveInk(_ drawing: PKDrawing, page: Int) {
        let data = drawing.strokes.isEmpty ? nil : drawing.dataRepresentation()
        guard data != inkByPage[page] else { return }
        inkByPage[page] = data
        do { try annotationStore.saveInk(data, documentID: document.id, page: page) }
        catch { print("Failed to save ink: \(error)") }
    }

    // MARK: Persistence

    private func markOpened() {
        let id = document.id
        Task {
            try? await database.writer.write { db in
                try db.execute(sql: """
                    UPDATE document
                    SET openedAt = ?, status = CASE status WHEN 'unread' THEN 'reading' ELSE status END
                    WHERE id = ?
                    """, arguments: [Date(), id])
            }
        }
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            persistPosition()
        }
    }

    /// Saves the exact reading position. Called on page changes (debounced) and when closing.
    func persistPosition() {
        canvas?.inkLayer.flush()
        if notebookSaveTask != nil { saveNotebook() }
        let destination = canvas?.currentDestination
        let page = destination.flatMap { $0.page.flatMap(pdf.index(for:)) } ?? pageIndex
        let y = destination.map { Double($0.point.y) }
        let progress = pageCount > 0 ? Double(page + 1) / Double(pageCount) : 0
        let id = document.id
        Task {
            try? await database.writer.write { db in
                try db.execute(sql: """
                    UPDATE document SET lastPage = ?, lastPageY = ?, progress = ?, openedAt = ?
                    WHERE id = ?
                    """, arguments: [page, y, progress, Date(), id])
            }
        }
    }
}

enum ReaderLayout: String, CaseIterable, Identifiable {
    case continuous, singlePage, twoUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continuous: "Continuous Scroll"
        case .singlePage: "Single Page"
        case .twoUp: "Two Pages"
        }
    }

    var symbol: String {
        switch self {
        case .continuous: "arrow.up.and.down.text.horizontal"
        case .singlePage: "doc"
        case .twoUp: "book"
        }
    }
}
