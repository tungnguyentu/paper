import SwiftUI

struct EditorView: View {
    @Bindable var store: DocumentStore

    var body: some View {
        VStack(spacing: 0) {
            LineNumberTextEditor(
                text: Binding(get: { store.text }, set: store.textDidChange)
            )

            HStack {
                Text("Plain Text")
                Spacer()
                Text("\(store.lineCount) lines  •  \(store.wordCount) words")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
