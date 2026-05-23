import Foundation

/// A rule auto-extracted by the reflection LLM call after a successful task.
struct LearnedRule: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let createdAt: Date
    var usageCount: Int

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.usageCount = 0
    }
}

/// Persists self-learned rules to JSON and injects them into the system prompt.
final class LearnedRulesStore {
    static let shared = LearnedRulesStore()

    static let didChangeNotification = Notification.Name("AIWindowLearnedRulesDidChange")

    private let fileURL: URL
    private let maxRules = 30
    private(set) var rules: [LearnedRule]

    private init() {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("AIWindow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("learned_rules.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([LearnedRule].self, from: data) {
            self.rules = decoded
        } else {
            self.rules = []
        }
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Dedupe on exact text — reflection can land on the same rule twice
        if rules.contains(where: { $0.text == trimmed }) { return }

        rules.append(LearnedRule(text: trimmed))
        if rules.count > maxRules {
            // Drop oldest to keep prompt size bounded
            rules.removeFirst(rules.count - maxRules)
        }
        persist()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        persist()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func clear() {
        rules.removeAll()
        persist()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rules) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Section appended to the base system prompt. Empty string if no rules yet.
    var promptSection: String {
        guard !rules.isEmpty else { return "" }
        let lines = rules.map { "- \($0.text)" }.joined(separator: "\n")
        return """


        過去の使用から自動学習したルール（同等の指示が来たらこれに従うこと）:
        \(lines)
        """
    }
}
