import Foundation

/// An article extracted by Readability.
struct ExtractedArticle {
    var title: String
    var byline: String?
    var siteName: String?
    var published: String?
    var contentHTML: String
    var sourceURL: URL
}

/// Typographic HTML wrapper for captured articles. Monochrome, print-oriented, sized for an
/// iPad-shaped page so captured posts read like book pages.
enum ArticleTemplate {
    static func html(for article: ExtractedArticle) -> String {
        let host = article.siteName ?? article.sourceURL.host(percentEncoded: false) ?? ""
        var meta = [host]
        if let byline = article.byline, !byline.isEmpty { meta.append(byline) }
        if let date = formattedDate(article.published) { meta.append(date) }

        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        </head><body>
        <header>
          <h1 class="title">\(escape(article.title))</h1>
          <div class="meta">\(meta.map(escape).joined(separator: " · "))</div>
          <div class="source">\(escape(article.sourceURL.absoluteString))</div>
        </header>
        <article>\(article.contentHTML)</article>
        </body></html>
        """
    }

    private static func formattedDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? {
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: raw)
        }()
        return date?.formatted(date: .long, time: .omitted)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static let css = """
    html { -webkit-text-size-adjust: 100%; }
    body { margin: 0; background: #fff; color: #111;
           font: 17px/1.62 "New York", "Iowan Old Style", Georgia, serif;
           -webkit-hyphens: auto; hyphens: auto; overflow-wrap: break-word; }
    header { margin: 0 0 30px; padding-bottom: 18px; border-bottom: 1px solid #d6d6d6; }
    h1.title { font: 700 31px/1.18 -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif;
               letter-spacing: -0.01em; margin: 0 0 12px; }
    .meta { font: 500 13px/1.4 -apple-system, sans-serif; color: #444; }
    .source { font: 11px/1.4 ui-monospace, Menlo, monospace; color: #888; margin-top: 4px; word-break: break-all; }
    h1, h2, h3, h4, h5 { font-family: -apple-system, "Helvetica Neue", sans-serif; line-height: 1.25;
                         break-after: avoid; page-break-after: avoid; }
    article h1 { font-size: 25px; } h2 { font-size: 22px; margin: 1.6em 0 .5em; }
    h3 { font-size: 19px; margin: 1.4em 0 .4em; } h4 { font-size: 17px; }
    p { margin: 0 0 1em; orphans: 3; widows: 3; }
    img, svg, video, canvas { max-width: 100% !important; height: auto !important; break-inside: avoid; }
    figure { margin: 1.4em 0; break-inside: avoid; page-break-inside: avoid; }
    figcaption { font: 13px/1.45 -apple-system, sans-serif; color: #555; margin-top: 6px; }
    pre { font: 12.5px/1.5 ui-monospace, "SF Mono", Menlo, monospace; white-space: pre-wrap;
          overflow-wrap: anywhere; background: #f3f3f3; padding: 12px 14px; border-radius: 6px;
          break-inside: avoid; page-break-inside: avoid; }
    code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: .86em;
           background: #f1f1f1; padding: .1em .3em; border-radius: 3px; }
    pre code { background: none; padding: 0; font-size: inherit; }
    blockquote { margin: 1.1em 0; padding: 0 0 0 16px; border-left: 3px solid #b5b5b5; color: #333; }
    a { color: inherit; text-decoration: underline; text-decoration-color: #9a9a9a; }
    ul, ol { padding-left: 1.4em; } li { margin: .25em 0; }
    table { border-collapse: collapse; width: 100%; font-size: 14px; margin: 1em 0; break-inside: avoid; }
    th, td { border: 1px solid #d6d6d6; padding: 6px 8px; text-align: left; vertical-align: top; }
    hr { border: 0; border-top: 1px solid #d6d6d6; margin: 2em 0; }
    """
}
