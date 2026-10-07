import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(AppEnvironment.self) private var app
    let shelf: Shelf
    let onOpen: (Document) -> Void

    @State private var query = ""
    @AppStorage("library.sort") private var sort: LibrarySort = .recent
    @State private var showingImporter = false
    @State private var showingBrowser = false
    @State private var renaming: Document?
    @State private var dropTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 28, alignment: .bottom)]

    var body: some View {
        let library = app.library
        let documents = library.documents(on: shelf, matching: query, sortedBy: sort)

        ScrollView {
            LazyVGrid(columns: columns, alignment: .center, spacing: 36) {
                ForEach(documents) { document in
                    Button { onOpen(document) } label: {
                        DocumentCard(document: document)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menu(for: document) }
                }
            }
            .padding(28)
        }
        .background(Theme.background)
        .overlay {
            if documents.isEmpty { emptyState }
        }
        .overlay(alignment: .bottom) {
            if library.importsInFlight > 0 {
                Label("Importing…", systemImage: "arrow.down.doc")
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.elevated, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.hairline))
                    .padding(.bottom, 24)
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.ink, style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(shelf.title)
        .searchable(text: $query, prompt: "Titles and authors")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                Menu {
                    Button { showingImporter = true } label: {
                        Label("Import PDFs…", systemImage: "doc.badge.plus")
                    }
                    Button { showingBrowser = true } label: {
                        Label("Save Web Page…", systemImage: "globe")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await library.importFiles(urls) }
            }
        }
        .onDrop(of: [.pdf], isTargeted: $dropTargeted) { providers in
            library.importDropped(providers)
        }
        .fullScreenCover(isPresented: $showingBrowser) {
            BrowserView()
                .monochromeTheme()
        }
        .sheet(item: $renaming) { document in
            EditDetailsSheet(document: document)
        }
    }

    @ViewBuilder
    private func menu(for document: Document) -> some View {
        let library = app.library
        Button { onOpen(document) } label: { Label("Open", systemImage: "book") }
        Button { renaming = document } label: { Label("Edit Details", systemImage: "pencil") }

        Menu {
            ForEach(DocumentKind.allCases, id: \.self) { kind in
                Button { library.update(document) { $0.kind = kind } } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
                .disabled(document.kind == kind)
            }
        } label: { Label("Kind", systemImage: "tag") }

        Menu {
            ForEach(ReadingStatus.allCases, id: \.self) { status in
                Button(status.title) { library.update(document) { $0.status = status } }
                    .disabled(document.status == status)
            }
        } label: { Label("Status", systemImage: "bookmark") }

        Divider()
        Button(role: .destructive) { library.delete(document) } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ContentUnavailableView {
                Label("Nothing here yet", systemImage: shelf.symbol)
            } description: {
                Text("Import PDFs from Files, drag them in, or save any web page as a PDF.")
            } actions: {
                HStack {
                    Button("Import PDFs") { showingImporter = true }
                    Button("Save Web Page") { showingBrowser = true }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct DocumentCard: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThumbnailView(documentID: document.id)
                .frame(maxWidth: .infinity, maxHeight: 230, alignment: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.hairline))

            if document.progress > 0 {
                ProgressBar(value: document.progress)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Image(systemName: document.kind.symbol)
                    Text(document.authors ?? document.kind.title)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
            }
            .frame(height: 54, alignment: .top)
        }
        .contentShape(Rectangle())
    }
}

/// Thin white-on-charcoal reading progress line.
struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.elevated)
                Capsule().fill(Theme.ink).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 2)
    }
}

struct EditDetailsSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    let document: Document

    @State private var title = ""
    @State private var authors = ""
    @State private var year = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title, axis: .vertical)
                TextField("Authors", text: $authors)
                TextField("Year", text: $year)
                    .keyboardType(.numberPad)
                if let source = document.sourceURL {
                    LabeledContent("Source", value: source)
                }
                if let doi = document.doi {
                    LabeledContent("DOI", value: doi)
                }
                if let arxiv = document.arxivID {
                    LabeledContent("arXiv", value: arxiv)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        app.library.update(document) { doc in
                            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmedTitle.isEmpty { doc.title = trimmedTitle }
                            let trimmedAuthors = authors.trimmingCharacters(in: .whitespacesAndNewlines)
                            doc.authors = trimmedAuthors.isEmpty ? nil : trimmedAuthors
                            doc.year = Int(year)
                        }
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            title = document.title
            authors = document.authors ?? ""
            year = document.year.map(String.init) ?? ""
        }
    }
}
