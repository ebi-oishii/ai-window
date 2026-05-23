import Foundation

struct ActionDispatcher {
    private let browser = BrowserExecutor()
    private let system = SystemSettingsExecutor()

    func dispatch(userInput: String, provider: ProviderType) async throws -> String {
        guard let apiKey = provider.apiKey else {
            throw AIError.missingAPIKey(provider.envKey)
        }
        switch provider {
        case .claude: return try await dispatchClaude(userInput: userInput, apiKey: apiKey)
        case .gemini: return try await dispatchGemini(userInput: userInput, apiKey: apiKey)
        }
    }

    // MARK: - Claude agentic loop

    private func dispatchClaude(userInput: String, apiKey: String) async throws -> String {
        let client = ClaudeClient(apiKey: apiKey)

        var messages: [[String: Any]] = [
            ["role": "user", "content": userInput],
        ]

        var response = try await client.send(
            system: Tools.systemPrompt,
            messages: messages,
            tools: Tools.claudeDefinitions
        )

        while response.stopReason == "tool_use" {
            var assistantContent: [[String: Any]] = []
            for block in response.content {
                switch block.type {
                case "text":
                    if let text = block.text {
                        assistantContent.append(["type": "text", "text": text])
                    }
                case "tool_use":
                    guard let id = block.id, let name = block.name else { continue }
                    assistantContent.append([
                        "type": "tool_use",
                        "id": id,
                        "name": name,
                        "input": flatten(block.input ?? [:]),
                    ])
                default: break
                }
            }
            messages.append(["role": "assistant", "content": assistantContent])

            var toolResults: [[String: Any]] = []
            for block in response.content where block.type == "tool_use" {
                guard let id = block.id, let name = block.name else { continue }
                let result = await execute(tool: name, input: block.input ?? [:])
                toolResults.append([
                    "type": "tool_result",
                    "tool_use_id": id,
                    "content": result,
                ])
            }
            messages.append(["role": "user", "content": toolResults])

            response = try await client.send(
                system: Tools.systemPrompt,
                messages: messages,
                tools: Tools.claudeDefinitions
            )
        }

        return response.content
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Gemini agentic loop

    private func dispatchGemini(userInput: String, apiKey: String) async throws -> String {
        let client = GeminiClient(apiKey: apiKey)

        var contents: [[String: Any]] = [
            ["role": "user", "parts": [["text": userInput]]],
        ]

        var response = try await client.generate(
            systemInstruction: Tools.systemPrompt,
            contents: contents,
            tools: Tools.geminiDefinitions
        )

        while response.hasFunctionCalls {
            var modelParts: [[String: Any]] = []
            for part in response.firstCandidateParts {
                if let text = part.text {
                    modelParts.append(["text": text])
                } else if let fc = part.functionCall {
                    modelParts.append([
                        "functionCall": ["name": fc.name, "args": flatten(fc.args ?? [:])]
                    ])
                }
            }
            contents.append(["role": "model", "parts": modelParts])

            var resultParts: [[String: Any]] = []
            for fc in response.functionCalls {
                let result = await execute(tool: fc.name, input: fc.args ?? [:])
                resultParts.append([
                    "functionResponse": ["name": fc.name, "response": ["result": result]]
                ])
            }
            contents.append(["role": "user", "parts": resultParts])

            response = try await client.generate(
                systemInstruction: Tools.systemPrompt,
                contents: contents,
                tools: Tools.geminiDefinitions
            )
        }

        return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Shared tool execution

    private func execute(tool: String, input: [String: JSONValue]) async -> String {
        switch tool {
        case "open_app":
            guard let name = input["name"]?.asString else { return "アプリ名が指定されていません" }
            let newWindow = input["new_window"]?.asBool ?? true
            return SystemAppLauncher.launch(name: name, newWindow: newWindow)

        case "open_url":
            guard let url = input["url"]?.asString else { return "URLが指定されていません" }
            _ = ShortcutRegistry.shared.recordOpenedURL(url)
            if let browserName = input["browser"]?.asString, !browserName.isEmpty {
                return browser.openInBrowser(url, appName: browserName)
            }
            browser.open(url)
            return "ブラウザで \(url) を開きました"

        case "control_volume":
            guard let action = input["action"]?.asString else { return "action が指定されていません" }
            let value = input["value"]?.asInt ?? 10
            return system.controlVolume(action: action, value: value)

        default:
            return "未知のツール: \(tool)"
        }
    }

    private func flatten(_ input: [String: JSONValue]) -> [String: Any] {
        input.compactMapValues { value -> Any? in
            switch value {
            case .string(let v): return v
            case .int(let v):    return v
            case .double(let v): return v
            case .bool(let v):   return v
            case .null:          return nil
            }
        }
    }
}
