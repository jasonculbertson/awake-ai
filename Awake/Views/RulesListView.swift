import SwiftUI

struct RulesListView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.rulesEngine.rules.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No rules configured")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Use the AI chat or toggle settings to create rules.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(viewModel.rulesEngine.rules) { rule in
                        RuleRow(rule: rule)
                    }
                    .onDelete { indexSet in
                        let ids = indexSet.map { viewModel.rulesEngine.rules[$0].id }
                        for id in ids {
                            viewModel.rulesEngine.removeRule(id: id)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

struct RuleRow: View {
    let rule: AwakeRule

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForType(rule.type))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(rule.label)
                    .font(.caption.bold())
                Text(rule.type.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if rule.createdByAI {
                Image(systemName: "brain")
                    .font(.caption2)
                    .foregroundStyle(.purple)
            }

            Circle()
                .fill(rule.isEnabled ? .green : .secondary.opacity(0.3))
                .frame(width: 6, height: 6)
        }
        .padding(.vertical, 2)
    }

    private func iconForType(_ type: RuleType) -> String {
        switch type {
        case .manual: return "hand.tap"
        case .timer: return "timer"
        case .appRunning: return "app.badge.checkmark"
        case .appFrontmost: return "macwindow"
        case .schedule: return "calendar"
        case .processRunning: return "terminal"
        case .batteryThreshold: return "battery.25"
        }
    }
}
