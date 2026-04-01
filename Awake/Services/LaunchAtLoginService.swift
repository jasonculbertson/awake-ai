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
            isEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            logger.error("Launch at login toggle failed: \(error.localizedDescription)")
        }
    }
}
