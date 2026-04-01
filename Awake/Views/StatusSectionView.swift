import SwiftUI

struct StatusSectionView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @State private var aiInput = ""
    @State private var aiMessages: [ChatMessage] = []
    @State private var aiLoading = false
    @State private var showAPIKeySetup = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                if viewModel.isAwake {
                    activeCard
                }

                timerSection
            }
            .padding(12)

            // AI chat area fills remaining space
            if viewModel.isAIConfigured {
                aiChatSection
            } else {
                aiSetupHint
            }
        }
        .onAppear {
            viewModel.refreshAIStatus()
        }
        .onChange(of: showAPIKeySetup) {
            if showAPIKeySetup {
                showAPIKeySetup = false
                openAPIKeyWindow(keychainService: viewModel.keychainService) {
                    viewModel.refreshAIStatus()
                }
            }
        }
    }

    // MARK: - Active Card

    private var activeCard: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.activeReasons) { reason in
                HStack(spacing: 6) {
                    Image(systemName: reason.icon)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(width: 14)
                    Text(reason.description)
                        .font(.caption)
                }
            }

            if viewModel.timerRemaining != nil {
                Button(action: { viewModel.cancelTimer() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.caption2.bold())
                        Text("Cancel Timer")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .glassCard(tint: .orange)
    }

    // MARK: - Timer

    private var timerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Timer")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 6) {
                timerButton("15m", minutes: 15)
                timerButton("30m", minutes: 30)
                timerButton("1h", minutes: 60)
                timerButton("2h", minutes: 120)
                timerButton("4h", minutes: 240)
                timerButton("8h", minutes: 480)
            }
        }
    }

    private func timerButton(_ label: String, minutes: Int) -> some View {
        Button(action: { viewModel.startTimer(minutes: minutes) }) {
            Text(label)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - AI Chat

    private var aiChatSection: some View {
        VStack(spacing: 0) {
            // Messages
            if !aiMessages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(aiMessages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            if aiLoading {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Thinking...")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .onChange(of: aiMessages.count) {
                        if let last = aiMessages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // AI input
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("AI Command")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !aiMessages.isEmpty {
                        Button(action: { aiMessages.removeAll() }) {
                            Text("Clear")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    TextField("e.g. \"Stay awake for 2 hours\"", text: $aiInput)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .onSubmit { sendAIMessage() }

                    Button(action: { sendAIMessage() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.body)
                            .foregroundStyle(aiInput.isEmpty ? Color.secondary : Color.orange)
                    }
                    .buttonStyle(.plain)
                    .disabled(aiInput.isEmpty || aiLoading)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private var aiSetupHint: some View {
        VStack {
            Spacer()
            Button(action: { showAPIKeySetup = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption2)
                    Text("Add API key for AI commands")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private func sendAIMessage() {
        let text = aiInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        aiInput = ""
        aiMessages.append(ChatMessage(role: .user, content: text))
        aiLoading = true

        Task {
            do {
                let command = try await viewModel.aiService.interpretCommand(
                    text,
                    currentRules: viewModel.rulesEngine.rules,
                    watchList: viewModel.rulesEngine.watchList
                )
                let result = viewModel.rulesEngine.applyCommand(command)
                aiMessages.append(ChatMessage(role: .assistant, content: result))
            } catch {
                aiMessages.append(ChatMessage(role: .assistant, content: error.localizedDescription))
            }
            aiLoading = false
        }
    }
}
