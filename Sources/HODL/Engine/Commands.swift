import AppKit
import Foundation

/// One command set for the `hodl://` URL scheme, the local HTTP API, the CLI, and hooks.
@MainActor
enum Commands {
    /// Runs a command and returns the status afterwards. `nil` means the command is unknown.
    static func run(_ name: String, _ query: [String: String], source: String) -> [String: Any]? {
        let engine = HoldEngine.shared
        let hours = query["hours"].flatMap(Double.init)
        switch name {
        case "hold", "overnight":
            let adaptive = query["until"] == "agents-idle" ? true : query["until"] == "timer" ? false : nil
            let duration: TimeInterval? = query["unlimited"] == "1" ? .infinity : hours.map { $0 * 3600 } ?? untilClock(query["at"])
            engine.hold(duration: duration, adaptive: adaptive, source: source)
        case "release", "stop":
            engine.release(.user)
        case "toggle":
            engine.toggle(source: source)
        case "extend", "add":
            engine.extend(hours: hours ?? 1)
        case "pause":
            engine.pause(minutes: query["minutes"].flatMap(Double.init) ?? 30)
        case "resume":
            engine.resume()
        case "display-off":
            engine.displayOffNow()
        case "status":
            break
        case "hook":
            AgentMonitor.shared.hook(agent: query["agent"] ?? "", session: query["session"] ?? "",
                                     state: query["state"] ?? "working", pid: query["pid"].flatMap { pid_t($0) })
            engine.evaluate()
        case "heartbeat", "lease":
            AgentMonitor.shared.heartbeat(id: query["id"] ?? "lease", agent: query["agent"],
                                          ttl: query["ttl"].flatMap(Double.init) ?? 90, pid: query["pid"].flatMap { pid_t($0) })
            engine.evaluate()
        case "lease-end":
            AgentMonitor.shared.endLease(id: query["id"] ?? "lease")
            engine.evaluate()
        case "install-hooks":
            var result = status()
            result["report"] = HookInstaller.installAll()
            return result
        default:
            return nil
        }
        return status()
    }

    /// "07:00" means the next 7 AM.
    private static func untilClock(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard let hour = parts.first, (0..<24).contains(hour) else { return nil }
        var components = DateComponents()
        components.hour = hour
        components.minute = parts.count > 1 ? parts[1] : 0
        guard let date = Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) else { return nil }
        return date.timeIntervalSinceNow
    }

    static func status() -> [String: Any] {
        let engine = HoldEngine.shared
        let power = PowerMonitor.shared
        var result: [String: Any] = [
            "holding": engine.session != nil,
            "engaged": engine.engaged,
            "status": engine.statusLine,
            "adaptive": engine.session?.adaptive ?? Prefs.bool(Prefs.adaptive),
            "on_ac": power.onAC,
            "thermal": power.thermalTitle.lowercased(),
            "lid_closed": power.lidClosed,
            "assertions": SleepGuard.shared.summary,
            "agents": AgentMonitor.shared.statuses.filter { $0.state != .off }.map {
                ["id": $0.harness.id, "title": $0.harness.title, "state": $0.state.rawValue,
                 "processes": $0.processes, "sessions": $0.sessions.count] as [String: Any]
            },
        ]
        if let percent = power.percent { result["battery"] = percent }
        if let remaining = engine.remaining { result["remaining_seconds"] = Int(remaining) }
        if let ends = engine.session?.ends { result["ends"] = ISO8601DateFormatter().string(from: ends) }
        if let standby = engine.standby { result["standby"] = standby }
        if let release = engine.lastRelease { result["last_release"] = release.reason.rawValue }
        if let refusal = engine.refusal { result["refused"] = refusal }
        if let warning = engine.restoreWarning { result["warning"] = warning }
        return result
    }

    static func handle(url: URL) {
        guard url.scheme?.lowercased() == "hodl" else { return }
        let name = (url.host() ?? url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        let query = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        }, uniquingKeysWith: { _, last in last })
        if name == "status" {
            AppWindows.shared.showSession()
            return
        }
        _ = run(name, query, source: "hodl://")
    }
}
