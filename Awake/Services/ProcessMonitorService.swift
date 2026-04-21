import AppKit
import Darwin
import Foundation
import os

struct DetectedProcess: Identifiable, Equatable {
    let id: Int32 // PID
    let name: String
    let startTime: Date
    let parentPID: Int32
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

    /// Returns child processes of the given parent PID from the watched list.
    func childProcesses(of parentPID: Int32) -> [DetectedProcess] {
        getAllProcesses().filter { $0.parentPID == parentPID }
    }

    /// Returns all child processes of the given parent PID matching the given name list.
    func childProcesses(of parentPID: Int32, matchingNames names: [String]) -> [DetectedProcess] {
        childProcesses(of: parentPID).filter { proc in
            names.contains { proc.name.lowercased().contains($0.lowercased()) }
        }
    }

    private func scan() {
        let watched = watchedProcessNames
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let found = self.getMatchingProcesses(watched: watched)

            DispatchQueue.main.async {
                self.detectedProcesses = found
            }
        }
    }

    // MARK: - sysctl helpers

    /// Uses sysctl to find running processes whose name matches the watched list.
    private func getMatchingProcesses(watched: [String]) -> [DetectedProcess] {
        getAllProcesses().filter { proc in
            watched.contains { proc.name.lowercased().contains($0.lowercased()) }
        }
    }

    /// Returns all running processes using sysctl KERN_PROC_ALL.
    func getAllProcesses() -> [DetectedProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0

        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else {
            logger.error("sysctl size query failed")
            return []
        }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)

        guard sysctl(&mib, UInt32(mib.count), &procList, &size, nil, 0) == 0 else {
            logger.error("sysctl proc query failed")
            return []
        }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride
        let now = Date()
        var results: [DetectedProcess] = []

        for i in 0..<actualCount {
            let proc = procList[i]
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }

            let name = withUnsafePointer(to: proc.kp_proc.p_comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cstr in
                    String(cString: cstr)
                }
            }
            guard !name.isEmpty else { continue }

            let parentPID = proc.kp_eproc.e_ppid
            let startSec = proc.kp_proc.p_starttime.tv_sec
            let startTime = Date(timeIntervalSince1970: TimeInterval(startSec))
            guard now.timeIntervalSince(startTime) >= Constants.processMinRuntime else { continue }

            results.append(DetectedProcess(id: pid, name: name, startTime: startTime, parentPID: parentPID))
        }

        return results
    }
}
