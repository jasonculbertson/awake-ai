import Darwin
import Foundation
import os

struct DetectedProcess: Identifiable, Equatable {
    let id: Int32 // PID
    let name: String
    let startTime: Date
}

final class ProcessMonitorService: ObservableObject {
    @Published private(set) var detectedProcesses: [DetectedProcess] = []
    @Published var watchedProcessNames: [String] = Constants.defaultWatchedProcesses

    private var timer: Timer?
    private let logger = Logger(subsystem: Constants.appName, category: "ProcessMonitor")

    var hasMatchingProcesses: Bool {
        !detectedProcesses.isEmpty
    }

    func startMonitoring(interval: TimeInterval = Constants.processPollingInterval) {
        // Guard against double-start: calling startMonitoring() while already monitoring
        // would add a second orphaned timer to the RunLoop causing duplicate scans.
        guard timer == nil else { return }
        scan()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.scan()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func scan() {
        // Run sysctl on a background queue so the main thread isn't blocked
        let watched = watchedProcessNames
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let allProcesses = self.getRunningProcesses()
            let now = Date()
            let found = allProcesses.filter { proc in
                let matchesName = watched.contains { w in
                    proc.name.lowercased().contains(w.lowercased())
                }
                return matchesName && now.timeIntervalSince(proc.startTime) >= Constants.processMinRuntime
            }
            DispatchQueue.main.async {
                self.detectedProcesses = found
            }
        }
    }

    /// Uses sysctl to enumerate processes — works inside App Sandbox
    private func getRunningProcesses() -> [DetectedProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0

        // Get buffer size
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else {
            logger.error("sysctl size query failed")
            return []
        }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)

        // Get process list
        guard sysctl(&mib, UInt32(mib.count), &procList, &size, nil, 0) == 0 else {
            logger.error("sysctl proc query failed")
            return []
        }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride
        var results: [DetectedProcess] = []

        for i in 0..<actualCount {
            let proc = procList[i]
            let pid = proc.kp_proc.p_pid

            // Extract process name from kp_proc.p_comm (C char array)
            let name = withUnsafePointer(to: proc.kp_proc.p_comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cstr in
                    String(cString: cstr)
                }
            }

            // Get start time
            let startSec = proc.kp_proc.p_starttime.tv_sec
            let startTime = Date(timeIntervalSince1970: TimeInterval(startSec))

            guard !name.isEmpty, pid > 0 else { continue }

            results.append(DetectedProcess(id: pid, name: name, startTime: startTime))
        }

        return results
    }
}
