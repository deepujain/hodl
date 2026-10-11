import Darwin
import Foundation

/// A per-user launchd job that undoes HODL’s changes if HODL dies before it can.
/// Installed only while the recovery journal holds something; it removes itself once everything is restored.
enum Backstop {
    static let label = "com.deepujain.hodl.backstop"
    static let flag = "--backstop"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/\(label).plist")
    }

    private static var domain: String { "gui/\(getuid())" }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func install() {
        guard !isInstalled, let executable = Bundle.main.executablePath, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, flag],
            "StartInterval": 20,
            "RunAtLoad": true,
            "ProcessType": "Background",
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: plistURL, options: .atomic)
        Shell.run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
    }

    static func remove() {
        guard isInstalled else { return }
        try? FileManager.default.removeItem(at: plistURL)
        // When the backstop itself calls this, bootout ends its own process, so it goes last.
        Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
    }

    /// Entry point for `HODL --backstop`: restore if the app that made the changes is gone.
    static func run() -> Never {
        guard let journal = Recovery.load() else {
            remove()
            exit(0)
        }
        if Recovery.ownerIsAlive(journal) { exit(0) }
        let failures = Recovery.restore(removingBackstop: false)
        Ledger.appendFromBackstop(failures.isEmpty
            ? "Backstop restored sleep, sound, and paused apps after HODL stopped unexpectedly."
            : "Backstop could not finish: \(failures.joined(separator: " "))")
        if failures.isEmpty { remove() }
        exit(failures.isEmpty ? 0 : 1)
    }
}
