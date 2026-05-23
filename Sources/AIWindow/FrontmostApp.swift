import AppKit
import ApplicationServices

/// Snapshot of what the user is looking at right now. Used as context for
/// every dispatch so the AI knows "Excel is open with foo.xlsx in front"
/// without the user having to spell it out.
struct FrontmostContext {
    let appName: String?
    let bundleID: String?
    let windowTitle: String?

    /// Best-effort grab. Never throws — missing pieces just become nil.
    static func capture() -> FrontmostContext {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let title = focusedWindowTitle(for: frontApp)
        return FrontmostContext(
            appName: frontApp?.localizedName,
            bundleID: frontApp?.bundleIdentifier,
            windowTitle: title
        )
    }

    /// One-line summary suitable for prepending to a user prompt.
    /// Returns nil if we couldn't determine anything useful.
    var promptLine: String? {
        guard let app = appName, !app.isEmpty else { return nil }
        if app == "AIWindow" { return nil } // The panel itself — not useful
        if let title = windowTitle, !title.isEmpty {
            return "[現在前面のアプリ: \(app) — \"\(title)\"]"
        }
        return "[現在前面のアプリ: \(app)]"
    }

    /// AXUIElement-based lookup. Requires Accessibility permission, which the
    /// app already has for the CGEventTap. Falls back to nil on any failure.
    private static func focusedWindowTitle(for app: NSRunningApplication?) -> String? {
        guard let pid = app?.processIdentifier else { return nil }
        let element = AXUIElementCreateApplication(pid)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else { return nil }
        // swiftlint:disable:next force_cast
        let windowEl = window as! AXUIElement

        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowEl, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        return titleRef as? String
    }
}
