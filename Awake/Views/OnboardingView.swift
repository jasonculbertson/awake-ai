import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @State private var currentStep = 0
    @State private var showAPIKeySetup = false

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Header with step indicator
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= currentStep ? Color.orange : Color(nsColor: .separatorColor))
                        .frame(width: i == currentStep ? 20 : 6, height: 6)
                        .animation(.spring(response: 0.3), value: currentStep)
                }
            }
            .padding(.top, 24)

            // Step content
            TabView(selection: $currentStep) {
                stepOne.tag(0)
                stepTwo.tag(1)
                stepThree.tag(2)
            }
            .tabViewStyle(.automatic)
            .frame(height: 340)

            // Navigation buttons
            HStack(spacing: 12) {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.regular)
                } else {
                    Button("Get Started") {
                        viewModel.completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .onChange(of: showAPIKeySetup) {
            if showAPIKeySetup {
                showAPIKeySetup = false
                openAPIKeyWindow(keychainService: viewModel.keychainService) {
                    viewModel.refreshAIStatus()
                }
            }
        }
    }

    // MARK: - Step 1: What Awake does

    private var stepOne: some View {
        VStack(spacing: 20) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
                .symbolEffect(.pulse)

            VStack(spacing: 6) {
                Text("Welcome to Awake AI")
                    .font(.title2.bold())

                Text("Your Mac, always on when you need it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "wand.and.stars", color: .orange,
                           title: "AI-powered commands",
                           detail: "Just type what you need in plain English")
                featureRow(icon: "app.badge.checkmark", color: .blue,
                           title: "Smart app detection",
                           detail: "Stays on while Xcode, Docker, or any app runs")
                featureRow(icon: "terminal", color: .green,
                           title: "Process awareness",
                           detail: "Knows when your build finishes and turns itself off")
                featureRow(icon: "battery.50", color: .yellow,
                           title: "Battery-smart",
                           detail: "Automatically steps back when battery is low")
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Step 2: Set up AI

    private var stepTwo: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            VStack(spacing: 6) {
                Text("AI Commands (Optional)")
                    .font(.title2.bold())

                Text("Connect your own API key to use natural language commands — free, forever.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            VStack(spacing: 10) {
                exampleCommand("Stay awake for 2 hours")
                exampleCommand("Keep on while Xcode is running")
                exampleCommand("Don't sleep while Docker runs")
                exampleCommand("Stay awake until 11pm")
            }
            .padding(.horizontal, 28)

            if viewModel.isAIConfigured {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("API key connected")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            } else {
                Button(action: { showAPIKeySetup = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "key")
                        Text("Connect API Key")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.horizontal, 28)
            }

            Text("Works with Anthropic, OpenAI, and Google AI. Or skip and use the subscription.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    // MARK: - Step 3: You're set

    private var stepThree: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: currentStep)

            VStack(spacing: 6) {
                Text("You're all set!")
                    .font(.title2.bold())

                Text("Awake lives in your menu bar. Click the sun icon to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            VStack(alignment: .leading, spacing: 12) {
                tipRow(icon: "sun.max.fill", tip: "Click the ☀️ icon in your menu bar to open Awake")
                tipRow(icon: "keyboard", tip: "Press ⌘⇧A anywhere to instantly toggle")
                tipRow(icon: "arrow.right.circle", tip: "Right-click the icon for quick timer presets")
                tipRow(icon: "bell", tip: "You'll get a notification when Awake activates or deactivates")
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Helpers

    private func featureRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold())
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func exampleCommand(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func tipRow(icon: String, tip: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(tip)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
