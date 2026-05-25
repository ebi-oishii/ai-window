import AppKit

struct KeyboardExecutor {
    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    /// Paste text into the target/frontmost app and optionally press Return.
    /// Pasting through the clipboard is more reliable for Japanese text than
    /// AppleScript's `keystroke "<text>"`.
    func pasteText(_ text: String, appName: String?, pressReturn: Bool) -> String {
        let trimmedApp = appName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetApp = (trimmedApp?.isEmpty == false) ? trimmedApp : nil

        if let targetApp {
            _ = SystemAppLauncher.launch(name: targetApp, newWindow: false)
            Thread.sleep(forTimeInterval: 0.35)
        }

        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let script = """
        tell application "System Events"
            keystroke "v" using command down
            delay 0.08
            \(pressReturn ? "key code 36" : "")
        end tell
        """

        var errorInfo: NSDictionary?
        _ = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)

        Thread.sleep(forTimeInterval: 0.12)
        restorePasteboard(pasteboard, snapshot: snapshot)

        if let err = errorInfo {
            return "入力に失敗しました: \(err["NSAppleScriptErrorMessage"] ?? err)"
        }

        let destination = targetApp ?? "前面アプリ"
        return pressReturn
            ? "\(destination) にテキストを貼り付けて送信しました"
            : "\(destination) にテキストを貼り付けました"
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        guard let pasteboardItems = pasteboard.pasteboardItems else {
            return PasteboardSnapshot(items: [])
        }
        let items: [[NSPasteboard.PasteboardType: Data]] = pasteboardItems.map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    values[type] = data
                }
            }
            return values
        }
        return PasteboardSnapshot(items: items)
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }

        let restoredItems = snapshot.items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}
