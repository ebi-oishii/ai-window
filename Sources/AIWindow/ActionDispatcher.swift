import Foundation

/// Optional follow-up the AI offers — rendered as buttons in easy mode.
struct SuggestedAction: Equatable {
    let label: String
    let prompt: String
}

/// Full result of one user turn: text response plus any AI-suggested buttons.
struct DispatchResult {
    let text: String
    let suggestions: [SuggestedAction]
}

/// Reference-typed sink so the tool-use loop (running on a struct dispatcher)
/// can accumulate AI-suggested buttons across turns.
final class SuggestionsBox {
    var actions: [SuggestedAction] = []
}

struct ActionDispatcher {
    private let browser = BrowserExecutor()
    private let system = SystemSettingsExecutor()
    private let files = FileExecutor()
    private let clipboard = ClipboardExecutor()
    private let appleScript = AppleScriptExecutor()
    private let webSearch = WebSearchExecutor()

    func dispatch(userInput: String, provider: ProviderType, imageBase64: String? = nil) async throws -> DispatchResult {
        guard let apiKey = provider.apiKey else {
            throw AIError.missingAPIKey(provider.envKey)
        }
        let contextLine = FrontmostContext.capture().promptLine
        let enriched = contextLine.map { "\($0)\n\nユーザー指示: \(userInput)" } ?? userInput

        let box = SuggestionsBox()
        let text: String
        switch provider {
        case .claude:
            text = try await dispatchClaude(userInput: enriched, apiKey: apiKey, imageBase64: imageBase64, suggestions: box)
        case .gemini:
            text = try await dispatchGemini(userInput: enriched, apiKey: apiKey, imageBase64: imageBase64, suggestions: box)
        case .chatgpt:
            text = try await dispatchOpenAI(client: .chatGPT(apiKey: apiKey), userInput: enriched, imageBase64: imageBase64, suggestions: box)
        case .ollama:
            text = try await dispatchOpenAI(client: .ollama(), userInput: enriched, imageBase64: imageBase64, suggestions: box)
        }
        // Reflection runs in the background so it never blocks the user. If it
        // hits a rate limit or any other error it's silently dropped.
        Task.detached(priority: .background) {
            await Reflector.reflectAndStore(
                userInput: userInput,
                finalAnswer: text,
                provider: provider,
                apiKey: apiKey
            )
        }
        return DispatchResult(text: text, suggestions: box.actions)
    }

    // MARK: - Claude agentic loop

    private func dispatchClaude(userInput: String, apiKey: String, imageBase64: String?, suggestions: SuggestionsBox) async throws -> String {
        let client = ClaudeClient(apiKey: apiKey)

        let firstContent: Any
        if let img = imageBase64 {
            firstContent = [
                ["type": "image", "source": [
                    "type": "base64", "media_type": "image/png", "data": img,
                ] as [String: Any]] as [String: Any],
                ["type": "text", "text": userInput] as [String: Any],
            ]
        } else {
            firstContent = userInput
        }
        var messages: [[String: Any]] = [
            ["role": "user", "content": firstContent],
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
                let result = await execute(tool: name, input: block.input ?? [:], suggestions: suggestions)
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

    private func dispatchGemini(userInput: String, apiKey: String, imageBase64: String?, suggestions: SuggestionsBox) async throws -> String {
        let client = GeminiClient(apiKey: apiKey)

        var parts: [[String: Any]] = [["text": userInput]]
        if let img = imageBase64 {
            parts.append(["inline_data": ["mime_type": "image/png", "data": img]])
        }
        var contents: [[String: Any]] = [
            ["role": "user", "parts": parts],
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
                let result = await execute(tool: fc.name, input: fc.args ?? [:], suggestions: suggestions)
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

    // MARK: - OpenAI-compatible agentic loop (ChatGPT / Ollama)

    private func dispatchOpenAI(client: OpenAIClient, userInput: String, imageBase64: String?, suggestions: SuggestionsBox) async throws -> String {
        let firstUserContent: Any
        if let img = imageBase64 {
            firstUserContent = [
                ["type": "text", "text": userInput] as [String: Any],
                ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(img)"] as [String: Any]] as [String: Any],
            ]
        } else {
            firstUserContent = userInput
        }

        var messages: [[String: Any]] = [
            ["role": "system", "content": Tools.systemPrompt],
            ["role": "user",   "content": firstUserContent],
        ]

        var response = try await client.chat(messages: messages, tools: Tools.openAIDefinitions)

        while let toolCalls = response.choices.first?.message.toolCalls, !toolCalls.isEmpty {
            // Echo the assistant turn back so the next request sees the same tool_calls
            var asstMsg: [String: Any] = ["role": "assistant"]
            asstMsg["content"] = response.choices.first?.message.content ?? NSNull()
            asstMsg["tool_calls"] = toolCalls.map { tc in
                [
                    "id": tc.id,
                    "type": "function",
                    "function": [
                        "name": tc.function.name,
                        "arguments": tc.function.arguments,
                    ] as [String: Any],
                ] as [String: Any]
            }
            messages.append(asstMsg)

            for tc in toolCalls {
                let argsData = tc.function.arguments.data(using: .utf8) ?? Data()
                let argsDict = (try? JSONDecoder().decode([String: JSONValue].self, from: argsData)) ?? [:]
                let result = await execute(tool: tc.function.name, input: argsDict, suggestions: suggestions)
                messages.append([
                    "role": "tool",
                    "tool_call_id": tc.id,
                    "content": result,
                ])
            }

            response = try await client.chat(messages: messages, tools: Tools.openAIDefinitions)
        }

        return (response.choices.first?.message.content ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Shared tool execution

    private func execute(tool: String, input: [String: JSONValue], suggestions: SuggestionsBox) async -> String {
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

        case "list_recent_files":
            guard let raw = input["location"]?.asString,
                  let location = FileLocation.from(raw) else {
                return "location が不正です（downloads / desktop / documents / home のいずれか）"
            }
            let limit = input["limit"]?.asInt ?? 5
            let urls = files.listRecent(in: location, limit: limit)
            return files.formatListing(urls, in: location)

        case "open_file":
            guard let path = input["path"]?.asString else { return "path が指定されていません" }
            return files.openFile(path: path, withApp: input["app"]?.asString)

        case "search_files":
            guard let query = input["query"]?.asString, !query.isEmpty else {
                return "query が指定されていません"
            }
            let nameOnly = input["name_only"]?.asBool ?? false
            let location = input["location"]?.asString.flatMap(FileLocation.from)
            let limit = input["limit"]?.asInt ?? 10
            let urls = files.searchFiles(query: query, nameOnly: nameOnly, location: location, limit: limit)
            return files.formatSearchResults(urls, query: query)

        case "read_clipboard":
            let text = clipboard.read()
            return text.isEmpty ? "クリップボードは空です" : text

        case "write_clipboard":
            guard let text = input["text"]?.asString else { return "text が指定されていません" }
            clipboard.write(text)
            return "クリップボードにコピーしました (\(text.count) 文字)"

        case "run_applescript":
            guard let script = input["script"]?.asString, !script.isEmpty else {
                return "script が指定されていません"
            }
            return appleScript.run(script)

        case "web_search":
            guard let query = input["query"]?.asString, !query.isEmpty else {
                return "query が指定されていません"
            }
            let limit = input["limit"]?.asInt ?? 5
            let results = await webSearch.search(query: query, limit: limit)
            return webSearch.format(results, query: query)

        case "suggest_actions":
            guard let arr = input["actions"]?.asArray, !arr.isEmpty else {
                return "actions が指定されていません"
            }
            var added = 0
            for v in arr {
                guard let obj = v.asObject,
                      let label = obj["label"]?.asString,
                      let prompt = obj["prompt"]?.asString,
                      !label.isEmpty, !prompt.isEmpty else { continue }
                suggestions.actions.append(SuggestedAction(label: label, prompt: prompt))
                added += 1
            }
            return "\(added) 個の次の選択肢を提示しました"

        default:
            return "未知のツール: \(tool)"
        }
    }

    private func flatten(_ input: [String: JSONValue]) -> [String: Any] {
        input.compactMapValues { Self.flattenValue($0) }
    }

    private static func flattenValue(_ value: JSONValue) -> Any? {
        switch value {
        case .string(let v): return v
        case .int(let v):    return v
        case .double(let v): return v
        case .bool(let v):   return v
        case .null:          return nil
        case .array(let arr):
            return arr.compactMap(flattenValue)
        case .object(let obj):
            return obj.compactMapValues(flattenValue)
        }
    }
}
