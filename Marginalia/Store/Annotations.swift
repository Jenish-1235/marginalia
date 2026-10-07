import CoreGraphics
import Foundation
import GRDB

/// How a text mark is drawn. Monochrome: meaning comes from shape, not colour.
nonisolated enum MarkStyle: String, Codable, CaseIterable, Sendable {
    case highlight, underline, strikethrough

    var title: String {
        switch self {
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .strikethrough: "Strike"
        }
    }

    var symbol: String {
        switch self {
        case .highlight: "highlighter"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        }
    }
}

/// Optional intent attached to a mark, shown as a glyph in the page margin.
nonisolated enum MarkFlag: String, Codable, CaseIterable, Sendable {
    case question, lookup

    var title: String {
        switch self {
        case .question: "Question"
        case .lookup: "Look Up Later"
        }
    }

    var symbol: String {
        switch self {
        case .question: "questionmark"
        case .lookup: "arrow.right"
        }
    }
}

nonisolated struct Highlight: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var documentID: String
    var page: Int
    var style: MarkStyle
    var flag: MarkFlag?
    /// Line rectangles in PDF page space (origin bottom-left).
    var rects: [CGRect]
    var text: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    var hasNote: Bool { !(note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
}

nonisolated extension Highlight: FetchableRecord, PersistableRecord {
    static let databaseTableName = "highlight"
}

nonisolated struct InkPage: Codable, Sendable {
    var documentID: String
    var page: Int
    var drawing: Data
    var updatedAt: Date
}

nonisolated extension InkPage: FetchableRecord, PersistableRecord {
    static let databaseTableName = "ink"
}

/// Reads and writes a document's annotations.
nonisolated struct AnnotationStore: Sendable {
    let database: AppDatabase

    func highlights(for documentID: String) throws -> [Highlight] {
        try database.reader.read { db in
            try Highlight.filter(Column("documentID") == documentID)
                .order(Column("page"), Column("createdAt"))
                .fetchAll(db)
        }
    }

    func inkPages(for documentID: String) throws -> [Int: Data] {
        let pages = try database.reader.read { db in
            try InkPage.filter(Column("documentID") == documentID).fetchAll(db)
        }
        return Dictionary(pages.map { ($0.page, $0.drawing) }, uniquingKeysWith: { a, _ in a })
    }

    // Writes are synchronous: they're small, and ordering matters (delete → undo → re-insert).

    func save(_ highlights: [Highlight]) throws {
        try database.writer.write { db in
            for highlight in highlights { try highlight.upsert(db) }
        }
    }

    func deleteHighlight(id: String) throws {
        _ = try database.writer.write { db in
            try Highlight.deleteOne(db, key: id)
        }
    }

    func documentNote(for documentID: String) throws -> String {
        try database.reader.read { db in
            try String.fetchOne(db, sql: "SELECT body FROM documentNote WHERE documentID = ?",
                                arguments: [documentID]) ?? ""
        }
    }

    func saveDocumentNote(_ body: String, documentID: String) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO documentNote (documentID, body, updatedAt) VALUES (?, ?, ?)
                ON CONFLICT(documentID) DO UPDATE SET body = excluded.body, updatedAt = excluded.updatedAt
                """, arguments: [documentID, body, Date()])
        }
    }

    /// An empty drawing removes the page's row.
    func saveInk(_ drawing: Data?, documentID: String, page: Int) throws {
        try database.writer.write { db in
            if let drawing {
                try InkPage(documentID: documentID, page: page, drawing: drawing, updatedAt: Date()).upsert(db)
            } else {
                _ = try InkPage.deleteOne(db, key: ["documentID": documentID, "page": page])
            }
        }
    }
}
