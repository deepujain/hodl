import AppKit
import Darwin

/// What HODL does when the lid closes during a hold: dim, mute, pause chat apps, Low Power Mode, lock.
/// Every change is journaled first, and agents, terminals, and meeting apps are never touched.
@MainActor
enum LidPack {
    static let chatBundleIDs: Set<String> = [
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.hnc.DiscordPTB", "com.hnc.DiscordCanary",
        "net.whatsapp.WhatsApp", "desktop.WhatsApp",
    ]

    static let neverPauseBundleIDs: Set<String> = Harness.protectedBundleIDs.union([
        "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark",
        "com.apple.FaceTime", "com.obsproject.obs-studio", "com.loom.desktop",
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
    ])

    private(set) static var isApplied = false

    static func apply(lowPower: Bool = true) {
        guard !isApplied else { return }
        isApplied = true
        var applied: [String] = []

        if Prefs.bool(Prefs.packDim), let level = Brightness.get() {
            Recovery.record { if $0.brightnessWas == nil { $0.brightnessWas = level } }
            Brightness.set(0)
            applied.append("dimmed")
        }
        if Prefs.bool(Prefs.packDim), let level = KeyboardLight.get(), level > 0 {
            Recovery.record { if $0.keyboardWas == nil { $0.keyboardWas = level } }
            KeyboardLight.set(0)
            applied.append("keyboard light off")
        }
        if Prefs.bool(Prefs.packMute), let device = Audio.defaultOutput(), Audio.isMuted(device) == false {
            Recovery.record { $0.mutedDevice = device }
            Audio.setMuted(true, device: device)
            applied.append("muted")
        }
        if Prefs.bool(Prefs.packPauseChat) {
            let targets = chatProcesses()
            if !targets.isEmpty {
                Recovery.record { $0.paused = Array(Set($0.paused).union(targets)) }
                targets.forEach { kill($0.pid, SIGSTOP) }
                applied.append("paused \(Set(targets.map(\.name)).sorted().joined(separator: ", "))")
            }
        }
        if Prefs.bool(Prefs.packPauseApps) {
            let targets = otherAppProcesses()
            if !targets.isEmpty {
                Recovery.record { $0.paused = Array(Set($0.paused).union(targets)) }
                targets.forEach { kill($0.pid, SIGSTOP) }
                applied.append("paused \(Set(targets.map(\.name)).count) other apps")
            }
        }
        if lowPower, Prefs.bool(Prefs.packLowPower) { LowPower.enable(because: "lid closed") }
        if Prefs.bool(Prefs.packLock) {
            ScreenLock.lockNow()
            applied.append("locked")
        }
        if !applied.isEmpty { Ledger.shared.add("lid pack", applied.joined(separator: " · ")) }
    }

    /// Undo the lid pack. Low Power Mode stays until the hold ends, since the battery step may also want it.
    static func undo() -> [String] {
        guard isApplied else { return [] }
        isApplied = false
        let failures = Recovery.restore([.processes, .audio, .brightness])
        Ledger.shared.add("lid pack", failures.isEmpty ? "Resumed apps and restored sound and brightness." : failures.joined(separator: " "))
        return failures
    }

    /// Browsers stay running because agents drive them, and editors because agents run inside them.
    static let neverPauseAnyApp: Set<String> = neverPauseBundleIDs.union([
        "com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary", "company.thebrowser.Browser",
        "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser", "org.chromium.Chromium",
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.jetbrains.intellij", "com.sublimetext.4",
        "dev.zed.Zed", "com.apple.dt.Xcode", "com.docker.docker", "com.utmapp.UTM",
    ])

    /// Chat apps plus their helper processes, minus anything protected.
    private static func chatProcesses() -> [PausedProcess] {
        processes(of: NSWorkspace.shared.runningApplications.filter { app in
            guard let id = app.bundleIdentifier else { return false }
            return chatBundleIDs.contains(id) && !neverPauseBundleIDs.contains(id)
        })
    }

    /// Every other Dock app that isn’t Apple’s, protected, a browser, an editor, or HODL itself.
    private static func otherAppProcesses() -> [PausedProcess] {
        processes(of: NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                  app.processIdentifier != getpid() else { return false }
            return !id.hasPrefix("com.apple.") && !neverPauseAnyApp.contains(id) && !chatBundleIDs.contains(id)
        })
    }

    private static func processes(of roots: [NSRunningApplication]) -> [PausedProcess] {
        guard !roots.isEmpty else { return [] }
        let tree = ProcessTable.snapshotParents()
        var result: [PausedProcess] = []
        for app in roots {
            let name = app.localizedName ?? app.bundleIdentifier ?? "App"
            for pid in [app.processIdentifier] + ProcessTable.descendants(of: app.processIdentifier, parents: tree) {
                if let started = ProcessControl.startTime(of: pid) {
                    result.append(PausedProcess(pid: pid, started: started, name: name))
                }
            }
        }
        return result
    }
}

/// Low Power Mode needs root, so it goes through the narrow sudoers rule when it is installed.
@MainActor
enum LowPower {
    static func enable(because why: String) {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled, Privileged.isInstalled else { return }
        guard Recovery.load()?.lowPowerWas == nil else { return }
        Recovery.record { $0.lowPowerWas = false }
        if Privileged.pmset(["-a", "lowpowermode", "1"]) {
            Ledger.shared.add("low power", "Turned on Low Power Mode (\(why)).")
        } else {
            Recovery.record { $0.lowPowerWas = nil }
        }
    }
}

/// Closed-lid sleep on battery can only be stopped with `pmset disablesleep`; assertions can’t do it.
@MainActor
enum ClosedLid {
    static var isOn: Bool { Recovery.load()?.sleepDisabled ?? false }

    static func set(_ on: Bool) {
        guard on != isOn else { return }
        if on {
            guard Privileged.isInstalled else { return }
            Recovery.record { $0.sleepDisabled = true }
            if Privileged.pmset(["-a", "disablesleep", "1"]) {
                Ledger.shared.add("closed lid", "Turned off lid-close sleep for tonight.")
            } else {
                Recovery.record { $0.sleepDisabled = false }
            }
        } else {
            let failures = Recovery.restore([.sleep])
            Ledger.shared.add("closed lid", failures.isEmpty ? "Restored lid-close sleep." : failures.joined(separator: " "))
        }
    }
}
