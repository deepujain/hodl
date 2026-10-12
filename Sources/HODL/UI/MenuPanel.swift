import SwiftUI

/// The menu bar panel: status, agents and session tiles, quick switches, and the way to everything else.
struct MenuPanel: View {
    let engine: HoldEngine
    let agents: AgentMonitor
    let power: PowerMonitor

    @AppStorage(Prefs.adaptive) private var adaptive = false
    @AppStorage(Prefs.displayOff) private var displayOff = false
    @AppStorage(Prefs.lidPack) private var lidPack = false
    @AppStorage(Prefs.playSounds) private var playSounds = true
    @AppStorage(Prefs.powerMode) private var powerMode = PowerMode.adaptive
    @AppStorage(Prefs.lidPolicy) private var lidPolicy = LidPolicy.either
    @AppStorage(Prefs.batteryFloor) private var batteryFloor = 15
    @AppStorage(Prefs.thermalGuard) private var thermalGuard = true
    @AppStorage(Prefs.allowUnlimited) private var allowUnlimited = false

    /// The menu bar window keeps the size it first opened at, so the card has a fixed height.
    private static let cardHeight: CGFloat = 262
    #if DEBUG
    /// Snapshots can’t draw pull-down menus.
    static var drawsFlat = false
    #else
    private static let drawsFlat = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            card
                .frame(height: Self.cardHeight)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)

            notice
                .padding(.horizontal, 16)
                .padding(.top, 8)

            switches
                .padding(.horizontal, 12)
                .padding(.top, 10)

            Divider().padding(.top, 12)
            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 344)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            HODLMark(size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "HODL")
                    .font(.system(.headline, design: .rounded))
                Text(verbatim: engine.statusLine)
                    .font(.subheadline)
                    .foregroundStyle(engine.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            if Self.drawsFlat {
                Image(systemName: engine.session != nil ? "plus.circle" : "timer").foregroundStyle(.secondary)
            } else if engine.session != nil {
                Menu {
                    Button("Add 30 Minutes") { engine.extend(hours: 0.5) }
                    Button("Add 1 Hour") { engine.extend(hours: 1) }
                    Button("Add 2 Hours") { engine.extend(hours: 2) }
                    Divider()
                    if engine.pausedUntil == nil {
                        Button("Pause for 30 Minutes") { engine.pause(minutes: 30) }
                        Button("Pause for 1 Hour") { engine.pause(minutes: 60) }
                    } else {
                        Button("Resume Now") { engine.resume() }
                    }
                    Divider()
                    Button("Turn Off") { engine.release(.user) }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Text("Add time, pause, or turn off"))
            } else {
                Menu {
                    Button("4 Hours") { engine.hold(duration: 4 * 3600) }
                    Button("8 Hours") { engine.hold(duration: 8 * 3600) }
                    Button("12 Hours") { engine.hold(duration: 12 * 3600) }
                    Button("Until 7 AM") { _ = Commands.run("hold", ["at": "07:00"], source: "menu") }
                    Divider()
                    Button("Until Agents Finish") { engine.hold(adaptive: true) }
                    if allowUnlimited { Button("No Time Limit") { engine.hold(duration: .infinity) } }
                } label: {
                    Image(systemName: "timer")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Text("Stay awake for a set time"))
            }
        }
    }

    // MARK: Card

    private var card: some View {
        let shown = Array(agents.visibleStatuses.prefix(6))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        return VStack(alignment: .leading, spacing: 6) {
            SectionHeading(title: "Agents", trailing: agentsSummary)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(shown) { status in
                    Tile(symbol: status.harness.symbol, title: status.harness.title, value: agentValue(status),
                         tint: .accentColor, dimmed: status.state == .off) {
                        StatusDot(state: status.state)
                    }
                    .help(Text(verbatim: agentHelp(status)))
                }
            }
            SectionHeading(title: "Session")
                .padding(.top, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                Menu {
                    Picker("Power", selection: $powerMode) {
                        ForEach(PowerMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Tile(symbol: powerMode.symbol, title: "Power", value: powerMode.title, tint: .accentColor) { MenuChevron() }
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .help(Text(verbatim: powerMode.detail))

                Menu {
                    Picker("Lid", selection: $lidPolicy) {
                        ForEach(LidPolicy.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Tile(symbol: power.lidClosed ? "laptopcomputer.slash" : "laptopcomputer", title: "Lid",
                         value: lidPolicy.short, tint: .accentColor) { MenuChevron() }
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .help(Text(verbatim: lidPolicy.detail))

                Menu {
                    Picker("Battery Floor", selection: $batteryFloor) {
                        ForEach([10, 15, 20, 25, 30], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Tile(symbol: "battery.25percent", title: "Battery", value: "Floor \(batteryFloor)%",
                         tint: power.lowPowerMode ? .yellow : .accentColor) { MenuChevron() }
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .help(Text("HODL lets the Mac sleep when the battery reaches this level.\(power.lowPowerMode ? " Low Power Mode is on." : "")"))

                Button {
                    thermalGuard.toggle()
                } label: {
                    Tile(symbol: "thermometer.medium", title: "Heat", value: thermalGuard ? "On · \(power.thermalTitle)" : "Off",
                         tint: power.thermal.rawValue >= ProcessInfo.ThermalState.serious.rawValue ? .orange : .accentColor,
                         dimmed: !thermalGuard)
                }
                .buttonStyle(.plain)
                .help(Text("Lets the Mac rest if it gets too hot. Click to turn the guard \(thermalGuard ? "off" : "on")."))
            }
        }
        .padding(10)
        .onChange(of: powerMode) { engine.settingsChanged() }
        .onChange(of: lidPolicy) { engine.settingsChanged() }
        .onChange(of: batteryFloor) { engine.settingsChanged() }
        .onChange(of: thermalGuard) { engine.settingsChanged() }
    }

    private var agentsSummary: String {
        let active = agents.activeCount
        if active > 0 { return "\(active) working" }
        let running = agents.runningCount
        return running > 0 ? "\(running) running" : "none running"
    }

    private func agentValue(_ status: HarnessStatus) -> String {
        let sessions = status.sessions.count
        switch status.state {
        case .off: return "Not running"
        case .active: return sessions > 1 ? "Active · \(sessions)" : "Active"
        case .idle: return sessions > 1 ? "Idle · \(sessions)" : "Idle"
        case .detected: return "Detected"
        }
    }

    private func agentHelp(_ status: HarnessStatus) -> String {
        switch status.state {
        case .off: "\(status.harness.title) isn’t running."
        case .active: "\(status.harness.title) is working."
        case .idle: "\(status.harness.title) is open and waiting."
        case .detected: "\(status.harness.title) is running. Install hooks in Settings to see when it works."
        }
    }

    // MARK: Notice

    @ViewBuilder
    private var notice: some View {
        if let warning = engine.restoreWarning {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(verbatim: warning).lineLimit(2)
                Spacer(minLength: 4)
                Button("Retry") { engine.retryRestore() }.controlSize(.small)
            }
            .font(.caption)
        } else if let refusal = engine.refusal, engine.session == nil {
            Label { Text(verbatim: refusal).lineLimit(2) } icon: { Image(systemName: "info.circle") }
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label { Text(verbatim: switchSummary).lineLimit(3).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: engine.session == nil ? "moon" : "moon.zzz.fill")
            }
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What the five switches below add up to, in plain words.
    private var switchSummary: String {
        guard let session = engine.session else {
            return "Stay Awake is off, so the Mac sleeps as usual. The other switches apply once it’s on."
        }
        let left = engine.remaining.map { "for \(HoldEngine.format($0))" } ?? "with no time limit"
        return [
            session.adaptive ? "Stays awake until agents finish." : "Stays awake \(left), even after agents finish.",
            displayOff ? "Screen off." : "Screen on.",
            lidPack ? "Closing the lid dims, mutes, and pauses chat apps." : "Closing the lid leaves sound and apps alone.",
            playSounds ? "Sounds on." : "Sounds off.",
        ].joined(separator: " ")
    }

    // MARK: Switches

    private var switches: some View {
        HStack(spacing: 0) {
            QuickSwitch(symbol: "moon.zzz.fill", title: "Stay Awake", isOn: Binding(
                get: { engine.session != nil },
                set: { $0 ? engine.hold() : engine.release(.user) }
            ), help: "Keep the Mac awake overnight (⌥⌘L). Ends on its own when the session timer runs out.")
            QuickSwitch(symbol: "sparkles", title: "Agents Only", isOn: $adaptive,
                        help: "Stay awake only while an agent is working, and let the Mac sleep once it has been idle for a while.")
            QuickSwitch(symbol: "display", title: "Display Off", isOn: $displayOff,
                        help: "Turn the display off once the Mac is set to stay awake. It keeps running.")
            QuickSwitch(symbol: "laptopcomputer.and.arrow.down", title: "Quiet Mode", isOn: $lidPack,
                        help: "When you close the lid: dim the screen and keyboard light, mute sound, and pause Slack, Discord, and WhatsApp. Agents are never paused. Everything comes back when you open it.")
            QuickSwitch(symbol: playSounds ? "speaker.wave.2.fill" : "speaker.slash.fill", title: "Sounds", isOn: $playSounds,
                        help: "Soft sounds when staying awake starts and ends.")
        }
        .onChange(of: displayOff) { _, on in
            if on, engine.engaged { engine.displayOffNow() }
        }
        .onChange(of: adaptive) { _, on in engine.setAgentsOnly(on) }
        .onChange(of: lidPack) { engine.settingsChanged() }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            FooterButton(symbol: "macwindow", title: "Session Window") {
                closeMenu()
                AppWindows.shared.showSession()
            }
            FooterButton(symbol: "display.and.arrow.down", title: "Turn Display Off Now") {
                closeMenu()
                engine.displayOffNow()
            }
            Spacer()
            FooterButton(symbol: "info.circle", title: "About HODL") {
                closeMenu()
                AppWindows.shared.showAbout()
            }
            SettingsLink {
                FooterIcon(symbol: "gearshape")
            }
            .buttonStyle(FooterButtonStyle())
            .keyboardShortcut(",")
            .help(Text("Settings"))
            .simultaneousGesture(TapGesture().onEnded { closeMenu() })
            FooterButton(symbol: "power", title: "Quit HODL") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func closeMenu() {
        NSApp.keyWindow?.close()
    }
}
