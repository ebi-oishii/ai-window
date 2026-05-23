import AppKit

struct BrowserExecutor {
    func open(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            print("[AIWindow] Invalid URL: \(urlString)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Open a URL in a specific browser by app name (e.g., "Google Chrome", "Safari", "Arc").
    /// Falls back to default browser if the named app cannot be resolved.
    func openInBrowser(_ urlString: String, appName: String) -> String {
        guard let url = URL(string: urlString) else { return "URL が不正です: \(urlString)" }
        guard let appURL = SystemAppLauncher.resolveAppURL(for: appName) else {
            NSWorkspace.shared.open(url)
            return "\(appName) が見つからなかったのでデフォルトブラウザで \(urlString) を開きました"
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in
            if let error { print("[AIWindow] openInBrowser failed: \(error)") }
        }
        return "\(appName) で \(urlString) を開きました"
    }
}

/// Resolves macOS app names → bundle URLs, and launches them.
struct SystemAppLauncher {
    /// Common spellings users might say in Japanese/English mapped to canonical app names.
    private static let aliases: [String: String] = [
        "chrome": "Google Chrome",
        "google chrome": "Google Chrome",
        "グーグルクローム": "Google Chrome",
        "クローム": "Google Chrome",
        "safari": "Safari",
        "サファリ": "Safari",
        "arc": "Arc",
        "アーク": "Arc",
        "firefox": "Firefox",
        "ファイアフォックス": "Firefox",
        "edge": "Microsoft Edge",
        "microsoft edge": "Microsoft Edge",
        "brave": "Brave Browser",
        "brave browser": "Brave Browser",
        "finder": "Finder",
        "ファインダー": "Finder",
        "terminal": "Terminal",
        "ターミナル": "Terminal",
        "iterm": "iTerm",
        "iterm2": "iTerm",
        "vscode": "Visual Studio Code",
        "vs code": "Visual Studio Code",
        "visual studio code": "Visual Studio Code",
        "cursor": "Cursor",
        "xcode": "Xcode",
        "slack": "Slack",
        "discord": "Discord",
        "zoom": "zoom.us",
        "notion": "Notion",
        "spotify": "Spotify",
        "メモ": "Notes",
        "notes": "Notes",
        "mail": "Mail",
        "メール": "Mail",
        "messages": "Messages",
        "メッセージ": "Messages",
    ]

    static func canonicalize(_ name: String) -> String {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return aliases[key] ?? name
    }

    static func resolveAppURL(for name: String) -> URL? {
        let canonical = canonicalize(name)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: canonical) {
            return url
        }
        if let path = NSWorkspace.shared.fullPath(forApplication: canonical) {
            return URL(fileURLWithPath: path)
        }
        // Fuzzy fallback: scan installed apps for the closest match
        // ("inso" → "Insomnia", "cursor" → "Cursor").
        if let fuzzy = AppInventory.bestMatch(for: canonical),
           let path = NSWorkspace.shared.fullPath(forApplication: fuzzy) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Launch app by user-friendly name. By default opens a new window — for
    /// apps that don't support `make new window` (VSCode, Slack, etc.) the
    /// AppleScript `try` block swallows the error and only `activate` runs.
    static func launch(name: String, newWindow: Bool = true) -> String {
        let canonical = canonicalize(name)
        guard resolveAppURL(for: canonical) != nil else {
            return "アプリ「\(name)」が見つかりませんでした"
        }

        let escaped = canonical.replacingOccurrences(of: "\\", with: "\\\\")
                               .replacingOccurrences(of: "\"", with: "\\\"")

        let script: String
        if newWindow {
            script = """
            tell application "\(escaped)"
                activate
                try
                    make new window
                end try
            end tell
            """
        } else {
            script = """
            tell application "\(escaped)"
                activate
            end tell
            """
        }

        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]
        do {
            try process.run()
        } catch {
            return "\(canonical) の起動に失敗しました: \(error.localizedDescription)"
        }
        return newWindow
            ? "\(canonical) を新しいウィンドウで開きました"
            : "\(canonical) を前面に出しました"
    }
}
