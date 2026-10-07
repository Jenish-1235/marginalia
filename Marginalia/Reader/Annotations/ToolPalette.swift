import SwiftUI

/// Floating vertical tool rail. Monochrome: the active tool is a white disc with black glyph.
struct ToolPalette: View {
    @Bindable var model: ReaderModel

    var body: some View {
        VStack(spacing: 6) {
            ForEach(PencilTool.allCases) { tool in
                toolButton(tool)
            }

            divider

            ForEach(InkShade.allCases) { shade in
                Button { model.tools.shade = shade } label: {
                    Circle()
                        .fill(shade == .ink ? Theme.ink : Theme.inkTertiary)
                        .frame(width: 14, height: 14)
                        .padding(3)
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: model.tools.shade == shade ? 1.5 : 0))
                        .frame(width: 40, height: 32)
                }
                .accessibilityLabel(shade.title)
            }

            ForEach(PenWidth.allCases) { width in
                Button { model.tools.width = width } label: {
                    Circle()
                        .fill(model.tools.width == width ? Theme.ink : Theme.inkTertiary)
                        .frame(width: width.dotSize, height: width.dotSize)
                        .frame(width: 40, height: 26)
                }
                .accessibilityLabel("Width \(width.rawValue)")
            }

            divider

            Button { model.tools.fingerDraws.toggle() } label: {
                Image(systemName: model.tools.fingerDraws ? "hand.draw.fill" : "hand.draw")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(model.tools.fingerDraws ? Theme.ink : Theme.inkSecondary)
                    .frame(width: 40, height: 36)
            }
            .accessibilityLabel(model.tools.fingerDraws ? "Finger draws" : "Only Pencil draws")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }

    private func toolButton(_ tool: PencilTool) -> some View {
        let selected = model.tools.tool == tool
        return Button { model.tools.tool = tool } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(selected ? Theme.background : Theme.ink)
                .frame(width: 36, height: 36)
                .background(selected ? Theme.ink : .clear, in: Circle())
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel(tool.title)
    }

    private var divider: some View {
        Theme.hairline.frame(width: 24, height: 1).padding(.vertical, 4)
    }
}

struct NoteEditorSheet: View {
    let model: ReaderModel
    let mark: Highlight

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(mark.text)
                    .font(.system(.callout, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(6)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Theme.inkTertiary.frame(width: 2) }

                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Theme.ink)
            }
            .padding()
            .background(Theme.surface)
            .navigationTitle("Note · p. \(mark.page + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var updated = mark
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.note = trimmed.isEmpty ? nil : trimmed
                        if updated.note != mark.note { model.update(updated) }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            text = mark.note ?? ""
            focused = true
        }
    }
}
