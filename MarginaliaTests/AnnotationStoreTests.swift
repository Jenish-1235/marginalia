import CoreGraphics
import Foundation
import Testing
@testable import Marginalia

@MainActor
struct AnnotationStoreTests {
    let database: AppDatabase
    let store: AnnotationStore
    let documentID = "doc-1"

    init() throws {
        database = try AppDatabase.inMemory()
        store = AnnotationStore(database: database)
        let now = Date()
        let document = Document(
            id: documentID, kind: .paper, title: "Test", authors: nil, year: nil, sourceURL: nil,
            doi: nil, arxivID: nil, contentHash: "hash", fileName: "doc-1.pdf", pageCount: 3,
            addedAt: now, openedAt: nil, updatedAt: now, lastPage: 0, lastPageY: nil,
            progress: 0, status: .unread, isIndexed: false)
        try database.writer.write { db in try document.insert(db) }
    }

    @Test func highlightRoundTripsRectsAndFlags() throws {
        let rects = [CGRect(x: 72, y: 600, width: 300, height: 12), CGRect(x: 72, y: 586, width: 120, height: 12)]
        let mark = Highlight(id: "h1", documentID: documentID, page: 2, style: .underline, flag: .question,
                             rects: rects, text: "attention is all you need", note: "why?",
                             createdAt: Date(), updatedAt: Date())
        try store.save([mark])

        let loaded = try #require(try store.highlights(for: documentID).first)
        #expect(loaded.rects == rects)
        #expect(loaded.style == .underline)
        #expect(loaded.flag == .question)
        #expect(loaded.hasNote)

        try store.deleteHighlight(id: "h1")
        #expect(try store.highlights(for: documentID).isEmpty)
    }

    @Test func emptyInkRemovesPage() throws {
        try store.saveInk(Data([1, 2, 3]), documentID: documentID, page: 1)
        #expect(try store.inkPages(for: documentID)[1] == Data([1, 2, 3]))
        try store.saveInk(nil, documentID: documentID, page: 1)
        #expect(try store.inkPages(for: documentID).isEmpty)
    }

    @Test func deletingDocumentCascadesAnnotations() throws {
        try store.saveInk(Data([9]), documentID: documentID, page: 0)
        try database.writer.write { db in _ = try Document.deleteOne(db, key: documentID) }
        #expect(try store.inkPages(for: documentID).isEmpty)
    }
}
