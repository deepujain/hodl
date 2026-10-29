import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let engine: HoldEngine

    @AppStorage(Prefs.sessionHours) private var sessionHours = 8.0
    @AppStorage(Prefs.maxHours) private var maxHours = 12.0
    @AppStorage(Prefs.allowUnlimited) private var allowUnlimited = false
    @AppStorage(Prefs.adaptive) private var adaptive = true
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
    @AppStorage(Prefs.packPauseApps) private var packPauseApps = false
    @AppStorage(Prefs.preventLock) private var preventLock = false
    @AppStorage(Prefs.closedLidOnBattery) private var closedLidOnBattery = false
    @AppStorage(Prefs.caffeinateAlways) private var caffeinateAlways = false
    @AppStorage(Prefs.playSounds) private var playSounds = false
    @AppStorage(Prefs.notifications) private var notifications = true
    @AppStorage(Prefs.hotkey) private var hotkey = true
    @AppStorage(Prefs.nightAuto) private var nightAuto = true
    @AppStorage(Prefs.nightStartHour) private var nightStartHour = 22

    private let loginState = State(initialValue: SMAppService.mainApp.status == .enabled)
    private let helperState = State(initialValue: Privileged.isInstalled)
    private let reportState = State(initialValue: [String]())
    private let hookedState = State(initialValue: HookInstaller.installedAgents)
    private let helperErrorState = State<String?>(initialValue: nil)
    private let appNapState = State(initialValue: AppNap.isDisabledForAgents)
    private let watchedState = State(initialValue: Prefs.watchedAppIDs)

    private var watchedApps: [String] {
        get { watchedState.wrappedValue }
        nonmutating set {
            watchedState.wrappedValue = newValue
            Prefs.watchedAppIDs = newValue
        }
    }

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

    enum Tab: Hashable { case awake, safety, lid, agents, general }

    private let tabState = State(initialValue: SettingsView.startTab)

    private static var startTab: Tab {
        #if DEBUG
        initialTab ?? .awake
        #else
        .awake
        #endif
    }
    private var tab: Tab {
        get { tabState.wrappedValue }
        nonmutating set { tabState.wrappedValue = newValue }
    }

    #if DEBUG
    /// Lets snapshots open a given tab.
    nonisolated(unsafe) static var initialTab: Tab?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabs(tabs: [
                (Tab.awake, "Awake", "moon.zzz.fill"),
                (.safety, "Safety", "shield.lefthalf.filled"),
                (.lid, "Lid & Display", "laptopcomputer"),
                (.agents, "Agents", "sparkles"),
                (.general, "General", "gearshape.fill"),
            ], selection: Binding(get: { tab }, set: { tab = $0 }))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            Divider()
            #if DEBUG
            if Self.initialTab != nil { page } else { ScrollView { page }.frame(height: 560) }
            #else
            ScrollView { page }.frame(height: 560)
            #endif
        }
        .frame(width: 560)
        .onAppear {
            NSApp.activate()
        }
        .onChange(of: adaptive) { _, on in engine.setAgentsOnly(on) }
        .onChange(of: keepDisplayAwake) { engine.settingsChanged() }
        .onChange(of: preventLock) { engine.settingsChanged() }
        .onChange(of: closedLidOnBattery) { engine.settingsChanged() }
        .onChange(of: hotkey) { engine.settingsChanged() }
        .onChange(of: lidPolicy) { engine.settingsChanged() }
        .onChange(of: powerMode) { engine.settingsChanged() }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch tab {
            case .awake: holdTab
            case .safety: safetyTab
            case .lid: lidTab
            case .agents: agentsTab
            case .general: generalTab
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hours(_ values: [Double]) -> [(value: Double, label: String)] {
        values.map { ($0, "\(Int($0)) h") }
    }

    @ViewBuilder private var holdTab: some View {
        SettingsCard(title: "At night",
                     note: "Stays awake until your agents finish, and never past \(HoldEngine.hourLabel(Prefs.morningHour)). Turn Stay Awake off and it stays off for the rest of the night.") {
            SwitchRow(symbol: "moon.stars.fill", title: "Turn on by itself when an agent is working", tint: .indigo, isOn: $nightAuto)
            RowDivider()
            ChoiceRow(symbol: "clock.fill", title: "Starting at", tint: .indigo, options: (19...23).map { ($0, HoldEngine.hourLabel($0)) }, selection: $nightStartHour)
            .disabled(!nightAuto)
        }
        SettingsCard(title: "Session",
                     note: "With no time limit, HODL still lets the Mac sleep for battery, heat, and unplugging, and puts normal sleep back if it quits or crashes.") {
            ChoiceRow(symbol: "hourglass", title: "Stay awake overnight for", options: hours([4, 6, 8, 10, 12]), selection: $sessionHours)
            RowDivider()
            ChoiceRow(symbol: "stopwatch.fill", title: "Never longer than", options: hours([8, 10, 12, 16, 24]), selection: $maxHours)
            RowDivider()
            SwitchRow(symbol: "infinity", title: "Offer a session with no time limit", isOn: $allowUnlimited)
        }
        SettingsCard(title: "Agents only") {
            SwitchRow(symbol: "sparkles", title: "Stay awake only while an agent is working", tint: .purple, isOn: $adaptive)
            RowDivider()
            ChoiceRow(symbol: "zzz", title: "Let the Mac sleep after agents are idle for", tint: .purple, options: [2, 5, 10, 15, 20, 30].map { ($0, "\($0) min") }, selection: $idleMinutes)
            .disabled(!adaptive)
        }
        SettingsCard(title: "Power", note: powerMode.detail) {
            ChoiceRow(symbol: powerMode.symbol, title: "Stay awake on", tint: .green, options: PowerMode.allCases.map { ($0, $0.title) }, selection: $powerMode)
        }
        SettingsCard(title: "Stay awake while an app runs",
                     note: "When one of these apps opens, HODL keeps the Mac awake until it quits, up to the longest time you allow. Good for a training run, a render, or a long download.") {
            ForEach(watchedApps, id: \.self) { id in
                HStack(spacing: 12) {
                    Group {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                        } else {
                            Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 24, height: 24)
                    Text(verbatim: HoldEngine.appName(id)).font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Button { watchedApps.removeAll { $0 == id } } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Stop watching this app"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                RowDivider()
            }
            Button { chooseApp() } label: {
                Label("Add App…", systemImage: "plus.circle.fill")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var safetyTab: some View {
        SettingsCard(title: "Battery",
                     note: "If the battery level can’t be read on battery, HODL lets the Mac sleep rather than guess. Low Power Mode needs the closed-lid helper in Lid & Display.") {
            ChoiceRow(symbol: "battery.25percent", title: "Let the Mac sleep at", tint: .red, options: [5, 10, 15, 20, 25, 30].map { ($0, "\($0)%") }, selection: $batteryFloor)
            RowDivider()
            ChoiceRow(symbol: "leaf.fill", title: "Turn on Low Power Mode at", tint: .yellow, options: [(0, "Never")] + [30, 40, 50, 60].map { ($0, "\($0)%") }, selection: $softFloor)
            RowDivider()
            ChoiceRow(symbol: "battery.75percent", title: "On battery, start only above", tint: .green, options: [(0, "Any level")] + [30, 50, 70].map { ($0, "\($0)%") }, selection: $engageAbove)
        }
        SettingsCard(title: "Heat") {
            SwitchRow(symbol: "thermometer.medium", title: "Let the Mac rest when it gets hot",
                      detail: "Low Power Mode on serious heat, sleep if it lasts 10 minutes, and sleep at once if it turns critical.",
                      tint: .orange, isOn: $thermalGuard)
        }
    }

    @ViewBuilder private var lidTab: some View {
        SettingsCard(title: "Lid") {
            ChoiceRow(symbol: "laptopcomputer", title: "Stay awake when the lid is", detail: lidPolicy.detail, options: LidPolicy.allCases.map { ($0, $0.short) }, selection: $lidPolicy)
            RowDivider()
            SwitchRow(symbol: "battery.100percent.bolt", title: "Stay awake with the lid closed on battery",
                      detail: "macOS always sleeps on lid close on battery. HODL switches that off only while it keeps the Mac awake, and always switches it back, even after a crash.",
                      tint: .green, isOn: $closedLidOnBattery)
                .disabled(!helperInstalled)
            RowDivider()
            SettingRow(symbol: "key.fill", title: "Closed-lid helper",
                       detail: helperInstalled ? "Installed" : "Needed to stay awake with the lid closed on battery, and for Low Power Mode.", tint: .gray) {
                RowButton(title: helperInstalled ? "Remove…" : "Install…", destructive: helperInstalled) { toggleHelper() }
            }
            if let helperError {
                Text(verbatim: helperError)
                    .font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
        Text("The helper adds /etc/sudoers.d/hodl, which lets HODL run only these four commands without a password: \(Privileged.commands.joined(separator: ", ")).")
            .font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, -12)
        SettingsCard(title: "When the lid closes while awake",
                     note: "Agents, terminals, meeting apps, browsers, editors, and Apple’s own apps are never paused. Everything comes back when the lid opens or HODL turns off.") {
            SwitchRow(symbol: "moon.fill", title: "Quiet Mode", detail: "Do the things below each time you close the lid.", tint: .indigo, isOn: $lidPack)
            Group {
                RowDivider()
                SwitchRow(symbol: "sun.min.fill", title: "Dim the display and keyboard light", tint: .yellow, isOn: $packDim)
                RowDivider()
                SwitchRow(symbol: "speaker.slash.fill", title: "Mute sound", tint: .pink, isOn: $packMute)
                RowDivider()
                SwitchRow(symbol: "bubble.left.and.bubble.right.fill", title: "Pause Slack, Discord, and WhatsApp", tint: .teal, isOn: $packPauseChat)
                RowDivider()
                SwitchRow(symbol: "dock.rectangle", title: "Pause other Dock apps too", tint: .teal, isOn: $packPauseApps)
                RowDivider()
                SwitchRow(symbol: "leaf.fill", title: "Turn on Low Power Mode", tint: .yellow, isOn: $packLowPower)
                    .disabled(!helperInstalled)
                RowDivider()
                SwitchRow(symbol: "lock.fill", title: "Lock the screen", tint: .gray, isOn: $packLock)
            }
            .disabled(!lidPack)
        }
        SettingsCard(title: "Display") {
            SwitchRow(symbol: "display", title: "Turn the display off when HODL turns on", tint: .blue, isOn: $displayOff)
            RowDivider()
            SwitchRow(symbol: "sun.max.fill", title: "Keep the display on", tint: .yellow, isOn: $keepDisplayAwake)
            RowDivider()
            SwitchRow(symbol: "lock.open.fill", title: "Prevent the screen saver and screen lock",
                      detail: "Off, the Mac locks as usual while agents keep working. On, nothing starts until HODL turns off.",
                      tint: .gray, isOn: $preventLock)
            RowDivider()
            ChoiceRow(symbol: "moon.zzz.fill", title: "Turn the display off after agents finish", tint: .blue, options: [(0, "Never"), (10, "10 s"), (30, "30 s"), (60, "1 min"), (300, "5 min")], selection: $displayOffAfterAgents)
        }
    }

    @ViewBuilder private var agentsTab: some View {
        SettingsCard(title: "Watching",
                     note: "HODL sees which agents run from process names and bundle IDs, and guesses whether they’re working from CPU use. It never reads code, prompts, or terminal output.") {
            SettingRow(symbol: "eye.fill", title: "Agents HODL watches for", detail: Harness.all.map(\.title).joined(separator: ", "), tint: .purple) { EmptyView() }
            RowDivider()
            SwitchRow(symbol: "bolt.fill", title: "Keep agent apps out of App Nap",
                      detail: "Stops macOS from slowing Cursor, Codex, and Windsurf in the background. Applies the next time each app opens.",
                      tint: .orange, isOn: Binding(
                          get: { appNapOff },
                          set: { AppNap.setDisabledForAgents($0); appNapOff = AppNap.isDisabledForAgents }
                      ))
        }
        SettingsCard(title: "Hooks",
                     note: "Working and Idle hooks for Claude Code, Codex, Cursor, and OpenCode tell HODL exactly when each session works. They send only the agent, its state, and a session ID to 127.0.0.1:8742, and every changed file is backed up first as .hodl-backup.") {
            SettingRow(symbol: "link", title: "Installed for", detail: hookedAgents.isEmpty ? "None yet" : hookedAgents.joined(separator: ", "), tint: .purple) {
                HStack(spacing: 6) {
                    RowButton(title: hookedAgents.isEmpty ? "Install" : "Reinstall") {
                        hookReport = HookInstaller.installAll()
                        hookedAgents = HookInstaller.installedAgents
                    }
                    if !hookedAgents.isEmpty {
                        RowButton(title: "Remove", destructive: true) {
                            hookReport = HookInstaller.uninstallAll()
                            hookedAgents = HookInstaller.installedAgents
                        }
                    }
                }
            }
            if !hookReport.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(hookReport, id: \.self) { Text(verbatim: $0).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.leading, 48).padding(.trailing, 12).padding(.bottom, 10)
            }
        }
        SettingsCard(title: "Command line",
                     note: "Installed with the hooks, to ~/.local/bin. hodl-run keeps the Mac awake while a command runs.") {
            Text(verbatim: "hodl hold --until agents-idle\nhodl status\nhodl-run -- <command>")
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    @ViewBuilder private var generalTab: some View {
        SettingsCard(title: "General") {
            SwitchRow(symbol: "power", title: "Open at login", tint: .green, isOn: Binding(
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
            RowDivider()
            SwitchRow(symbol: "command", title: "Turn HODL on or off with ⌥⌘L", tint: .gray, isOn: $hotkey)
            RowDivider()
            SwitchRow(symbol: "bell.badge.fill", title: "Show notifications", tint: .red, isOn: $notifications)
            RowDivider()
            SwitchRow(symbol: "speaker.wave.2.fill", title: "Play sounds", tint: .pink, isOn: $playSounds)
            RowDivider()
            SwitchRow(symbol: "cup.and.saucer.fill", title: "Also run caffeinate as a backup",
                      detail: "HODL uses IOKit power assertions, and starts caffeinate -i -s on its own only if macOS refuses them.",
                      tint: .brown, isOn: $caffeinateAlways)
        }
        SettingsCard(title: "Uninstall",
                     note: "Removes hooks, command-line tools, the closed-lid helper, and the login item, then moves HODL to the Trash. It waits while HODL is keeping the Mac awake or still has something to put back.") {
            SettingRow(symbol: "trash.fill", title: "Remove HODL from this Mac", tint: .red) {
                RowButton(title: "Uninstall…", destructive: true) { Uninstaller.run() }
            }
        }
        VStack(spacing: 6) {
            HODLMark(size: 40)
            HStack(spacing: 6) {
                Text("Made by").foregroundStyle(.secondary)
                Text(verbatim: "1xAI").font(.system(.callout, design: .rounded).weight(.heavy))
            }
            HStack(spacing: 10) {
                Link("Visit the website", destination: AppLinks.website)
                Link(AppLinks.repositoryLabel, destination: AppLinks.repository)
            }
            .font(.caption)
            Text(verbatim: "HODL \(Bundle.main.shortVersion) · \(Bundle.main.copyright)")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { $0 != Bundle.main.bundleIdentifier }
        watchedApps = Array(NSOrderedSet(array: watchedApps + ids)) as? [String] ?? watchedApps
    }

    private func toggleHelper() {
        helperError = helperInstalled ? Privileged.removeRule() : Privileged.installRule()
        helperInstalled = Privileged.isInstalled
        if !helperInstalled { closedLidOnBattery = false }
    }
}
