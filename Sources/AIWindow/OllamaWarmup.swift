import Foundation

enum OllamaWarmup {
    private static var warmedModels = Set<String>()

    static func warmTextModelIfNeeded() {
        warm(model: ProviderType.ollamaModelToUse(needsVision: false))
    }

    static func keepTextModelWarm() {
        keepWarm(model: ProviderType.ollamaModelToUse(needsVision: false))
    }

    static func warm(model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, warmedModels.insert(trimmed).inserted else { return }

        Task.detached(priority: .utility) {
            await preload(model: trimmed)
        }
    }

    static func keepWarm(model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        warmedModels.insert(trimmed)

        Task.detached(priority: .utility) {
            await preload(model: trimmed)
        }
    }

    /// Use Ollama's native API for keep_alive; the OpenAI-compatible endpoint
    /// does not consistently expose model lifecycle controls.
    private static func preload(model: String) async {
        let host = ProviderType.ollamaHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = host.hasSuffix("/") ? String(host.dropLast()) : host
        guard let url = URL(string: "\(cleaned)/api/generate") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": "",
            "stream": false,
            "keep_alive": "30m",
        ] as [String: Any])

        do {
            _ = try await URLSession.shared.data(for: req)
            print("[AIWindow] warmed Ollama model: \(model)")
        } catch {
            print("[AIWindow] Ollama warmup skipped: \(error.localizedDescription)")
        }
    }
}
