import Foundation

struct ShortcutCommand: Codable, Equatable {
    /// Slug used as the `/slug` token. Lowercased ASCII letters/digits only.
    let id: String
    /// Human-facing label on the chip button.
    let title: String
    /// Text prepended to the prompt to tell the AI the operation context.
    let promptContext: String
    /// Hosts that count as "this shortcut" for learning suppression.
    let hosts: [String]
    let isBuiltIn: Bool

    static let builtIns: [ShortcutCommand] = [
        ShortcutCommand(
            id: "gmail", title: "Gmail",
            promptContext: "操作対象: Gmail (https://mail.google.com)。未起動なら open_url で開いてから作業すること。",
            hosts: ["mail.google.com"], isBuiltIn: true
        ),
        ShortcutCommand(
            id: "calendar", title: "カレンダー",
            promptContext: "操作対象: Google カレンダー (https://calendar.google.com)。未起動なら open_url で開いてから作業すること。",
            hosts: ["calendar.google.com"], isBuiltIn: true
        ),
        ShortcutCommand(
            id: "drive", title: "Drive",
            promptContext: "操作対象: Google Drive (https://drive.google.com)。未起動なら open_url で開いてから作業すること。",
            hosts: ["drive.google.com"], isBuiltIn: true
        ),
        ShortcutCommand(
            id: "youtube", title: "YouTube",
            promptContext: "操作対象: YouTube (https://youtube.com)。未起動なら open_url で開いてから作業すること。",
            hosts: ["youtube.com", "www.youtube.com"], isBuiltIn: true
        ),
        ShortcutCommand(
            id: "slack", title: "Slack",
            promptContext: "操作対象: Slack (https://app.slack.com)。未起動なら open_url で開いてから作業すること。",
            hosts: ["app.slack.com", "slack.com"], isBuiltIn: true
        ),
        ShortcutCommand(
            id: "github", title: "GitHub",
            promptContext: "操作対象: GitHub (https://github.com)。未起動なら open_url で開いてから作業すること。",
            hosts: ["github.com"], isBuiltIn: true
        ),
        ShortcutCommand(
            id: "x", title: "X",
            promptContext: "操作対象: X / Twitter (https://x.com)。未起動なら open_url で開いてから作業すること。",
            hosts: ["x.com", "twitter.com"], isBuiltIn: true
        ),
        ShortcutCommand(
            id: "chatgpt", title: "ChatGPT",
            promptContext: "操作対象: ChatGPT (https://chat.openai.com)。未起動なら open_url で開いてから作業すること。",
            hosts: ["chat.openai.com", "chatgpt.com"], isBuiltIn: true
        ),
        ShortcutCommand(
            id: "notion", title: "Notion",
            promptContext: "操作対象: Notion (https://notion.so)。未起動なら open_url で開いてから作業すること。",
            hosts: ["notion.so", "www.notion.so"], isBuiltIn: true
        ),
    ]

    func matches(host: String) -> Bool {
        let h = host.lowercased()
        return hosts.contains(where: { h == $0 || h.hasSuffix("." + $0) })
    }
}
