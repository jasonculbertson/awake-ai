import AppKit
import SwiftUI

private var addAppWindow: NSWindow?

/// Opens the Add App picker in a standalone NSWindow to avoid MenuBarExtra issues.
func openAddAppWindow(existingBundleIDs: Set<String>, onAdd: @escaping (AppWatchEntry) -> Void) {
    addAppWindow?.close()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "Add App to Watch List"
    window.center()
    window.isReleasedWhenClosed = false
    window.level = .floating

    let hostingView = NSHostingView(
        rootView: AddAppWindowContent(
            existingBundleIDs: existingBundleIDs,
            onAdd: { entry in
                onAdd(entry)
            },
            onDone: {
                window.close()
                addAppWindow = nil
            }
        )
    )
    window.contentView = hostingView
    addAppWindow = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

private struct AddAppWindowContent: View {
    let existingBundleIDs: Set<String>
    let onAdd: (AppWatchEntry) -> Void
    let onDone: () -> Void

    @State private var runningApps: [(name: String, bundleID: String)] = []
    @State private var searchText = ""
    @State private var addedBundleIDs: Set<String> = []
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search running apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .padding(12)

            List(filteredApps, id: \.bundleID) { app in
                let isAdded = existingBundleIDs.contains(app.bundleID) || addedBundleIDs.contains(app.bundleID)
                HStack {
                    Text(app.name)
                        .font(.body)
                    Spacer()
                    if isAdded {
                        Label("Added", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button("Add") {
                            let entry = AppWatchEntry(
                                bundleIdentifier: app.bundleID,
                                appName: app.name,
                                mode: .whenRunning,
                                isEnabled: true
                            )
                            onAdd(entry)
                            addedBundleIDs.insert(app.bundleID)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)

            HStack {
                Spacer()
                Button("Done") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 400, height: 400)
        .onAppear {
            loadRunningApps()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isSearchFocused = true
            }
        }
    }

    private var filteredApps: [(name: String, bundleID: String)] {
        if searchText.isEmpty { return runningApps }
        return runningApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func loadRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let name = app.localizedName,
                      let bundleID = app.bundleIdentifier else { return nil }
                return (name: name, bundleID: bundleID)
            }
            .sorted { $0.name < $1.name }
    }
}
