import Foundation

struct ClaudeClient {
    let apiKey: String
    static let model = "claude-sonnet-4-6"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    struct Response: Decodable {
        let id: String
        let content: [ContentBlock]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case id, content
            case stopReason = "stop_reason"
        }
    }

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
        let id: String?
        let name: String?
        let input: [String: JSONValue]?
    }

    func send(system: String, messages: [[String: Any]], tools: [[String: Any]]) async throws -> Response {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 1024,
            "system": system,
            "messages": messages,
            "tools": tools,
        ]

        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else { throw AIError.networkError }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw AIError.apiError(http.statusCode, body)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }
}
