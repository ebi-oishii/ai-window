import Foundation
import AppKit

struct SystemSettingsExecutor {
    func controlVolume(action: String, value: Int) -> String {
        let script: String
        switch action {
        case "set":
            let v = max(0, min(100, value))
            script = "set volume output volume \(v)"
        case "increase":
            let delta = max(1, value)
            script = "set volume output volume ((output volume of (get volume settings)) + \(delta))"
        case "decrease":
            let delta = max(1, value)
            script = "set volume output volume ((output volume of (get volume settings)) - \(delta))"
        case "mute":
            script = "set volume with output muted"
        case "unmute":
            script = "set volume without output muted"
        default:
            return "不明なアクション: \(action)"
        }

        var errorInfo: NSDictionary?
        _ = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)

        if let err = errorInfo {
            print("[AIWindow] AppleScript error: \(err)")
            return "音量変更に失敗しました: \(err["NSAppleScriptErrorMessage"] ?? err)"
        }
        return "音量を\(describe(action: action, value: value))しました"
    }

    private func describe(action: String, value: Int) -> String {
        switch action {
        case "set":      return "\(value) に設定"
        case "increase": return "\(value) 増加"
        case "decrease": return "\(value) 減少"
        case "mute":     return "ミュート"
        case "unmute":   return "ミュート解除"
        default:         return action
        }
    }
}
