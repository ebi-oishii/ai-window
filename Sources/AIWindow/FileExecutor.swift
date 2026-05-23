import AppKit

/// User-facing folder shortcuts that the AI can target by name.
enum FileLocation: String, CaseIterable {
    case downloads, desktop, documents, home

    var url: URL {
        let fm = FileManager.default
        switch self {
        case .downloads: return fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
                            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        case .desktop:   return fm.urls(for: .desktopDirectory,   in: .userDomainMask).first
                            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
        case .documents: return fm.urls(for: .documentDirectory,  in: .userDomainMask).first
                            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Documents")
        case .home:      return fm.homeDirectoryForCurrentUser
        }
    }

    static func from(_ raw: String) -> FileLocation? {
        let key = raw.lowercased().trimmingCharacters(in: .whitespaces)
        // Accept Japanese aliases too
        switch key {
        case "downloads", "download", "ダウンロード": return .downloads
        case "desktop", "デスクトップ":               return .desktop
        case "documents", "document", "書類", "ドキュメント": return .documents
        case "home", "ホーム", "~":                   return .home
        default: return FileLocation(rawValue: key)
        }
    }
}

struct FileExecutor {
    /// Top `limit` files (and directories) by recent modification time.
    func listRecent(in location: FileLocation, limit: Int) -> [URL] {
        let dir = location.url
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let sorted = contents.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
        return Array(sorted.prefix(max(1, limit)))
    }

    /// Format a recent-files listing into a compact string for the AI to read.
    func formatListing(_ urls: [URL], in location: FileLocation) -> String {
        if urls.isEmpty { return "\(location.rawValue) フォルダに最近のファイルはありません" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let lines = urls.enumerated().map { idx, url -> String in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                .map(f.string(from:)) ?? "?"
            return "\(idx + 1). \(url.path)  (\(date))"
        }
        return lines.joined(separator: "\n")
    }

    /// Spotlight-backed search. macOS keeps the index up to date, so this is
    /// cheap to call ad-hoc — no caching needed on our side.
    /// - parameter query: search term (filename or content depending on nameOnly)
    /// - parameter nameOnly: when true, matches against filename only (`mdfind -name`)
    /// - parameter location: restrict the search to a known folder
    /// - parameter limit: max results to return
    func searchFiles(query: String, nameOnly: Bool, location: FileLocation?, limit: Int) -> [URL] {
        var args: [String] = []
        if let location {
            args.append("-onlyin")
            args.append(location.url.path)
        }
        if nameOnly {
            args.append("-name")
            args.append(query)
        } else {
            args.append(query)
        }

        let process = Process()
        process.launchPath = "/usr/bin/mdfind"
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe() // discard
        do { try process.run() } catch { return [] }
        process.waitUntilExit()

        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
        return Array(lines.prefix(max(1, limit))).map { URL(fileURLWithPath: $0) }
    }

    /// Format a recent-files listing into a compact string for the AI to read.
    func formatSearchResults(_ urls: [URL], query: String) -> String {
        if urls.isEmpty { return "「\(query)」に一致するファイルは見つかりませんでした" }
        return urls.enumerated().map { idx, url in
            "\(idx + 1). \(url.path)"
        }.joined(separator: "\n")
    }

    /// Open a file with the default handler, or with a named app if provided.
    func openFile(path: String, withApp appName: String? = nil) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "ファイルが見つかりません: \(url.path)"
        }

        if let appName, !appName.isEmpty,
           let appURL = SystemAppLauncher.resolveAppURL(for: appName) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in
                if let error { print("[AIWindow] openFile failed: \(error)") }
            }
            return "\(appName) で \(url.lastPathComponent) を開きました"
        }

        NSWorkspace.shared.open(url)
        return "\(url.lastPathComponent) を開きました"
    }
}
