import Foundation

/// A coding agent HODL watches for. Matching uses only executable paths, the script an interpreter runs,
/// and bundle IDs. HODL never reads code, prompts, or terminal output.
struct Harness: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbol: String
    /// Exact executable names (case-sensitive, so the Claude desktop app is not Claude Code).
    var executables: [String] = []
    /// Substrings of the executable or script path.
    var pathMarkers: [String] = []
    var bundleIDs: [String] = []
    /// Shown even when not running.
    var primary = false
    /// Tree CPU percent that counts as working when no hook says otherwise.
    var busyCPU: Double = 3
    /// Its hooks report both "working" and "idle", so they override CPU guesses.
    var hooksReportWork = false

    static let all: [Harness] = [
        Harness(id: "cursor", title: "Cursor", symbol: "cursorarrow.rays",
                executables: ["cursor-agent"], bundleIDs: ["com.todesktop.230313mzl4w4u92"],
                primary: true, busyCPU: 15, hooksReportWork: true),
        Harness(id: "claude", title: "Claude Code", symbol: "asterisk",
                executables: ["claude"], pathMarkers: ["@anthropic-ai/claude-code", "/claude/versions/"],
                primary: true, hooksReportWork: true),
        Harness(id: "codex", title: "Codex", symbol: "chevron.left.forwardslash.chevron.right",
                executables: ["codex"], pathMarkers: ["@openai/codex"], bundleIDs: ["com.openai.codex"],
                primary: true, busyCPU: 8),
        Harness(id: "aider", title: "Aider", symbol: "hammer",
                executables: ["aider"], primary: true),
        Harness(id: "pi", title: "Pi", symbol: "p.circle",
                executables: ["pi"], pathMarkers: ["pi-coding-agent"], primary: true),
        Harness(id: "opencode", title: "OpenCode", symbol: "curlybraces",
                executables: ["opencode"], pathMarkers: ["opencode-ai"], hooksReportWork: true),
        Harness(id: "gemini", title: "Gemini CLI", symbol: "sparkles",
                executables: ["gemini"], pathMarkers: ["@google/gemini-cli"]),
        Harness(id: "copilot", title: "Copilot CLI", symbol: "paperplane",
                executables: ["copilot"], pathMarkers: ["@github/copilot"]),
        Harness(id: "windsurf", title: "Windsurf", symbol: "wind",
                bundleIDs: ["com.exafunction.windsurf"], busyCPU: 15),
        Harness(id: "cline", title: "Cline", symbol: "terminal",
                executables: ["cline"]),
    ]

    static func named(_ id: String) -> Harness? { all.first { $0.id == id.lowercased() } }

    /// Executables and bundles that must never be paused, throttled, or signalled.
    static var protectedBundleIDs: Set<String> { Set(all.flatMap(\.bundleIDs)) }
}

enum AgentState: String, Sendable {
    case off, detected, idle, active

    var title: String {
        switch self {
        case .off: "Not running"
        case .detected: "Detected"
        case .idle: "Idle"
        case .active: "Active"
        }
    }
}

/// One tracked agent session: a hook-reporting terminal session or an `hodl-run` lease.
struct AgentSession: Identifiable, Sendable {
    enum Source: String, Sendable { case hook, lease }

    let key: String
    let harnessID: String
    let session: String
    var source: Source
    var working: Bool
    var since: Date
    var updated: Date
    var pid: pid_t?
    var expires: Date?

    var id: String { key }
}

struct HarnessStatus: Identifiable, Sendable {
    let harness: Harness
    var state: AgentState
    var processes: Int
    var cpu: Double
    var sessions: [AgentSession]

    var id: String { harness.id }
}
