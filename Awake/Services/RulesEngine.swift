import AppKit
import Combine
import Foundation
import os

@MainActor
final class RulesEngine: ObservableObject {
    @Published private(set) var currentState: AwakeState = .inactive
    @Published var rules: [AwakeRule] = []
    @Published var watchList: [AppWatchEntry] = []

    private let powerManager: PowerManager
    private let appMonitor: AppMonitorService
    private let processMonitor: ProcessMonitorService
    private let batteryMonitor: BatteryMonitorService
    private let persistence: PersistenceService
    private let notificationService: NotificationService

    private var evaluationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var previouslyActive = false
    private var previousReasons: [String] = []
    private let logger = Logger(subsystem: Constants.appName, category: "RulesEngine")

    init(
        powerManager: PowerManager,
        appMonitor: AppMonitorService,
        processMonitor: ProcessMonitorService,
        batteryMonitor: BatteryMonitorService,
        persistence: PersistenceService,
        notificationService: NotificationService = NotificationService()
    ) {
        self.powerManager = powerManager
        self.appMonitor = appMonitor
        self.processMonitor = processMonitor
        self.batteryMonitor = batteryMonitor
        self.persistence = persistence
        self.notificationService = notificationService

        rules = persistence.loadRules()
        watchList = persistence.loadWatchList()

        setupBindings()
    }

    func startEvaluating(interval: TimeInterval = Constants.evaluationInterval) {
        evaluate()
        evaluationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }
    }

    func stopEvaluating() {
        evaluationTimer?.invalidate()
        evaluationTimer = nil
    }

    // MARK: - Rule Management

    func addRule(_ rule: AwakeRule) {
        rules.append(rule)
        persistence.saveRules(rules)
        evaluate()
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        persistence.saveRules(rules)
        evaluate()
    }

    func updateRule(_ rule: AwakeRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            persistence.saveRules(rules)
            evaluate()
        }
    }

    func clearAllRules() {
        rules.removeAll()
        persistence.saveRules(rules)
        evaluate()
    }

    // MARK: - Watch List

    func updateWatchList(_ entries: [AppWatchEntry]) {
        watchList = entries
        persistence.saveWatchList(entries)
        evaluate()
    }

    func toggleWatchEntry(id: UUID) {
        if let index = watchList.firstIndex(where: { $0.id == id }) {
            watchList[index].isEnabled.toggle()
            persistence.saveWatchList(watchList)
            evaluate()
        }
    }

    // MARK: - Manual Toggle

    func toggleManual() {
        if let manualIndex = rules.firstIndex(where: { $0.type == .manual }) {
            rules.remove(at: manualIndex)
        } else {
            let rule = AwakeRule(type: .manual, label: "Manually activated")
            rules.append(rule)
        }
        persistence.saveRules(rules)
        evaluate()
    }

    var isManuallyActive: Bool {
        rules.contains { $0.type == .manual && $0.isEnabled }
    }

    // MARK: - Timer

    func startTimer(minutes: Int) {
        // Remove existing timers
        rules.removeAll { $0.type == .timer }

        let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let rule = AwakeRule(
            type: .timer,
            label: "Timer",
            timerEndDate: endDate,
            timerDuration: TimeInterval(minutes * 60)
        )
        rules.append(rule)
        persistence.saveRules(rules)
        evaluate()
    }

    func cancelTimer() {
        rules.removeAll { $0.type == .timer }
        persistence.saveRules(rules)
        evaluate()
    }

    var activeTimer: AwakeRule? {
        rules.first { $0.type == .timer && $0.isEnabled }
    }

    var timerRemaining: TimeInterval? {
        guard let timer = activeTimer, let endDate = timer.timerEndDate else { return nil }
        let remaining = endDate.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    // MARK: - AI Command Handling

    func applyCommand(_ command: AICommand) -> String {
        switch command {
        case .setTimer(let mins):
            startTimer(minutes: mins)
            return command.responseDescription

        case .setDelayedTimer(let delay, let duration):
            // Schedule a timer to start after delay
            let delaySeconds = TimeInterval(delay * 60)
            DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
                Task { @MainActor in
                    self?.startTimer(minutes: duration)
                }
            }
            return command.responseDescription

        case .awakeUntil(let hour, let minute):
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard var targetDate = calendar.date(from: components) else {
                return "Could not parse that time."
            }

            // If the time has already passed today, use tomorrow
            if targetDate <= Date() {
                targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate) ?? targetDate
            }

            let remaining = targetDate.timeIntervalSinceNow
            let minutes = Int(remaining / 60)
            if minutes > 0 {
                startTimer(minutes: minutes)
            }
            return command.responseDescription

        case .awakeAt(let hour, let minute, let durationMinutes):
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard var targetDate = calendar.date(from: components) else {
                return "Could not parse that time."
            }

            if targetDate <= Date() {
                targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate) ?? targetDate
            }

            let delay = targetDate.timeIntervalSinceNow
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                Task { @MainActor in
                    let duration = durationMinutes ?? 60 // Default 1 hour if not specified
                    self?.startTimer(minutes: duration)
                }
            }
            return command.responseDescription

        case .watchApp(let name, let mode):
            let nameLower = name.lowercased()
            // Try to find in existing watch list (by name, case-insensitive, partial match)
            if let index = watchList.firstIndex(where: {
                $0.appName.lowercased().contains(nameLower) || nameLower.contains($0.appName.lowercased())
            }) {
                watchList[index].isEnabled = true
                watchList[index].mode = mode
                logger.info("AI: Enabled existing watch entry: \(self.watchList[index].appName) (\(self.watchList[index].bundleIdentifier))")
            } else {
                // Look up bundle ID from running apps via appMonitor
                let bundleID = appMonitor.findBundleID(forName: name) ?? ""
                let resolvedName = appMonitor.findAppName(forQuery: name) ?? name
                logger.info("AI: Adding new watch entry: \(resolvedName) bundleID=\(bundleID)")
                let entry = AppWatchEntry(
                    bundleIdentifier: bundleID,
                    appName: resolvedName,
                    mode: mode,
                    isEnabled: true
                )
                watchList.append(entry)
            }
            persistence.saveWatchList(watchList)
            logger.info("AI: Watchlist saved with \(self.watchList.count) entries, \(self.watchList.filter(\.isEnabled).count) enabled")
            evaluate()
            return command.responseDescription

        case .unwatchApp(let name):
            let nameLower = name.lowercased()
            if let index = watchList.firstIndex(where: {
                $0.appName.lowercased().contains(nameLower) || nameLower.contains($0.appName.lowercased())
            }) {
                watchList[index].isEnabled = false
                persistence.saveWatchList(watchList)
                evaluate()
            }
            return command.responseDescription

        case .extendTimer(let mins):
            if let current = activeTimer, let endDate = current.timerEndDate {
                let newEnd = endDate.addingTimeInterval(TimeInterval(mins * 60))
                var updated = current
                updated.timerEndDate = newEnd
                updateRule(updated)
            } else {
                // No timer running, just start one
                startTimer(minutes: mins)
            }
            return command.responseDescription

        case .sleepAt(let hour, let minute):
            // "sleep at midnight" = stay awake until that time, then allow sleep
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard var targetDate = calendar.date(from: components) else {
                return "Could not parse that time."
            }
            if targetDate <= Date() {
                targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate) ?? targetDate
            }
            let remaining = Int(targetDate.timeIntervalSinceNow / 60)
            if remaining > 0 {
                // Turn on now, set timer to expire at the target time
                if !isManuallyActive { toggleManual() }
                startTimer(minutes: remaining)
            }
            return command.responseDescription

        case .pause(let mins):
            // Save current state, disable everything, re-enable after delay
            let savedManual = isManuallyActive
            let savedEnabledWatchIDs = watchList.filter(\.isEnabled).map(\.id)
            // Disable everything
            if isManuallyActive { toggleManual() }
            for i in watchList.indices where watchList[i].isEnabled {
                watchList[i].isEnabled = false
            }
            persistence.saveWatchList(watchList)
            evaluate()
            // Re-enable after pause
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(mins * 60)) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    if savedManual { self.toggleManual() }
                    for i in self.watchList.indices where savedEnabledWatchIDs.contains(self.watchList[i].id) {
                        self.watchList[i].isEnabled = true
                    }
                    self.persistence.saveWatchList(self.watchList)
                    self.evaluate()
                }
            }
            return command.responseDescription

        case .watchProcess(let processName):
            // Add to watched process list and enable process detection
            if !processMonitor.watchedProcessNames.contains(where: { $0.lowercased() == processName.lowercased() }) {
                processMonitor.watchedProcessNames.append(processName)
            }
            persistence.processDetectionEnabled = true
            processMonitor.startMonitoring()
            evaluate()
            return command.responseDescription

        case .setSchedule(let start, let end, let days):
            rules.removeAll { $0.type == .schedule }
            let rule = AwakeRule(
                type: .schedule,
                label: "Schedule: \(start):00-\(end):00",
                scheduleStartHour: start,
                scheduleEndHour: end,
                scheduleDays: Set(days)
            )
            addRule(rule)
            return command.responseDescription

        case .setBatteryThreshold(let pct):
            persistence.batteryThreshold = pct
            persistence.batteryThresholdEnabled = true
            evaluate()
            return command.responseDescription

        case .toggle(let state):
            if state && !isManuallyActive {
                toggleManual()
            } else if !state && isManuallyActive {
                toggleManual()
            }
            return command.responseDescription

        case .cancelRule(let name):
            let nameLower = name.lowercased()
            // Try rules first
            if let index = rules.firstIndex(where: { $0.label.lowercased().contains(nameLower) || nameLower.contains($0.type.rawValue.lowercased()) }) {
                rules.remove(at: index)
                persistence.saveRules(rules)
                evaluate()
                return command.responseDescription
            }
            // Try watch list
            if let index = watchList.firstIndex(where: { $0.appName.lowercased().contains(nameLower) || nameLower.contains($0.appName.lowercased()) }) {
                watchList[index].isEnabled = false
                persistence.saveWatchList(watchList)
                evaluate()
                return "Disabled: \(watchList[index].appName)."
            }
            // Try "timer"
            if nameLower.contains("timer") {
                cancelTimer()
                return "Timer cancelled."
            }
            return "No rule found matching \"\(name)\"."

        case .clearRules:
            clearAllRules()
            return command.responseDescription

        case .listRules:
            let ruleDescriptions = rules.filter(\.isEnabled).map { "• \($0.label)" }
            let watchDescriptions = watchList.filter(\.isEnabled).map { "• \($0.appName) (\($0.mode.rawValue))" }
            let all = ruleDescriptions + watchDescriptions
            if persistence.batteryThresholdEnabled {
                return (all.isEmpty ? "No active rules." : all.joined(separator: "\n")) + "\n• Battery threshold: \(persistence.batteryThreshold)%"
            }
            return all.isEmpty ? "No active rules." : all.joined(separator: "\n")

        case .listApps:
            let enabled = watchList.filter(\.isEnabled)
            if enabled.isEmpty {
                return "No apps being watched."
            }
            return "Watching:\n" + enabled.map { "• \($0.appName) (\($0.mode.rawValue))" }.joined(separator: "\n")

        case .status:
            if !currentState.isActive {
                return "Asleep. No active rules keeping the system awake."
            }
            let reasons = currentState.reasons.map { "• \($0.description)" }.joined(separator: "\n")
            return "Awake because:\n\(reasons)"

        case .unknown:
            return command.responseDescription
        }
    }

    // MARK: - Evaluation

    private func evaluate() {
        var reasons: [ActivationReason] = []

        // Check battery threshold override first
        if persistence.batteryThresholdEnabled &&
            batteryMonitor.isBelowThreshold(persistence.batteryThreshold) {
            deactivate()
            logger.info("Battery below threshold (\(self.persistence.batteryThreshold)%), deactivating")
            return
        }

        // Check manual rule
        if let manual = rules.first(where: { $0.type == .manual && $0.isEnabled }) {
            reasons.append(ActivationReason(ruleID: manual.id, description: "Manually activated", icon: "hand.tap"))
        }

        // Check timer rules
        for rule in rules where rule.type == .timer && rule.isEnabled {
            if let endDate = rule.timerEndDate {
                let remaining = endDate.timeIntervalSinceNow
                if remaining > 0 {
                    let formatted = formatTimeInterval(remaining)
                    reasons.append(ActivationReason(ruleID: rule.id, description: "Timer: \(formatted) remaining", icon: "timer"))
                } else {
                    // Timer expired, clean it up
                    rules.removeAll { $0.id == rule.id }
                    persistence.saveRules(rules)
                }
            }
        }

        // Check app watch list
        for i in watchList.indices where watchList[i].isEnabled {
            var entry = watchList[i]

            // If bundle ID is empty, try to resolve it from running apps
            if entry.bundleIdentifier.isEmpty {
                if let resolvedBID = appMonitor.findBundleID(forName: entry.appName) {
                    entry.bundleIdentifier = resolvedBID
                    watchList[i].bundleIdentifier = resolvedBID
                    persistence.saveWatchList(watchList)
                    logger.info("Resolved bundle ID for \(entry.appName): \(resolvedBID)")
                }
            }

            let isActive: Bool
            if !entry.bundleIdentifier.isEmpty {
                switch entry.mode {
                case .whenRunning:
                    isActive = appMonitor.isAppRunning(bundleID: entry.bundleIdentifier)
                case .whenFrontmost:
                    isActive = appMonitor.isAppFrontmost(bundleID: entry.bundleIdentifier)
                }
            } else {
                // Fallback: match by name
                switch entry.mode {
                case .whenRunning:
                    isActive = appMonitor.isAppRunning(name: entry.appName)
                case .whenFrontmost:
                    isActive = appMonitor.isAppFrontmost(name: entry.appName)
                }
            }

            if isActive {
                reasons.append(ActivationReason(
                    ruleID: entry.id,
                    description: "\(entry.appName) is \(entry.mode == .whenRunning ? "running" : "frontmost")",
                    icon: "app.badge.checkmark"
                ))
            }
        }

        // Check schedule rules
        for rule in rules where rule.type == .schedule && rule.isEnabled {
            if isInSchedule(rule) {
                reasons.append(ActivationReason(ruleID: rule.id, description: rule.label, icon: "calendar"))
            }
        }

        // Check process detection
        if persistence.processDetectionEnabled && processMonitor.hasMatchingProcesses {
            let names = processMonitor.detectedProcesses.map(\.name).joined(separator: ", ")
            reasons.append(ActivationReason(
                description: "Processes running: \(names)",
                icon: "terminal"
            ))
        }

        if reasons.isEmpty {
            deactivate()
        } else {
            activate(reasons: reasons)
        }
    }

    private func activate(reasons: [ActivationReason]) {
        let reasonText = reasons.map(\.description).joined(separator: "; ")

        // Apply sleep prevention mode from settings
        powerManager.mode = persistence.sleepPreventionMode
        _ = powerManager.preventSleep(reason: reasonText)

        // Notify on state change (was inactive, now active)
        let reasonDescriptions = reasons.map(\.description)
        if !previouslyActive && persistence.notificationsEnabled {
            notificationService.sendActivated(reasons: reasonDescriptions)
        }

        previouslyActive = true
        previousReasons = reasonDescriptions
        currentState = .active(reasons: reasons)
    }

    private func deactivate() {
        // Notify on state change (was active, now inactive)
        if previouslyActive && persistence.notificationsEnabled {
            let reason = previousReasons.first ?? "no active rules"
            notificationService.sendDeactivated(reason: reason)
        }

        previouslyActive = false
        previousReasons = []
        powerManager.allowSleep()
        currentState = .inactive
    }

    private func isInSchedule(_ rule: AwakeRule) -> Bool {
        guard let startHour = rule.scheduleStartHour,
              let endHour = rule.scheduleEndHour else { return false }

        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentWeekday = calendar.component(.weekday, from: now)

        if let days = rule.scheduleDays, !days.isEmpty {
            guard days.contains(currentWeekday) else { return false }
        }

        if startHour <= endHour {
            return currentHour >= startHour && currentHour < endHour
        } else {
            // Wraps midnight
            return currentHour >= startHour || currentHour < endHour
        }
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func setupBindings() {
        // Re-evaluate when app monitoring changes
        appMonitor.$runningBundleIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)

        appMonitor.$frontmostBundleID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)
    }

}
