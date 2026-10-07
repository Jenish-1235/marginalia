import Foundation

/// Canonical paper metadata from arXiv (by id) or Crossref (by DOI). Free, no API keys.
nonisolated struct PaperMetadata: Sendable, Equatable {
    var title: String
    var authors: [String]
    var year: Int?

    var authorLine: String? {
        switch authors.count {
        case 0: nil
        case 1, 2, 3: authors.joined(separator: ", ")
        default: "\(authors[0]) et al."
        }
    }

    static func lookup(arxivID: String?, doi: String?) async -> PaperMetadata? {
        if let arxivID, let found = try? await arxiv(arxivID) { return found }
        if let doi, let found = try? await crossref(doi) { return found }
        return nil
    }

    static func arxiv(_ id: String) async throws -> PaperMetadata? {
        var components = URLComponents(string: "https://export.arxiv.org/api/query")!
        components.queryItems = [URLQueryItem(name: "id_list", value: id)]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return ArxivFeedParser.parse(data)
    }

    static func crossref(_ doi: String) async throws -> PaperMetadata? {
        guard let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.crossref.org/works/\(encoded)") else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parseCrossref(data)
    }

    static func parseCrossref(_ data: Data) -> PaperMetadata? {
        struct Envelope: Decodable {
            struct Message: Decodable {
                struct Author: Decodable { var given: String?; var family: String? }
                struct DateParts: Decodable { var dateParts: [[Int]]?
                    enum CodingKeys: String, CodingKey { case dateParts = "date-parts" } }
                var title: [String]?
                var author: [Author]?
                var issued: DateParts?
            }
            var message: Message
        }
        guard let message = try? JSONDecoder().decode(Envelope.self, from: data).message,
              let title = message.title?.first, !title.isEmpty else { return nil }
        let authors = (message.author ?? []).map { [$0.given, $0.family].compactMap { $0 }.joined(separator: " ") }
        return PaperMetadata(title: clean(title), authors: authors, year: message.issued?.dateParts?.first?.first)
    }

    static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Minimal Atom parser for the arXiv API: first entry's title, authors and published year.
nonisolated final class ArxivFeedParser: NSObject, XMLParserDelegate {
    private var inEntry = false
    private var inAuthor = false
    private var text = ""
    private var title: String?
    private var authors: [String] = []
    private var year: Int?
    private var done = false

    static func parse(_ data: Data) -> PaperMetadata? {
        let delegate = ArxivFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        guard let title = delegate.title, !title.isEmpty, title != "Error" else { return nil }
        return PaperMetadata(title: PaperMetadata.clean(title), authors: delegate.authors, year: delegate.year)
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        guard !done else { return }
        if name == "entry" { inEntry = true }
        if name == "author" { inAuthor = true }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard inEntry, !done else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title" where title == nil: title = value
        case "name" where inAuthor: authors.append(value)
        case "author": inAuthor = false
        case "published": year = Int(value.prefix(4))
        case "entry": done = true
        default: break
        }
    }
}
