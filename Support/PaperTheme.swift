import AppKit
import SwiftUI

enum PaperTheme {
    static let accent = Color(red: 0.91, green: 0.31, blue: 0.06)
    static let editorBackground = Color(red: 0.99, green: 0.99, blue: 0.98)
    static let gutterBackground = Color(red: 0.95, green: 0.95, blue: 0.94)
    static let divider = Color(red: 0.84, green: 0.84, blue: 0.83)

    // MARK: - AppKit equivalents (editor is backed by NSTextView)

    static let nsAccent = NSColor(red: 0.91, green: 0.31, blue: 0.06, alpha: 1)
    static let nsEditorBackground = NSColor(red: 0.99, green: 0.99, blue: 0.98, alpha: 1)
    static let nsGutterBackground = NSColor(red: 0.95, green: 0.95, blue: 0.94, alpha: 1)
    static let nsGutterText = NSColor(red: 0.30, green: 0.30, blue: 0.32, alpha: 1)
    static let nsDivider = NSColor(red: 0.84, green: 0.84, blue: 0.83, alpha: 1)
    static let nsEditorText = NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)
}
