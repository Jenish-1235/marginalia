import Foundation
import PDFKit

/// Best-effort metadata from a PDF's info dictionary and its first pages.
nonisolated struct ExtractedMetadata: Sendable, Equatable {
    var title: String
    var authors: String?
    var year: Int?
    var doi: String?
    var arxivID: String?
    var kind: DocumentKind
}

nonisolated enum MetadataExtractor {
    static func extract(from pdf: PDFDocument, fallbackTitle: String) -> ExtractedMetadata {
        let attributes = pdf.documentAttributes ?? [:]
        let infoTitle = attributes[PDFDocumentAttribute.titleAttribute] as? String
        let infoAuthor = attributes[PDFDocumentAttribute.authorAttribute] as? String

        let leadingText = (0..<min(2, pdf.pageCount))
            .compactMap { pdf.page(at: $0)?.string }
            .joined(separator: "\n")

        let arxivID = firstArxivID(in: leadingText)
        let doi = firstDOI(in: leadingText)

        return ExtractedMetadata(
            title: usableTitle(infoTitle) ?? cleanedFileName(fallbackTitle),
            authors: usableAuthor(infoAuthor),
            year: arxivID.flatMap(yearFromArxivID),
            doi: doi,
            arxivID: arxivID,
            kind: guessKind(pageCount: pdf.pageCount, leadingText: leadingText,
                            hasIdentifier: arxivID != nil || doi != nil)
        )
    }

    static func guessKind(pageCount: Int, leadingText: String, hasIdentifier: Bool) -> DocumentKind {
        if pageCount >= 90 { return .book }
        if hasIdentifier { return .paper }
        if leadingText.range(of: "abstract", options: .caseInsensitive) != nil { return .paper }
        return pageCount >= 40 ? .book : .paper
    }

    static func firstArxivID(in text: String) -> String? {
        let pattern = /arXiv:\s*(\d{4}\.\d{4,5})(v\d+)?/
        return text.firstMatch(of: pattern).map { String($0.output.1) }
    }

    static func firstDOI(in text: String) -> String? {
        let pattern = /10\.\d{4,9}\/[-._;()\/:A-Za-z0-9]+/
        guard let match = text.firstMatch(of: pattern) else { return nil }
        return String(match.output).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)"))
    }

    /// arXiv ids start with YYMM.
    static func yearFromArxivID(_ id: String) -> Int? {
        guard let yy = Int(id.prefix(2)) else { return nil }
        return 2000 + yy
    }

    static func usableTitle(_ raw: String?) -> String? {
        guard let title = raw?.trimmingCharacters(in: .whitespacesAndNewlines), title.count >= 4 else { return nil }
        let lower = title.lowercased()
        let junkPrefixes = ["untitled", "microsoft word", "document", "slide 1", "title"]
        let junkSuffixes = [".pdf", ".doc", ".docx", ".tex", ".dvi", ".indd", ".txt", ".rtf", ".html", ".md"]
        if junkPrefixes.contains(where: { lower.hasPrefix($0) }) { return nil }
        if junkSuffixes.contains(where: { lower.hasSuffix($0) }) { return nil }
        return title
    }

    static func usableAuthor(_ raw: String?) -> String? {
        guard let author = raw?.trimmingCharacters(in: .whitespacesAndNewlines), author.count >= 2 else { return nil }
        let lower = author.lowercased()
        if ["user", "admin", "author", "unknown", "owner"].contains(lower) { return nil }
        return author
    }

    static func cleanedFileName(_ name: String) -> String {
        let spaced = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return spaced.isEmpty ? "Untitled" : spaced
    }
}
