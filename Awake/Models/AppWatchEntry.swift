import Foundation

enum WatchMode: String, Codable, CaseIterable {
    case whenRunning = "When Running"
    case whenFrontmost = "When Frontmost"
}

struct AppWatchEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var bundleIdentifier: String
    var appName: String
    var mode: WatchMode
    var isEnabled: Bool

    // Activity-aware monitoring
    var watchChildProcesses: Bool
    var cpuThreshold: Double?    // Deactivate when CPU drops below this % (nil = disabled)
    var cpuIdleMinutes: Int      // Minutes of low CPU before deactivating (default 3)

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        appName: String,
        mode: WatchMode = .whenRunning,
        isEnabled: Bool = false,
        watchChildProcesses: Bool = false,
        cpuThreshold: Double? = nil,
        cpuIdleMinutes: Int = 3
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.mode = mode
        self.isEnabled = isEnabled
        self.watchChildProcesses = watchChildProcesses
        self.cpuThreshold = cpuThreshold
        self.cpuIdleMinutes = cpuIdleMinutes
    }
}
