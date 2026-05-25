import Foundation

/// OpenAI-compatible chat client. Used for both ChatGPT (api.openai.com)
/// and Ollama (which exposes an OpenAI-compatible endpoint at /v1).
struct OpenAIClient {
    let apiKey: String?
    let baseURL: URL
    let model: String
    let requestTimeout: TimeInterval
    let isOllama: Bool
    let maxTokens: Int

    static func chatGPT(apiKey: String) -> OpenAIClient {
        OpenAIClient(
            apiKey: apiKey,
            baseURL: URL(string: "https://api.openai.com/v1")!,
            model: ProviderType.chatGPTModel,
            requestTimeout: 90,
            isOllama: false,
            maxTokens: 1024
        )
    }

    static func ollama(needsVision: Bool) -> OpenAIClient {
        let host = ProviderType.ollamaHost.trimmingCharacters(in: .whitespaces)
        let cleaned = host.hasSuffix("/") ? String(host.dropLast()) : host
        return OpenAIClient(
            apiKey: nil,
            baseURL: URL(string: "\(cleaned)/v1")!,
            model: ProviderType.ollamaModelToUse(needsVision: needsVision),
            requestTimeout: needsVision ? 240 : 180,
            isOllama: true,
            maxTokens: needsVision ? 768 : 512
        )
    }

    struct Response: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }

        struct Message: Decodable {
            let role: String
            /// `content` is sometimes null when the model returns only tool_calls.
            let content: String?
            let toolCalls: [ToolCall]?

            enum CodingKeys: String, CodingKey {
                case role, content
                case toolCalls = "tool_calls"
            }
        }

        struct ToolCall: Decodable {
            let id: String
            let type: String
            let function: FunctionCall

            struct FunctionCall: Decodable {
                let name: String
                /// Arguments arrive as a JSON-encoded string, not a JSON value.
                let arguments: String
            }
        }
    }

    func chat(messages: [[String: Any]], tools: [[String: Any]]) async throws -> Response {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = requestTimeout
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": 0.1,
            "top_p": 0.9,
        ]
        if isOllama {
            // Avoid slow hidden thinking on reasoning-capable local models for
            // short command-routing tasks.
            body["reasoning_effort"] = "none"
        }
        if !tools.isEmpty {
            body["tools"] = tools
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AIError.networkError }
        guard http.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "(no body)"
            throw AIError.apiError(http.statusCode, bodyStr)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
