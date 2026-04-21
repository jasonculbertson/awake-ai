import Foundation
import os

/// Monitors CPU usage per process using proc_pidinfo (allowed in App Sandbox for
/// processes owned by the current user).
final class CPUMonitorService {
    private struct Sample {
        let userTicks: UInt64
        let systemTicks: UInt64
        let timestamp: Date
    }

    private var samples: [Int32: Sample] = [:]
    private let logger = Logger(subsystem: Constants.appName, category: "CPUMonitor")

    /// Returns the approximate CPU usage (0–100%) for the given PID.
    /// Two calls are needed to compute a delta; the first call returns nil.
    func cpuUsage(for pid: Int32) -> Double? {
        var taskInfo = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(size))
        guard result == size else { return nil }

        let now = Date()
        let userTicks = taskInfo.pti_total_user
        let sysTicks = taskInfo.pti_total_system

        defer {
            samples[pid] = Sample(userTicks: userTicks, systemTicks: sysTicks, timestamp: now)
        }

        guard let prev = samples[pid] else {
            // First sample — store and return nil
            return nil
        }

        let elapsed = now.timeIntervalSince(prev.timestamp)
        guard elapsed > 0 else { return nil }

        // Ticks are in nanoseconds on Apple Silicon, microseconds on Intel
        // Use the delta in absolute units and divide by elapsed time converted to same units
        let userDelta = Double(userTicks - prev.userTicks)
        let sysDelta = Double(sysTicks - prev.systemTicks)
        let totalDelta = userDelta + sysDelta

        // Convert nanoseconds to seconds and divide by wall-clock elapsed seconds
        // then multiply by 100 to get percentage (normalized to single core)
        let cpuUsage = (totalDelta / 1_000_000_000) / elapsed * 100.0
        return min(cpuUsage, 100.0 * Double(ProcessInfo.processInfo.activeProcessorCount))
    }

    /// Clear stored sample for a PID (e.g. when the app closes).
    func clearSample(for pid: Int32) {
        samples.removeValue(forKey: pid)
    }

    func clearAllSamples() {
        samples.removeAll()
    }
}
