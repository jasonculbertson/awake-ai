import SwiftUI

struct AppWatchListView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @State private var showingAddApp = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(viewModel.rulesEngine.watchList) { entry in
                    AppWatchRow(entry: entry) { updated in
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
                    if newVal { viewModel.processMonitor.startMonitoring() }
                    else { viewModel.processMonitor.stopMonitoring() }
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

// MARK: - App Watch Row

struct AppWatchRow: View {
    let entry: AppWatchEntry
    let onUpdate: (AppWatchEntry) -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Main row ──────────────────────────────────────────
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { entry.isEnabled },
                    set: { _ in
                        var e = entry; e.isEnabled.toggle(); onUpdate(e)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()

                Text(entry.appName)
                    .font(.caption.bold())

                Spacer()

                // Mode picker
                Picker("", selection: Binding(
                    get: { entry.mode },
                    set: { v in var e = entry; e.mode = v; onUpdate(e) }
                )) {
                    ForEach(WatchMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .labelsHidden()
                .fixedSize()

                // Expand / collapse
                Button(action: { withAnimation(.spring(response: 0.28)) { expanded.toggle() } }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)

            // ── Expanded activity detection ───────────────────────
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().opacity(0.5)

                    HStack(spacing: 6) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("Auto-deactivate when idle")
                            .font(.caption.bold())
                        InfoButton(text: "When enabled, Awake watches the app's CPU usage. If it stays below the threshold for the set duration, sleep prevention is automatically turned off — great for long AI tasks or builds you walk away from.")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { entry.cpuThreshold != nil },
                            set: { on in
                                var e = entry
                                e.cpuThreshold = on ? 8.0 : nil
                                onUpdate(e)
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    if entry.cpuThreshold != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            // CPU threshold
                            HStack(spacing: 8) {
                                Text("CPU threshold")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)
                                Slider(
                                    value: Binding(
                                        get: { entry.cpuThreshold ?? 8.0 },
                                        set: { v in var e = entry; e.cpuThreshold = v; onUpdate(e) }
                                    ),
                                    in: 2...25, step: 1
                                )
                                Text("\(Int(entry.cpuThreshold ?? 8))%")
                                    .font(.caption2.monospacedDigit())
                                    .frame(width: 28)
                            }

                            // Idle duration
                            HStack(spacing: 8) {
                                Text("Idle for")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)
                                Stepper(
                                    value: Binding(
                                        get: { entry.cpuIdleMinutes },
                                        set: { v in var e = entry; e.cpuIdleMinutes = v; onUpdate(e) }
                                    ),
                                    in: 1...15
                                ) {
                                    Text("\(entry.cpuIdleMinutes) min")
                                        .font(.caption2.monospacedDigit())
                                }
                                .controlSize(.mini)
                            }

                            Text("Awake turns off after \(entry.cpuIdleMinutes) min of CPU below \(Int(entry.cpuThreshold ?? 8))%")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.leading, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
