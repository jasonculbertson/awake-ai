import Foundation
import IOKit.ps
import os

final class BatteryMonitorService: ObservableObject {
    @Published private(set) var batteryLevel: Int = 100
    @Published private(set) var isPluggedIn: Bool = true
    @Published private(set) var hasBattery: Bool = false

    private var timer: Timer?
    private let logger = Logger(subsystem: Constants.appName, category: "BatteryMonitor")

    func startMonitoring(interval: TimeInterval = Constants.batteryPollingInterval) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func isBelowThreshold(_ threshold: Int) -> Bool {
        hasBattery && !isPluggedIn && batteryLevel < threshold
    }

    private func refresh() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            hasBattery = false
            return
        }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            if let type = desc[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                hasBattery = true

                if let currentCapacity = desc[kIOPSCurrentCapacityKey] as? Int,
                   let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int,
                   maxCapacity > 0 {
                    batteryLevel = Int(Double(currentCapacity) / Double(maxCapacity) * 100)
                }

                if let powerSource = desc[kIOPSPowerSourceStateKey] as? String {
                    isPluggedIn = (powerSource == kIOPSACPowerValue)
                }

                return
            }
        }

        hasBattery = false
    }
}
