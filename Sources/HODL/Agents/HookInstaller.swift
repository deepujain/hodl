import Foundation

/// Installs the `hodl` command-line tools and Working/Idle hooks into coding agents.
/// Hooks send only an agent name, a state, and a session ID to 127.0.0.1:8742.
enum HookInstaller {
    static let marker = "hodl-hook"
    private static let home: URL = {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["HODL_TEST_HOME"] { return URL(fileURLWithPath: path, isDirectory: true) }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }()
    static let binFolder = home.appending(path: ".local/bin", directoryHint: .isDirectory)
    static var hookPath: String { binFolder.appending(path: "hodl-hook").path }

    private static let claudeSettings = home.appending(path: ".claude/settings.json")
    private static let codexConfig = home.appending(path: ".codex/config.toml")
    private static let cursorHooks = home.appending(path: ".cursor/hooks.json")
    private static let openCodePlugin = home.appending(path: ".config/opencode/plugin/hodl.js")

    private static let claudeEvents: [(event: String, state: String, matcher: String?)] = [
        ("UserPromptSubmit", "working", nil), ("PreToolUse", "working", "*"),
        ("Stop", "idle", nil), ("Notification", "idle", nil), ("SessionEnd", "ended", nil),
    ]
    private static let cursorEvents: [(event: String, state: String)] = [("beforeSubmitPrompt", "working"), ("stop", "idle")]

    static var toolsInstalled: Bool { FileManager.default.isExecutableFile(atPath: hookPath) }

    static var installedAgents: [String] {
        var names: [String] = []
        if (try? String(contentsOf: claudeSettings, encoding: .utf8))?.contains(marker) == true { names.append("Claude Code") }
        if (try? String(contentsOf: codexConfig, encoding: .utf8))?.contains(marker) == true { names.append("Codex") }
        if (try? String(contentsOf: cursorHooks, encoding: .utf8))?.contains(marker) == true { names.append("Cursor") }
        if FileManager.default.fileExists(atPath: openCodePlugin.path) { names.append("OpenCode") }
        return names
    }

    // MARK: Install

    /// Installs tools, then hooks for every agent whose config folder exists. Returns one line per step.
    static func installAll() -> [String] {
        var report: [String] = []
        do {
            try installTools()
            report.append("Installed hodl, hodl-run, and hodl-hook in ~/.local/bin.")
        } catch {
            return ["Couldn’t install the command-line tools: \(error.localizedDescription)"]
        }
        report.append(attempt("Claude Code", folder: ".claude", installClaude))
        report.append(attempt("Codex", folder: ".codex", installCodex))
        report.append(attempt("Cursor", folder: ".cursor", installCursor))
        report.append(attempt("OpenCode", folder: ".config/opencode", installOpenCode))
        return report
    }

    static func uninstallAll() -> [String] {
        var report: [String] = []
        report.append(attempt("Claude Code", folder: ".claude", uninstall: true) { try editJSON(claudeSettings) { removeClaude(&$0) } })
        report.append(attempt("Codex", folder: ".codex", uninstall: true, uninstallCodex))
        report.append(attempt("Cursor", folder: ".cursor", uninstall: true) { try editJSON(cursorHooks) { removeCursor(&$0) } })
        try? FileManager.default.removeItem(at: openCodePlugin)
        return report
    }

    private static func attempt(_ name: String, folder: String, uninstall: Bool = false, _ work: () throws -> Void) -> String {
        guard FileManager.default.fileExists(atPath: home.appending(path: folder).path) else { return "\(name): not installed, skipped." }
        do {
            try work()
            return uninstall ? "\(name): hooks removed." : "\(name): hooks installed."
        } catch {
            return "\(name): \(error.localizedDescription)"
        }
    }

    static func installTools() throws {
        guard let source = Bundle.main.resourceURL?.appending(path: "bin") else { throw CocoaError(.fileNoSuchFile) }
        let manager = FileManager.default
        try manager.createDirectory(at: binFolder, withIntermediateDirectories: true)
        for tool in ["hodl", "hodl-run", "hodl-hook"] {
            let target = binFolder.appending(path: tool)
            try? manager.removeItem(at: target)
            try manager.copyItem(at: source.appending(path: tool), to: target)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        }
    }

    private static func command(_ agent: String, _ state: String) -> String {
        "\"\(hookPath)\" \(agent) \(state)"
    }

    // MARK: Claude Code (~/.claude/settings.json)

    private static func installClaude() throws {
        try editJSON(claudeSettings) { root in
            removeClaude(&root)
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            for item in claudeEvents {
                var group: [String: Any] = ["hooks": [["type": "command", "command": command("claude", item.state), "timeout": 5]]]
                if let matcher = item.matcher { group["matcher"] = matcher }
                hooks[item.event] = (hooks[item.event] as? [Any] ?? []) + [group]
            }
            root["hooks"] = hooks
        }
    }

    private static func removeClaude(_ root: inout [String: Any]) {
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            let groups = (value as? [[String: Any]] ?? []).filter { group in
                !((group["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
    }

    // MARK: Cursor (~/.cursor/hooks.json)

    private static func installCursor() throws {
        try editJSON(cursorHooks) { root in
            removeCursor(&root)
            root["version"] = root["version"] ?? 1
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            for item in cursorEvents {
                hooks[item.event] = (hooks[item.event] as? [Any] ?? []) + [["command": command("cursor", item.state)]]
            }
            root["hooks"] = hooks
        }
    }

    private static func removeCursor(_ root: inout [String: Any]) {
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            let entries = (value as? [[String: Any]] ?? []).filter { ($0["command"] as? String)?.contains(marker) != true }
            hooks[event] = entries.isEmpty ? nil : entries
        }
        root["hooks"] = hooks
    }

    // MARK: Codex (~/.codex/config.toml)

    private static let codexOriginalPrefix = "# hodl-original-notify = "

    /// Codex runs one `notify` command when a turn ends. An existing one is kept and chained after HODL’s.
    private static func installCodex() throws {
        try uninstallCodex()
        let text = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
        var lines = text.components(separatedBy: "\n")
        let hook = "\"\(hookPath)\", \"codex\", \"idle\""
        var newLines: [String]
        if let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("notify") }) {
            let original = lines[index]
            guard let open = original.firstIndex(of: "["), let close = original.lastIndex(of: "]"), open < close else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "its notify setting spans several lines; add HODL by hand."])
            }
            let inner = original[original.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            lines.remove(at: index)
            newLines = [codexOriginalPrefix + original, "notify = [\(hook), \"--then\", \(inner)]"]
        } else {
            newLines = ["notify = [\(hook)]"]
        }
        try backup(codexConfig)
        // Top-level keys must come before any [table], so HODL’s line goes first.
        try (newLines + lines).joined(separator: "\n").write(to: codexConfig, atomically: true, encoding: .utf8)
    }

    private static func uninstallCodex() throws {
        guard let text = try? String(contentsOf: codexConfig, encoding: .utf8), text.contains(marker) else { return }
        var lines = text.components(separatedBy: "\n")
        let original = lines.first { $0.hasPrefix(codexOriginalPrefix) }.map { String($0.dropFirst(codexOriginalPrefix.count)) }
        lines.removeAll { $0.hasPrefix(codexOriginalPrefix) || ($0.trimmingCharacters(in: .whitespaces).hasPrefix("notify") && $0.contains(marker)) }
        if let original { lines.insert(original, at: 0) }
        try lines.joined(separator: "\n").write(to: codexConfig, atomically: true, encoding: .utf8)
    }

    // MARK: OpenCode (~/.config/opencode/plugin/hodl.js)

    private static func installOpenCode() throws {
        try FileManager.default.createDirectory(at: openCodePlugin.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plugin = """
        // Installed by HODL. Tells HODL when an OpenCode session starts and stops working.
        // Sends only the session ID and state to 127.0.0.1:8742; never prompts, code, or output.
        export const HodlPlugin = async () => {
          const send = (state, id) =>
            fetch(`http://127.0.0.1:8742/hook?agent=opencode&state=${state}&session=${encodeURIComponent(id ?? "")}&pid=${process.pid}`,
              { method: "POST", headers: { "X-HODL": "1" } }).catch(() => {});
          return {
            event: async ({ event }) => {
              const id = event.properties?.sessionID ?? event.properties?.info?.id;
              if (event.type === "session.status") send(event.properties?.status?.type === "idle" ? "idle" : "working", id);
              else if (event.type === "session.idle") send("idle", id);
              else if (event.type === "session.deleted") send("ended", id);
            },
          };
        };

        """
        try plugin.write(to: openCodePlugin, atomically: true, encoding: .utf8)
    }

    // MARK: Helpers

    private static func editJSON(_ url: URL, _ change: (inout [String: Any]) -> Void) throws {
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent) isn’t a JSON object; left untouched."])
            }
            root = parsed
            try backup(url)
        }
        change(&root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    /// Keeps the first copy HODL ever saw, so the original is always one rename away.
    private static func backup(_ url: URL) throws {
        let copy = url.appendingPathExtension("hodl-backup")
        guard FileManager.default.fileExists(atPath: url.path), !FileManager.default.fileExists(atPath: copy.path) else { return }
        try FileManager.default.copyItem(at: url, to: copy)
    }
}
