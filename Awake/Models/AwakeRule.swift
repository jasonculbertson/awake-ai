import Foundation

enum RuleType: String, Codable, CaseIterable {
    case manual
    case timer
    case appRunning
    case appFrontmost
    case schedule
    case processRunning
    case batteryThreshold
}

struct AwakeRule: Identifiable, Codable, Equatable {
    let id: UUID
    var type: RuleType
    var isEnabled: Bool
    var label: String

    // App-related
    var appBundleID: String?
    var appName: String?

    // Timer
    var timerEndDate: Date?
    var timerDuration: TimeInterval?

    // Schedule
    var scheduleStartHour: Int?
    var scheduleEndHour: Int?
    var scheduleDays: Set<Int>? // 1=Sunday...7=Saturday

    // Process
    var processNames: [String]?

    // Battery
    var batteryThreshold: Int?

    // Metadata
    var createdByAI: Bool

    init(
        id: UUID = UUID(),
        type: RuleType,
        isEnabled: Bool = true,
        label: String,
        appBundleID: String? = nil,
        appName: String? = nil,
        timerEndDate: Date? = nil,
        timerDuration: TimeInterval? = nil,
        scheduleStartHour: Int? = nil,
        scheduleEndHour: Int? = nil,
        scheduleDays: Set<Int>? = nil,
        processNames: [String]? = nil,
        batteryThreshold: Int? = nil,
        createdByAI: Bool = false
    ) {
        self.id = id
        self.type = type
        self.isEnabled = isEnabled
        self.label = label
        self.appBundleID = appBundleID
        self.appName = appName
        self.timerEndDate = timerEndDate
        self.timerDuration = timerDuration
        self.scheduleStartHour = scheduleStartHour
        self.scheduleEndHour = scheduleEndHour
        self.scheduleDays = scheduleDays
        self.processNames = processNames
        self.batteryThreshold = batteryThreshold
        self.createdByAI = createdByAI
    }
}
