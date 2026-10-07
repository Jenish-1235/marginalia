import Foundation
import GRDB
import Observation
import UniformTypeIdentifiers

enum Shelf: String, CaseIterable, Identifiable, Hashable {
    case readingNow, all, books, papers, articles, unread, finished

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readingNow: "Reading Now"
        case .all: "All"
        case .books: "Books"
        case .papers: "Papers"
        case .articles: "Articles"
        case .unread: "Unread"
        case .finished: "Finished"
        }
    }

    var symbol: String {
        switch self {
        case .readingNow: "book.pages"
        case .all: "square.grid.2x2"
        case .books: DocumentKind.book.symbol
        case .papers: DocumentKind.paper.symbol
        case .articles: DocumentKind.article.symbol
        case .unread: "circle.dashed"
        case .finished: "checkmark.circle"
        }
    }

    func contains(_ document: Document) -> Bool {
        switch self {
        case .readingNow: document.status == .reading
        case .all: true
        case .books: document.kind == .book
        case .papers: document.kind == .paper
        case .articles: document.kind == .article
        case .unread: document.status == .unread
        case .finished: document.status == .finished
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent, added, title, progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recently Opened"
        case .added: "Date Added"
        case .title: "Title"
        case .progress: "Progress"
        }
    }
}

@Observable
final class LibraryModel {
    private(set) var documents: [Document] = []
    private(set) var importsInFlight = 0
    var lastError: String?

    private let database: AppDatabase
    private let importer: ImportService
    @ObservationIgnored private var observation: Task<Void, Never>?

    init(database: AppDatabase) {
        self.database = database
        self.importer = ImportService(database: database)
        observe()
    }

    private func observe() {
        let reader = database.reader
        observation = Task {
            let request = ValueObservation.tracking { db in try Document.fetchAll(db) }
            do {
                for try await documents in request.values(in: reader) {
                    self.documents = documents
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: Queries

    func documents(on shelf: Shelf, matching query: String, sortedBy sort: LibrarySort) -> [Document] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return documents
            .filter { shelf.contains($0) }
            .filter { doc in
                needle.isEmpty
                    || doc.title.localizedCaseInsensitiveContains(needle)
                    || (doc.authors?.localizedCaseInsensitiveContains(needle) ?? false)
            }
            .sorted { a, b in
                switch sort {
                case .recent: a.lastTouched > b.lastTouched
                case .added: a.addedAt > b.addedAt
                case .title: a.title.localizedStandardCompare(b.title) == .orderedAscending
                case .progress: a.progress > b.progress
                }
            }
    }

    func count(on shelf: Shelf) -> Int {
        documents.lazy.filter { shelf.contains($0) }.count
    }

    // MARK: Import

    func importFiles(_ urls: [URL], options: ImportService.Options = .init()) async {
        for url in urls {
            importsInFlight += 1
            defer { importsInFlight -= 1 }
            do {
                _ = try await importer.importPDF(from: url, options: options)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Saves a web page (or a linked PDF) into the library.
    func saveWebPage(_ url: URL) async {
        importsInFlight += 1
        defer { importsInFlight -= 1 }
        do {
            try await store(try await WebCapture().capture(url: url))
        } catch {
            lastError = error.localizedDescription
        }
    }

    func store(_ capture: WebCapture.Result) async throws {
        let options = ImportService.Options(
            kind: capture.kind, title: capture.title, authors: capture.byline,
            sourceURL: capture.sourceURL.absoluteString)
        _ = try await importer.importPDF(data: capture.pdf, suggestedName: capture.suggestedName, options: options)
    }

    /// Handles PDFs dragged in from Files or other apps.
    func importDropped(_ providers: [NSItemProvider]) -> Bool {
        let pdfProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }
        for provider in pdfProviders {
            _ = provider.loadFileRepresentation(for: .pdf, openInPlace: false) { url, _, _ in
                // The provided file is deleted when this handler returns, so copy it first.
                guard let url else { return }
                let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                let copy = folder.appending(path: url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: copy)
                } catch { return }
                Task { @MainActor in
                    await self.importFiles([copy])
                    try? FileManager.default.removeItem(at: folder)
                }
            }
        }
        return !pdfProviders.isEmpty
    }

    // MARK: Edits

    func update(_ document: Document, _ change: (inout Document) -> Void) {
        var updated = document
        change(&updated)
        updated.updatedAt = Date()
        let record = updated
        Task {
            do { try await database.writer.write { db in try record.update(db) } }
            catch { lastError = error.localizedDescription }
        }
    }

    func delete(_ document: Document) {
        let id = document.id
        Task {
            do {
                try await database.writer.write { db in
                    try db.execute(sql: "DELETE FROM pageText WHERE documentID = ?", arguments: [id])
                    _ = try Document.deleteOne(db, key: id)
                }
                FileStore.removeFiles(for: document)
                ThumbnailCache.shared.remove(id)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}
