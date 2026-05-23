import Foundation

enum ProviderType: String, CaseIterable {
    case claude  = "Claude"
    case gemini  = "Gemini"
    case chatgpt = "ChatGPT"
    case ollama  = "Ollama"

    /// Env / Keychain account name. Ollama has no auth so it stores the
    /// host URL here instead of an API key.
    var envKey: String {
        switch self {
        case .claude:  return "ANTHROPIC_API_KEY"
        case .gemini:  return "GEMINI_API_KEY"
        case .chatgpt: return "OPENAI_API_KEY"
        case .ollama:  return "OLLAMA_HOST"
        }
    }

    /// Keychain takes precedence so GUI launches (which don't inherit shell
    /// env) still find the key. Env var remains a fallback for `make run`
    /// during development. For Ollama this returns the configured host URL
    /// (default `http://localhost:11434`).
    var apiKey: String? {
        switch self {
        case .ollama:
            return Self.ollamaHost
        default:
            if let k = KeychainStore.read(account: envKey), !k.isEmpty { return k }
            return ProcessInfo.processInfo.environment[envKey]
        }
    }

    var isConfigured: Bool {
        switch self {
        case .ollama:
            // Treated as configured by default; real connectivity failures
            // surface at dispatch time when the local server is not running.
            return true
        default:
            if let key = apiKey { return !key.isEmpty }
            return false
        }
    }

    // MARK: - Ollama settings

    private static let ollamaHostKey  = "AIWindow.OllamaHost"
    private static let ollamaModelKey = "AIWindow.OllamaModel"

    static var ollamaHost: String {
        get { UserDefaults.standard.string(forKey: ollamaHostKey) ?? "http://localhost:11434" }
        set { UserDefaults.standard.set(newValue, forKey: ollamaHostKey) }
    }
    static var ollamaModel: String {
        get { UserDefaults.standard.string(forKey: ollamaModelKey) ?? "llama3.2" }
        set { UserDefaults.standard.set(newValue, forKey: ollamaModelKey) }
    }

    // MARK: - ChatGPT settings

    private static let chatGPTModelKey = "AIWindow.ChatGPTModel"
    static var chatGPTModel: String {
        get { UserDefaults.standard.string(forKey: chatGPTModelKey) ?? "gpt-4o-mini" }
        set { UserDefaults.standard.set(newValue, forKey: chatGPTModelKey) }
    }

    static let defaultsKey = "AIWindowSelectedProvider"
}

// Shared JSON value type for decoding tool call arguments from both providers
indirect enum JSONValue: Decodable {
    case string(String), int(Int), double(Double), bool(Bool), null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self)   { self = .bool(v);   return }
        if let v = try? c.decode(Int.self)    { self = .int(v);    return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        self = .null
    }

    var asString: String? { if case .string(let v) = self { return v }; return nil }
    var asInt: Int?       { if case .int(let v)    = self { return v }; return nil }
    var asBool: Bool?     { if case .bool(let v)   = self { return v }; return nil }
    var asArray: [JSONValue]?         { if case .array(let v)  = self { return v }; return nil }
    var asObject: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
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
