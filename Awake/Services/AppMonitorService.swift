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

        // Re-evaluate immediately after wake so the power assertion is
        // re-created before the idle timer has a chance to fire again.
        center.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func stopMonitoring() {
        cancellables.removeAll()
    }

    func isAppRunning(bundleID: String) -> Bool {
        // Query live so evaluate() never acts on a stale notification-based cache.
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    func isAppRunning(name: String) -> Bool {
        let nameLower = name.lowercased()
        return NSWorkspace.shared.runningApplications.contains { app in
            guard let appName = app.localizedName else { return false }
            return appName.lowercased().contains(nameLower) || nameLower.contains(appName.lowercased())
        }
    }

    func isAppFrontmost(bundleID: String) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    func isAppFrontmost(name: String) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let frontName = front.localizedName else { return false }
        let nameLower = name.lowercased()
        return frontName.lowercased().contains(nameLower) || nameLower.contains(frontName.lowercased())
    }

    /// Returns the PID for an app with the given bundle ID, or -1 if not running.
    func pid(forBundleID bundleID: String) -> Int32 {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }
            .map { Int32($0.processIdentifier) } ?? -1
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

    func refresh() {
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
