import Foundation

/// Markdown export of a document's notebook (Obsidian-friendly).
enum NotebookExporter {
    static func markdown(document: Document, body: String, marks: [Highlight]) -> String {
        var lines: [String] = ["# \(document.title)", ""]

        var meta: [String] = []
        if let authors = document.authors { meta.append("**Authors:** \(authors)") }
        if let year = document.year { meta.append("**Year:** \(year)") }
        if let source = document.sourceURL { meta.append("**Source:** \(source)") }
        if let arxiv = document.arxivID { meta.append("**arXiv:** [\(arxiv)](https://arxiv.org/abs/\(arxiv))") }
        if let doi = document.doi { meta.append("**DOI:** [\(doi)](https://doi.org/\(doi))") }
        if !meta.isEmpty { lines += meta.map { "- \($0)" } + [""] }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            lines += ["## Notes", "", trimmedBody, ""]
        }

        let questions = marks.filter { $0.flag == .question }
        if !questions.isEmpty {
            lines += ["## Open Questions", ""]
            lines += questions.map { "- [ ] \($0.note ?? $0.text) *(p. \($0.page + 1))*" }
            lines.append("")
        }

        let lookups = marks.filter { $0.flag == .lookup }
        if !lookups.isEmpty {
            lines += ["## To Look Up", ""]
            lines += lookups.map { "- [ ] \($0.text) *(p. \($0.page + 1))*" }
            lines.append("")
        }

        if !marks.isEmpty {
            lines += ["## Highlights", ""]
            for mark in marks {
                lines.append("> \(mark.text.replacingOccurrences(of: "\n", with: " "))")
                lines.append(">")
                lines.append("> — p. \(mark.page + 1)\(mark.style == .highlight ? "" : " · \(mark.style.title.lowercased())")")
                if let note = mark.note, mark.hasNote {
                    lines.append("")
                    lines.append(note)
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }
}
