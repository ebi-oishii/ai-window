import Foundation

/// In-memory + UserDefaults-backed store of slash-command shortcuts.
/// Owns built-in catalog, learned shortcuts, usage counters, and the
/// domain-open counter that drives auto-learning.
final class ShortcutRegistry {
    static let shared = ShortcutRegistry()

    static let didChangeNotification = Notification.Name("AIWindowShortcutsDidChange")

    private let usageKey      = "AIWindow.ShortcutUsage"
    private let learnedKey    = "AIWindow.LearnedShortcuts"
    private let domainOpenKey = "AIWindow.DomainOpenCounts"

    private(set) var commands: [ShortcutCommand]
    private var usage: [String: Int]

    /// Threshold of distinct opens before a domain auto-promotes to a learned shortcut.
    private let learnThreshold = 3

    private init() {
        self.usage = (UserDefaults.standard.dictionary(forKey: usageKey) as? [String: Int]) ?? [:]
        let learned: [ShortcutCommand]
        if let data = UserDefaults.standard.data(forKey: learnedKey),
           let decoded = try? JSONDecoder().decode([ShortcutCommand].self, from: data) {
            learned = decoded
        } else {
            learned = []
        }
        let builtInIDs = Set(ShortcutCommand.builtIns.map(\.id))
        self.commands = ShortcutCommand.builtIns + learned.filter { !builtInIDs.contains($0.id) }
    }

    // MARK: - Lookup / ordering

    func command(forID id: String) -> ShortcutCommand? {
        let needle = id.lowercased()
        return commands.first { $0.id.lowercased() == needle }
    }

    /// Most-used first; ties broken by builtins before learned, then title.
    var ordered: [ShortcutCommand] {
        commands.sorted { a, b in
            let ua = usage[a.id] ?? 0
            let ub = usage[b.id] ?? 0
            if ua != ub { return ua > ub }
            if a.isBuiltIn != b.isBuiltIn { return a.isBuiltIn && !b.isBuiltIn }
            return a.title < b.title
        }
    }

    // MARK: - Usage tracking

    func recordUsage(ids: [String]) {
        guard !ids.isEmpty else { return }
        for id in ids { usage[id, default: 0] += 1 }
        UserDefaults.standard.set(usage, forKey: usageKey)
    }

    // MARK: - Auto-learning from open_url

    /// Record that a URL was opened. If the same non-shortcut host has been
    /// opened `learnThreshold` times, auto-create a learned shortcut and
    /// return it so callers can surface a notification.
    @discardableResult
    func recordOpenedURL(_ urlString: String) -> ShortcutCommand? {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return nil }
        // Already covered by an existing shortcut — nothing to learn.
        if commands.contains(where: { $0.matches(host: host) }) { return nil }

        var counts = (UserDefaults.standard.dictionary(forKey: domainOpenKey) as? [String: Int]) ?? [:]
        counts[host, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: domainOpenKey)

        guard (counts[host] ?? 0) >= learnThreshold else { return nil }

        let learned = makeLearnedShortcut(host: host)
        // Guard against collisions on the slug.
        if commands.contains(where: { $0.id.lowercased() == learned.id.lowercased() }) { return nil }

        commands.append(learned)
        persistLearned()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        return learned
    }

    private func makeLearnedShortcut(host: String) -> ShortcutCommand {
        let core = host
            .replacingOccurrences(of: "www.", with: "")
            .split(separator: ".")
            .first
            .map(String.init) ?? host
        let slug = core.lowercased().filter { $0.isLetter || $0.isNumber }
        let title = core.prefix(1).uppercased() + core.dropFirst()
        return ShortcutCommand(
            id: slug.isEmpty ? host : slug,
            title: title,
            promptContext: "操作対象: \(title) (https://\(host))。未起動なら open_url で開いてから作業すること。",
            hosts: [host],
            isBuiltIn: false
        )
    }

    private func persistLearned() {
        let learned = commands.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(learned) {
            UserDefaults.standard.set(data, forKey: learnedKey)
        }
    }
}

/// Pure parser: extracts leading `/slug` tokens from user input and
/// composes them with toggled chip IDs into a single expanded prompt.
enum ShortcutExpander {
    /// Strip leading `/slug` tokens from `input`. Returns the recognized ids
    /// (in order, deduped) and the remainder of the text.
    static func parsePrefix(_ input: String) -> (ids: [String], remaining: String) {
        var ids: [String] = []
        var seen = Set<String>()
        var rest = input.trimmingCharacters(in: .whitespaces)
        while rest.hasPrefix("/") {
            let body = rest.dropFirst() // remove leading '/'
            let endIdx = body.firstIndex(where: { $0.isWhitespace }) ?? body.endIndex
            let token = String(body[..<endIdx]).lowercased()
            guard !token.isEmpty, token.allSatisfy({ $0.isLetter || $0.isNumber }) else { break }
            if !seen.contains(token) {
                ids.append(token)
                seen.insert(token)
            }
            rest = String(body[endIdx...]).trimmingCharacters(in: .whitespaces)
        }
        return (ids, rest)
    }

    /// Build the final prompt sent to the model. `toggledIDs` are layered on
    /// top of any `/slug` typed in the input; unknown slugs are dropped.
    static func expand(input: String, toggledIDs: [String]) -> (prompt: String, activeIDs: [String]) {
        let (typedIDs, remaining) = parsePrefix(input)

        var seen = Set<String>()
        var ordered: [String] = []
        for id in toggledIDs + typedIDs {
            let key = id.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                ordered.append(key)
            }
        }

        let registry = ShortcutRegistry.shared
        let known = ordered.compactMap { registry.command(forID: $0) }
        guard !known.isEmpty else {
            return (remaining.isEmpty ? input : remaining, [])
        }

        let header = known.map(\.promptContext).joined(separator: "\n")
        let body = remaining.isEmpty ? "(指示の本文なし。上記の操作対象を開く、または現在の状況を報告する。)" : remaining
        return (header + "\n\n" + body, known.map(\.id))
    }
}
