import SwiftUI

/// A native SwiftUI editor with a visible, high-contrast line-number gutter.
/// SwiftUI owns text rendering, avoiding the AppKit appearance conflict that
/// made the previous editor content unreadable.
struct LineNumberTextEditor: View {
    @Binding var text: String

    private var lineCount: Int {
        max(text.components(separatedBy: .newlines).count, 1)
    }

    private var lineNumbers: String {
        (1...lineCount).map(String.init).joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 0) {
            TextEditor(text: .constant(lineNumbers))
                .font(.system(size: 16, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(red: 0.30, green: 0.30, blue: 0.32))
                .multilineTextAlignment(.trailing)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            .frame(width: 58)
            .background(Color(red: 0.95, green: 0.95, blue: 0.94))

            Rectangle()
                .fill(Color(red: 0.84, green: 0.84, blue: 0.83))
                .frame(width: 1)

            TextEditor(text: $text)
                .font(.system(size: 16, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.09))
                .tint(Color(red: 0.20, green: 0.38, blue: 0.82))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.99, green: 0.99, blue: 0.98))
        }
        .accessibilityElement(children: .contain)
    }
}
