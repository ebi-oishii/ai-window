import Foundation

/// Two-mode UI selector. `.normal` is the existing Detroit dark HUD;
/// `.easy` is the beginner-friendly light layout with suggestion buttons.
enum UIMode: String, CaseIterable {
    case normal
    case easy

    var displayName: String {
        switch self {
        case .normal: return "通常モード"
        case .easy:   return "簡単モード"
        }
    }

    private static let defaultsKey = "AIWindow.UIMode"

    static var current: UIMode {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? UIMode.normal.rawValue
            return UIMode(rawValue: raw) ?? .normal
        }
        set {
            let old = current
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            if old != newValue {
                NotificationCenter.default.post(name: .uiModeDidChange, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let uiModeDidChange = Notification.Name("AIWindow.UIModeDidChange")
}
