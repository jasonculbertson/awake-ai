import Foundation
import os

final class PersistenceService {
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: Constants.appName, category: "Persistence")

    private var appSupportDir: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Awake", isDirectory: true)
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }

    private var rulesURL: URL {
        appSupportDir.appendingPathComponent("rules.json")
    }

    private var watchListURL: URL {
        appSupportDir.appendingPathComponent("watchlist.json")
    }

    // MARK: - Rules

    func loadRules() -> [AwakeRule] {
        guard let data = try? Data(contentsOf: rulesURL) else { return [] }
        do {
            return try JSONDecoder().decode([AwakeRule].self, from: data)
        } catch {
            logger.error("Failed to decode rules: \(error.localizedDescription)")
            return []
        }
    }

    func saveRules(_ rules: [AwakeRule]) {
        do {
            let data = try JSONEncoder().encode(rules)
            try data.write(to: rulesURL, options: .atomic)
        } catch {
            logger.error("Failed to save rules: \(error.localizedDescription)")
        }
    }

    // MARK: - Watch List

    func loadWatchList() -> [AppWatchEntry] {
        guard let data = try? Data(contentsOf: watchListURL) else {
            return defaultWatchList()
        }
        do {
            return try JSONDecoder().decode([AppWatchEntry].self, from: data)
        } catch {
            logger.error("Failed to decode watch list: \(error.localizedDescription)")
            return defaultWatchList()
        }
    }

    func saveWatchList(_ entries: [AppWatchEntry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: watchListURL, options: .atomic)
        } catch {
            logger.error("Failed to save watch list: \(error.localizedDescription)")
        }
    }

    func defaultWatchList() -> [AppWatchEntry] {
        Constants.defaultWatchedApps.map { bundleID, name in
            AppWatchEntry(
                bundleIdentifier: bundleID,
                appName: name,
                mode: .whenRunning,
                isEnabled: false
            )
        }
    }

    // MARK: - Settings (UserDefaults)

    var batteryThreshold: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: "batteryThreshold")
            return val == 0 ? Constants.defaultBatteryThreshold : val
        }
        set { UserDefaults.standard.set(newValue, forKey: "batteryThreshold") }
    }

    var batteryThresholdEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "batteryThresholdEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "batteryThresholdEnabled") }
    }

    var processDetectionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "processDetectionEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "processDetectionEnabled") }
    }

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    var notificationsEnabled: Bool {
        get {
            // Default to true if never set
            if UserDefaults.standard.object(forKey: "notificationsEnabled") == nil { return true }
            return UserDefaults.standard.bool(forKey: "notificationsEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "notificationsEnabled") }
    }

    var sleepPreventionMode: SleepPreventionMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "sleepPreventionMode"),
                  let mode = SleepPreventionMode(rawValue: raw) else {
                return .systemAndDisplay
            }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "sleepPreventionMode") }
    }
}
