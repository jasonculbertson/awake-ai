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

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        appName: String,
        mode: WatchMode = .whenRunning,
        isEnabled: Bool = false
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.mode = mode
        self.isEnabled = isEnabled
    }
}
