import AppKit

/// Visual tokens for the Detroit: Become Human-inspired look.
/// Pure values — no AppKit widgets here, just colors and fonts.
enum Theme {
    /// Primary accent — electric violet, leaning toward Detroit's android-internal hues.
    static let accent     = NSColor(red: 0.63, green: 0.42, blue: 1.00, alpha: 1.0)
    static let accentDim  = NSColor(red: 0.63, green: 0.42, blue: 1.00, alpha: 0.5)
    static let accentGlow = NSColor(red: 0.63, green: 0.42, blue: 1.00, alpha: 0.18)

    /// Foreground text — soft white, never pure white.
    static let foreground = NSColor(white: 0.94, alpha: 1.0)
    static let foregroundDim = NSColor(white: 0.94, alpha: 0.55)

    /// Background overlay — sits on top of the NSVisualEffectView tint.
    static let backgroundOverlay = NSColor(red: 0.02, green: 0.04, blue: 0.07, alpha: 0.55)

    static let success = NSColor(red: 0.34, green: 0.97, blue: 0.62, alpha: 1.0)
    static let danger  = NSColor(red: 1.00, green: 0.35, blue: 0.35, alpha: 1.0)

    /// Display: condensed-feel sans-serif for body/input; monospaced for HUD lines.
    static func body(_ size: CGFloat, weight: NSFont.Weight = .light) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func hud(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
}
