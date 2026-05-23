import Foundation

// Gemini API client — gemini-2.5-flash-lite (free tier: 30 RPM, 1000 RPD)
struct GeminiClient {
    let apiKey: String
    static let model = "gemini-2.5-flash-lite"

    private var endpoint: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.model):generateContent?key=\(apiKey)")!
    }

    struct Response: Decodable {
        let candidates: [Candidate]?

        // True if the model wants to call one or more functions
        var hasFunctionCalls: Bool {
            candidates?.first?.content.parts.contains { $0.functionCall != nil } ?? false
        }

        // All function calls from the first candidate
        var functionCalls: [Part.FunctionCall] {
            candidates?.first?.content.parts.compactMap(\.functionCall) ?? []
        }

        // Concatenated text from the first candidate
        var text: String {
            candidates?.first?.content.parts.compactMap(\.text).joined(separator: "\n") ?? ""
        }

        // Raw parts for reconstructing conversation history
        var firstCandidateParts: [Part] {
            candidates?.first?.content.parts ?? []
        }

        struct Candidate: Decodable {
            let content: Content
            let finishReason: String?
        }

        struct Content: Decodable {
            let parts: [Part]
            let role: String?
        }

        struct Part: Decodable {
            let text: String?
            let functionCall: FunctionCall?

            struct FunctionCall: Decodable {
                let name: String
                let args: [String: JSONValue]?
            }
        }
    }

    func generate(
        systemInstruction: String,
        contents: [[String: Any]],
        tools: [[String: Any]]
    ) async throws -> Response {
        let body: [String: Any] = [
            "contents": contents,
            "tools": tools,
            "system_instruction": ["parts": [["text": systemInstruction]]],
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
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
