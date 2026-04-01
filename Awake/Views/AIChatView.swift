import SwiftUI

struct AIChatView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @StateObject private var chatVM: AIChatViewModel

    init() {
        // Placeholder - will be replaced in onAppear
        _chatVM = StateObject(wrappedValue: AIChatViewModel(
            aiService: AIService(keychainService: KeychainService()),
            rulesEngine: RulesEngine(
                powerManager: PowerManager(),
                appMonitor: AppMonitorService(),
                processMonitor: ProcessMonitorService(),
                batteryMonitor: BatteryMonitorService(),
                persistence: PersistenceService()
            )
        ))
    }

    var body: some View {
        AIChatInnerView()
            .environmentObject(viewModel)
    }
}

struct AIChatInnerView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @State private var chatVM: AIChatViewModel?
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var messages: [ChatMessage] = []
    @State private var showAPIKeySetup = false

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.aiService.isConfigured {
                apiKeyPrompt
            } else {
                messageList
                Divider()
                inputBar
            }
        }
        .onAppear {
            if viewModel.aiService.isConfigured {
                messages = [ChatMessage(
                    role: .assistant,
                    content: "Tell me what to do:\n\"Stay awake for 2 hours\"\n\"Keep awake when Cursor is running\"\n\"Show my rules\""
                )]
            }
        }
        .onChange(of: showAPIKeySetup) {
            if showAPIKeySetup {
                showAPIKeySetup = false
                openAPIKeyWindow(keychainService: viewModel.keychainService)
            }
        }
    }

    private var apiKeyPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("AI Chat requires an API key")
                .font(.subheadline)
            Text("Add your Anthropic API key to use natural language commands.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Set Up API Key") {
                showAPIKeySetup = true
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if isLoading {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(12)
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Tell me what to do...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.caption)
                .onSubmit { sendMessage() }

            Button(action: { sendMessage() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.orange)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || isLoading)
        }
        .padding(10)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        messages.append(ChatMessage(role: .user, content: text))
        isLoading = true

        Task {
            do {
                let command = try await viewModel.aiService.interpretCommand(
                    text,
                    currentRules: viewModel.rulesEngine.rules,
                    watchList: viewModel.rulesEngine.watchList
                )
                let result = viewModel.rulesEngine.applyCommand(command)
                messages.append(ChatMessage(role: .assistant, content: result))
            } catch {
                messages.append(ChatMessage(role: .assistant, content: error.localizedDescription))
            }
            isLoading = false
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            Text(message.content)
                .font(.caption)
                .padding(8)
                .background(backgroundColor)
                .foregroundStyle(foregroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: return .orange.opacity(0.15)
        case .assistant: return .white.opacity(0.1)
        case .system: return .yellow.opacity(0.08)
        }
    }

    private var foregroundColor: Color {
        .primary
    }
}
