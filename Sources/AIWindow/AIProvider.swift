import Foundation

enum ProviderType: String, CaseIterable {
    case claude = "Claude"
    case gemini = "Gemini"

    var envKey: String {
        switch self {
        case .claude: return "ANTHROPIC_API_KEY"
        case .gemini: return "GEMINI_API_KEY"
        }
    }

    var apiKey: String? {
        ProcessInfo.processInfo.environment[envKey]
    }

    var isConfigured: Bool { apiKey != nil }

    static let defaultsKey = "AIWindowSelectedProvider"
}

// Shared JSON value type for decoding tool call arguments from both providers
enum JSONValue: Decodable {
    case string(String), int(Int), double(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self)   { self = .bool(v);   return }
        if let v = try? c.decode(Int.self)    { self = .int(v);    return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        self = .null
    }

    var asString: String? { if case .string(let v) = self { return v }; return nil }
    var asInt: Int?       { if case .int(let v)    = self { return v }; return nil }
    var asBool: Bool?     { if case .bool(let v)   = self { return v }; return nil }
}

enum AIError: LocalizedError {
    case networkError
    case apiError(Int, String)
    case missingAPIKey(String)

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "ネットワークエラーが発生しました"
        case .apiError(let code, let body):
            return "APIエラー \(code): \(body.prefix(300))"
        case .missingAPIKey(let key):
            return "環境変数 \(key) が設定されていません"
        }
    }
}
