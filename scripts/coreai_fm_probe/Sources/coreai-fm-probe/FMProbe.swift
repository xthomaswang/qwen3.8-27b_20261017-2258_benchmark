// Multi-turn, in-process probe: one LanguageModelSession over a CoreAILanguageModel.
// Turn 3 can only be answered from turn 1, so a correct answer shows the session
// carried the history. Prints load time, then TTFT and total time per turn.
//
// Usage: coreai-fm-probe <bundle-dir> [max-response-tokens (default 128)]

import CoreAILanguageModels
import Foundation
import FoundationModels

@main
struct FMProbe {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            print("usage: coreai-fm-probe <bundle-dir> [max-response-tokens]")
            exit(2)
        }
        let url = URL(fileURLWithPath: (args[1] as NSString).expandingTildeInPath)
        let maxTokens = args.count >= 3 ? (Int(args[2]) ?? 128) : 128
        let clock = ContinuousClock()

        let loadStart = clock.now
        let model = try await CoreAILanguageModel(resourcesAt: url, mode: .eager)
        print("load: \(loadStart.duration(to: clock.now))")
        print("capabilities: \(model.capabilities)")

        let session = LanguageModelSession(model: model)
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: maxTokens)
        let turns = [
            "My name is Melo. Remember it. Reply with one short sentence.",
            "List three prime numbers greater than 10, comma-separated.",
            "What is my name? Answer with the name only.",
        ]

        for (index, prompt) in turns.enumerated() {
            let start = clock.now
            var firstContent: ContinuousClock.Instant?
            var text = ""
            var updates = 0
            for try await snapshot in session.streamResponse(to: prompt, options: options) {
                updates += 1
                if firstContent == nil, !snapshot.content.isEmpty {
                    firstContent = clock.now
                }
                text = snapshot.content
            }
            let total = start.duration(to: clock.now)
            let ttft = firstContent.map { "\(start.duration(to: $0))" } ?? "n/a"
            print("turn \(index + 1): ttft=\(ttft) total=\(total) updates=\(updates) chars=\(text.count)")
            print("  > \(text.prefix(240))")
        }
    }
}
