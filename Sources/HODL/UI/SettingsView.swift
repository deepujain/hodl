import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let engine: HoldEngine

    @AppStorage(Prefs.sessionHours) private var sessionHours = 8.0
    @AppStorage(Prefs.maxHours) private var maxHours = 12.0
    @AppStorage(Prefs.allowUnlimited) private var allowUnlimited = false
    @AppStorage(Prefs.adaptive) private var adaptive = false
    @AppStorage(Prefs.idleMinutes) private var idleMinutes = 10
    @AppStorage(Prefs.powerMode) private var powerMode = PowerMode.adaptive
    @AppStorage(Prefs.lidPolicy) private var lidPolicy = LidPolicy.either
    @AppStorage(Prefs.batteryFloor) private var batteryFloor = 15
    @AppStorage(Prefs.softFloor) private var softFloor = 40
    @AppStorage(Prefs.engageAbove) private var engageAbove = 0
    @AppStorage(Prefs.thermalGuard) private var thermalGuard = true
    @AppStorage(Prefs.keepDisplayAwake) private var keepDisplayAwake = false
    @AppStorage(Prefs.displayOff) private var displayOff = false
    @AppStorage(Prefs.displayOffAfterAgents) private var displayOffAfterAgents = 0
    @AppStorage(Prefs.lidPack) private var lidPack = false
    @AppStorage(Prefs.packDim) private var packDim = true
    @AppStorage(Prefs.packMute) private var packMute = true
    @AppStorage(Prefs.packPauseChat) private var packPauseChat = true
    @AppStorage(Prefs.packLowPower) private var packLowPower = false
    @AppStorage(Prefs.packLock) private var packLock = false
    @AppStorage(Prefs.closedLidOnBattery) private var closedLidOnBattery = false
    @AppStorage(Prefs.caffeinateAlways) private var caffeinateAlways = false
    @AppStorage(Prefs.playSounds) private var playSounds = true
    @AppStorage(Prefs.notifications) private var notifications = true
    @AppStorage(Prefs.hotkey) private var hotkey = true

    private let loginState = State(initialValue: SMAppService.mainApp.status == .enabled)
    private let helperState = State(initialValue: Privileged.isInstalled)
    private let reportState = State(initialValue: [String]())
    private let hookedState = State(initialValue: HookInstaller.installedAgents)
    private let helperErrorState = State<String?>(initialValue: nil)
    private let appNapState = State(initialValue: AppNap.isDisabledForAgents)

    private var appNapOff: Bool {
        get { appNapState.wrappedValue }
        nonmutating set { appNapState.wrappedValue = newValue }
    }

    private var launchAtLogin: Bool {
        get { loginState.wrappedValue }
        nonmutating set { loginState.wrappedValue = newValue }
    }

    private var helperInstalled: Bool {
        get { helperState.wrappedValue }
        nonmutating set { helperState.wrappedValue = newValue }
    }

    private var hookReport: [String] {
        get { reportState.wrappedValue }
        nonmutating set { reportState.wrappedValue = newValue }
    }

    private var hookedAgents: [String] {
        get { hookedState.wrappedValue }
        nonmutating set { hookedState.wrappedValue = newValue }
    }

    private var helperError: String? {
        get { helperErrorState.wrappedValue }
        nonmutating set { helperErrorState.wrappedValue = newValue }
    }

    var body: some View {
        TabView {
            holdTab.tabItem { Label("Hold", systemImage: "moon.zzz") }
            safetyTab.tabItem { Label("Safety", systemImage: "shield.lefthalf.filled") }
            lidTab.tabItem { Label("Lid & Display", systemImage: "laptopcomputer") }
            agentsTab.tabItem { Label("Agents", systemImage: "sparkles") }
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 540)
        .onAppear { NSApp.activate() }
        .onChange(of: keepDisplayAwake) { engine.settingsChanged() }
        .onChange(of: closedLidOnBattery) { engine.settingsChanged() }
        .onChange(of: hotkey) { engine.settingsChanged() }
        .onChange(of: lidPolicy) { engine.settingsChanged() }
        .onChange(of: powerMode) { engine.settingsChanged() }
    }

    private var holdTab: some View {
        Form {
            Section("Session") {
                Picker("Hold overnight for", selection: $sessionHours) {
                    ForEach([4.0, 6, 8, 10, 12], id: \.self) { Text("\(Int($0)) hours").tag($0) }
                }
                Picker("Never hold longer than", selection: $maxHours) {
                    ForEach([8.0, 10, 12, 16, 24], id: \.self) { Text("\(Int($0)) hours").tag($0) }
                }
                Toggle("Offer a session with no time limit", isOn: $allowUnlimited)
                Text("A no-limit hold still stops for battery, heat, and unplugging, and is restored if HODL quits or crashes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Adaptive") {
                Toggle("Hold only while an agent is working", isOn: $adaptive)
                Picker("Let go after agents are idle for", selection: $idleMinutes) {
                    ForEach([2, 5, 10, 15, 20, 30], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                .disabled(!adaptive)
            }
            Section("Power") {
                Picker("Power mode", selection: $powerMode) {
                    ForEach(PowerMode.allCases) { Text($0.title).tag($0) }
                }
                Text(powerMode.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var safetyTab: some View {
        Form {
            Section("Battery") {
                Picker("Stop holding at", selection: $batteryFloor) {
                    ForEach([5, 10, 15, 20, 25, 30], id: \.self) { Text("\($0)%").tag($0) }
                }
                Picker("Turn on Low Power Mode at", selection: $softFloor) {
                    Text("Never").tag(0)
                    ForEach([30, 40, 50, 60], id: \.self) { Text("\($0)%").tag($0) }
                }
                Picker("On battery, start only above", selection: $engageAbove) {
                    Text("Any level").tag(0)
                    ForEach([30, 50, 70], id: \.self) { Text("\($0)%").tag($0) }
                }
                Text("If the battery level can’t be read while on battery, HODL lets go rather than guess. Low Power Mode needs the closed-lid helper below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Heat") {
                Toggle("Let the Mac rest when it gets hot", isOn: $thermalGuard)
                Text("HODL turns on Low Power Mode when macOS reports serious heat, lets go if it lasts 10 minutes, and lets go at once if it becomes critical.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Label("Keep the Mac on a desk or stand with room to breathe, never in a closed bag or sleeve.", systemImage: "wind")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var lidTab: some View {
        Form {
            Section("Lid") {
                Picker("Hold when the lid is", selection: $lidPolicy) {
                    ForEach(LidPolicy.allCases) { Text($0.title).tag($0) }
                }
                Text(lidPolicy.detail).font(.caption).foregroundStyle(.secondary)
                Toggle("Keep holding with the lid closed on battery", isOn: $closedLidOnBattery)
                    .disabled(!helperInstalled)
                Text("On AC power HODL’s sleep assertions keep the Mac awake with the lid closed. On battery, macOS sleeps on lid close no matter what, unless lid-close sleep is switched off with `pmset disablesleep`. HODL turns it off only during a hold, journals it first, and always turns it back on, even after a crash.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Closed-lid helper") {
                    HStack {
                        Text(helperInstalled ? "Installed" : "Not installed").foregroundStyle(.secondary)
                        Button(helperInstalled ? "Remove…" : "Install…") { toggleHelper() }
                    }
                }
                Text("Adds /etc/sudoers.d/hodl, which lets HODL run only these four commands without a password: \(Privileged.commands.joined(separator: ", ")).")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let helperError {
                    Text(verbatim: helperError).font(.caption).foregroundStyle(.orange)
                }
            }
            Section("When the lid closes during a hold") {
                Toggle("Use the lid pack", isOn: $lidPack)
                Group {
                    Toggle("Dim the display", isOn: $packDim)
                    Toggle("Mute sound", isOn: $packMute)
                    Toggle("Pause Slack, Discord, and WhatsApp", isOn: $packPauseChat)
                    Toggle("Turn on Low Power Mode", isOn: $packLowPower).disabled(!helperInstalled)
                    Toggle("Lock the screen", isOn: $packLock)
                }
                .disabled(!lidPack)
                Text("Agents, terminals, and meeting apps (Zoom, Teams, Webex, FaceTime, OBS, Loom) are never paused. Everything resumes when the lid opens or the hold ends. On Apple silicon the built-in microphone disconnects while the lid is closed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Display") {
                Toggle("Turn the display off when a hold starts", isOn: $displayOff)
                Toggle("Keep the display on and the screen saver away", isOn: $keepDisplayAwake)
                Picker("Turn the display off after agents finish", selection: $displayOffAfterAgents) {
                    Text("Never").tag(0)
                    ForEach([10, 30, 60, 300], id: \.self) { Text($0 < 60 ? "After \($0) seconds" : "After \($0 / 60) minute\($0 == 60 ? "" : "s")").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var agentsTab: some View {
        Form {
            Section("Watching") {
                Text(Harness.all.map(\.title).joined(separator: ", "))
                Text("HODL sees which agents are running from process names and bundle IDs, and guesses whether they’re working from CPU use. It never reads code, prompts, or terminal output.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Keep agent apps out of App Nap", isOn: Binding(
                    get: { appNapOff },
                    set: { AppNap.setDisabledForAgents($0); appNapOff = AppNap.isDisabledForAgents }
                ))
                Text("Stops macOS from throttling Cursor, Codex, and Windsurf when their windows are in the background. Takes effect the next time each app opens.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Hooks") {
                LabeledContent("Installed for") {
                    Text(hookedAgents.isEmpty ? "None" : hookedAgents.joined(separator: ", ")).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Install Hooks and Command-Line Tools") {
                        hookReport = HookInstaller.installAll()
                        hookedAgents = HookInstaller.installedAgents
                    }
                    Button("Remove Hooks") {
                        hookReport = HookInstaller.uninstallAll()
                        hookedAgents = HookInstaller.installedAgents
                    }
                    .disabled(hookedAgents.isEmpty)
                }
                Text("Adds Working/Idle hooks to Claude Code, Codex, Cursor, and OpenCode, so HODL knows exactly when each session works. Hooks send only the agent, its state, and a session ID to 127.0.0.1:8742. Each changed file is backed up first as .hodl-backup.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(hookReport, id: \.self) { Text(verbatim: $0).font(.caption) }
            }
            Section("Command line") {
                Text(verbatim: "hodl hold --until agents-idle\nhodl status\nhodl-run -- <command>")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text("`hodl-run` keeps a hold alive while a command runs, with a heartbeat to 127.0.0.1:8742. The tools install to ~/.local/bin.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSSound.beep()
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                ))
                Toggle("Toggle the hold with ⌥⌘L", isOn: $hotkey)
                Toggle("Show notifications", isOn: $notifications)
                Toggle("Play sounds", isOn: $playSounds)
                Toggle("Also run caffeinate as a backup", isOn: $caffeinateAlways)
                Text("HODL uses IOKit power assertions. It starts `caffeinate -i -s` on its own only if macOS refuses them.")
                    .font(.caption).foregroundStyle(.secondary)
            } footer: {
                VStack(spacing: 2) {
                    Text("HODL \(Bundle.main.shortVersion) · Hold the Door Lid.")
                    Link(AppLinks.repositoryLabel, destination: AppLinks.repository)
                }
                .font(.caption).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func toggleHelper() {
        helperError = nil
        let rule = Privileged.sudoersRule.replacingOccurrences(of: "\n", with: "\\n")
        let script: String
        if helperInstalled {
            script = "rm -f \(Privileged.sudoersPath)"
        } else {
            let temp = "/tmp/hodl-sudoers-\(UUID().uuidString)"
            script = "printf '\(rule)' > \(temp) && /usr/sbin/visudo -cf \(temp) && install -m 0440 -o root -g wheel \(temp) \(Privileged.sudoersPath); rc=$?; rm -f \(temp); exit $rc"
        }
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges")?
            .executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) != -128 {
            helperError = error[NSAppleScript.errorMessage] as? String ?? "The helper couldn’t be changed."
        }
        helperInstalled = Privileged.isInstalled
        if !helperInstalled { closedLidOnBattery = false }
    }
}
