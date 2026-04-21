import SwiftUI

struct AppWatchListView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @State private var showingAddApp = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(viewModel.rulesEngine.watchList) { entry in
                    AppWatchRow(entry: entry) {
                        viewModel.rulesEngine.toggleWatchEntry(id: entry.id)
                    } onModeChange: { newMode in
                        var updated = entry
                        updated.mode = newMode
                        var list = viewModel.rulesEngine.watchList
                        if let idx = list.firstIndex(where: { $0.id == entry.id }) {
                            list[idx] = updated
                            viewModel.rulesEngine.updateWatchList(list)
                        }
                    }
                }
                .onDelete { indexSet in
                    var list = viewModel.rulesEngine.watchList
                    list.remove(atOffsets: indexSet)
                    viewModel.rulesEngine.updateWatchList(list)
                }
            }
            .listStyle(.plain)

            Divider()

            // Process detection toggle
            Toggle(isOn: Binding(
                get: { viewModel.persistence.processDetectionEnabled },
                set: { newVal in
                    viewModel.persistence.processDetectionEnabled = newVal
                    if newVal {
                        viewModel.processMonitor.startMonitoring()
                    } else {
                        viewModel.processMonitor.stopMonitoring()
                    }
                }
            )) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading) {
                        Text("Detect terminal processes")
                            .font(.caption.bold())
                        Text("npm, docker, ffmpeg, etc.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    InfoButton(text: "Watches for command-line processes by name. Useful for keeping your Mac awake during builds, transcodes, or server processes that run without a visible app window.")
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(12)

            Button(action: { showingAddApp = true }) {
                Label("Add App", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 12)
        }
        .onChange(of: showingAddApp) {
            if showingAddApp {
                showingAddApp = false
                let existingIDs = Set(viewModel.rulesEngine.watchList.map(\.bundleIdentifier))
                openAddAppWindow(existingBundleIDs: existingIDs) { entry in
                    var list = viewModel.rulesEngine.watchList
                    list.append(entry)
                    viewModel.rulesEngine.updateWatchList(list)
                }
            }
        }
    }
}

struct AppWatchRow: View {
    let entry: AppWatchEntry
    let onToggle: () -> Void
    let onModeChange: (WatchMode) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { entry.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()

            Text(entry.appName)
                .font(.caption.bold())

            Spacer()

            Picker("", selection: Binding(
                get: { entry.mode },
                set: { onModeChange($0) }
            )) {
                ForEach(WatchMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .labelsHidden()
            .fixedSize()

            InfoButton(text: entry.mode == .whenRunning
                ? "Awake stays on as long as this app is running, even if you switch to another window."
                : "Awake only stays on while this app is the active foreground window — turns off the moment you click away."
            )

        }
        .padding(.vertical, 2)
    }
}
