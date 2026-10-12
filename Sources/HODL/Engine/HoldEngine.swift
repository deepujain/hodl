import AppKit
import Observation

/// Decides when the Mac is held awake, and why it stops.
///
/// A *session* is what the user started (overnight, timed, or until agents finish). While a session runs,
/// the Mac is *engaged* (assertions held) unless the lid policy or a pause says to stand by.
/// Safety stops (battery, heat, timer, unplugged, agents finished) end the session and always record why.
@MainActor @Observable
final class HoldEngine {
    static let shared = HoldEngine()

    struct Session: Sendable {
        var started = Date()
        var ends: Date?
        var adaptive: Bool
        var source: String
        var warnedBeforeEnd = false
        /// Bundle ID of the app this hold follows. The hold ends when it quits.
        var watchedApp: String?
    }

    struct Release: Sendable {
        var reason: ReleaseReason
        var date = Date()
    }

    private(set) var session: Session?
    private(set) var engaged = false
    /// Why the Mac isn’t engaged while a session runs.
    private(set) var standby: String?
    private(set) var pausedUntil: Date?
    private(set) var lastRelease: Release?
    /// Why the last hold request was turned down.
    private(set) var refusal: String?
    /// A restore that didn’t finish. Stays until it does.
    private(set) var restoreWarning: String?
    private(set) var clock = Date()

    @ObservationIgnored private var hotSince: Date?
    @ObservationIgnored private var agentsWereActive = false
    @ObservationIgnored private var displayTask: Task<Void, Never>?
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var signalSources: [DispatchSourceSignal] = []
    /// A watched app the user released or HODL refused; it won’t start a hold again until it quits.
    @ObservationIgnored private var skippedApps: Set<String> = []
    @ObservationIgnored private var lowPowerSeen: Bool?
    /// The user turned Low Power Mode off during this hold, so HODL won’t turn it back on.
    @ObservationIgnored private var lowPowerDeclined = false

    private let power = PowerMonitor.shared
    private let agents = AgentMonitor.shared

    private init() {}

    // MARK: Lifecycle

    func start() {
        recoverFromLastRun()
        power.start()
        power.onChange = { [weak self] in
            SleepGuard.shared.reassert()
            self?.evaluate()
        }
        agents.refresh()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { HoldEngine.shared.tick() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { HoldEngine.shared.tick() }
            }
        }
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { HoldEngine.shared.shutdown() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Restore everything before HODL exits. Safe to call more than once.
    func shutdown() {
        if session != nil {
            release(.quit, quietly: true)
        } else {
            Recovery.restore()
        }
        SleepGuard.shared.release()
    }

    private func recoverFromLastRun() {
        guard let journal = Recovery.load(), !Recovery.ownerIsAlive(journal), !journal.isEmpty else { return }
        let failures = Recovery.restore()
        restoreWarning = failures.first
        lastRelease = Release(reason: .recovered)
        Ledger.shared.add("recovered", failures.isEmpty ? ReleaseReason.recovered.sentence : failures.joined(separator: " "), reason: .recovered)
        if !failures.isEmpty { Notifier.post("HODL needs attention", failures.joined(separator: " "), important: true) }
    }

    private func tick() {
        power.refresh()
        agents.refresh()
        followWatchedApps()
        evaluate()
    }

    /// Starts a hold when a watched app is running, once per launch of that app.
    private func followWatchedApps() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        skippedApps.formIntersection(running)
        guard session == nil,
              let id = Prefs.watchedAppIDs.first(where: { running.contains($0) && !skippedApps.contains($0) }) else { return }
        skippedApps.insert(id)
        hold(duration: .infinity, adaptive: false, source: Self.appName(id), watchedApp: id)
    }

    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: Actions

    /// Starts a hold. `duration` nil means the default session; `.infinity` means no limit (when allowed).
    func hold(duration: TimeInterval? = nil, adaptive: Bool? = nil, source: String = "menu", watchedApp: String? = nil) {
        power.refresh()
        if let problem = startProblem() {
            refusal = problem
            Notifier.post("HODL didn’t start", problem)
            Sounds.warning()
            return
        }
        refusal = nil
        let unlimited = duration == .infinity && Prefs.bool(Prefs.allowUnlimited)
        let ceiling = Prefs.double(Prefs.maxHours) * 3600
        let length = min(duration.flatMap { $0.isFinite ? $0 : nil } ?? (watchedApp == nil ? Prefs.defaultSession : ceiling), ceiling)
        let wasHolding = session != nil
        session = Session(ends: unlimited ? nil : Date().addingTimeInterval(length),
                          adaptive: adaptive ?? Prefs.bool(Prefs.adaptive), source: source, watchedApp: watchedApp)
        pausedUntil = nil
        lowPowerDeclined = false
        lastRelease = nil
        let summary = describeSession()
        Ledger.shared.add("awake", watchedApp == nil ? "\(summary) · from \(source)" : "\(summary)")
        if !wasHolding {
            Sounds.hold()
            Notifier.post("Keeping your Mac awake", "\(summary).")
        }
        evaluate()
        if Prefs.bool(Prefs.displayOff) { sleepDisplay(after: 1.5) }
    }

    func release(_ reason: ReleaseReason = .user, quietly: Bool = false) {
        guard let ending = session else { return }
        if let app = ending.watchedApp { skippedApps.insert(app) }
        session = nil
        pausedUntil = nil
        standby = nil
        hotSince = nil
        disengage()
        let failures = Recovery.restore()
        restoreWarning = failures.first
        lastRelease = Release(reason: reason)
        Ledger.shared.add("stopped", failures.isEmpty ? reason.sentence : "\(reason.sentence) \(failures.joined(separator: " "))", reason: reason)
        guard !quietly else { return }
        Sounds.release()
        if reason.isSafetyStop {
            Notifier.post("HODL stopped for safety", reason.sentence, important: true)
        } else if reason == .agentsIdle {
            Notifier.post("Agents finished", "\(reason.sentence) The Mac can sleep normally now.")
        } else {
            Notifier.post("Your Mac can sleep again", reason.sentence)
        }
        if !failures.isEmpty { Notifier.post("HODL needs attention", failures.joined(separator: " "), important: true) }
    }

    func toggle(source: String = "menu") {
        session == nil ? hold(source: source) : release(.user)
    }

    /// Adds time. Never schedules more than the hard maximum ahead of now.
    func extend(hours: Double) {
        guard var current = session else { return hold(duration: hours * 3600, source: "extend") }
        guard let ends = current.ends else { return }
        let ceiling = Date().addingTimeInterval(Prefs.double(Prefs.maxHours) * 3600)
        current.ends = min(max(ends, Date()).addingTimeInterval(hours * 3600), ceiling)
        current.warnedBeforeEnd = false
        session = current
        Ledger.shared.add("extend", "Added \(Self.format(hours * 3600)) · now ends \(current.ends!.formatted(date: .omitted, time: .shortened))")
        evaluate()
    }

    func pause(minutes: Double) {
        guard session != nil else { return }
        pausedUntil = Date().addingTimeInterval(minutes * 60)
        Ledger.shared.add("pause", "Paused for \(Int(minutes)) minutes.")
        evaluate()
    }

    func resume() {
        guard pausedUntil != nil else { return }
        pausedUntil = nil
        Ledger.shared.add("resume", "Resumed.")
        evaluate()
    }

    func displayOffNow() { sleepDisplay(after: 1.0) }

    /// Re-applies settings that change how the hold is made.
    func settingsChanged() {
        let guardian = SleepGuard.shared
        if engaged, guardian.keepsDisplayAwake != Prefs.bool(Prefs.keepDisplayAwake) || guardian.preventsLock != Prefs.bool(Prefs.preventLock) {
            holdAssertions()
        }
        if engaged { ClosedLid.set(wantsClosedLid) }
        Hotkey.setEnabled(Prefs.bool(Prefs.hotkey))
        evaluate()
    }

    /// The Agents Only switch applies to the running session as well as the next one.
    func setAgentsOnly(_ on: Bool) {
        guard session != nil, session?.adaptive != on else { return }
        session?.adaptive = on
        Ledger.shared.add("awake", on ? "Now only while agents work." : "Now for the whole session, even after agents finish.")
        evaluate()
    }

    func retryRestore() {
        let failures = Recovery.restore()
        restoreWarning = failures.first
        if failures.isEmpty { Ledger.shared.add("restore", "Everything is back to normal.") }
    }

    // MARK: Policy

    private func startProblem() -> String? {
        let mode = Prefs.powerModeValue
        let onBattery = power.hasBattery && !power.onAC
        if mode == .ac && onBattery { return "AC Only is on. Plug in to keep the Mac awake." }
        if onBattery {
            guard let percent = power.percent else { return "The battery level can’t be read, so HODL won’t keep the Mac awake on battery." }
            let floor = Prefs.int(Prefs.batteryFloor)
            if percent <= floor { return "The battery is at \(percent)%, at or below the \(floor)% floor." }
            let engageAbove = Prefs.int(Prefs.engageAbove)
            if engageAbove > 0, percent < engageAbove { return "HODL starts on battery only above \(engageAbove)%. It’s at \(percent)%." }
        }
        if Prefs.bool(Prefs.thermalGuard), power.thermal == .critical { return "The Mac is too hot to keep awake right now." }
        return nil
    }

    private var wantsClosedLid: Bool {
        Prefs.bool(Prefs.closedLidOnBattery) && Prefs.lidPolicyValue != .open
    }

    func evaluate() {
        clock = Date()
        guard let current = session else {
            if engaged { disengage() }
            return
        }
        let now = clock

        if let ends = current.ends, now >= ends { return release(.timer) }
        if let app = current.watchedApp, NSRunningApplication.runningApplications(withBundleIdentifier: app).isEmpty {
            return release(.appQuit)
        }
        noteLowPowerChanges()
        let onBattery = power.hasBattery && !power.onAC
        if Prefs.powerModeValue == .ac && onBattery { return release(.unplugged) }
        if onBattery {
            guard let percent = power.percent else { return release(.batteryUnknown) }
            if percent <= Prefs.int(Prefs.batteryFloor) { return release(.battery) }
            if Prefs.powerModeValue == .adaptive, percent <= Prefs.int(Prefs.softFloor), !lowPowerDeclined {
                LowPower.enable(because: "battery at \(percent)%")
            }
        }
        if Prefs.bool(Prefs.thermalGuard) {
            switch power.thermal {
            case .critical:
                return release(.thermal)
            case .serious:
                if hotSince == nil {
                    hotSince = now
                    if !lowPowerDeclined { LowPower.enable(because: "the Mac is hot") }
                    Ledger.shared.add("thermal", "The Mac is hot. HODL lets it sleep if it stays hot for 10 minutes.")
                }
                if let hotSince, now.timeIntervalSince(hotSince) >= 600 { return release(.thermal) }
            default:
                hotSince = nil
            }
        }
        if current.adaptive, !agents.anyActive {
            let lastWork = max(agents.lastActive ?? current.started, current.started)
            if now.timeIntervalSince(lastWork) >= Double(max(1, Prefs.int(Prefs.idleMinutes))) * 60 { return release(.agentsIdle) }
        }
        if let ends = current.ends, !current.warnedBeforeEnd, ends.timeIntervalSince(now) <= 600 {
            session?.warnedBeforeEnd = true
            Notifier.post("HODL ends in 10 minutes", "Add time from the menu bar if your agents need longer.")
        }

        var why: String?
        if let pausedUntil {
            if pausedUntil > now {
                why = "Paused until \(pausedUntil.formatted(date: .omitted, time: .shortened))"
            } else {
                self.pausedUntil = nil
                Ledger.shared.add("resume", "Pause ended.")
            }
        }
        let policy = Prefs.lidPolicyValue
        if why == nil, power.lidKnown, !policy.allows(lidClosed: power.lidClosed) {
            why = power.lidClosed ? "Lid closed · set to stay awake only while open" : "Waiting for the lid to close"
        }
        standby = why
        why == nil ? engage() : disengage()

        if engaged, power.lidClosed, Prefs.bool(Prefs.lidPack) {
            LidPack.apply(lowPower: !lowPowerDeclined)
        } else if LidPack.isApplied, !power.lidClosed || !engaged {
            let failures = LidPack.undo()
            if let first = failures.first { restoreWarning = first }
        }

        let active = agents.anyActive
        let delay = Prefs.int(Prefs.displayOffAfterAgents)
        if agentsWereActive, !active, engaged, delay > 0 { sleepDisplay(after: Double(delay)) }
        agentsWereActive = active
    }

    /// Low Power Mode belongs to the user. If they switch it off mid-hold, HODL forgets its change and leaves it off.
    private func noteLowPowerChanges() {
        let on = power.lowPowerMode
        defer { lowPowerSeen = on }
        guard let before = lowPowerSeen, before != on else { return }
        if !on, Recovery.load()?.lowPowerWas != nil {
            Recovery.record { $0.lowPowerWas = nil }
            lowPowerDeclined = true
            Ledger.shared.add("low power", "You turned Low Power Mode off. HODL won’t turn it back on tonight.")
        } else {
            Ledger.shared.add("low power", "macOS Low Power Mode is \(on ? "on" : "off"). HODL keeps the Mac awake either way.")
        }
    }

    private func engage() {
        if !engaged || !SleepGuard.shared.isHeld {
            holdAssertions()
            engaged = SleepGuard.shared.isHeld
        }
        if engaged, wantsClosedLid != ClosedLid.isOn { ClosedLid.set(wantsClosedLid) }
    }

    private func holdAssertions() {
        SleepGuard.shared.hold(keepDisplayAwake: Prefs.bool(Prefs.keepDisplayAwake), preventLock: Prefs.bool(Prefs.preventLock))
    }

    private func disengage() {
        guard engaged || SleepGuard.shared.isHeld || ClosedLid.isOn || LidPack.isApplied else { return }
        SleepGuard.shared.release()
        ClosedLid.set(false)
        if LidPack.isApplied, let first = LidPack.undo().first { restoreWarning = first }
        engaged = false
    }

    private func sleepDisplay(after seconds: Double) {
        displayTask?.cancel()
        displayTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            Display.sleepNow()
        }
    }

    #if DEBUG
    /// Puts the engine in a state for marketing renders without holding anything.
    func stage(endsIn: TimeInterval?, released: ReleaseReason? = nil) {
        clock = Date()
        standby = nil
        refusal = nil
        restoreWarning = nil
        if let endsIn {
            session = Session(started: clock.addingTimeInterval(-3600), ends: clock.addingTimeInterval(endsIn), adaptive: Prefs.bool(Prefs.adaptive), source: "menu")
            engaged = true
            lastRelease = nil
        } else {
            session = nil
            engaged = false
            lastRelease = released.map { Release(reason: $0) }
        }
    }
    #endif

    // MARK: Presentation

    var remaining: TimeInterval? { session?.ends.map { max(0, $0.timeIntervalSince(clock)) } }

    var statusLine: String {
        if let restoreWarning, session == nil { return "Needs attention · \(restoreWarning.prefix(28))…" }
        if let session {
            let time = remaining.map(Self.format) ?? "no limit"
            if let standby { return "Standing by · \(standby.prefix(1).lowercased())\(standby.dropFirst())" }
            if session.adaptive, !agents.anyActive { return "Awake · \(power.batteryLabel) · waiting on agents" }
            return "Awake · \(power.batteryLabel) · \(time)"
        }
        if let lastRelease { return "Sleeping normally · \(lastRelease.reason.short)" }
        return "Ready · \(power.batteryLabel)"
    }

    var isWarning: Bool {
        if restoreWarning != nil { return true }
        guard session != nil else { return false }
        if power.thermal == .serious || power.thermal == .critical { return true }
        if power.hasBattery, !power.onAC, let percent = power.percent, percent <= Prefs.int(Prefs.batteryFloor) + 5 { return true }
        return false
    }

    var menuSymbol: String {
        if isWarning { return "exclamationmark.triangle.fill" }
        if session != nil { return engaged ? "moon.zzz.fill" : "moon.zzz" }
        return "moon"
    }

    func describeSession() -> String {
        guard let session else { return "Off" }
        if let app = session.watchedApp { return "Awake while \(Self.appName(app)) runs" }
        let length = session.ends.map { "until \($0.formatted(date: .omitted, time: .shortened))" } ?? "with no time limit"
        return session.adaptive ? "Awake \(length) while agents work" : "Awake \(length)"
    }

    static func format(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded(.up))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
