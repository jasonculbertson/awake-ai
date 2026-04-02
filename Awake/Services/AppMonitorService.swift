import AppKit
import Combine
import os

final class AppMonitorService: ObservableObject {
    @Published private(set) var runningBundleIDs: Set<String> = []
    @Published private(set) var runningAppNames: [String: String] = [:] // bundleID -> name
    @Published private(set) var frontmostBundleID: String?

    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: Constants.appName, category: "AppMonitor")

    init() {
        refresh()
    }

    func startMonitoring() {
        guard cancellables.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter

        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.frontmostBundleID = app.bundleIdentifier
                }
            }
            .store(in: &cancellables)
    }

    func stopMonitoring() {
        cancellables.removeAll()
    }

    func isAppRunning(bundleID: String) -> Bool {
        runningBundleIDs.contains(bundleID)
    }

    func isAppRunning(name: String) -> Bool {
        let nameLower = name.lowercased()
        return runningAppNames.values.contains { appName in
            appName.lowercased().contains(nameLower) || nameLower.contains(appName.lowercased())
        }
    }

    func isAppFrontmost(bundleID: String) -> Bool {
        frontmostBundleID == bundleID
    }

    func isAppFrontmost(name: String) -> Bool {
        guard let frontBID = frontmostBundleID,
              let frontName = runningAppNames[frontBID] else { return false }
        let nameLower = name.lowercased()
        return frontName.lowercased().contains(nameLower) || nameLower.contains(frontName.lowercased())
    }

    /// Look up bundle ID by app name from running apps
    func findBundleID(forName name: String) -> String? {
        let nameLower = name.lowercased()
        // Exact match first
        if let match = runningAppNames.first(where: { $0.value.lowercased() == nameLower }) {
            return match.key
        }
        // Partial match
        if let match = runningAppNames.first(where: {
            $0.value.lowercased().contains(nameLower) || nameLower.contains($0.value.lowercased())
        }) {
            return match.key
        }
        return nil
    }

    /// Look up display name by app name query
    func findAppName(forQuery name: String) -> String? {
        let nameLower = name.lowercased()
        if let match = runningAppNames.first(where: { $0.value.lowercased() == nameLower }) {
            return match.value
        }
        if let match = runningAppNames.first(where: {
            $0.value.lowercased().contains(nameLower) || nameLower.contains($0.value.lowercased())
        }) {
            return match.value
        }
        return nil
    }

    private func refresh() {
        let apps = NSWorkspace.shared.runningApplications
        runningBundleIDs = Set(apps.compactMap(\.bundleIdentifier))
        var nameMap: [String: String] = [:]
        for app in apps {
            if let bid = app.bundleIdentifier, let name = app.localizedName {
                nameMap[bid] = name
            }
        }
        runningAppNames = nameMap
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
