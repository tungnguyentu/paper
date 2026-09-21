import AppKit
import SwiftUI

struct EditorView: View {
    @Bindable var store: DocumentStore

    var body: some View {
        VStack(spacing: 0) {
            if store.isRecovered && !store.recoveryNoticeDismissed {
                RecoveryNotice(store: store)
            }

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

/// A slim strip naming recovered unsaved work. It carries one action,
/// Dismiss, which hides the strip without discarding anything; discarding
/// lives in the overflow menu so it stays reachable after dismissal.
private struct RecoveryNotice: View {
    @Bindable var store: DocumentStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: store.recoveredAfterUnexpectedExit ? "exclamationmark.triangle" : "arrow.uturn.backward.circle")
                .foregroundStyle(store.recoveredAfterUnexpectedExit ? .orange : .secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(titleText)
                    .font(.system(size: 12, weight: .semibold))
                Text(detailText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Dismiss") {
                store.recoveryNoticeDismissed = true
            }
            .buttonStyle(.link)
            .help("Hide this notice; the recovered work stays")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titleText). \(detailText)")
        .accessibilityHint("Dismiss hides this notice without discarding the recovered work")
        .onAppear {
            guard !store.recoveryAnnouncementPosted else { return }
            store.recoveryAnnouncementPosted = true
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: "\(titleText). \(detailText)"]
            )
        }
    }

    private var titleText: String {
        store.recoveredAfterUnexpectedExit ? "Paper quit unexpectedly" : "Recovered unsaved work"
    }

    private var detailText: String {
        var text = store.recoveredAfterUnexpectedExit
            ? "Your unsaved work was recovered."
            : "Your unsaved changes are back."
        if store.fileURL == nil, let source = store.recoveredSourcePath {
            text += " Detached from \(URL(fileURLWithPath: source).lastPathComponent); saving will ask where to put it."
        }
        return text
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
