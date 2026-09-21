import AppKit

/// Vertical ruler that draws a line number per paragraph of an NSTextView.
///
/// Drawing inside the scroll view's ruler keeps the numbers scroll-synced with
/// the document, and only this ruler's document view (the single
/// NSScrollView) owns a scroller — so the editor shows exactly one scrollbar.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    private let lineNumberFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    private lazy var numberAttributes: [NSAttributedString.Key: Any] = [
        .font: lineNumberFont,
        .foregroundColor: PaperTheme.nsGutterText,
    ]

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = 58
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    /// Redraw the gutter; called on text, selection, and scroll changes.
    func invalidateLineNumbers() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Fill bounds, never dirtyRect: AppKit can hand this view a dirty
        // rect larger than its frame (observed: full window size), and
        // filling it paints over the entire editor.
        PaperTheme.nsGutterBackground.setFill()
        bounds.fill()

        // NSRulerView's base draw(_:) is what invokes
        // drawHashMarksAndLabels(in:); since this overrides draw(_:) without
        // super, the labels must be drawn explicitly. Pass bounds rather
        // than dirtyRect for the same over-large-dirty-rect reason.
        drawHashMarksAndLabels(in: bounds)

        let dividerRect = NSRect(
            x: bounds.maxX - 1,
            y: bounds.minY,
            width: 1,
            height: bounds.height
        )
        PaperTheme.nsDivider.setFill()
        dividerRect.fill()
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard
            let textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return }

        let string = textView.string as NSString

        // An empty document still shows line 1 at the top.
        guard string.length > 0 else {
            drawNumber(1, atTextViewY: textView.textContainerOrigin.y, lineHeight: lineNumberFontLineHeight(), in: rect)
            return
        }

        // Visible glyph range, in text-view coordinates.
        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Line number of the first visible paragraph.
        var lineNumber = 1
        if charRange.location > 0 {
            string.enumerateSubstrings(
                in: NSRange(location: 0, length: charRange.location),
                options: [.byParagraphs, .substringNotRequired]
            ) { _, _, _, _ in lineNumber += 1 }
        }

        // Draw one number per paragraph (wrapped lines are not renumbered).
        var paragraphStart = 0
        var paragraphEnd = 0
        var contentsEnd = 0
        string.getParagraphStart(&paragraphStart, end: &paragraphEnd, contentsEnd: &contentsEnd, for: charRange)
        let visibleEnd = NSMaxRange(charRange)
        // A position past the last character is only a real (empty) line
        // when the string ends with a newline.
        let endsWithNewline = (UnicodeScalar(string.character(at: string.length - 1)).map(CharacterSet.newlines.contains) ?? false)

        var index = paragraphStart
        while index <= visibleEnd {
            let y: CGFloat
            let height: CGFloat
            if index < string.length {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
                var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                // Line fragment rects are relative to the text container;
                // textContainerOrigin already includes textContainerInset.
                lineRect.origin.x += textView.textContainerOrigin.x
                lineRect.origin.y += textView.textContainerOrigin.y
                y = convert(lineRect.origin, from: textView).y
                height = lineRect.height
            } else {
                // Past the last character: only draw when the string ends
                // with a newline (trailing empty line). It has no glyphs, so
                // place it directly below the last fragment.
                guard endsWithNewline else { break }
                let lastGlyph = layoutManager.glyphIndexForCharacter(at: string.length - 1)
                var lastRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
                lastRect.origin.x += textView.textContainerOrigin.x
                lastRect.origin.y += textView.textContainerOrigin.y
                y = convert(lastRect.origin, from: textView).y + lastRect.height
                height = lastRect.height
            }

            drawNumber(lineNumber, atRulerY: y, lineHeight: height, in: rect)

            lineNumber += 1
            var start = 0
            var end = 0
            var endOfContents = 0
            string.getParagraphStart(&start, end: &end, contentsEnd: &endOfContents, for: NSRange(location: index, length: 0))
            if end == index { break } // Defensive: paragraph range did not advance.
            index = end
        }
    }

    private func lineNumberFontLineHeight() -> CGFloat {
        lineNumberFont.ascender - lineNumberFont.descender + lineNumberFont.leading
    }

    /// Draws a right-aligned number whose baseline matches a document row.
    /// `y` is in ruler coordinates; provide either text-view or ruler coords.
    private func drawNumber(_ number: Int, atTextViewY y: CGFloat, lineHeight: CGFloat, in rect: NSRect) {
        guard let textView else { return }
        drawNumber(number, atRulerY: convert(NSPoint(x: 0, y: y), from: textView).y, lineHeight: lineHeight, in: rect)
    }

    private func drawNumber(_ number: Int, atRulerY y: CGFloat, lineHeight: CGFloat, in rect: NSRect) {
        guard y + lineHeight >= rect.minY, y <= rect.maxY else { return }
        let label = "\(number)"
        let labelSize = label.size(withAttributes: numberAttributes)
        let labelRect = NSRect(
            x: ruleThickness - labelSize.width - 8,
            y: y + (lineHeight - labelSize.height) / 2,
            width: labelSize.width,
            height: labelSize.height
        )
        label.draw(in: labelRect, withAttributes: numberAttributes)
    }
}
