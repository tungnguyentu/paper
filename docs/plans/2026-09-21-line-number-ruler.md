# Plan: Fix duplicate scrollbar via `NSTextView` + line-number `NSRulerView`

## Problem

`Support/LineNumberTextEditor.swift` composes the editor from **two independent
`TextEditor`s**:

- `LineNumberTextEditor.swift:19` — the gutter is a full `TextEditor`, i.e. its
  own `NSScrollView` with its own `NSScroller` → the **left** scrollbar.
- `LineNumberTextEditor.swift:35` — the real editor → the **right** scrollbar.

`.allowsHitTesting(false)` (line 26) blocks mouse input but does **not** remove
the gutter's scroller. There is no SwiftUI modifier that strips a
`TextEditor`'s scroller on macOS 14.

Secondary defect: the gutter is non-interactive, so it never scroll-syncs with
the document — line numbers drift out of alignment on long files.

## Approach

Make the editor a single AppKit scroll view whose line numbers live in the
scroll view's vertical ruler. One scrollbar, native scroll sync.

## Changes

### 1. `Support/PaperTheme.swift`

Add `NSColor` equivalents (`editorBackground`, `gutterBackground`, `divider`,
`accent`, gutter text color) so AppKit drawing matches the SwiftUI theme.

### 2. `Support/LineNumberRulerView.swift` (new)

`final class LineNumberRulerView: NSRulerView`

- `init(scrollView:textView:)`, `orientation = .verticalRuler`,
  `isFlipped = true`, `ruleThickness = 58`.
- `draw(_:)`: fill gutter background, draw 1px right divider.
- `drawHashMarksAndLabels(in:)`:
  - Visible char range from `scrollView.contentView.bounds` → text coordinates.
  - Enumerate paragraphs via
    `NSString.getParagraphStart:end:contentsEnd:forRange:` so wrapped lines get
    only one number.
  - y from `layoutManager.boundingRect(forGlyphRange:in:)`, converted via
    `convert(_, from: textView)`.
  - Right-aligned monospaced 16pt numbers; paragraph index derived from newlines
    before the visible range so scrolling stays correct.
  - Handle trailing-newline empty line.

### 3. `Support/LineNumberTextEditor.swift` (rewrite)

Convert to `NSViewRepresentable`. Public signature
`LineNumberTextEditor(text: Binding<String>)` stays unchanged, so
`Views/EditorView.swift` is untouched.

- Build TextKit 1 stack explicitly (`NSTextStorage` → `NSLayoutManager` →
  `NSTextContainer`) to guarantee `layoutManager` availability.
- `NSTextView`: monospaced 16; `textColor` dark; `backgroundColor` =
  editorBackground; `insertionPointColor` = accent; `isRichText = false`; smart
  substitutions/spelling off; `allowsUndo = true`; `textContainerInset` =
  H12/V8 (matches current padding).
- `NSScrollView`: `hasVerticalScroller = true`, `hasHorizontalScroller = false`,
  `autohidesScrollers = true`, `hasVerticalRuler = true`, `rulersVisible = true`.
  This is the only view with a scroller.
- `Coordinator: NSObject, NSTextViewDelegate` (`@MainActor`):
  - `textDidChange` → `binding.wrappedValue = textView.string` (drives
    `store.textDidChange` → dirty state).
  - `textViewDidChangeSelection` → ruler redraw.
  - Observe clip-view `boundsDidChangeNotification`
    (`postsBoundsChangedNotifications = true`) → `ruler.needsDisplay = true`.
- `updateNSView`: set `string` only when `textView.string != text`, preserving
  `selectedRange`, skipping while `hasMarkedText()` (IME). Prevents cursor
  jumps from the store round-trip and edit loops.

### 4. `docs/editor-ui-troubleshooting.md`

Update "Current implementation"; document the two-`TextEditor` →
duplicate-`NSScroller` + no-scroll-sync defects and this replacement; re-affirm
the contrast verification from the earlier AppKit regression.

## Edge cases

Trailing newline, wrapped paragraphs, IME marked text, undo, store round-trip
selection preservation, long files (only visible fragments drawn).

## Verification

1. `swift build`
2. `./script/build_and_run.sh --verify` (process stays up)
3. Manual: exactly one scrollbar; numbers aligned while scrolling;
   blank/wrapped lines; strong text contrast; caret/selection visible;
   light + dark mode.
4. Rebuild, copy `dist/Paper.app` → `/Applications/Paper.app`, relaunch.

## Risk / rollback

Primary risk: previously-observed near-white AppKit text; mitigated by explicit
`textColor`/`backgroundColor`/`insertionPointColor`. Rollback:
`git checkout Support/LineNumberTextEditor.swift` (and delete the new ruler
file) to restore the SwiftUI version.
