import CoreAudio
import CoreGraphics
import Darwin
import Foundation

/// Everything HODL has changed outside its own process, written to disk *before* each change.
/// The app, its next launch, and the launchd backstop all undo it from this one file.
struct RecoveryJournal: Codable, Sendable {
    var ownerPID: Int32
    var created = Date()
    var sleepDisabled = false
    /// Non-nil when HODL turned Low Power Mode on; holds the value to put back.
    var lowPowerWas: Bool?
    var paused: [PausedProcess] = []
    /// The output device HODL muted; it was unmuted before.
    var mutedDevice: UInt32?
    var brightnessWas: Float?

    var isEmpty: Bool {
        !sleepDisabled && lowPowerWas == nil && paused.isEmpty && mutedDevice == nil && brightnessWas == nil
    }
}

struct PausedProcess: Codable, Sendable, Hashable {
    var pid: Int32
    /// Start time, so a recycled PID is never signalled by mistake.
    var started: UInt64
    var name: String
}

enum Recovery {
    enum Part: CaseIterable, Sendable { case sleep, lowPower, processes, audio, brightness }

    static let folder: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "HODL", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var journalURL: URL { folder.appending(path: "recovery.json") }

    static func load() -> RecoveryJournal? {
        guard let data = try? Data(contentsOf: journalURL) else { return nil }
        return try? JSONDecoder().decode(RecoveryJournal.self, from: data)
    }

    static var hasPendingChanges: Bool { !(load()?.isEmpty ?? true) }

    /// Record a change before making it.
    static func record(_ change: (inout RecoveryJournal) -> Void) {
        var journal = load() ?? RecoveryJournal(ownerPID: getpid())
        journal.ownerPID = getpid()
        change(&journal)
        save(journal)
        if !journal.isEmpty { Backstop.install() }
    }

    private static func save(_ journal: RecoveryJournal) {
        if journal.isEmpty {
            try? FileManager.default.removeItem(at: journalURL)
        } else if let data = try? JSONEncoder().encode(journal) {
            try? data.write(to: journalURL, options: .atomic)
        }
    }

    /// Undo the requested parts. Returns what could not be undone; those stay journaled for another try.
    @discardableResult
    static func restore(_ parts: Set<Part> = Set(Part.allCases), removingBackstop: Bool = true) -> [String] {
        guard var journal = load() else { return [] }
        var failures: [String] = []

        if parts.contains(.processes), !journal.paused.isEmpty {
            for process in journal.paused where ProcessControl.startTime(of: process.pid) == process.started {
                kill(process.pid, SIGCONT)
            }
            journal.paused.removeAll()
        }
        if parts.contains(.audio), let device = journal.mutedDevice {
            if Audio.setMuted(false, device: device) || !Audio.exists(device) {
                journal.mutedDevice = nil
            } else {
                failures.append("Couldn’t unmute the sound output.")
            }
        }
        if parts.contains(.brightness), let level = journal.brightnessWas {
            Brightness.set(level)
            journal.brightnessWas = nil
        }
        if parts.contains(.lowPower), let was = journal.lowPowerWas {
            if Privileged.pmset(["-a", "lowpowermode", was ? "1" : "0"]) {
                journal.lowPowerWas = nil
            } else {
                failures.append("Couldn’t turn Low Power Mode back \(was ? "on" : "off").")
            }
        }
        if parts.contains(.sleep), journal.sleepDisabled {
            if Privileged.pmset(["-a", "disablesleep", "0"]) {
                journal.sleepDisabled = false
            } else {
                failures.append("Closed-lid sleep is still off. Run: sudo pmset -a disablesleep 0")
            }
        }

        save(journal)
        if journal.isEmpty && removingBackstop { Backstop.remove() }
        return failures
    }

    static func ownerIsAlive(_ journal: RecoveryJournal) -> Bool {
        guard journal.ownerPID > 0, journal.ownerPID != getpid() else { return false }
        return kill(journal.ownerPID, 0) == 0 && ProcessControl.path(of: journal.ownerPID)?.hasSuffix("/HODL") == true
    }
}

/// Root-only `pmset` switches, allowed through a narrow sudoers rule the user installs once.
enum Privileged {
    static let sudoersPath = "/etc/sudoers.d/hodl"
    static let commands = [
        "/usr/bin/pmset -a disablesleep 0", "/usr/bin/pmset -a disablesleep 1",
        "/usr/bin/pmset -a lowpowermode 0", "/usr/bin/pmset -a lowpowermode 1",
    ]

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: sudoersPath) }

    static func pmset(_ arguments: [String]) -> Bool {
        Shell.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset"] + arguments).status == 0
    }

    static var sudoersRule: String {
        "# Installed by HODL. Lets HODL switch closed-lid sleep and Low Power Mode, and nothing else.\n"
            + "\(NSUserName()) ALL=(root) NOPASSWD: \(commands.joined(separator: ", "))\n"
    }
}

enum ProcessControl {
    static func startTime(of pid: Int32) -> UInt64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_start_tvsec
    }

    static func path(of pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }
}

enum Audio {
    static func defaultOutput() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func exists(_ device: AudioObjectID) -> Bool {
        var address = muteAddress()
        return AudioObjectHasProperty(device, &address)
    }

    static func isMuted(_ device: AudioObjectID) -> Bool? {
        var address = muteAddress()
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    @discardableResult
    static func setMuted(_ muted: Bool, device: AudioObjectID) -> Bool {
        var address = muteAddress()
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}

/// Built-in display brightness through DisplayServices, the framework Control Center uses.
enum Brightness {
    private typealias Getter = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (UInt32, Float) -> Int32

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    static func get() -> Float? {
        guard let getter = symbol("DisplayServicesGetBrightness", as: Getter.self) else { return nil }
        var level: Float = 0
        return getter(CGMainDisplayID(), &level) == 0 ? level : nil
    }

    static func set(_ level: Float) {
        guard let setter = symbol("DisplayServicesSetBrightness", as: Setter.self) else { return }
        _ = setter(CGMainDisplayID(), max(0, min(1, level)))
    }
}

enum ScreenLock {
    static func lockNow() {
        typealias Lock = @convention(c) () -> Void
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let pointer = dlsym(handle, "SACLockScreenImmediate") {
            unsafeBitCast(pointer, to: Lock.self)()
        } else {
            Display.sleepNow()
        }
    }
}

enum Display {
    static func sleepNow() {
        Shell.run("/usr/bin/pmset", ["displaysleepnow"])
    }
}
