import PDFKit
import SwiftUI

/// A flattened, Identifiable mirror of the PDF's outline tree.
struct OutlineItem: Identifiable {
    let id: String
    let title: String
    let pageIndex: Int?
    let destination: PDFDestination?
    let children: [OutlineItem]?

    static func tree(for pdf: PDFDocument) -> [OutlineItem] {
        guard let root = pdf.outlineRoot else { return [] }
        return children(of: root, in: pdf, path: "")
    }

    private static func children(of node: PDFOutline, in pdf: PDFDocument, path: String) -> [OutlineItem] {
        (0..<node.numberOfChildren).compactMap { index in
            guard let child = node.child(at: index) else { return nil }
            let id = "\(path)/\(index)"
            let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
            let nested = children(of: child, in: pdf, path: id)
            return OutlineItem(
                id: id,
                title: child.label ?? "Untitled",
                pageIndex: destination?.page.map(pdf.index(for:)),
                destination: destination,
                children: nested.isEmpty ? nil : nested
            )
        }
    }
}

struct OutlineSheet: View {
    let model: ReaderModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [OutlineItem] = []

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("No table of contents", systemImage: "list.bullet.indent",
                                           description: Text("This PDF doesn’t include an outline."))
                } else {
                    List(items, children: \.children) { item in
                        Button {
                            if let destination = item.destination {
                                model.go(to: destination)
                            } else if let page = item.pageIndex {
                                model.go(toPage: page)
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Text(item.title)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                if let page = item.pageIndex {
                                    Text("\(page + 1)")
                                        .font(.footnote.monospacedDigit())
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { items = OutlineItem.tree(for: model.pdf) }
    }
}
