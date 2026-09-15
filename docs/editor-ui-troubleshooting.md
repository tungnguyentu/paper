# Editor UI Troubleshooting

This note records the fixes for two editor UI problems encountered while building Paper.

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

## Verification

After changing either editor, rebuild and launch through:

```bash
./script/build_and_run.sh --verify
```

Visually check a document containing consecutive one-character lines and blank lines. Each number should remain on the same baseline as its corresponding document row, and all document text should have strong contrast against the editor background.

## Current implementation

The editor and gutter are implemented in `Support/LineNumberTextEditor.swift`.
