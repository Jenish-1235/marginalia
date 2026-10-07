import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @SceneStorage("root.shelf") private var shelf: Shelf = .all
    @State private var openDocument: Document?

    var body: some View {
        let library = app.library

        NavigationSplitView {
            List(selection: Binding<Shelf?>(get: { shelf }, set: { if let new = $0 { shelf = new } })) {
                HStack(spacing: 10) {
                    Image("Logo")
                        .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                    Text("Marginalia")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.bottom, 8)
                .listRowBackground(Color.clear)
                .selectionDisabled()
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                ForEach(Shelf.allCases) { item in
                    let selected = item == shelf
                    HStack {
                        Label(item.title, systemImage: item.symbol)
                        Spacer()
                        let count = library.count(on: item)
                        if count > 0 {
                            Text("\(count)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(selected ? Theme.background.opacity(0.6) : Theme.inkTertiary)
                        }
                    }
                    .foregroundStyle(selected ? Theme.background : Theme.ink)
                    .fontWeight(selected ? .semibold : .regular)
                    .tag(item)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .navigationTitle("Marginalia")
            .toolbar(removing: .title)

        } detail: {
            NavigationStack {
                LibraryView(shelf: shelf) { openDocument = $0 }
            }
        }
        .fullScreenCover(item: $openDocument) { document in
            ReaderView(document: document)
                .environment(app)
                .monochromeTheme()
        }
        .onOpenURL { url in
            // marginalia://save?url=<page> — used by Shortcuts and the share sheet.
            if url.scheme == "marginalia", url.host() == "save",
               let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value.flatMap(URL.init(string:)) {
                Task { await library.saveWebPage(target) }
                return
            }
            guard url.isFileURL else { return }
            Task {
                await library.importFiles([url])
                // Files handed to us via "Open in…" land in Documents/Inbox; don't leave copies behind.
                if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
            }
        }
        #if DEBUG
        .task { await debugLaunchActions() }
        #endif
        .alert("Something went wrong", isPresented: Binding(
            get: { library.lastError != nil },
            set: { if !$0 { library.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
    }

    #if DEBUG
    /// Simulator automation: `SIMCTL_CHILD_MARGINALIA_IMPORT_DIR=<dir>` imports every PDF in a folder,
    /// `SIMCTL_CHILD_MARGINALIA_OPEN=<title prefix>` opens a document straight into the reader.
    private func debugLaunchActions() async {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["MARGINALIA_IMPORT_DIR"] {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: URL(filePath: dir), includingPropertiesForKeys: nil)) ?? []
            await app.library.importFiles(urls.filter { $0.pathExtension.lowercased() == "pdf" })
        }
        if let prefix = env["MARGINALIA_OPEN"] {
            try? await Task.sleep(for: .milliseconds(300))
            openDocument = app.library.documents.first { $0.title.hasPrefix(prefix) }
        }
    }
    #endif
}
