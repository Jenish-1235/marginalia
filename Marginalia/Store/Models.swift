import Foundation
import GRDB

nonisolated enum DocumentKind: String, Codable, CaseIterable, Sendable {
    case book, paper, article

    var title: String {
        switch self {
        case .book: "Book"
        case .paper: "Paper"
        case .article: "Article"
        }
    }

    var symbol: String {
        switch self {
        case .book: "book.closed"
        case .paper: "doc.text"
        case .article: "globe"
        }
    }
}

nonisolated enum ReadingStatus: String, Codable, CaseIterable, Sendable {
    case unread, reading, finished

    var title: String {
        switch self {
        case .unread: "Unread"
        case .reading: "Reading"
        case .finished: "Finished"
        }
    }
}

nonisolated struct Document: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var kind: DocumentKind
    var title: String
    var authors: String?
    var year: Int?
    var sourceURL: String?
    var doi: String?
    var arxivID: String?
    var contentHash: String
    var fileName: String
    var pageCount: Int
    var addedAt: Date
    var openedAt: Date?
    var updatedAt: Date
    var lastPage: Int
    /// Vertical position within `lastPage`, in PDF page space, for exact resume.
    var lastPageY: Double?
    var progress: Double
    var status: ReadingStatus
    var isIndexed: Bool

    /// Most recent interaction, used for "recent" ordering.
    var lastTouched: Date { openedAt ?? addedAt }
}

nonisolated extension Document: FetchableRecord, PersistableRecord {
    static let databaseTableName = "document"
}
