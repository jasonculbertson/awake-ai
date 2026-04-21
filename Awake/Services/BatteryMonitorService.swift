import Foundation
import IOKit.ps
import os

final class BatteryMonitorService: ObservableObject {
    @Published private(set) var batteryLevel: Int = 100
    @Published private(set) var isPluggedIn: Bool = true
    @Published private(set) var hasBattery: Bool = false

    private var timer: Timer?
    private var runLoopSource: CFRunLoopSource?
    private let logger = Logger(subsystem: Constants.appName, category: "BatteryMonitor")

    func startMonitoring(interval: TimeInterval = Constants.batteryPollingInterval) {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // Register IOPowerSource notification for immediate plug/unplug events
        startPowerSourceNotification()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        stopPowerSourceNotification()
    }

    func isBelowThreshold(_ threshold: Int) -> Bool {
        hasBattery && !isPluggedIn && batteryLevel < threshold
    }

    // MARK: - IOPowerSource Notification

    private func startPowerSourceNotification() {
        // IOPSNotificationCreateRunLoopSource(callback, context) – both params are passed directly.
        let selfPtr = Unmanaged.passRetained(self)
        let callback: IOPowerSourceCallbackType = { context in
            guard let ctx = context else { return }
            Unmanaged<BatteryMonitorService>.fromOpaque(ctx).takeUnretainedValue().refresh()
        }
        if let src = IOPSNotificationCreateRunLoopSource(callback, selfPtr.toOpaque())?.takeRetainedValue() {
            runLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            logger.info("Power source notification registered")
        } else {
            logger.warning("Failed to create power source run loop source")
            selfPtr.release()
        }
    }

    private func stopPowerSourceNotification() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
    }

    // MARK: - Refresh

    @objc private func refresh() {
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
