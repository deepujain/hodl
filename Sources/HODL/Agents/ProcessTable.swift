import Darwin
import Foundation

/// A lightweight process snapshot through libproc. Reads executable paths, parent PIDs, and CPU time.
/// For interpreters (node, bun, python) it reads only the script path, never the remaining arguments.
struct ProcessSample: Sendable {
    let pid: pid_t
    let parent: pid_t
    let started: UInt64
    let cpuNanos: UInt64
    let path: String
    let script: String?
}

enum ProcessTable {
    private static let interpreters: Set<String> = ["node", "bun", "deno"]

    static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return pids.prefix(Int(max(0, filled))).filter { $0 > 0 }
    }

    static func snapshotParents() -> [pid_t: pid_t] {
        var parents: [pid_t: pid_t] = [:]
        for pid in allPIDs() {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size { parents[pid] = pid_t(info.pbi_ppid) }
        }
        return parents
    }

    static func descendants(of root: pid_t, parents: [pid_t: pid_t]) -> [pid_t] {
        var children: [pid_t: [pid_t]] = [:]
        for (pid, parent) in parents { children[parent, default: []].append(pid) }
        var result: [pid_t] = []
        var queue = children[root] ?? []
        while let pid = queue.popLast() {
            result.append(pid)
            queue.append(contentsOf: children[pid] ?? [])
        }
        return result
    }

    /// Scans processes owned by this user. `cache` keeps paths keyed by PID and start time between scans.
    static func scan(cache: inout [String: (path: String, script: String?)]) -> [ProcessSample] {
        let uid = getuid()
        let timebase: mach_timebase_info_data_t = {
            var info = mach_timebase_info_data_t()
            mach_timebase_info(&info)
            return info
        }()
        var samples: [ProcessSample] = []
        var seen = Set<String>()
        for pid in allPIDs() {
            var bsd = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize, bsd.pbi_uid == uid else { continue }
            var task = proc_taskinfo()
            let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let cpuTicks = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize
                ? task.pti_total_user + task.pti_total_system : 0
            let nanos = cpuTicks * UInt64(timebase.numer) / UInt64(max(1, timebase.denom))

            let key = "\(pid):\(bsd.pbi_start_tvsec)"
            seen.insert(key)
            let entry: (path: String, script: String?)
            if let cached = cache[key] {
                entry = cached
            } else {
                let path = ProcessControl.path(of: pid) ?? ""
                let name = (path as NSString).lastPathComponent.lowercased()
                let script = interpreters.contains(name) || name.hasPrefix("python") ? scriptPath(of: pid) : nil
                entry = (path, script)
                cache[key] = entry
            }
            samples.append(ProcessSample(pid: pid, parent: pid_t(bsd.pbi_ppid), started: bsd.pbi_start_tvsec,
                                         cpuNanos: nanos, path: entry.path, script: entry.script))
        }
        cache = cache.filter { seen.contains($0.key) }
        return samples
    }

    /// The first non-flag argument after the interpreter: the script it runs. Nothing else is read out.
    private static func scriptPath(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        func skipString() { while index < size, buffer[index] != 0 { index += 1 } }
        func skipNulls() { while index < size, buffer[index] == 0 { index += 1 } }
        skipString()
        skipNulls()
        var argument = 0
        while index < size, argument < min(Int(argc), 4) {
            let start = index
            skipString()
            let value = String(decoding: buffer[start..<index], as: UTF8.self)
            index += 1
            if argument > 0, !value.hasPrefix("-") { return value }
            argument += 1
        }
        return nil
    }
}
