import Foundation
import ServiceManagement
import os

final class LaunchAtLoginService: ObservableObject {
    @Published var isEnabled: Bool = false

    private let logger = Logger(subsystem: Constants.appName, category: "LaunchAtLogin")

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            logger.error("Launch at login toggle failed: \(error.localizedDescription)")
        }
        // Always sync from the real system state — even if the call threw, the
        // OS may have partially succeeded or the pre-call state may have drifted.
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
