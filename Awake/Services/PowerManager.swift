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
    private let logger = Logger(subsystem: Constants.appName, category: "PowerManager")

    func preventSleep(reason: String = "Awake is keeping the system awake") -> Bool {
        if isAsserted && currentMode != mode {
            allowSleep()
        }

        guard !isAsserted else { return true }

        let result = IOPMAssertionCreateWithName(
            mode.assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isAsserted = true
            currentMode = mode
            logger.info("Sleep prevention activated (\(self.mode.rawValue)): \(reason)")
            return true
        } else {
            logger.error("Failed to create power assertion: \(result)")
            return false
        }
    }

    func allowSleep() {
        guard isAsserted else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isAsserted = false
        currentMode = nil
        logger.info("Sleep prevention deactivated")
    }

    deinit {
        allowSleep()
    }
}
