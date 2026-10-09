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
    @State private var sharing: URL?
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
        .overlay(alignment: .bottom) {
            if let saved = model.savedCopy {
                SavedCopyBanner(saved: saved) {
                    sharing = saved.url
                    model.savedCopy = nil
                } dismiss: {
                    model.savedCopy = nil
                }
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: saved.url) {
                    try? await Task.sleep(for: .seconds(5))
                    withAnimation { model.savedCopy = nil }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.savedCopy?.id)
        .sheet(item: $sharing) { url in
            ShareSheet(items: [url])
        }
        .alert("Couldn’t save", isPresented: Binding(
            get: { model.exportError != nil },
            set: { if !$0 { model.exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.exportError ?? "")
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

            Button {
                Task { await model.saveAnnotatedCopy() }
            } label: {
                Group {
                    if model.isSavingCopy {
                        ProgressView().tint(Theme.ink)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .frame(width: 36, height: 36)
            }
            .disabled(model.isSavingCopy)
            .accessibilityLabel("Save Annotated PDF")

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

/// Confirmation after saving the annotated copy, with a shortcut to share it.
private struct SavedCopyBanner: View {
    let saved: ReaderModel.SavedCopy
    let share: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(saved.replaced ? "Saved — replaced previous version" : "Saved annotated PDF")
                    .font(.subheadline.weight(.semibold))
                Text("Files › On My iPad › Marginalia › Annotated › \(saved.url.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Share", action: share)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.background)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Theme.ink, in: Capsule())
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Dismiss")
        }
        .foregroundStyle(Theme.ink)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: 620)
        .background(Theme.elevated, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }
}
