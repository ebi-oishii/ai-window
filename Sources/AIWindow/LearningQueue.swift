import Foundation

actor LearningQueue {
    static let shared = LearningQueue()

    private struct Job {
        let userInput: String
        let finalAnswer: String
        let provider: ProviderType
        let apiKey: String
    }

    private var jobs: [Job] = []
    private var isRunning = false
    private var activeUserRequests = 0

    func userRequestStarted() {
        activeUserRequests += 1
    }

    func userRequestFinished() {
        activeUserRequests = max(0, activeUserRequests - 1)
    }

    func enqueue(userInput: String, finalAnswer: String, provider: ProviderType, apiKey: String) {
        jobs.append(Job(userInput: userInput, finalAnswer: finalAnswer, provider: provider, apiKey: apiKey))
        if !isRunning {
            isRunning = true
            Task.detached(priority: .background) {
                await self.run()
            }
        }
    }

    private func run() async {
        while true {
            guard let job = await nextJobWhenIdle() else {
                isRunning = false
                return
            }

            await Reflector.reflectAndStore(
                userInput: job.userInput,
                finalAnswer: job.finalAnswer,
                provider: job.provider,
                apiKey: job.apiKey
            )

            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func nextJobWhenIdle() async -> Job? {
        while activeUserRequests > 0 {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard !jobs.isEmpty else { return nil }
        return jobs.removeFirst()
    }
}
