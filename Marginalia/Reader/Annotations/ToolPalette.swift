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

            // Two swatches per row keeps the rail narrow.
            VStack(spacing: 2) {
                ForEach(Array(stride(from: 0, to: InkColor.allCases.count, by: 2)), id: \.self) { start in
                    HStack(spacing: 0) {
                        ForEach(InkColor.allCases[start..<min(start + 2, InkColor.allCases.count)]) { ink in
                            swatch(ink)
                        }
                    }
                }
            }
            .padding(.vertical, 2)

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

            Button { model.tools.fingerSelects.toggle() } label: {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(model.tools.fingerSelects ? Theme.background : Theme.inkSecondary)
                    .frame(width: 32, height: 32)
                    .background(model.tools.fingerSelects ? Theme.ink : .clear, in: Circle())
                    .frame(width: 40, height: 36)
            }
            .accessibilityLabel("Finger Text Selection")
            .accessibilityValue(model.tools.fingerSelects ? "On" : "Off")

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

    /// Picking a colour also switches to the pen, since only the pen uses it.
    private func swatch(_ ink: InkColor) -> some View {
        let selected = model.tools.color == ink
        return Button {
            model.tools.color = ink
            model.tools.tool = .pen
        } label: {
            Circle()
                .fill(Color(ink.color))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .frame(width: 14, height: 14)
                .padding(2.5)
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: selected ? 1.5 : 0))
                .frame(width: 20, height: 22)
        }
        .accessibilityLabel("\(ink.title) ink")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
