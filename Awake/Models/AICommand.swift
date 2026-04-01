import Foundation

enum AICommand {
    // Timer
    case setTimer(durationMinutes: Int)
    case setDelayedTimer(delayMinutes: Int, durationMinutes: Int)
    case extendTimer(minutes: Int)
    case awakeUntil(hour: Int, minute: Int)
    case awakeAt(hour: Int, minute: Int, durationMinutes: Int?)
    case sleepAt(hour: Int, minute: Int)
    case pause(minutes: Int)

    // Apps
    case watchApp(appName: String, mode: WatchMode)
    case unwatchApp(appName: String)
    case watchProcess(processName: String)

    // Schedule
    case setSchedule(startHour: Int, endHour: Int, days: [Int])
    case setBatteryThreshold(percentage: Int)

    // Control
    case toggle(state: Bool)
    case cancelRule(name: String)
    case clearRules

    // Info
    case listRules
    case listApps
    case status

    case unknown(raw: String)

    var responseDescription: String {
        switch self {
        case .setTimer(let mins):
            return "Timer set for \(formatDuration(mins))."
        case .setDelayedTimer(let delay, let duration):
            return "Will stay awake in \(delay)m for \(formatDuration(duration))."
        case .extendTimer(let mins):
            return "Timer extended by \(formatDuration(mins))."
        case .awakeUntil(let hour, let minute):
            return "Staying awake until \(formatTime(hour, minute))."
        case .awakeAt(let hour, let minute, let duration):
            if let d = duration {
                return "Will activate at \(formatTime(hour, minute)) for \(formatDuration(d))."
            }
            return "Will activate at \(formatTime(hour, minute))."
        case .sleepAt(let hour, let minute):
            return "Will allow sleep at \(formatTime(hour, minute))."
        case .pause(let mins):
            return "Paused for \(mins) minutes. Will re-enable after."
        case .watchApp(let name, let mode):
            return "Now watching \(name) (\(mode == .whenRunning ? "when running" : "when frontmost"))."
        case .unwatchApp(let name):
            return "Stopped watching \(name)."
        case .watchProcess(let name):
            return "Will stay awake while \(name) is running."
        case .setSchedule(let start, let end, _):
            return "Schedule set: \(formatTime(start, 0)) to \(formatTime(end, 0))."
        case .setBatteryThreshold(let pct):
            return "Battery threshold set to \(pct)%."
        case .toggle(let state):
            return state ? "Keeping awake indefinitely." : "Allowing sleep."
        case .cancelRule(let name):
            return "Removed rule: \(name)."
        case .clearRules:
            return "All rules cleared."
        case .listRules:
            return "" // Handled by applyCommand
        case .listApps:
            return "" // Handled by applyCommand
        case .status:
            return "" // Handled by applyCommand
        case .unknown(let raw):
            return "I'm not sure how to handle that: \(raw)"
        }
    }

    private func formatTime(_ hour: Int, _ minute: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        if minute == 0 {
            return "\(h) \(ampm)"
        }
        return String(format: "%d:%02d %@", h, minute, ampm)
    }

    private func formatDuration(_ mins: Int) -> String {
        if mins >= 60 {
            let hours = mins / 60
            let remaining = mins % 60
            if remaining == 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s")"
            }
            return "\(hours)h \(remaining)m"
        }
        return "\(mins) minutes"
    }
}
