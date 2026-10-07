import SwiftUI
import UIKit

enum NotebookFilter: String, CaseIterable, Identifiable {
    case all, notes, questions, lookups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .notes: "Notes"
        case .questions: "Questions"
        case .lookups: "Look Up"
        }
    }

    func includes(_ mark: Highlight) -> Bool {
        switch self {
        case .all: true
        case .notes: mark.hasNote
        case .questions: mark.flag == .question
        case .lookups: mark.flag == .lookup
        }
    }
}

/// The document's notebook: free-form notes on top, every mark below in reading order.
struct NotebookPanel: View {
    @Bindable var model: ReaderModel
    @State private var filter: NotebookFilter = .all
    @State private var shareURL: URL?
    @FocusState private var editingBody: Bool

    var body: some View {
        let marks = model.orderedMarks.filter(filter.includes)

        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    notesEditor
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)

                    Picker("Filter", selection: $filter) {
                        ForEach(NotebookFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    if marks.isEmpty {
                        Text(model.highlights.isEmpty
                             ? "Highlight with Apple Pencil, or select text and choose Highlight. Marks collect here."
                             : "Nothing in this filter.")
                            .font(.callout)
                            .foregroundStyle(Theme.inkTertiary)
                            .padding(16)
                    }

                    ForEach(marks) { mark in
                        MarkRow(mark: mark)
                            .contentShape(Rectangle())
                            .onTapGesture { model.reveal(mark) }
                            .contextMenu {
                                Button { model.editingHighlight = mark } label: {
                                    Label(mark.hasNote ? "Edit Note" : "Add Note", systemImage: "text.bubble")
                                }
                                Button { UIPasteboard.general.string = mark.text } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                Button(role: .destructive) { model.deleteMark(id: mark.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        Theme.hairline.frame(height: 1).padding(.leading, 16)
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.surface)
        .overlay(alignment: .leading) { Theme.hairline.frame(width: 1) }
        .sheet(item: $shareURL) { url in
            ShareSheet(items: [url])
        }
    }

    private var header: some View {
        HStack {
            Text("Notebook")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("\(model.highlights.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.inkTertiary)
            Spacer()
            Button { shareURL = model.exportMarkdown() } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Export Markdown")
            Button { withAnimation(.easeInOut(duration: 0.2)) { model.showingNotebook = false } } label: {
                Image(systemName: "xmark")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Close Notebook")
        }
        .foregroundStyle(Theme.ink)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
    }

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            if model.notebookBody.isEmpty && !editingBody {
                Text("Your notes on this document — summary, ideas, connections…")
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $model.notebookBody)
                .focused($editingBody)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(minHeight: 120)
                .padding(8)
        }
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct MarkRow: View {
    let mark: Highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: mark.style.symbol)
                Text("p. \(mark.page + 1)")
                if let flag = mark.flag {
                    Image(systemName: flag.symbol)
                        .fontWeight(.bold)
                }
                Spacer()
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.inkTertiary)

            Text(mark.text)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(8)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Theme.inkTertiary.frame(width: mark.style == .highlight ? 3 : 1)
                }

            if let note = mark.note, mark.hasNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
