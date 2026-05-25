import Foundation

enum InputHistoryStore {
    private static let key = "AIWindow.InputHistory"
    private static let maxItems = 80

    static var entries: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var values = entries.filter { $0 != trimmed }
        values.append(trimmed)
        if values.count > maxItems {
            values.removeFirst(values.count - maxItems)
        }
        UserDefaults.standard.set(values, forKey: key)
    }
}
