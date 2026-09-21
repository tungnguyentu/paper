# Editor UI Troubleshooting

This note records the fixes for editor UI problems encountered while building Paper.

## Text appears white or extremely faint

### Symptom

The document background is light, but existing and newly typed text is almost white and difficult to read.

### Cause

The first line-number implementation wrapped `NSTextView` with `NSViewRepresentable`. Its foreground attributes and effective appearance did not render consistently inside the SwiftUI window. Reapplying `textColor`, typing attributes, and text-storage attributes did not resolve the problem reliably.

### Working fix

Use SwiftUI's native `TextEditor` for document editing and set an explicit foreground and background:

```swift
TextEditor(text: $text)
    .font(.system(size: 16, weight: .regular, design: .monospaced))
    .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.09))
    .scrollContentBackground(.hidden)
    .background(Color(red: 0.99, green: 0.99, blue: 0.98))
```

Do not restore the former AppKit editor without first verifying text contrast in the running app.

**Update (2026-09-21):** the editor is AppKit-backed again (see "Duplicate
scrollbars" below). The near-white-text regression was avoided this time by
setting `textColor`, `backgroundColor`, `insertionPointColor`, and selection
attributes explicitly on the `NSTextView` instead of relying on inherited
appearance (see `Support/LineNumberTextEditor.swift`). Any future change to
editor colors must re-verify strong contrast in the running app, light and
dark mode.

## Line numbers do not align with document rows

### Symptom

Line numbers and document text have the same nominal font size, but their baselines drift or appear several points apart. Adjusting top padding only moves the mismatch and is fragile across font metrics and display scaling.

### Cause

The gutter originally used `Text` inside a `ScrollView`, while the document used `TextEditor`. Those controls use different internal text layout, padding, and baseline metrics.

### Working fix

Render the line-number gutter with a second, non-interactive `TextEditor`. Give both editors the same font and vertical padding so they use identical layout metrics:

```swift
TextEditor(text: .constant(lineNumbers))
    .font(.system(size: 16, weight: .regular, design: .monospaced))
    .multilineTextAlignment(.trailing)
    .scrollContentBackground(.hidden)
    .padding(.vertical, 8)
    .allowsHitTesting(false)

TextEditor(text: $text)
    .font(.system(size: 16, weight: .regular, design: .monospaced))
    .scrollContentBackground(.hidden)
    .padding(.vertical, 8)
```

Avoid fixing baseline mismatches with a guessed `.padding(.top, ...)` value. Matching the rendering control and its font metrics is more reliable.

## Duplicate scrollbars (editor shows two vertical scrollbars)

### Symptom

A second scrollbar appears inside the line-number gutter, next to the main
editor scrollbar.

### Cause

The gutter was a second, non-interactive SwiftUI `TextEditor`. Every
`TextEditor` is backed by its own `NSScrollView`, so the gutter rendered its
own `NSScroller`. `.allowsHitTesting(false)` blocks mouse input but does not
remove the scroller, and SwiftUI offers no modifier that strips a
`TextEditor`'s scroller on macOS 14. As a side effect, the gutter also never
scrolled in sync with the document, so line numbers drifted on long files.

### Working fix

Use a single `NSTextView` inside one `NSScrollView` (`NSViewRepresentable`)
and draw line numbers in the scroll view's vertical ruler:

- `Support/LineNumberRulerView.swift` — `NSRulerView` subclass that draws one
  number per paragraph at the matching line-fragment y, so wrapped lines are
  not renumbered and numbers track scrolling natively.
- `Support/LineNumberTextEditor.swift` — builds an explicit TextKit 1
  text stack (`NSTextStorage` → `NSLayoutManager` → `NSTextContainer`) so the
  ruler always has a layout manager; configures one scroll view with
  `hasVerticalScroller = true` / `hasHorizontalScroller = false`.
- `updateNSView` only pushes the store value down when it differs, preserves
  the caret, and skips while `hasMarkedText()` (IME composition).
- `Support/PaperTheme.swift` exposes `NSColor` equivalents so AppKit drawing
  matches the SwiftUI theme exactly.

Two `NSRulerView` gotchas found while implementing this (2026-09-21, verified
with screenshots and pixel sampling):

- Overriding `draw(_:)` without `super` stops `drawHashMarksAndLabels(in:)`
  from ever being called — the base `NSRulerView.draw(_:)` is what invokes
  it. The ruler subclass must call `drawHashMarksAndLabels(in:)` explicitly.
- Never fill `dirtyRect` in the ruler's `draw(_:)`. AppKit handed the ruler a
  dirty rect the size of the whole window, and filling it painted over the
  entire editor. Always fill `bounds` instead.
- Only draw a trailing-empty-line number when the string actually ends with a
  newline; otherwise a document without a trailing newline gains a phantom
  extra number.

### Document cannot scroll (no scrollbar at all)

A separate regression followed the ruler rewrite: the editor showed no
scrollbar and could not scroll.

Two causes:

- The `NSTextView` was created with an explicit `NSTextContainer` but without
  the resizable sizing configuration, so AppKit clamped `maxSize` to the
  viewport (`MinSize = MaxSize = {969, 660}` in a runtime dump) and the
  document could never grow past one screen. The text stack must set
  `textContainer.heightTracksTextView = false`,
  `textContainer.containerSize.height = CGFloat.greatestFiniteMagnitude`,
  `textView.minSize = .zero`, and
  `textView.maxSize = (CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude)`.
- Assigning `textView.string` programmatically (opening a file, the initial
  document) does **not** resize the text view — only real user edits do. A
  loaded document therefore stayed one viewport tall. `Coordinator.fitDocument()`
  fixes this by setting the text view width to the clip width, calling
  `sizeToFit()`, and clamping the height to at least the viewport; it runs on
  load (`updateNSView`), on `textDidChange`, and on viewport resize.

Also set `scrollView.autohidesScrollers = false` so the single remaining
scrollbar stays visible instead of fading out, which is what made it look like
both scrollbars had disappeared.

Both were verified with a standalone AppKit harness (document height 400 →
2816 for 200 lines) and end to end in the app (paste 200 lines, `⌘↓`: view
scrolled to line 200 with the gutter aligned).

Do not reintroduce a second scrollable control for the gutter. If the gutter
must be changed, keep the numbers inside the same scroll view's ruler.

## Verification

After changing either editor, rebuild and launch through:

```bash
./script/build_and_run.sh --verify
```

Visually check a document containing consecutive one-character lines and blank lines. Each number should remain on the same baseline as its corresponding document row, and all document text should have strong contrast against the editor background.

Additionally, after the ruler rewrite, check:

- Exactly one scrollbar is visible (the editor's).
- A multi-screen document actually scrolls, including right after opening a
  file (not only after typing).
- Line numbers stay aligned with document rows while scrolling.
- Wrapped lines show a single number; a trailing newline shows one extra number.
- Caret and selection stay stable while typing, opening files, and creating new documents.

## Current implementation

The editor is an `NSTextView` in a single `NSScrollView`, exposed to SwiftUI
as `LineNumberTextEditor` (`NSViewRepresentable`) in
`Support/LineNumberTextEditor.swift`. Line numbers are drawn by
`Support/LineNumberRulerView.swift`. Theme colors live in
`Support/PaperTheme.swift` (both `Color` and `NSColor` variants).

## Appearance and dark mode

Every `PaperTheme` token is a dynamic `NSColor` with a light and a dark value,
bridged to SwiftUI with `Color(nsColor:)`. Three rules keep the editor
adapting correctly:

- **Dynamic colors resolve at draw time.** AppKit resolves them against
  `NSAppearance.current`, which Cocoa sets automatically inside `draw(_:)`,
  `layout()`, `updateConstraints()`, and `updateLayer()`. The line-number
  ruler already fills inside `draw(_:)`, so it adapts with no extra plumbing.
- **Never store a resolved `CGColor`.** A `CGColor` captured from an `NSColor`
  is a fixed value and will not follow an appearance change. Assign `NSColor`
  and let drawing resolve it.
- **Never read a dynamic color's components outside a drawing context.** Doing
  so resolves the color against whatever appearance happened to be current at
  that moment — the cause of the classic "launched in dark mode, painted
  light" bug. When a component value is genuinely needed outside drawing, wrap
  the read in `NSAppearance.performAsCurrentDrawingAppearance(_:)`.

`usesAdaptiveColorMappingForDarkAppearance` stays **off**. It maps
component-based colors by inverting brightness, which fights the hand-authored
dark palette rather than using it.

Vibrant and high-contrast appearance names (`.vibrantDark`,
`.accessibilityHighContrastDarkAqua`, and their light counterparts) are matched
explicitly in the token provider, so a window drawn with vibrancy never falls
back to the light value.

### Verifying dark mode

`Tests/PaperTests/PaperThemeTests.swift` resolves each token under the light
and dark appearances and asserts the light values are unchanged, the dark
palette is ordered correctly, and body text, line numbers, and the caret clear
their contrast thresholds. Run it with:

```bash
swift test
```

Contrast is also worth an eye check: launch in dark appearance, open a
multi-screen document, and confirm the canvas, gutter, divider, status bar,
caret, and selection all read correctly, then switch appearance with text
selected.


## Unsaved work recovery

Paper keeps an app-managed recovery copy of the in-progress document under
`Application Support/<bundle id>/recovery/` (`Stores/RecoveryStore.swift`).
It holds the document text plus the title, the file it came from when it had
one, a content digest of that file, and when the copy was last written. The
copy is plain JSON and is **not encrypted**.

Rules that must stay true:

- **Quitting is not a discard event.** The copy is discarded only when the
  document is saved, the user explicitly discards it, or the document is
  replaced. Every path that clears the modified flag routes through one
  funnel in `Stores/DocumentStore.swift`; a new path that clears the flag
  without going through it will strand a copy and resurrect stale text.
- **Only a graceful quit runs the termination path.** Quitting from the menu,
  ⌘Q, logout, or restart delivers an Apple event, so `applicationWillTerminate`
  flushes a final capture and removes the sentinel. Signals (`kill`, `pkill`,
  force-quit) do not — the process dies without the hook running, which is
  correct: the sentinel stays and the next launch treats it as an unexpected
  exit. Never use `pkill` to simulate a clean quit when verifying recovery.
- **Recovered copies never expire.** They re-announce on every launch until
  they are saved or discarded. Dismissing the notice hides it without
  discarding; discarding lives in the overflow menu behind its own
  confirmation.
- **The sentinel is notice wording only.** `Stores/LaunchSentinel.swift`
  records whether the last session ended gracefully. Nothing about the copy's
  existence, restoration, or discard may depend on it.
- **The digest is checked twice and never refreshed.** It is compared at
  restore and again immediately before every save to an attached path; a
  mismatch detaches the document instead of writing. Captures must never
  recompute it, or an external change would be absorbed into the check.

### Proving recovery still works

Type without saving, then `pkill -9 -x Paper` (crash) or quit normally
(clean exit). Relaunch: the text must return marked as modified in both
cases. Then save and relaunch again: no restore, no leftover copy.
