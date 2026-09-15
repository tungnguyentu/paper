import SwiftUI

struct EditorView: View {
    @Bindable var store: DocumentStore

    var body: some View {
        VStack(spacing: 0) {
            LineNumberTextEditor(
                text: Binding(get: { store.text }, set: store.textDidChange)
            )

            EditorStatusBar(lineCount: store.lineCount, wordCount: store.wordCount)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(PaperTheme.editorBackground)
    }
}

private struct EditorStatusBar: View {
    let lineCount: Int
    let wordCount: Int

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                statusContent
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
            } else {
                statusContent
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5)
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statusContent: some View {
        HStack(spacing: 10) {
            Label("Plain Text", systemImage: "doc.plaintext")

            Spacer()

            Text("UTF-8")
            Divider()
                .frame(height: 12)
            Text("\(lineCount) \(lineCount == 1 ? "line" : "lines")")
            Divider()
                .frame(height: 12)
            Text("\(wordCount) \(wordCount == 1 ? "word" : "words")")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
    }
}
