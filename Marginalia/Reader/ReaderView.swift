import PDFKit
import SwiftUI

struct ReaderView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    let document: Document

    @State private var model: ReaderModel?
    @State private var failedToOpen = false

    var body: some View {
        Group {
            if let model {
                ReaderScreen(model: model) {
                    model.persistPosition()
                    dismiss()
                }
            } else if failedToOpen {
                ContentUnavailableView {
                    Label("Couldn’t open this PDF", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Close") { dismiss() }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            guard model == nil else { return }
            if let opened = ReaderModel(document: document, database: app.database) {
                model = opened
            } else {
                failedToOpen = true
            }
        }
    }
}

private struct ReaderScreen: View {
    @Bindable var model: ReaderModel
    let close: () -> Void

    @State private var showingOutline = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 0) {
            readerColumn
            if model.showingNotebook {
                NotebookPanel(model: model)
                    .frame(width: 380)
                    .transition(.move(edge: .trailing))
            }
        }
        .background(Theme.background)
        .statusBarHidden(!model.chromeVisible)
        .persistentSystemOverlays(model.chromeVisible ? .automatic : .hidden)
        .sheet(isPresented: $showingOutline) {
            OutlineSheet(model: model)
        }
        .sheet(item: $model.editingHighlight) { mark in
            NoteEditorSheet(model: model, mark: mark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.persistPosition() }
        }
    }

    private var readerColumn: some View {
        ReaderCanvas(model: model)
            .ignoresSafeArea(edges: model.showingNotebook ? [.top, .bottom, .leading] : .all)
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.chromeVisible { topBar.transition(.move(edge: .top).combined(with: .opacity)) }
            }
            .overlay(alignment: .trailing) {
                if model.chromeVisible {
                    ToolPalette(model: model)
                        .padding(.trailing, 12)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button(action: close) {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Close")

            VStack(spacing: 1) {
                Text(model.document.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(model.pageLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity)

            Menu {
                Picker("Layout", selection: $model.layout) {
                    ForEach(ReaderLayout.allCases) { layout in
                        Label(layout.title, systemImage: layout.symbol).tag(layout)
                    }
                }
            } label: {
                Image(systemName: "rectangle.split.2x1")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Layout")

            Button { showingOutline = true } label: {
                Image(systemName: "list.bullet.indent")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Contents")

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { model.showingNotebook.toggle() }
            } label: {
                Image(systemName: model.showingNotebook ? "book.pages.fill" : "book.pages")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Notebook")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(Theme.ink)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
    }
}
