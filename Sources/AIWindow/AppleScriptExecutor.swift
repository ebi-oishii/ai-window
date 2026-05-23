import Foundation

/// Generic AppleScript execution via osascript subprocess. Anything not
/// already covered by a dedicated tool (Notes, Reminders, Finder, wallpaper,
/// etc.) can be reached through here.
struct AppleScriptExecutor {
    /// 10s ceiling — well above realistic interactive scripts, well below
    /// "hung forever" annoyance.
    private static let timeoutSeconds: TimeInterval = 10

    func run(_ script: String) -> String {
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return "AppleScript 起動失敗: \(error.localizedDescription)"
        }

        // Guard against runaway scripts.
        let deadline = Date().addingTimeInterval(Self.timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return "AppleScript がタイムアウトしました (>\(Int(Self.timeoutSeconds))s)"
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "AppleScript エラー (status \(process.terminationStatus)): \(msg.isEmpty ? "(no message)" : msg)"
        }

        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "AppleScript 実行完了" : trimmed
    }
}
