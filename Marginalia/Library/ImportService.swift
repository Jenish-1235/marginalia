import CryptoKit
import Foundation
import GRDB
import PDFKit
import UIKit

/// Copies PDFs into the library, extracts metadata, renders a thumbnail and indexes page text.
nonisolated struct ImportService: Sendable {
    let database: AppDatabase

    struct Options: Sendable {
        var kind: DocumentKind?
        var title: String?
        var authors: String?
        var sourceURL: String?
    }

    enum ImportError: LocalizedError {
        case unreadable(String)
        case locked(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): "“\(name)” isn’t a readable PDF."
            case .locked(let name): "“\(name)” is password protected."
            }
        }
    }

    /// Imports a file the app may only have security-scoped access to.
    /// Returns the existing document when the same file was imported before.
    @concurrent
    func importPDF(from url: URL, options: Options = Options()) async throws -> Document {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try await importPDF(data: data, suggestedName: url.deletingPathExtension().lastPathComponent,
                                   options: options)
    }

    @concurrent
    func importPDF(data: Data, suggestedName: String, options: Options = Options()) async throws -> Document {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let existing = try await database.reader.read({ db in
            try Document.filter(Column("contentHash") == hash).fetchOne(db)
        }) {
            return existing
        }

        guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
            throw ImportError.unreadable(suggestedName)
        }
        if pdf.isLocked && !pdf.unlock(withPassword: "") {
            throw ImportError.locked(suggestedName)
        }

        let id = UUID().uuidString
        let fileName = "\(id).pdf"
        try data.write(to: FileStore.libraryDirectory.appending(path: fileName), options: .atomic)
        Self.writeThumbnail(for: pdf, documentID: id)

        let meta = MetadataExtractor.extract(from: pdf, fallbackTitle: suggestedName)
        let now = Date()
        let document = Document(
            id: id,
            kind: options.kind ?? meta.kind,
            title: options.title ?? meta.title,
            authors: options.authors ?? meta.authors,
            year: meta.year,
            sourceURL: options.sourceURL,
            doi: meta.doi,
            arxivID: meta.arxivID,
            contentHash: hash,
            fileName: fileName,
            pageCount: pdf.pageCount,
            addedAt: now,
            openedAt: nil,
            updatedAt: now,
            lastPage: 0,
            lastPageY: nil,
            progress: 0,
            status: .unread,
            isIndexed: false
        )
        try await database.writer.write { db in try document.insert(db) }

        // Papers get their official title, authors and year (unless the caller named them).
        var result = document
        if options.title == nil, meta.arxivID != nil || meta.doi != nil,
           let paper = await PaperMetadata.lookup(arxivID: meta.arxivID, doi: meta.doi) {
            result.title = paper.title
            result.authors = options.authors ?? paper.authorLine ?? result.authors
            result.year = paper.year ?? result.year
            result.kind = options.kind ?? .paper
            let updated = result
            try await database.writer.write { db in try updated.update(db) }
        }

        try await indexText(of: pdf, documentID: id)
        return result
    }

    /// Stores every page's text in the FTS index. Large books are written in chunks so readers
    /// of the database are never blocked for long.
    private func indexText(of pdf: PDFDocument, documentID: String) async throws {
        let chunkSize = 50
        var start = 0
        while start < pdf.pageCount {
            let end = min(start + chunkSize, pdf.pageCount)
            let pages: [(Int, String)] = (start..<end).compactMap { index in
                guard let text = pdf.page(at: index)?.string, !text.isEmpty else { return nil }
                return (index, text)
            }
            try await database.writer.write { db in
                for (index, text) in pages {
                    try db.execute(
                        sql: "INSERT INTO pageText (documentID, page, text) VALUES (?, ?, ?)",
                        arguments: [documentID, index, text])
                }
            }
            start = end
        }
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE document SET isIndexed = 1 WHERE id = ?", arguments: [documentID])
        }
    }

    private static func writeThumbnail(for pdf: PDFDocument, documentID: String) {
        guard let page = pdf.page(at: 0) else { return }
        let bounds = page.bounds(for: .cropBox)
        let width: CGFloat = 360
        let size = CGSize(width: width, height: width * bounds.height / max(bounds.width, 1))
        let image = page.thumbnail(of: size, for: .cropBox)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: FileStore.thumbnailURL(for: documentID), options: .atomic)
        }
    }
}
