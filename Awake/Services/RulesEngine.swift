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
    private let wifiMonitor: WiFiMonitorService
    private let cpuMonitor: CPUMonitorService

    private var evaluationTimer: Timer?
    private var delayedTimers: [UUID: Timer] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var previouslyActive = false
    private var previousReasons: [String] = []
    private let logger = Logger(subsystem: Constants.appName, category: "RulesEngine")

    // Session tracking for reminder notifications
    private var sessionStartDate: Date?

    // Activity-aware monitoring: tracks when each watch entry's app went CPU-idle
    // Key: AppWatchEntry.id, Value: date when CPU dropped below threshold
    private var cpuIdleSince: [UUID: Date] = [:]

    // Child process activity tracking: entry IDs that were active due to child processes last tick
    private var previouslyActiveFromChildren: Set<UUID> = []

    // Screen change observer for external display detection
    private var screenChangeObserver: NSObjectProtocol?

    init(
        powerManager: PowerManager,
        appMonitor: AppMonitorService,
        processMonitor: ProcessMonitorService,
        batteryMonitor: BatteryMonitorService,
        persistence: PersistenceService,
        notificationService: NotificationService = NotificationService(),
        wifiMonitor: WiFiMonitorService = WiFiMonitorService(),
        cpuMonitor: CPUMonitorService = CPUMonitorService()
    ) {
        self.powerManager = powerManager
        self.appMonitor = appMonitor
        self.processMonitor = processMonitor
        self.batteryMonitor = batteryMonitor
        self.persistence = persistence
        self.notificationService = notificationService
        self.wifiMonitor = wifiMonitor
        self.cpuMonitor = cpuMonitor

        rules = persistence.loadRules()
        watchList = persistence.loadWatchList()

        setupBindings()
    }

    func startEvaluating(interval: TimeInterval = Constants.evaluationInterval) {
        guard evaluationTimer == nil else { return }
        restorePendingActions()

        // Start Wi-Fi monitoring
        wifiMonitor.startMonitoring()

        evaluate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        evaluationTimer = timer
    }

    func stopEvaluating() {
        evaluationTimer?.invalidate()
        evaluationTimer = nil
        wifiMonitor.stopMonitoring()

        if let obs = screenChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            screenChangeObserver = nil
        }
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

    // MARK: - Power Adapter Rule Convenience

    func setPowerAdapterRule(enabled: Bool, state: PowerAdapterState = .connected) {
        // Remove any existing power adapter rules
        rules.removeAll { $0.type == .powerAdapter }

        if enabled {
            let label = state == .connected ? "When power adapter connected" : "When power adapter disconnected"
            let rule = AwakeRule(
                type: .powerAdapter,
                label: label,
                powerAdapterState: state
            )
            rules.append(rule)
        }

        persistence.saveRules(rules)
        persistence.powerAdapterRuleEnabled = enabled
        evaluate()
    }

    var isPowerAdapterRuleEnabled: Bool {
        rules.contains { $0.type == .powerAdapter && $0.isEnabled }
    }

    // MARK: - Closed Lid Convenience

    func setClosedLidRule(enabled: Bool) {
        rules.removeAll { $0.type == .closedLid }

        if enabled {
            let rule = AwakeRule(
                type: .closedLid,
                label: "While lid is closed"
            )
            rules.append(rule)
        }

        persistence.saveRules(rules)
        evaluate()
    }

    var isClosedLidRuleEnabled: Bool {
        rules.contains { $0.type == .closedLid && $0.isEnabled }
    }

    // MARK: - AI Command Handling

    func applyCommand(_ command: AICommand) -> String {
        switch command {
        case .setTimer(let mins):
            startTimer(minutes: mins)
            return command.responseDescription

        case .setDelayedTimer(let delay, let duration):
            let fireDate = Date().addingTimeInterval(TimeInterval(delay * 60))
            schedulePersistedDelayedTimer(fireDate: fireDate, durationMinutes: duration)
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

            let duration = durationMinutes ?? 60
            schedulePersistedDelayedTimer(fireDate: targetDate, durationMinutes: duration)
            return command.responseDescription

        case .watchApp(let name, let mode):
            let nameLower = name.lowercased()
            if let index = watchList.firstIndex(where: {
                $0.appName.lowercased().contains(nameLower) || nameLower.contains($0.appName.lowercased())
            }) {
                watchList[index].isEnabled = true
                watchList[index].mode = mode
                logger.info("AI: Enabled existing watch entry: \(self.watchList[index].appName)")
            } else {
                let bundleID = appMonitor.findBundleID(forName: name) ?? ""
                let resolvedName = appMonitor.findAppName(forQuery: name) ?? name
                let entry = AppWatchEntry(
                    bundleIdentifier: bundleID,
                    appName: resolvedName,
                    mode: mode,
                    isEnabled: true
                )
                watchList.append(entry)
            }
            persistence.saveWatchList(watchList)
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
                startTimer(minutes: mins)
            }
            return command.responseDescription

        case .sleepAt(let hour, let minute):
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
                startTimer(minutes: remaining)
            }
            return command.responseDescription

        case .pause(let mins):
            let savedManual = isManuallyActive
            let savedEnabledWatchIDs = watchList.filter(\.isEnabled).map(\.id)
            if isManuallyActive { toggleManual() }
            for i in watchList.indices where watchList[i].isEnabled {
                watchList[i].isEnabled = false
            }
            persistence.saveWatchList(watchList)
            evaluate()
            let fireDate = Date().addingTimeInterval(TimeInterval(mins * 60))
            var action = PersistenceService.PendingAction(
                id: UUID(),
                fireDate: fireDate,
                durationMinutes: 0,
                kind: .pauseResume
            )
            action.savedManualActive = savedManual
            action.savedEnabledWatchIDs = savedEnabledWatchIDs
            persistence.addPendingAction(action)
            scheduleTimerForAction(action)
            return command.responseDescription

        case .watchProcess(let processName):
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
            if let index = rules.firstIndex(where: { $0.label.lowercased().contains(nameLower) || nameLower.contains($0.type.rawValue.lowercased()) }) {
                rules.remove(at: index)
                persistence.saveRules(rules)
                evaluate()
                return command.responseDescription
            }
            if let index = watchList.firstIndex(where: { $0.appName.lowercased().contains(nameLower) || nameLower.contains($0.appName.lowercased()) }) {
                watchList[index].isEnabled = false
                persistence.saveWatchList(watchList)
                evaluate()
                return "Disabled: \(watchList[index].appName)."
            }
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
        powerManager.validateAssertion()

        var reasons: [ActivationReason] = []

        // Check battery threshold override first
        if persistence.batteryThresholdEnabled &&
            batteryMonitor.isBelowThreshold(persistence.batteryThreshold) {
            deactivate()
            logger.info("Battery below threshold (\(self.persistence.batteryThreshold)%), deactivating")
            return
        }

        // Manual rule
        if let manual = rules.first(where: { $0.type == .manual && $0.isEnabled }) {
            reasons.append(ActivationReason(ruleID: manual.id, description: "Manually activated", icon: "hand.tap"))
        }

        // Timer rules
        for rule in rules where rule.type == .timer && rule.isEnabled {
            if let endDate = rule.timerEndDate {
                let remaining = endDate.timeIntervalSinceNow
                if remaining > 0 {
                    let formatted = formatTimeInterval(remaining)
                    reasons.append(ActivationReason(ruleID: rule.id, description: "Timer: \(formatted) remaining", icon: "timer"))
                } else {
                    rules.removeAll { $0.id == rule.id }
                    persistence.saveRules(rules)
                }
            }
        }

        // App watch list (with activity-aware monitoring)
        var currentlyActiveFromChildren: Set<UUID> = []
        for i in watchList.indices where watchList[i].isEnabled {
            var entry = watchList[i]

            // Resolve bundle ID if empty
            if entry.bundleIdentifier.isEmpty {
                if let resolvedBID = appMonitor.findBundleID(forName: entry.appName) {
                    entry.bundleIdentifier = resolvedBID
                    watchList[i].bundleIdentifier = resolvedBID
                    persistence.saveWatchList(watchList)
                }
            }

            let isRunning: Bool
            if !entry.bundleIdentifier.isEmpty {
                switch entry.mode {
                case .whenRunning:
                    isRunning = appMonitor.isAppRunning(bundleID: entry.bundleIdentifier)
                case .whenFrontmost:
                    isRunning = appMonitor.isAppFrontmost(bundleID: entry.bundleIdentifier)
                }
            } else {
                switch entry.mode {
                case .whenRunning:
                    isRunning = appMonitor.isAppRunning(name: entry.appName)
                case .whenFrontmost:
                    isRunning = appMonitor.isAppFrontmost(name: entry.appName)
                }
            }

            guard isRunning else {
                // App not running — clear CPU idle tracking
                cpuIdleSince.removeValue(forKey: entry.id)
                continue
            }

            // --- Activity-aware monitoring ---

            // 1. Child process detection
            if entry.watchChildProcesses {
                let appPID = appMonitor.pid(forBundleID: entry.bundleIdentifier)
                let childNames = Constants.appChildProcessMap[entry.bundleIdentifier] ?? []

                if appPID > 0 {
                    let activeChildren = processMonitor.childProcesses(of: appPID, matchingNames: childNames)
                    if !activeChildren.isEmpty {
                        let childNameList = activeChildren.prefix(2).map(\.name).joined(separator: ", ")
                        reasons.append(ActivationReason(
                            ruleID: entry.id,
                            description: "\(entry.appName) is working (\(childNameList))",
                            icon: "hammer.fill"
                        ))
                        currentlyActiveFromChildren.insert(entry.id)
                        cpuIdleSince.removeValue(forKey: entry.id)
                        continue
                    }
                }
            }

            // 2. CPU threshold check
            if let threshold = entry.cpuThreshold {
                let appPID = appMonitor.pid(forBundleID: entry.bundleIdentifier)
                if appPID > 0, let usage = cpuMonitor.cpuUsage(for: appPID) {
                    if usage < threshold {
                        // App is below CPU threshold
                        let idleSince = cpuIdleSince[entry.id] ?? Date()
                        if cpuIdleSince[entry.id] == nil {
                            cpuIdleSince[entry.id] = idleSince
                        }
                        let idleMinutes = Date().timeIntervalSince(idleSince) / 60
                        if idleMinutes >= Double(entry.cpuIdleMinutes) {
                            // Been idle long enough — skip this entry
                            logger.info("CPU idle for \(entry.appName) (\(usage, format: .fixed(precision: 1))% < \(threshold)%) — skipping")
                            continue
                        }
                    } else {
                        // Active — reset idle timer
                        cpuIdleSince.removeValue(forKey: entry.id)
                    }
                }
            }

            // App is running and passes activity checks
            reasons.append(ActivationReason(
                ruleID: entry.id,
                description: "\(entry.appName) is \(entry.mode == .whenRunning ? "running" : "frontmost")",
                icon: "app.badge.checkmark"
            ))
        }

        // Detect work-completion transitions (child processes disappeared)
        let justFinished = previouslyActiveFromChildren.subtracting(currentlyActiveFromChildren)
        for entryID in justFinished {
            if let entry = watchList.first(where: { $0.id == entryID }) {
                notificationService.sendWorkCompleted(
                    appName: entry.appName,
                    reason: "Build/process finished"
                )
            }
        }
        previouslyActiveFromChildren = currentlyActiveFromChildren

        // Schedule rules
        for rule in rules where rule.type == .schedule && rule.isEnabled {
            if isInSchedule(rule) {
                reasons.append(ActivationReason(ruleID: rule.id, description: rule.label, icon: "calendar"))
            }
        }

        // Process detection
        if persistence.processDetectionEnabled && processMonitor.hasMatchingProcesses {
            let names = processMonitor.detectedProcesses.map(\.name).joined(separator: ", ")
            reasons.append(ActivationReason(
                description: "Processes running: \(names)",
                icon: "terminal"
            ))
        }

        // Power adapter trigger
        for rule in rules where rule.type == .powerAdapter && rule.isEnabled {
            if let adapterState = rule.powerAdapterState {
                let conditionMet: Bool
                switch adapterState {
                case .connected:
                    conditionMet = batteryMonitor.isPluggedIn
                case .disconnected:
                    conditionMet = !batteryMonitor.isPluggedIn && batteryMonitor.hasBattery
                }
                if conditionMet {
                    reasons.append(ActivationReason(
                        ruleID: rule.id,
                        description: rule.label,
                        icon: "bolt.fill"
                    ))
                }
            }
        }

        // External display trigger
        for rule in rules where rule.type == .externalDisplay && rule.isEnabled {
            if hasExternalDisplay() {
                reasons.append(ActivationReason(
                    ruleID: rule.id,
                    description: "External display connected",
                    icon: "display"
                ))
            }
        }

        // Wi-Fi SSID trigger
        for rule in rules where rule.type == .wifiSSID && rule.isEnabled {
            if let ssid = rule.wifiSSID, wifiMonitor.matches(ssid: ssid) {
                reasons.append(ActivationReason(
                    ruleID: rule.id,
                    description: "Connected to \(ssid)",
                    icon: "wifi"
                ))
            }
        }

        // Closed lid mode
        for rule in rules where rule.type == .closedLid && rule.isEnabled {
            if isLidClosed() {
                // Force system-only mode when lid is closed (display assertion is useless)
                powerManager.mode = .systemOnly
                reasons.append(ActivationReason(
                    ruleID: rule.id,
                    description: "Keeping awake with lid closed",
                    icon: "laptopcomputer"
                ))
            }
        }

        if reasons.isEmpty {
            deactivate()
        } else {
            activate(reasons: reasons)
        }
    }

    private func activate(reasons: [ActivationReason]) {
        let reasonText = reasons.map(\.description).joined(separator: "; ")

        // Restore saved sleep mode (may have been overridden by closed lid)
        if !rules.contains(where: { $0.type == .closedLid && $0.isEnabled && isLidClosed() }) {
            powerManager.mode = persistence.sleepPreventionMode
        }

        let asserted = powerManager.preventSleep(reason: reasonText)

        if !asserted {
            logger.error("preventSleep failed — deactivating to avoid false 'awake' state")
            deactivate()
            return
        }

        let reasonDescriptions = reasons.map(\.description)

        // Session start tracking for reminder notifications
        if !previouslyActive {
            sessionStartDate = Date()
            if persistence.sessionReminderEnabled {
                let interval = TimeInterval(persistence.sessionReminderHours * 3600)
                notificationService.scheduleSessionReminder(after: interval)
            }
            if persistence.notificationsEnabled {
                notificationService.sendActivated(reasons: reasonDescriptions)
            }
        }

        previouslyActive = true
        previousReasons = reasonDescriptions
        currentState = .active(reasons: reasons)
    }

    private func deactivate() {
        if previouslyActive {
            // Cancel any pending session reminder
            notificationService.cancelSessionReminder()
            sessionStartDate = nil

            if persistence.notificationsEnabled {
                let reason = previousReasons.first ?? "no active rules"
                notificationService.sendDeactivated(reason: reason)
            }
        }

        previouslyActive = false
        previousReasons = []
        powerManager.allowSleep()
        currentState = .inactive
    }

    // MARK: - Schedule Helpers

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
            return currentHour >= startHour || currentHour < endHour
        }
    }

    // MARK: - Display Helpers

    private func hasExternalDisplay() -> Bool {
        // Any screen beyond the built-in display counts as external
        if NSScreen.screens.count > 1 { return true }
        // Single screen: check if it's NOT the built-in (e.g. Mac mini or Mac Pro)
        guard let screen = NSScreen.main else { return false }
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        return screenNumber.map { CGDisplayIsBuiltin($0) == 0 } ?? false
    }

    // MARK: - Lid State Helper

    private func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }

        // Try to read the LidOpen / AppleClamshellState property
        if let lidOpen = IORegistryEntryCreateCFProperty(service, "LidOpen" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool {
            return !lidOpen
        }

        // Fallback: check IOPMrootDomain for AppleClamshellState
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(rootDomain) }

        if let clamshell = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool {
            return clamshell
        }

        return false
    }

    // MARK: - Format Helpers

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: - Bindings Setup

    private func setupBindings() {
        appMonitor.$runningBundleIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)

        appMonitor.$frontmostBundleID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)

        processMonitor.$detectedProcesses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)

        // Re-evaluate when plugged in / unplugged (instant via IOPSNotification)
        batteryMonitor.$isPluggedIn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)

        // Re-evaluate when Wi-Fi SSID changes
        wifiMonitor.$currentSSID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)

        // Re-evaluate when screens are added/removed
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }

        // Handle "Stop Session" action from notification
        NotificationCenter.default.addObserver(
            forName: .stopSessionFromNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearAllRules()
                // Also disable all watch list entries
                if let self {
                    for i in self.watchList.indices {
                        self.watchList[i].isEnabled = false
                    }
                    self.persistence.saveWatchList(self.watchList)
                    self.evaluate()
                }
            }
        }
    }

    // MARK: - Persistent Delayed Actions

    private func schedulePersistedDelayedTimer(fireDate: Date, durationMinutes: Int) {
        let action = PersistenceService.PendingAction(
            id: UUID(),
            fireDate: fireDate,
            durationMinutes: durationMinutes,
            kind: .delayedTimer
        )
        persistence.addPendingAction(action)
        scheduleTimerForAction(action)
    }

    private func scheduleTimerForAction(_ action: PersistenceService.PendingAction) {
        let delay = max(0, action.fireDate.timeIntervalSinceNow)
        if delay <= 0 {
            handleActionFired(action)
            return
        }
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleActionFired(action)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        delayedTimers[action.id] = t
    }

    private func handleActionFired(_ action: PersistenceService.PendingAction) {
        persistence.removePendingAction(id: action.id)
        delayedTimers.removeValue(forKey: action.id)

        switch action.kind {
        case .delayedTimer:
            startTimer(minutes: action.durationMinutes)
        case .pauseResume:
            if action.savedManualActive == true && !isManuallyActive {
                toggleManual()
            }
            if let savedIDs = action.savedEnabledWatchIDs {
                for i in watchList.indices where savedIDs.contains(watchList[i].id) {
                    watchList[i].isEnabled = true
                }
                persistence.saveWatchList(watchList)
            }
            evaluate()
        }
    }

    private func restorePendingActions() {
        let actions = persistence.loadPendingActions()
        for action in actions {
            scheduleTimerForAction(action)
        }
    }
}
