import AppKit

/// Text-only clipboard for now. Images / files come later if needed.
struct ClipboardExecutor {
    func read() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }

    func write(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
