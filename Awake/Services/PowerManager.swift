import Foundation
import IOKit.pwr_mgt
import os

enum SleepPreventionMode: String, Codable, CaseIterable {
    /// Holds both a display-sleep and a system-sleep assertion, matching Jolt of Caffeine.
    case screenAndSystem = "Keep Screen On"
    /// Holds only a system-sleep assertion; display may still dim (useful for background workflows).
    case systemOnly = "System Sleep Only"
}

final class PowerManager: ObservableObject {
    @Published private(set) var isAsserted = false
    @Published var mode: SleepPreventionMode = .screenAndSystem

    /// Display-sleep assertion (PreventUserIdleDisplaySleep)
    private var displayAssertionID: IOPMAssertionID = 0
    /// System-sleep assertion (PreventUserIdleSystemSleep) — held alongside display assertion
    /// in screenAndSystem mode, matching Jolt of Caffeine's dual-assertion approach.
    private var systemAssertionID: IOPMAssertionID = 0
    private var currentMode: SleepPreventionMode?
    /// ProcessInfo activity token — prevents App Nap from throttling our timers
    private var activityToken: NSObjectProtocol?
    private let logger = Logger(subsystem: Constants.appName, category: "PowerManager")

    /// Checks whether the current assertions are still valid via IOKit.
    /// If any have been invalidated externally, resets internal state so the
    /// next `preventSleep` call will re-create them.
    func validateAssertion() {
        guard isAsserted else { return }
        let displayValid = displayAssertionID != 0 &&
            IOPMAssertionCopyProperties(displayAssertionID)?.takeRetainedValue() != nil
        let systemValid = systemAssertionID == 0 ||
            IOPMAssertionCopyProperties(systemAssertionID)?.takeRetainedValue() != nil
        if !displayValid || !systemValid {
            logger.warning("One or more power assertions are no longer valid — resetting")
            releaseAssertion()
        }
    }

    @discardableResult
    func preventSleep(reason: String = "Awake is keeping the system awake") -> Bool {
        if isAsserted && currentMode != mode {
            releaseAssertion()
        }

        guard !isAsserted else { return true }

        // Always create the display-sleep assertion
        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &displayAssertionID
        )
        guard displayResult == kIOReturnSuccess else {
            logger.error("Failed to create display assertion: \(displayResult)")
            return false
        }

        // In screenAndSystem mode also hold a system-sleep assertion, matching Caffeine
        if mode == .screenAndSystem {
            let systemResult = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &systemAssertionID
            )
            if systemResult != kIOReturnSuccess {
                logger.warning("Failed to create system assertion: \(systemResult) — display assertion still held")
            }
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
        if displayAssertionID != 0 {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
        }
        if systemAssertionID != 0 {
            IOPMAssertionRelease(systemAssertionID)
            systemAssertionID = 0
        }
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
