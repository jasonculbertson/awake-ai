import Foundation
import CoreWLAN
import os

/// Monitors the current Wi-Fi SSID using CoreWLAN.
/// Note: Reading the SSID requires the `com.apple.security.personal-information.location`
/// entitlement on macOS 10.15+. Without it, `ssid()` returns nil.
final class WiFiMonitorService: NSObject, ObservableObject, CWEventDelegate {
    @Published private(set) var currentSSID: String?

    private var client: CWWiFiClient?
    private var pollingTimer: Timer?
    private let logger = Logger(subsystem: Constants.appName, category: "WiFiMonitor")

    func startMonitoring() {
        client = CWWiFiClient.shared()
        client?.delegate = self

        do {
            try client?.startMonitoringEvent(with: .ssidDidChange)
            logger.info("WiFi SSID event monitoring started")
        } catch {
            logger.warning("Failed to start WiFi event monitoring: \(error.localizedDescription). Falling back to polling.")
        }

        // Always poll initially and as fallback
        refresh()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        pollingTimer = t
    }

    func stopMonitoring() {
        try? client?.stopMonitoringAllEvents()
        pollingTimer?.invalidate()
        pollingTimer = nil
        client = nil
    }

    func matches(ssid: String) -> Bool {
        guard let current = currentSSID else { return false }
        return current.lowercased() == ssid.lowercased()
    }

    private func refresh() {
        let ssid = client?.interface()?.ssid()
        DispatchQueue.main.async { [weak self] in
            self?.currentSSID = ssid
        }
    }

    // MARK: - CWEventDelegate

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        refresh()
    }
}
