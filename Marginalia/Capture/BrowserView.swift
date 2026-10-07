import Observation
import SwiftUI
import WebKit

@Observable
final class BrowserModel: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var address = ""
    var title = ""
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var progress = 0.0
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.title) { [weak self] view, _ in
                Task { @MainActor in self?.title = view.title ?? "" }
            },
            webView.observe(\.estimatedProgress) { [weak self] view, _ in
                Task { @MainActor in self?.progress = view.estimatedProgress }
            },
            webView.observe(\.isLoading) { [weak self] view, _ in
                Task { @MainActor in
                    self?.isLoading = view.isLoading
                    self?.canGoBack = view.canGoBack
                    self?.canGoForward = view.canGoForward
                    if let url = view.url { self?.address = url.absoluteString }
                }
            },
        ]
    }

    func open(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url: URL?
        if trimmed.contains(".") && !trimmed.contains(" ") {
            url = URL(string: trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)")
        } else {
            var components = URLComponents(string: "https://duckduckgo.com/")
            components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
            url = components?.url
        }
        if let url { webView.load(URLRequest(url: url)) }
    }
}

/// In-app browser: browse (and log in) normally, then save the page as a PDF.
struct BrowserView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    var initialURL: URL?

    @State private var browser = BrowserModel()
    @State private var saving = false
    @State private var errorMessage: String?
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if browser.isLoading {
                ProgressView(value: browser.progress)
                    .tint(Theme.ink)
                    .frame(height: 2)
            } else {
                Theme.hairline.frame(height: 1)
            }
            WebViewHost(webView: browser.webView)
                .overlay {
                    if browser.webView.url == nil && !browser.isLoading {
                        ContentUnavailableView("Paste a link", systemImage: "link",
                                               description: Text("Open any article, log in if needed, then tap Save PDF."))
                    }
                }
        }
        .background(Theme.background)
        .onAppear {
            if let initialURL {
                browser.address = initialURL.absoluteString
                browser.open(initialURL.absoluteString)
            } else {
                addressFocused = true
            }
        }
        .alert("Couldn’t save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").frame(width: 34, height: 34)
            }
            .accessibilityLabel("Close")
            Button { browser.webView.goBack() } label: {
                Image(systemName: "chevron.left").frame(width: 34, height: 34)
            }
            .disabled(!browser.canGoBack)
            Button { browser.webView.goForward() } label: {
                Image(systemName: "chevron.right").frame(width: 34, height: 34)
            }
            .disabled(!browser.canGoForward)

            TextField("Search or paste a link", text: $browser.address)
                .focused($addressFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .onSubmit { browser.open(browser.address) }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 9))

            Menu {
                Button { save(keepOriginalLayout: false) } label: {
                    Label("Clean Article", systemImage: "doc.richtext")
                }
                Button { save(keepOriginalLayout: true) } label: {
                    Label("Original Layout", systemImage: "safari")
                }
            } label: {
                Group {
                    if saving {
                        ProgressView().tint(Theme.background)
                    } else {
                        Text("Save PDF").font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(Theme.background)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Theme.ink, in: Capsule())
            } primaryAction: {
                save(keepOriginalLayout: false)
            }
            .disabled(saving || browser.webView.url == nil)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface)
    }

    private func save(keepOriginalLayout: Bool) {
        guard let url = browser.webView.url else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let result = try await WebCapture().capture(
                    loadedPage: browser.webView, sourceURL: url, keepOriginalLayout: keepOriginalLayout)
                try await app.library.store(result)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
