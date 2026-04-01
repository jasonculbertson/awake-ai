import SwiftUI

enum PopoverTab: String, CaseIterable {
    case timer = "Timer"
    case apps = "Apps"
    case settings = "Settings"
}

struct PopoverContentView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @State private var selectedTab: PopoverTab = .timer

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            tabPicker
            tabContent
        }
        .frame(width: 320, height: 440)
        .background(.ultraThinMaterial)
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Button(action: { viewModel.toggleManual() }) {
                Image(systemName: viewModel.isAwake ? "sun.max.fill" : "moon.zzz")
                    .font(.system(size: 28))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(viewModel.isAwake ? .orange : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isAwake ? "Awake" : "Asleep")
                    .font(.headline)

                Text(viewModel.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let remaining = viewModel.timerRemaining {
                timerBadge(remaining)
            }

            Button(action: { showQuitConfirmDialog() }) {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit Awake")
        }
        .padding(12)
    }

    private func showQuitConfirmDialog() {
        let alert = NSAlert()
        alert.messageText = "Quit Awake?"
        alert.informativeText = "Sleep prevention will be disabled and all rules will stop running."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }

    private func timerBadge(_ remaining: TimeInterval) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.caption2)
            Text(formatTimer(remaining))
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .overlay(
            Capsule()
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .foregroundStyle(.orange)
        .clipShape(Capsule())
    }

    @Namespace private var tabAnimation

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(PopoverTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    if selectedTab == tab {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                            .shadow(color: .black.opacity(0.04), radius: 3, y: 2)
                            .matchedGeometryEffect(id: "activeTab", in: tabAnimation)
                    }
                }
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(.quaternary.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .timer:
            StatusSectionView()
        case .apps:
            AppWatchListView()
        case .settings:
            SettingsView()
        }
    }

    private func formatTimer(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
