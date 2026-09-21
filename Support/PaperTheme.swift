import AppKit
import SwiftUI

/// Paper's color palette.
///
/// Every token is one dynamic color that resolves to a light or dark value for
/// the appearance it is drawn in. AppKit resolves dynamic colors at draw time
/// against `NSAppearance.current`, which Cocoa sets inside `draw(_:)`,
/// `layout()`, `updateConstraints()`, and `updateLayer()` — so the editor and
/// the line-number ruler adapt without any appearance-change plumbing.
///
/// Two rules keep that working:
///
/// - never store a resolved `CGColor` — it does not adapt to appearance; and
/// - never read a dynamic color's components outside a drawing context, or it
///   resolves against whatever appearance happened to be current at that
///   moment, which is what makes an app paint light after launching in dark.
enum PaperTheme {

    // MARK: - Light palette

    private static let lightAccent = NSColor(srgbRed: 0.91, green: 0.31, blue: 0.06, alpha: 1)
    private static let lightEditorBackground = NSColor(srgbRed: 0.99, green: 0.99, blue: 0.98, alpha: 1)
    private static let lightGutterBackground = NSColor(srgbRed: 0.95, green: 0.95, blue: 0.94, alpha: 1)
    private static let lightGutterText = NSColor(srgbRed: 0.30, green: 0.30, blue: 0.32, alpha: 1)
    private static let lightDivider = NSColor(srgbRed: 0.84, green: 0.84, blue: 0.83, alpha: 1)
    private static let lightEditorText = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1)

    // MARK: - Dark palette (warm, paper-like — deliberately not a neutral gray)

    private static let darkAccent = NSColor(srgbRed: 0.98, green: 0.45, blue: 0.20, alpha: 1)
    private static let darkEditorBackground = NSColor(srgbRed: 0.10, green: 0.094, blue: 0.086, alpha: 1)
    private static let darkGutterBackground = NSColor(srgbRed: 0.145, green: 0.137, blue: 0.127, alpha: 1)
    private static let darkGutterText = NSColor(srgbRed: 0.62, green: 0.605, blue: 0.585, alpha: 1)
    private static let darkDivider = NSColor(srgbRed: 0.22, green: 0.21, blue: 0.20, alpha: 1)
    private static let darkEditorText = NSColor(srgbRed: 0.93, green: 0.925, blue: 0.915, alpha: 1)

    // MARK: - AppKit tokens (editor and line-number ruler draw with these)

    static let nsAccent = adaptive(light: lightAccent, dark: darkAccent)
    static let nsEditorBackground = adaptive(light: lightEditorBackground, dark: darkEditorBackground)
    static let nsGutterBackground = adaptive(light: lightGutterBackground, dark: darkGutterBackground)
    static let nsGutterText = adaptive(light: lightGutterText, dark: darkGutterText)
    static let nsDivider = adaptive(light: lightDivider, dark: darkDivider)
    static let nsEditorText = adaptive(light: lightEditorText, dark: darkEditorText)

    // MARK: - SwiftUI tokens

    static let accent = Color(nsColor: nsAccent)
    static let editorBackground = Color(nsColor: nsEditorBackground)
    static let gutterBackground = Color(nsColor: nsGutterBackground)
    static let divider = Color(nsColor: nsDivider)

    // MARK: - Adaptive color construction

    /// One token, two values. `bestMatch(from:)` is AppKit's own dark-mode
    /// test: it ranks the vibrant and high-contrast appearance names under
    /// their base names, so a window drawn with vibrancy resolves dark rather
    /// than falling back to light.
    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}
