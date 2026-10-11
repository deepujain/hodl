import AppKit
import Observation

/// Works out which coding agents are running and whether they are working.
/// Hooks and `hodl-run` leases are authoritative; process CPU is the fallback for agents without hooks.
@MainActor @Observable
final class AgentMonitor {
    static let shared = AgentMonitor()

    private(set) var statuses: [HarnessStatus] = Harness.all.map {
        HarnessStatus(harness: $0, state: .off, processes: 0, cpu: 0, sessions: [])
    }
    private(set) var sessions: [String: AgentSession] = [:]
    private(set) var lastActive: Date?

    @ObservationIgnored private var pathCache: [String: (path: String, script: String?)] = [:]
    @ObservationIgnored private var previousCPU: [String: UInt64] = [:]
    @ObservationIgnored private var previousScan: Date?
    @ObservationIgnored private var smoothedCPU: [String: Double] = [:]
    @ObservationIgnored private var busyUntil: [String: Date] = [:]

    private init() {}

    var anyActive: Bool { statuses.contains { $0.state == .active } }
    var activeCount: Int { statuses.filter { $0.state == .active }.count }
    var runningCount: Int { statuses.filter { $0.state != .off }.count }

    #if DEBUG
    func stage(_ states: [String: AgentState]) {
        statuses = statuses.map { status in
            var staged = status
            staged.state = states[status.harness.id] ?? .off
            staged.processes = staged.state == .off ? 0 : 3
            staged.cpu = staged.state == .active ? 38 : 0
            staged.sessions = []
            return staged
        }
    }
    #endif

    /// Primary agents always, plus any others that are running.
    var visibleStatuses: [HarnessStatus] {
        statuses.filter { $0.harness.primary || $0.state != .off }
    }

    // MARK: Scanning

    func refresh() {
        let now = Date()
        let samples = ProcessTable.scan(cache: &pathCache)
        let bundles = Dictionary(NSWorkspace.shared.runningApplications.compactMap { app in
            app.bundleIdentifier.map { (app.processIdentifier, $0) }
        }, uniquingKeysWith: { first, _ in first })
        let byPID = Dictionary(samples.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let me = getpid()

        var direct: [pid_t: String] = [:]
        for sample in samples where sample.pid != me {
            if let id = Self.match(sample, bundleID: bundles[sample.pid]) { direct[sample.pid] = id }
        }

        var owner: [pid_t: String?] = [:]
        func harness(of pid: pid_t, depth: Int = 0) -> String? {
            if let known = owner[pid] { return known }
            let result: String?
            if let id = direct[pid] {
                result = id
            } else if depth < 64, let parent = byPID[pid]?.parent, parent > 1, parent != pid {
                result = harness(of: parent, depth: depth + 1)
            } else {
                result = nil
            }
            owner[pid] = result
            return result
        }

        let elapsed = previousScan.map { now.timeIntervalSince($0) } ?? 0
        var cpu: [String: Double] = [:]
        var nextCPU: [String: UInt64] = [:]
        for sample in samples {
            let key = "\(sample.pid):\(sample.started)"
            nextCPU[key] = sample.cpuNanos
            guard let id = harness(of: sample.pid), elapsed > 0, let before = previousCPU[key], sample.cpuNanos >= before else { continue }
            cpu[id, default: 0] += Double(sample.cpuNanos - before) / (elapsed * 1e9) * 100
        }
        previousCPU = nextCPU
        previousScan = now

        expireSessions(now: now, alive: Set(samples.map(\.pid)))

        statuses = Harness.all.map { harness in
            let processes = direct.values.filter { $0 == harness.id }.count
            let smoothed = 0.5 * (smoothedCPU[harness.id] ?? 0) + 0.5 * (cpu[harness.id] ?? 0)
            smoothedCPU[harness.id] = smoothed
            if processes > 0, smoothed >= harness.busyCPU { busyUntil[harness.id] = now.addingTimeInterval(45) }
            let busy = (busyUntil[harness.id] ?? .distantPast) > now && processes > 0

            let mine = sessions.values.filter { $0.harnessID == harness.id }.sorted { $0.since < $1.since }
            let hooks = mine.filter { $0.source == .hook }
            let working = mine.contains { $0.working }
            let state: AgentState
            if working {
                state = .active
            } else if harness.hooksReportWork, !hooks.isEmpty {
                state = .idle
            } else if busy {
                state = .active
            } else if !hooks.isEmpty {
                state = .idle
            } else if processes > 0 {
                state = .detected
            } else {
                state = .off
            }
            return HarnessStatus(harness: harness, state: state, processes: processes, cpu: smoothed, sessions: mine)
        }
        if anyActive { lastActive = now }
    }

    private static func match(_ sample: ProcessSample, bundleID: String?) -> String? {
        let name = (sample.path as NSString).lastPathComponent
        let insideApp = sample.path.contains(".app/Contents/MacOS/")
        let scriptName = sample.script.map { ($0 as NSString).lastPathComponent }
        for harness in Harness.all {
            if let bundleID, harness.bundleIDs.contains(bundleID) { return harness.id }
            if !insideApp, harness.executables.contains(name) { return harness.id }
            if let scriptName, harness.executables.contains(scriptName) { return harness.id }
            if harness.pathMarkers.contains(where: { sample.path.contains($0) || (sample.script?.contains($0) ?? false) }) {
                return harness.id
            }
        }
        return nil
    }

    private func expireSessions(now: Date, alive: Set<pid_t>) {
        sessions = sessions.filter { _, session in
            if let expires = session.expires, expires < now { return false }
            if let pid = session.pid, !alive.contains(pid) { return false }
            return now.timeIntervalSince(session.updated) < 12 * 3600
        }
        // A hook that said "working" and then went silent for hours without a process to watch is stale.
        for (key, session) in sessions where session.working && session.pid == nil && session.source == .hook
            && now.timeIntervalSince(session.updated) > 3 * 3600 {
            sessions[key]?.working = false
        }
    }

    // MARK: Hooks and leases

    /// A lifecycle hook from Claude Code, Codex, OpenCode, or Cursor. Only the session ID is sent; nothing else.
    func hook(agent: String, session: String, state: String, pid: pid_t?) {
        guard let harness = Harness.named(agent) else { return }
        let sessionID = Self.clean(session).isEmpty ? "default" : Self.clean(session)
        let key = "hook:\(harness.id):\(sessionID)"
        let now = Date()
        if state == "ended" {
            sessions[key] = nil
        } else {
            let working = state == "working"
            var entry = sessions[key] ?? AgentSession(key: key, harnessID: harness.id, session: sessionID, source: .hook,
                                                      working: working, since: now, updated: now,
                                                      pid: pid.flatMap { Self.agentProcess(from: $0, harness: harness) })
            if entry.working != working { entry.since = now }
            entry.working = working
            entry.updated = now
            sessions[key] = entry
        }
        refresh()
    }

    /// A heartbeat from `hodl-run` or any script: "keep holding while I’m alive", renewed before `ttl` runs out.
    func heartbeat(id: String, agent: String?, ttl: TimeInterval, pid: pid_t?) {
        let leaseID = Self.clean(id).isEmpty ? "lease" : Self.clean(id)
        let harnessID = agent.flatMap { Harness.named($0)?.id } ?? "cline"
        let key = "lease:\(leaseID)"
        let now = Date()
        var lease = sessions[key] ?? AgentSession(key: key, harnessID: harnessID, session: leaseID, source: .lease,
                                                  working: true, since: now, updated: now, pid: pid)
        lease.updated = now
        lease.expires = now.addingTimeInterval(min(max(ttl, 15), 900))
        sessions[key] = lease
        refresh()
    }

    func endLease(id: String) {
        sessions["lease:\(Self.clean(id))"] = nil
        refresh()
    }

    /// Hooks run in a short-lived shell; walk up to the agent process itself so the session ends when it does.
    private static func agentProcess(from pid: pid_t, harness: Harness) -> pid_t? {
        let parents = ProcessTable.snapshotParents()
        var current = pid
        for _ in 0..<12 {
            guard current > 1 else { break }
            if let path = ProcessControl.path(of: current) {
                let sample = ProcessSample(pid: current, parent: parents[current] ?? 0, started: 0, cpuNanos: 0, path: path, script: nil)
                let bundle = NSRunningApplication(processIdentifier: current)?.bundleIdentifier
                if match(sample, bundleID: bundle) == harness.id { return current }
            }
            current = parents[current] ?? 0
        }
        return nil
    }

    private static func clean(_ value: String) -> String {
        String(value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || "-_.:".unicodeScalars.contains($0) }.prefix(64))
    }
}
