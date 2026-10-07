import UIKit
import WebKit

/// Turns a URL into a PDF for the library.
///
/// - Links that are already PDFs (incl. arXiv `abs/` pages) are downloaded as-is.
/// - Everything else is loaded in a WKWebView, cleaned with Mozilla Readability, set in our
///   article template and paginated onto iPad-shaped pages.
final class WebCapture {
    struct Result {
        var pdf: Data
        /// nil for downloaded PDFs: the importer reads the title from the file itself.
        var title: String?
        var byline: String?
        /// nil lets the importer guess book vs paper.
        var kind: DocumentKind?
        var sourceURL: URL
        var suggestedName: String
    }

    enum CaptureError: LocalizedError {
        case loadFailed(String)
        case noContent
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .loadFailed(let reason): "Couldn’t load the page: \(reason)"
            case .noContent: "Couldn’t find readable content on this page."
            case .renderFailed: "Couldn’t create a PDF from this page."
            }
        }
    }

    /// iPad 11" portrait in points: captured pages fill the screen edge to edge.
    static let pageSize = CGSize(width: 820, height: 1180)
    static let pageInsets = UIEdgeInsets(top: 64, left: 60, bottom: 64, right: 60)

    // MARK: Entry points

    /// Headless capture of a URL.
    func capture(url: URL) async throws -> Result {
        if let pdf = try await downloadIfPDF(url) { return pdf }
        let webView = makeWebView()
        defer { webView.removeFromSuperview() }
        try await PageLoader.load(URLRequest(url: url), in: webView)
        return try await capture(loadedPage: webView, sourceURL: webView.url ?? url)
    }

    /// Capture of a page the user has already loaded (and maybe logged into) in the browser.
    func capture(loadedPage webView: WKWebView, sourceURL: URL, keepOriginalLayout: Bool = false) async throws -> Result {
        if let pdf = try await downloadIfPDF(sourceURL) { return pdf }
        try? await webView.callAsyncJavaScript(Self.settleScript, contentWorld: .defaultClient)

        if !keepOriginalLayout, let article = try await extractArticle(from: webView, sourceURL: sourceURL) {
            let renderView = makeWebView()
            defer { renderView.removeFromSuperview() }
            try await PageLoader.loadHTML(ArticleTemplate.html(for: article), baseURL: sourceURL, in: renderView)
            try? await renderView.callAsyncJavaScript(Self.waitForImagesScript, contentWorld: .defaultClient)
            let pdf = try render(renderView)
            return Result(pdf: pdf, title: article.title, byline: article.byline, kind: .article,
                          sourceURL: sourceURL, suggestedName: article.title)
        }

        // Fallback: paginate the page exactly as the site lays it out.
        let pdf = try render(webView)
        let title = webView.title.flatMap { $0.isEmpty ? nil : $0 } ?? sourceURL.host() ?? "Web Page"
        return Result(pdf: pdf, title: title, byline: nil, kind: .article, sourceURL: sourceURL, suggestedName: title)
    }

    // MARK: PDF links

    /// arXiv abstract pages map to their PDF; direct PDF links are downloaded.
    static func pdfURL(for url: URL) -> URL? {
        if let host = url.host(), host.hasSuffix("arxiv.org") {
            let path = url.path()
            if path.hasPrefix("/abs/") {
                return URL(string: "https://arxiv.org/pdf/\(path.dropFirst("/abs/".count))")
            }
            if path.hasPrefix("/pdf/") { return url }
        }
        if url.pathExtension.lowercased() == "pdf" { return url }
        return nil
    }

    private func downloadIfPDF(_ url: URL) async throws -> Result? {
        guard url.scheme?.hasPrefix("http") == true else { return nil }
        let candidate = Self.pdfURL(for: url) ?? url
        var request = URLRequest(url: candidate)
        request.httpMethod = Self.pdfURL(for: url) == nil ? "HEAD" : "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.mimeType == "application/pdf" else { return nil }

        let body = request.httpMethod == "GET" ? data : try await URLSession.shared.data(from: candidate).0
        guard body.starts(with: Data("%PDF".utf8)) else { return nil }
        let isArxiv = candidate.host()?.hasSuffix("arxiv.org") == true
        let name = candidate.deletingPathExtension().lastPathComponent
        return Result(pdf: body, title: nil, byline: nil, kind: isArxiv ? .paper : nil, sourceURL: url,
                      suggestedName: name)
    }

    // MARK: Readability

    private static let readabilitySource: String = {
        guard let url = Bundle.main.url(forResource: "Readability", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return source
    }()

    private func extractArticle(from webView: WKWebView, sourceURL: URL) async throws -> ExtractedArticle? {
        guard !Self.readabilitySource.isEmpty else { return nil }
        // An isolated content world: immune to the page's CSP and globals.
        _ = try? await webView.evaluateJavaScript(Self.readabilitySource, in: nil, contentWorld: .defaultClient)
        let result = try? await webView.callAsyncJavaScript("""
            const article = new Readability(document.cloneNode(true), { charThreshold: 250 }).parse();
            if (!article || !article.content) { return null; }
            return { title: article.title || document.title || "", byline: article.byline || "",
                     siteName: article.siteName || "", published: article.publishedTime || "",
                     content: article.content, length: article.length || 0 };
            """, contentWorld: .defaultClient)

        guard let dict = result as? [String: Any],
              let content = dict["content"] as? String,
              (dict["length"] as? Int ?? 0) > 200 || content.count > 1500 else { return nil }

        func nonEmpty(_ key: String) -> String? {
            (dict[key] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }
        return ExtractedArticle(
            title: nonEmpty("title") ?? sourceURL.host() ?? "Article",
            byline: nonEmpty("byline"),
            siteName: nonEmpty("siteName"),
            published: nonEmpty("published"),
            contentHTML: content,
            sourceURL: sourceURL)
    }

    /// Promotes lazy images and scrolls through the page so lazy loaders fire.
    private static let settleScript = """
        for (const img of document.querySelectorAll('img')) {
          const lazy = img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || img.getAttribute('data-original');
          if (lazy && (!img.getAttribute('src') || img.src.startsWith('data:'))) { img.src = lazy; }
          const lazySet = img.getAttribute('data-srcset');
          if (lazySet) { img.srcset = lazySet; }
          img.loading = 'eager';
        }
        const height = document.documentElement.scrollHeight;
        for (let y = 0; y < height; y += window.innerHeight) {
          window.scrollTo(0, y);
          await new Promise(r => setTimeout(r, 50));
        }
        window.scrollTo(0, 0);
        await new Promise(r => setTimeout(r, 400));
        return true;
        """

    private static let waitForImagesScript = """
        const pending = Array.from(document.images).filter(i => !i.complete)
          .map(i => new Promise(r => { i.onload = r; i.onerror = r; }));
        await Promise.race([Promise.all(pending), new Promise(r => setTimeout(r, 10000))]);
        return document.images.length;
        """

    // MARK: Rendering

    private func render(_ webView: WKWebView) throws -> Data {
        let renderer = PagedRenderer(pageSize: Self.pageSize, insets: Self.pageInsets)
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)

        let bounds = CGRect(origin: .zero, size: Self.pageSize)
        let pageCount = renderer.numberOfPages
        guard pageCount > 0 else { throw CaptureError.renderFailed }

        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            renderer.prepare(forDrawingPages: NSRange(location: 0, length: pageCount))
            for index in 0..<pageCount {
                context.beginPage()
                renderer.drawPage(at: index, in: bounds)
            }
        }
        return data
    }

    /// Off-screen web views still need a window to lay out and run timers normally.
    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // shares cookies with the in-app browser
        let webView = WKWebView(frame: CGRect(origin: .zero, size: Self.pageSize), configuration: config)
        webView.alpha = 0.01
        webView.isUserInteractionEnabled = false
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            window.insertSubview(webView, at: 0)
        }
        return webView
    }
}

/// Print renderer with a fixed paper size.
nonisolated private final class PagedRenderer: UIPrintPageRenderer {
    private let pageSize: CGSize
    private let insets: UIEdgeInsets

    init(pageSize: CGSize, insets: UIEdgeInsets) {
        self.pageSize = pageSize
        self.insets = insets
        super.init()
    }

    override var paperRect: CGRect { CGRect(origin: .zero, size: pageSize) }
    override var printableRect: CGRect { paperRect.inset(by: insets) }
}

/// Bridges WKNavigationDelegate callbacks into async/await.
private final class PageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    static func load(_ request: URLRequest, in webView: WKWebView) async throws {
        let loader = PageLoader()
        try await loader.run(in: webView) { webView.load(request) }
    }

    static func loadHTML(_ html: String, baseURL: URL, in webView: WKWebView) async throws {
        let loader = PageLoader()
        try await loader.run(in: webView) { webView.loadHTMLString(html, baseURL: baseURL) }
    }

    private func run(in webView: WKWebView, start: () -> Void) async throws {
        webView.navigationDelegate = self
        defer { webView.navigationDelegate = nil }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            start()
            // Give up waiting on pages that never finish (endless trackers), but keep what loaded.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(25))
                self?.finish(nil)
            }
        }
        // Let client-side rendered sites (Medium, Substack…) hydrate.
        try? await Task.sleep(for: .seconds(1.2))
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil) }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(WebCapture.CaptureError.loadFailed(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(WebCapture.CaptureError.loadFailed(error.localizedDescription))
    }
}
