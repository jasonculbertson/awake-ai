import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @State private var showAPIKeySetup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Launch at Login
                Toggle(isOn: Binding(
                    get: { viewModel.launchAtLogin.isEnabled },
                    set: { _ in viewModel.launchAtLogin.toggle() }
                )) {
                    Label("Launch at login", systemImage: "arrow.right.circle")
                        .font(.caption.bold())
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Divider()

                // Sleep Prevention Mode
                VStack(alignment: .leading, spacing: 8) {
                    Label("Sleep prevention mode", systemImage: "display")
                        .font(.caption.bold())

                    Picker("", selection: Binding(
                        get: { viewModel.persistence.sleepPreventionMode },
                        set: {
                            viewModel.persistence.sleepPreventionMode = $0
                            viewModel.powerManager.mode = $0
                        }
                    )) {
                        ForEach(SleepPreventionMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .controlSize(.small)

                    Text(viewModel.persistence.sleepPreventionMode == .displayOnly
                        ? "Keeps screen on but allows system sleep"
                        : "Prevents both screen and system sleep")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Notifications
                Toggle(isOn: Binding(
                    get: { viewModel.persistence.notificationsEnabled },
                    set: { viewModel.persistence.notificationsEnabled = $0 }
                )) {
                    Label("Notifications", systemImage: "bell")
                        .font(.caption.bold())
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Text("Notify when auto-activating or deactivating")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                // Keyboard shortcut
                VStack(alignment: .leading, spacing: 4) {
                    Label("Global shortcut", systemImage: "keyboard")
                        .font(.caption.bold())
                    Text("Cmd + Shift + A to toggle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Divider()

                // Battery
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { viewModel.persistence.batteryThresholdEnabled },
                        set: { viewModel.persistence.batteryThresholdEnabled = $0 }
                    )) {
                        Label("Battery threshold", systemImage: "battery.25")
                            .font(.caption.bold())
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    if viewModel.persistence.batteryThresholdEnabled {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.persistence.batteryThreshold) },
                                    set: { viewModel.persistence.batteryThreshold = Int($0) }
                                ),
                                in: 5...50,
                                step: 5
                            )
                            Text("\(viewModel.persistence.batteryThreshold)%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 32)
                        }

                        Text("Allow sleep when battery drops below this level")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.batteryMonitor.hasBattery {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.batteryMonitor.isPluggedIn ? "battery.100.bolt" : "battery.50")
                                .font(.caption2)
                            Text("Battery: \(viewModel.batteryMonitor.batteryLevel)%")
                                .font(.caption2)
                            if viewModel.batteryMonitor.isPluggedIn {
                                Text("(plugged in)")
                                    .font(.caption2)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // AI Providers
                VStack(alignment: .leading, spacing: 8) {
                    Label("AI Providers", systemImage: "key")
                        .font(.caption.bold())

                    ForEach(AIProvider.allCases) { provider in
                        HStack(spacing: 8) {
                            Image(systemName: provider.icon)
                                .font(.caption)
                                .frame(width: 14)

                            Text(provider.rawValue)
                                .font(.caption)

                            Spacer()

                            if viewModel.keychainService.hasAPIKey(for: provider) {
                                if viewModel.keychainService.selectedProvider == provider {
                                    Text("Active")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                } else {
                                    Button("Use") {
                                        viewModel.keychainService.selectedProvider = provider
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }

                                Circle()
                                    .fill(.green)
                                    .frame(width: 6, height: 6)
                            } else {
                                Circle()
                                    .fill(Color(nsColor: .separatorColor))
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }

                    Button("Manage API Keys") { showAPIKeySetup = true }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Divider()

                // About
                VStack(alignment: .leading, spacing: 4) {
                    Text("Awake v1.0.0")
                        .font(.caption.bold())
                    Text("A modern replacement for Caffeine")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            }
            .padding(12)
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
}
