import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @State private var currentStep = 0
    @State private var showAPIKeySetup = false
    @State private var goingForward = true

    private let totalSteps = 3

    var body: some View {
        ZStack {
            // Full background
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header band ──────────────────────────────────────
                ZStack {
                    // Gradient header
                    LinearGradient(
                        colors: [Color.orange.opacity(0.18), Color.orange.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .top)

                    // Step content
                    ZStack {
                        if currentStep == 0 { headerContent(for: 0).transition(forwardTransition) }
                        if currentStep == 1 { headerContent(for: 1).transition(forwardTransition) }
                        if currentStep == 2 { headerContent(for: 2).transition(forwardTransition) }
                    }
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: currentStep)
                    .padding(.top, 36)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 32)
                }

                Divider()
                    .opacity(0.5)

                // ── Body content ─────────────────────────────────────
                ZStack {
                    if currentStep == 0 { bodyContent(for: 0).transition(forwardTransition) }
                    if currentStep == 1 { bodyContent(for: 1).transition(forwardTransition) }
                    if currentStep == 2 { bodyContent(for: 2).transition(forwardTransition) }
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: currentStep)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

                Divider()
                    .opacity(0.4)

                // ── Footer navigation ─────────────────────────────────
                HStack {
                    // Back
                    Button(action: goBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(currentStep > 0 ? 1 : 0)
                    .disabled(currentStep == 0)

                    Spacer()

                    // Dots
                    HStack(spacing: 7) {
                        ForEach(0..<totalSteps, id: \.self) { i in
                            Circle()
                                .fill(i == currentStep ? Color.orange : Color(nsColor: .separatorColor))
                                .frame(width: i == currentStep ? 8 : 6, height: i == currentStep ? 8 : 6)
                                .animation(.spring(response: 0.3), value: currentStep)
                        }
                    }

                    Spacer()

                    // Next / Get Started
                    if currentStep < totalSteps - 1 {
                        Button(action: goNext) {
                            HStack(spacing: 4) {
                                Text("Next")
                                Image(systemName: "chevron.right")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color.orange)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: { viewModel.completeOnboarding() }) {
                            Text("Get Started")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(Color.orange)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
            }
        }
        .frame(width: 400, height: 520)
        .onChange(of: showAPIKeySetup) {
            if showAPIKeySetup {
                showAPIKeySetup = false
                openAPIKeyWindow(keychainService: viewModel.keychainService) {
                    viewModel.refreshAIStatus()
                }
            }
        }
    }

    // MARK: - Navigation

    private func goNext() {
        goingForward = true
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { currentStep += 1 }
    }

    private func goBack() {
        goingForward = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { currentStep -= 1 }
    }

    private var forwardTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
            removal:   .move(edge: goingForward ? .leading  : .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Header content per step

    @ViewBuilder
    private func headerContent(for step: Int) -> some View {
        switch step {
        case 0:
            VStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)
                VStack(spacing: 4) {
                    Text("Welcome to Awake AI")
                        .font(.title2.bold())
                    Text("Your Mac, always on when you need it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        case 1:
            VStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.orange)
                VStack(spacing: 4) {
                    Text("AI Commands")
                        .font(.title2.bold())
                    Text("Use plain English to control Awake — free with your own API key.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        default:
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: currentStep)
                VStack(spacing: 4) {
                    Text("You're all set!")
                        .font(.title2.bold())
                    Text("Awake lives in your menu bar, ready whenever you need it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Body content per step

    @ViewBuilder
    private func bodyContent(for step: Int) -> some View {
        switch step {
        case 0:
            VStack(spacing: 8) {
                featureRow(icon: "wand.and.stars",      color: .orange, title: "AI-powered commands",  detail: "Just type what you need in plain English")
                featureRow(icon: "app.badge.checkmark", color: .blue,   title: "Smart app detection",  detail: "Stays on while Xcode, Docker, or any app runs")
                featureRow(icon: "terminal",            color: .green,  title: "Process awareness",    detail: "Knows when your build finishes and turns itself off")
                featureRow(icon: "battery.50",          color: .yellow, title: "Battery-smart",        detail: "Automatically steps back when battery is low")
            }
        case 1:
            VStack(spacing: 10) {
                VStack(spacing: 6) {
                    exampleCommand("Stay awake for 2 hours")
                    exampleCommand("Keep on while Xcode is running")
                    exampleCommand("Don't sleep while Docker runs")
                    exampleCommand("Stay awake until 11pm")
                }

                if viewModel.isAIConfigured {
                    Label("API key connected", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .padding(.top, 4)
                } else {
                    Button(action: { showAPIKeySetup = true }) {
                        Label("Connect API Key", systemImage: "key")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.regular)
                    .padding(.top, 4)
                }

                Text("Works with Anthropic, OpenAI, and Google AI.\nOr skip and unlock with a subscription later.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        default:
            VStack(spacing: 8) {
                tipRow(icon: "cursorarrow.click",         tip: "Click the ☀️ icon in the menu bar to open Awake")
                tipRow(icon: "keyboard",                  tip: "Press ⌘⇧A anywhere to instantly toggle")
                tipRow(icon: "contextualmenu.and.cursorarrow", tip: "Right-click the icon for quick timer presets")
                tipRow(icon: "bell",                      tip: "Get a notification when Awake activates or deactivates")
            }
        }
    }

    // MARK: - Reusable rows

    private func featureRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func tipRow(icon: String, tip: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.orange)
            }
            Text(tip)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func exampleCommand(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
        )
    }
}
