import AppKit

/// Cached snapshot of installed .app names on disk. Refreshed lazily — first
/// access triggers a directory scan, subsequent calls return the cached list.
enum AppInventory {
    private static let searchDirs: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: NSHomeDirectory() + "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
    ]

    private static var cache: [String]?

    /// Sorted list of installed app display names (no `.app` suffix, deduped).
    static func names() -> [String] {
        if let cache { return cache }
        let names = scan()
        cache = names
        return names
    }

    /// Force a re-scan — useful if the user installs an app while AIWindow is running.
    static func refresh() {
        cache = scan()
    }

    private static func scan() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let fm = FileManager.default
        for dir in searchDirs {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for url in contents where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                if seen.insert(name).inserted { result.append(name) }
            }
        }
        return result.sorted()
    }

    /// Case-insensitive fuzzy match: exact > prefix > substring. Returns the
    /// best installed-app name for a user-supplied query, or nil.
    static func bestMatch(for query: String) -> String? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        let all = names()

        if let exact = all.first(where: { $0.lowercased() == q }) { return exact }
        if let prefix = all.first(where: { $0.lowercased().hasPrefix(q) }) { return prefix }
        if let contains = all.first(where: { $0.lowercased().contains(q) }) { return contains }
        return nil
    }
}
