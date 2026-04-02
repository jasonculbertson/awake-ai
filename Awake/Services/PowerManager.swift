import Foundation
import IOKit.pwr_mgt
import os

enum SleepPreventionMode: String, Codable, CaseIterable {
    case systemAndDisplay = "System & Display"
    case displayOnly = "Display Only"

    var assertionType: String {
        switch self {
        case .systemAndDisplay:
            return kIOPMAssertionTypePreventUserIdleSystemSleep
        case .displayOnly:
            return kIOPMAssertionTypePreventUserIdleDisplaySleep
        }
    }
}

final class PowerManager: ObservableObject {
    @Published private(set) var isAsserted = false
    @Published var mode: SleepPreventionMode = .systemAndDisplay

    private var assertionID: IOPMAssertionID = 0
    private var currentMode: SleepPreventionMode?
    /// ProcessInfo activity token — prevents App Nap from throttling our timers
    private var activityToken: NSObjectProtocol?
    private let logger = Logger(subsystem: Constants.appName, category: "PowerManager")

    @discardableResult
    func preventSleep(reason: String = "Awake is keeping the system awake") -> Bool {
        if isAsserted && currentMode != mode {
            releaseAssertion()
        }

        guard !isAsserted else { return true }

        let result = IOPMAssertionCreateWithName(
            mode.assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            logger.error("Failed to create power assertion: \(result) — retrying once")
            // Retry once after a brief yield
            let retry = IOPMAssertionCreateWithName(
                mode.assertionType as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &assertionID
            )
            guard retry == kIOReturnSuccess else {
                logger.error("Power assertion retry also failed: \(retry)")
                return false
            }
            isAsserted = true
            currentMode = mode
            beginActivityToken(reason: reason)
            return true
        }

        isAsserted = true
        currentMode = mode
        beginActivityToken(reason: reason)
        logger.info("Sleep prevention activated (\(self.mode.rawValue)): \(reason)")
        return true
    }

    func allowSleep() {
        guard isAsserted else { return }
        releaseAssertion()
        endActivityToken()
        logger.info("Sleep prevention deactivated")
    }

    deinit {
        releaseAssertion()
        endActivityToken()
    }

    // MARK: - Private helpers

    private func releaseAssertion() {
        guard isAsserted else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isAsserted = false
        currentMode = nil
    }

    private func beginActivityToken(reason: String) {
        guard activityToken == nil else { return }
        // .background prevents App Nap so our evaluation timer fires on schedule
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.background, .idleSystemSleepDisabled],
            reason: reason
        )
    }

    private func endActivityToken() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }
}
