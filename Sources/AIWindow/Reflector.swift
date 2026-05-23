import Foundation

/// Self-improvement loop: after every successful task, ask the LLM to extract
/// a permanent rule that would help next time, and persist it.
/// Fire-and-forget — errors (rate limits, decode failures, etc.) are silenced.
enum Reflector {
    private static let reflectionPrompt = """
    あなたは AI Window というアプリの自己改善モジュールです。
    以下の「ユーザー指示」と「最終応答」を分析し、次回似た指示が来たときに
    AI が即座に正しく動けるような **永続的なルール** を最大 1 つだけ抽出してください。

    抽出すべきもの:
    - 具体的な URL パターン（例: Gmail 検索の deep link 形式）
    - 特定アプリを呼ぶ条件（例: 「コードを書く」と言われたら open_app("Cursor")）
    - ユーザー固有の呼び方とアプリ/サービスの対応（例: 「メモ帳」= Notes）
    - エンコーディング規則、デフォルトの引数など

    抽出しないもの:
    - 「Gmail を開く」のような既に明白な動作
    - 1 回限りの内容（人名、特定の検索語、その日固有の事柄）

    出力形式（厳守）:
    - 学んだルールがあれば 1 行で: RULE: <日本語のルール>
    - なければ: NO_RULE

    例:
    RULE: 「Gmail で <人物> からのメール」と言われたら https://mail.google.com/mail/u/0/#search/from%3A<URL エンコード済み人物> を open_url
    RULE: 「コードを書く」「コーディング」と言われたら open_app("Cursor")
    NO_RULE
    """

    static func reflectAndStore(
        userInput: String,
        finalAnswer: String,
        provider: ProviderType,
        apiKey: String
    ) async {
        let payload = """
        ユーザー指示: \(userInput)

        最終応答: \(finalAnswer)
        """

        do {
            let raw = try await callReflection(payload: payload, provider: provider, apiKey: apiKey)
            if let rule = parseRule(raw) {
                await MainActor.run { LearnedRulesStore.shared.add(rule) }
                print("[AIWindow] 🧠 learned rule: \(rule)")
            }
        } catch {
            // Silently swallow — reflection is best-effort
            print("[AIWindow] reflection skipped: \(error.localizedDescription)")
        }
    }

    private static func callReflection(payload: String, provider: ProviderType, apiKey: String) async throws -> String {
        switch provider {
        case .claude:
            let client = ClaudeClient(apiKey: apiKey)
            let resp = try await client.send(
                system: reflectionPrompt,
                messages: [["role": "user", "content": payload]],
                tools: []
            )
            return resp.content.compactMap(\.text).joined(separator: "\n")
        case .gemini:
            let client = GeminiClient(apiKey: apiKey)
            let resp = try await client.generate(
                systemInstruction: reflectionPrompt,
                contents: [["role": "user", "parts": [["text": payload]]]],
                tools: []
            )
            return resp.text
        }
    }

    /// Accepts either `RULE: ...` (extract suffix) or pure rule text.
    /// Rejects empty / NO_RULE / suspicious entries.
    static func parseRule(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.uppercased().contains("NO_RULE") { return nil }

        // Find the RULE: marker on any line
        for line in trimmed.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if let range = l.range(of: "RULE:", options: .caseInsensitive) {
                let rule = String(l[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return rule.isEmpty ? nil : rule
            }
        }

        // No marker — only accept if it looks like a single short imperative line
        if trimmed.count < 200 && !trimmed.contains("\n") {
            return trimmed
        }
        return nil
    }
}
