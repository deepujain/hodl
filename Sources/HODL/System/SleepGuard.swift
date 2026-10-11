import Foundation
import IOKit.pwr_mgt

/// Holds IOKit power assertions; falls back to `caffeinate -i -s` if macOS refuses them.
/// Assertions belong to this process, so macOS drops them the moment HODL exits or crashes.
/// `caffeinate` is started with `-w <our pid>`, so it exits with us too.
@MainActor
final class SleepGuard {
    static let shared = SleepGuard()

    private var assertions: [IOPMAssertionID] = []
    private var caffeinate: Process?
    private(set) var isHeld = false
    private(set) var usingCaffeinate = false
    private(set) var keepsDisplayAwake = false
    private(set) var preventsLock = false
    private var activity = IOPMAssertionID(0)
    private var activityTimer: Timer?

    private init() {}

    func hold(keepDisplayAwake: Bool, preventLock: Bool) {
        release()
        let reason = "HODL is keeping the Mac awake for coding agents" as CFString
        var types = [kIOPMAssertPreventUserIdleSystemSleep as String, "PreventSystemSleep"]
        if keepDisplayAwake { types.append(kIOPMAssertPreventUserIdleDisplaySleep as String) }
        var failed = false
        for type in types {
            var id = IOPMAssertionID(0)
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id) == kIOReturnSuccess {
                assertions.append(id)
            } else if type != "PreventSystemSleep" {
                failed = true
            }
        }
        if failed || Prefs.bool(Prefs.caffeinateAlways) {
            startCaffeinate(keepDisplayAwake: keepDisplayAwake)
        }
        keepsDisplayAwake = keepDisplayAwake
        isHeld = !assertions.isEmpty || usingCaffeinate
        if preventLock, isHeld { startActivity() }
    }

    /// The screen saver and idle lock follow input idle time, which no assertion stops.
    /// Declaring user activity resets it, like `caffeinate -u`.
    private func startActivity() {
        preventsLock = true
        declareActivity()
        activityTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { SleepGuard.shared.declareActivity() }
        }
    }

    private func declareActivity() {
        _ = IOPMAssertionDeclareUserActivity("HODL is preventing the screen saver and lock" as CFString, kIOPMUserActiveLocal, &activity)
    }

    func release() {
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions.removeAll()
        activityTimer?.invalidate()
        activityTimer = nil
        if activity != 0 { IOPMAssertionRelease(activity) }
        activity = 0
        preventsLock = false
        if let caffeinate, caffeinate.isRunning { caffeinate.terminate() }
        caffeinate = nil
        usingCaffeinate = false
        isHeld = false
    }

    /// Recreate the assertions, as Amphetamine does, so a plug or unplug with the lid closed can’t slip through.
    func reassert() {
        guard isHeld else { return }
        hold(keepDisplayAwake: keepsDisplayAwake, preventLock: preventsLock)
    }

    private func startCaffeinate(keepDisplayAwake: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        task.arguments = (keepDisplayAwake ? ["-d"] : []) + ["-i", "-s", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            caffeinate = task
            usingCaffeinate = true
        } catch {
            usingCaffeinate = false
        }
    }

    var summary: String {
        var parts: [String] = []
        if !assertions.isEmpty { parts.append("\(assertions.count) IOKit assertion\(assertions.count == 1 ? "" : "s")") }
        if usingCaffeinate { parts.append("caffeinate -i -s") }
        if preventsLock { parts.append("user activity") }
        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }

    nonisolated static func pmsetAssertions() async -> String {
        await Task.detached { Shell.run("/usr/bin/pmset", ["-g", "assertions"]).output }.value
    }
}

enum Shell {
    struct Result: Sendable {
        var status: Int32
        var output: String
    }

    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> Result {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return Result(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return Result(status: task.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
