import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date

    enum Role: Equatable {
        case user
        case assistant
        case system
    }

    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

@MainActor
final class AIChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var showAPIKeySetup: Bool = false

    private let aiService: AIService
    private let rulesEngine: RulesEngine

    init(aiService: AIService, rulesEngine: RulesEngine) {
        self.aiService = aiService
        self.rulesEngine = rulesEngine

        if !aiService.isConfigured {
            messages.append(ChatMessage(
                role: .system,
                content: "Add your Anthropic API key in Settings to enable AI commands."
            ))
        } else {
            messages.append(ChatMessage(
                role: .assistant,
                content: "Hi! Tell me what to do. For example:\n\"Stay awake for 2 hours\"\n\"Keep awake when Cursor is running\"\n\"Show my rules\""
            ))
        }
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        messages.append(ChatMessage(role: .user, content: text))

        guard aiService.isConfigured else {
            showAPIKeySetup = true
            messages.append(ChatMessage(role: .system, content: "Please add your API key in Settings first."))
            return
        }

        isLoading = true

        do {
            let command = try await aiService.interpretCommand(
                text,
                currentRules: rulesEngine.rules,
                watchList: rulesEngine.watchList
            )
            let result = rulesEngine.applyCommand(command)
            messages.append(ChatMessage(role: .assistant, content: result))
        } catch {
            messages.append(ChatMessage(role: .assistant, content: error.localizedDescription))
        }

        isLoading = false
    }
}
