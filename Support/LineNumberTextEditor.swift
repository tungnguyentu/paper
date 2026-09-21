import AppKit
import SwiftUI

/// A single-scroller editor with a scroll-synced line-number gutter.
///
/// The document is an NSTextView inside one NSScrollView; line numbers are
/// drawn by the scroll view's vertical ruler (see `LineNumberRulerView`), so
/// they always track the document and no second scrollbar can appear.
///
/// The previous implementation used two side-by-side SwiftUI `TextEditor`s,
/// which gave the gutter its own `NSScroller` (the duplicate scrollbar) and
/// never scrolled the numbers in sync with the text.
struct LineNumberTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        // Explicit TextKit 1 stack so `layoutManager` is always available
        // for the line-number ruler.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        // Width follows the view, height is unbounded and does NOT track the
        // text view — otherwise the text view can never grow past the
        // viewport and the scroll view has nothing to scroll.
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        // Explicit colors: a previous AppKit editor rendered text near-white
        // because it inherited the window appearance — never rely on defaults.
        textView.textColor = PaperTheme.nsEditorText
        textView.backgroundColor = PaperTheme.nsEditorBackground
        textView.insertionPointColor = PaperTheme.nsAccent
        textView.selectedTextAttributes = [
            .backgroundColor: PaperTheme.nsAccent.withAlphaComponent(0.22),
        ]
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.allowsUndo = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.string = text
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = PaperTheme.nsEditorBackground
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        // Keep the single scrollbar visible instead of letting it fade out, so
        // it is obvious the document scrolls and there is exactly one of them.
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder

        let ruler = LineNumberRulerView(scrollView: scrollView, textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.ruler = ruler

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.clipViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        // The scroll view is created at zero size and resized by SwiftUI
        // afterwards; re-tile on every resize so the clip view is inset for
        // the ruler instead of underlapping it.
        scrollView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidResize),
            name: NSView.frameDidChangeNotification,
            object: scrollView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only push the store value down when it actually differs (e.g. file
        // opened, new document). Never clobber an in-progress edit or IME
        // composition, and preserve the caret.
        guard textView.string != text, !textView.hasMarkedText() else { return }
        let selectedRange = textView.selectedRange()
        textView.string = text
        let clamped = NSRange(
            location: min(selectedRange.location, (text as NSString).length),
            length: 0
        )
        textView.setSelectedRange(clamped)
        context.coordinator.fitDocument()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var ruler: LineNumberRulerView?
        weak var textView: NSTextView?
        private var lastFitWidth: CGFloat = -1

        init(text: Binding<String>) {
            self.text = text
        }

        /// Grows the text view to at least the height of its content.
        ///
        /// Setting `textView.string` programmatically (opening a file, the
        /// initial document) does not resize the view — only real edits do —
        /// so without this the document never becomes taller than the viewport
        /// and the scroll view has nothing to scroll. Re-run on edits and on
        /// viewport width changes, since both change wrapped height.
        func fitDocument(force: Bool = false) {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let width = scrollView.contentSize.width
            guard width > 0, force || width != lastFitWidth else { return }
            lastFitWidth = width
            textView.frame.size.width = width
            textView.sizeToFit()
            let viewportHeight = scrollView.contentSize.height
            if textView.frame.height < viewportHeight {
                textView.frame.size.height = viewportHeight
            }
            ruler?.invalidateLineNumbers()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            fitDocument(force: true)
            ruler?.invalidateLineNumbers()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            ruler?.invalidateLineNumbers()
        }

        @objc func clipViewDidScroll() {
            ruler?.invalidateLineNumbers()
        }

        @objc func scrollViewDidResize(_ notification: Notification) {
            guard let scrollView = notification.object as? NSScrollView else { return }
            scrollView.tile()
            // The clip view's width changed with the frame, so recompute the
            // wrapped document height even though the text did not change.
            lastFitWidth = -1
            fitDocument()
        }
    }
}
