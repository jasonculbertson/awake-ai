import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @State private var showAPIKeySetup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: General
                sectionHeader("General")

                settingsCard {
                    toggleRow(
                        icon: "arrow.right.circle", color: .blue,
                        title: "Launch at login",
                        info: "Awake starts automatically when you log in, so sleep prevention is always available.",
                        isOn: Binding(
                            get: { viewModel.launchAtLogin.isEnabled },
                            set: { _ in viewModel.launchAtLogin.toggle() }
                        )
                    )

                    rowDivider()

                    // Sleep mode picker inline
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            iconBadge("display", color: .purple)
                            Text("Sleep prevention")
                                .font(.caption.bold())
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .help("Screen & System: keeps the display on and prevents sleep.\nSystem Only: prevents the Mac from sleeping but allows the screen to dim — useful when you need the CPU running but don't need the display.")
                            Spacer()
                        }
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
                        .padding(.leading, 30)

                        Text(viewModel.persistence.sleepPreventionMode == .systemOnly
                            ? "Prevents system sleep but allows display to dim"
                            : "Keeps screen on and prevents system sleep")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 30)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: Smart Triggers
                sectionHeader("Smart Triggers")

                settingsCard {
                    toggleRow(
                        icon: "bolt.fill", color: .yellow,
                        title: "Stay awake when plugged in",
                        subtitle: "Activates when AC power is connected",
                        info: "Automatically enables Awake whenever your Mac is connected to power, and deactivates when you unplug.",
                        isOn: Binding(
                            get: { viewModel.rulesEngine.isPowerAdapterRuleEnabled },
                            set: { viewModel.rulesEngine.setPowerAdapterRule(enabled: $0) }
                        )
                    )

                    rowDivider()

                    toggleRow(
                        icon: "laptopcomputer", color: .indigo,
                        title: "Stay awake with lid closed",
                        subtitle: "Clamshell mode (best with AC power)",
                        info: "Keeps your Mac running when the lid is shut and an external display is connected. Without AC power, this will drain your battery quickly.",
                        isOn: Binding(
                            get: { viewModel.rulesEngine.isClosedLidRuleEnabled },
                            set: { viewModel.rulesEngine.setClosedLidRule(enabled: $0) }
                        )
                    )

                    rowDivider()

                    let hasExternalDisplayRule = viewModel.rulesEngine.rules.contains {
                        $0.type == .externalDisplay && $0.isEnabled
                    }
                    toggleRow(
                        icon: "display", color: .teal,
                        title: "Stay awake with external display",
                        subtitle: "Activates when a monitor or TV is connected",
                        info: "Enables Awake whenever an HDMI, DisplayPort, or USB-C display is detected. Useful for desk setups where you always want sleep prevention when docked.",
                        isOn: Binding(
                            get: { hasExternalDisplayRule },
                            set: { enabled in
                                if enabled {
                                    viewModel.rulesEngine.addRule(AwakeRule(
                                        type: .externalDisplay,
                                        label: "When external display connected"
                                    ))
                                } else {
                                    viewModel.rulesEngine.rules
                                        .filter { $0.type == .externalDisplay }
                                        .forEach { viewModel.rulesEngine.removeRule(id: $0.id) }
                                }
                            }
                        )
                    )
                }

                // MARK: Notifications
                sectionHeader("Notifications")

                settingsCard {
                    toggleRow(
                        icon: "bell.fill", color: .orange,
                        title: "Notify on activation",
                        subtitle: "Alert when Awake turns on or off",
                        info: "Sends a notification when Awake automatically activates or deactivates due to a smart trigger or timer expiring.",
                        isOn: Binding(
                            get: { viewModel.persistence.notificationsEnabled },
                            set: { viewModel.persistence.notificationsEnabled = $0 }
                        )
                    )

                    rowDivider()

                    VStack(alignment: .leading, spacing: 6) {
                        toggleRow(
                            icon: "clock.badge.exclamationmark", color: .red,
                            title: "Session reminder",
                            info: "Reminds you that Awake has been active for a while, in case you forgot to turn it off.",
                            isOn: Binding(
                                get: { viewModel.persistence.sessionReminderEnabled },
                                set: { viewModel.persistence.sessionReminderEnabled = $0 }
                            )
                        )

                        if viewModel.persistence.sessionReminderEnabled {
                            HStack(spacing: 6) {
                                Text("Remind me after")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Stepper(
                                    value: Binding(
                                        get: { viewModel.persistence.sessionReminderHours },
                                        set: { viewModel.persistence.sessionReminderHours = $0 }
                                    ),
                                    in: 1...12
                                ) {
                                    Text("\(viewModel.persistence.sessionReminderHours) hour\(viewModel.persistence.sessionReminderHours == 1 ? "" : "s")")
                                        .font(.caption2.monospacedDigit())
                                }
                                .controlSize(.mini)
                            }
                            .padding(.leading, 30)
                        }
                    }
                }

                // MARK: Battery
                sectionHeader("Battery")

                settingsCard {
                    VStack(alignment: .leading, spacing: 6) {
                        toggleRow(
                            icon: "battery.25", color: .green,
                            title: "Stop when battery is low",
                            info: "Automatically deactivates Awake when battery drops below the threshold, so sleep prevention doesn't drain a low battery.",
                            isOn: Binding(
                                get: { viewModel.persistence.batteryThresholdEnabled },
                                set: { viewModel.persistence.batteryThresholdEnabled = $0 }
                            )
                        )

                        if viewModel.persistence.batteryThresholdEnabled {
                            HStack(spacing: 8) {
                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.persistence.batteryThreshold) },
                                        set: { viewModel.persistence.batteryThreshold = Int($0) }
                                    ),
                                    in: 5...50, step: 5
                                )
                                Text("\(viewModel.persistence.batteryThreshold)%")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 32)
                            }
                            .padding(.leading, 30)

                            Text("Allow sleep below this battery level")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 30)
                        }
                    }

                    if viewModel.batteryMonitor.hasBattery {
                        rowDivider()
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.batteryMonitor.isPluggedIn ? "battery.100.bolt" : "battery.50")
                                .font(.caption2)
                            Text("\(viewModel.batteryMonitor.batteryLevel)%\(viewModel.batteryMonitor.isPluggedIn ? " · Charging" : "")")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                    }
                }

                // MARK: AI
                sectionHeader("AI")

                settingsCard {
                    // API key status rows
                    ForEach(Array(AIProvider.allCases.enumerated()), id: \.element) { index, provider in
                        if index > 0 { rowDivider() }
                        HStack(spacing: 8) {
                            iconBadge(provider.icon, color: .orange)
                            Text(provider.rawValue)
                                .font(.caption)
                            Spacer()
                            if viewModel.keychainService.hasAPIKey(for: provider) {
                                if viewModel.keychainService.selectedProvider == provider {
                                    Text("Active")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.green)
                                } else {
                                    Button("Use") {
                                        viewModel.keychainService.selectedProvider = provider
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                                Circle().fill(.green).frame(width: 6, height: 6)
                            } else {
                                Circle().fill(Color(nsColor: .separatorColor)).frame(width: 6, height: 6)
                            }
                        }
                        .padding(.vertical, 1)
                    }

                    rowDivider()

                    Button(action: { showAPIKeySetup = true }) {
                        Label("Manage API Keys", systemImage: "key")
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                }

                // Subscription (only if no own key)
                if !viewModel.isAIConfigured {
                    settingsCard {
                        if viewModel.storeKit.hasPurchased {
                            HStack(spacing: 8) {
                                iconBadge("checkmark.seal.fill", color: .orange)
                                Text("AI Pro Active")
                                    .font(.caption.bold())
                                Spacer()
                            }
                        } else {
                            Text("No API key? Subscribe to use AI commands.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if let yearly = viewModel.storeKit.yearlyProduct {
                                Button(action: { Task { await viewModel.storeKit.purchase(yearly) } }) {
                                    HStack {
                                        Text("Subscribe \(yearly.displayPrice)/year")
                                            .font(.caption.bold())
                                        Spacer()
                                        Text("Best Value")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.black)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(.orange).clipShape(Capsule())
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .controlSize(.small)
                                .disabled(viewModel.storeKit.isPurchasing)
                            }

                            if let monthly = viewModel.storeKit.monthlyProduct {
                                Button(action: { Task { await viewModel.storeKit.purchase(monthly) } }) {
                                    Text("Subscribe \(monthly.displayPrice)/month")
                                        .font(.caption)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(viewModel.storeKit.isPurchasing)
                            }

                            Button("Restore Purchases") { Task { await viewModel.storeKit.restorePurchases() } }
                                .font(.caption2)
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .disabled(viewModel.storeKit.isPurchasing)
                        }
                    }
                }

                // MARK: About
                sectionHeader("About")

                settingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Awake AI  v1.0.0")
                                .font(.caption.bold())
                            Text("A modern replacement for Caffeine")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                    }

                    rowDivider()

                    HStack(spacing: 6) {
                        Image(systemName: "keyboard")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("⌘⇧A")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text("to toggle anywhere")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
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

    // MARK: - Layout helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .padding(.leading, 4)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
        )
    }

    private func rowDivider() -> some View {
        Divider().opacity(0.5)
    }

    private func iconBadge(_ name: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(color.opacity(0.15))
                .frame(width: 22, height: 22)
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
        }
    }

    private func toggleRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String? = nil,
        info: String? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 8) {
            iconBadge(icon, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.bold())
                if let sub = subtitle {
                    Text(sub).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let tip = info {
                infoIcon(tip)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }

    private func infoIcon(_ tip: String) -> some View {
        Image(systemName: "info.circle")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .help(tip)
    }
}
