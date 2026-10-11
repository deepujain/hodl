import SwiftUI

/// The desktop control window: the current hold, agent sessions, power assertions, and the ledger.
struct SessionView: View {
    let engine: HoldEngine
    let agents: AgentMonitor
    let power: PowerMonitor

    private let assertionsState = State(initialValue: "")
    private let loadingState = State(initialValue: false)

    private var assertions: String {
        get { assertionsState.wrappedValue }
        nonmutating set { assertionsState.wrappedValue = newValue }
    }

    private var loadingAssertions: Bool {
        get { loadingState.wrappedValue }
        nonmutating set { loadingState.wrappedValue = newValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                controls
                agentSessions
                assertionsSection
                history
            }
            .padding(24)
            .padding(.top, 12)
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private var hero: some View {
        HStack(spacing: 16) {
            HODLMark(size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: engine.session == nil ? "Not holding" : engine.engaged ? "Holding" : "Standing by")
                    .font(.system(.title, design: .rounded).weight(.semibold))
                Text(verbatim: engine.session == nil ? (engine.lastRelease?.reason.sentence ?? "Your Mac sleeps as usual.") : engine.describeSession())
                    .foregroundStyle(.secondary)
                if let standby = engine.standby {
                    Text(verbatim: standby).font(.callout).foregroundStyle(.orange)
                }
            }
            Spacer()
            if let remaining = engine.remaining {
                VStack(alignment: .trailing) {
                    Text(verbatim: HoldEngine.format(remaining))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("left").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var controls: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if engine.session == nil {
                        Button("Hold Overnight") { engine.hold() }.keyboardShortcut(.defaultAction)
                        Button("Until Agents Finish") { engine.hold(adaptive: true) }
                        Menu("Hold For…") {
                            Button("4 Hours") { engine.hold(duration: 4 * 3600) }
                            Button("8 Hours") { engine.hold(duration: 8 * 3600) }
                            Button("12 Hours") { engine.hold(duration: 12 * 3600) }
                            Button("Until 7 AM") { _ = Commands.run("hold", ["at": "07:00"], source: "session window") }
                            if Prefs.bool(Prefs.allowUnlimited) { Button("No Time Limit") { engine.hold(duration: .infinity) } }
                        }
                        .fixedSize()
                    } else {
                        Button("Release") { engine.release(.user) }.keyboardShortcut(.defaultAction)
                        Button("+30m") { engine.extend(hours: 0.5) }
                        Button("+1h") { engine.extend(hours: 1) }
                        Button("+2h") { engine.extend(hours: 2) }
                        if engine.pausedUntil == nil {
                            Menu("Pause") {
                                Button("30 Minutes") { engine.pause(minutes: 30) }
                                Button("1 Hour") { engine.pause(minutes: 60) }
                            }
                            .fixedSize()
                        } else {
                            Button("Resume") { engine.resume() }
                        }
                    }
                    Spacer()
                    Button("Display Off") { engine.displayOffNow() }
                }
                Divider()
                HStack(spacing: 18) {
                    stat("Battery", power.hasBattery ? "\(power.batteryLabel)\(power.onAC ? " · AC" : "")" : "AC power")
                    stat("Thermal", power.thermalTitle)
                    stat("Lid", power.lidClosed ? "Closed" : "Open")
                    stat("Low Power", power.lowPowerMode ? "On" : "Off")
                    stat("Keeping awake", SleepGuard.shared.summary)
                }
                Label("Keep the Mac on a desk or stand, not in a closed bag. macOS battery and thermal limits can still win.",
                      systemImage: "wind")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(.tertiary)
            Text(verbatim: value).font(.callout).lineLimit(1)
        }
    }

    private var agentSessions: some View {
        GroupBox("Agents") {
            VStack(alignment: .leading, spacing: 6) {
                let running = agents.statuses.filter { $0.state != .off }
                if running.isEmpty {
                    Text("No coding agents are running.").foregroundStyle(.secondary)
                }
                ForEach(running) { status in
                    HStack(spacing: 8) {
                        StatusDot(state: status.state)
                        Image(systemName: status.harness.symbol).frame(width: 18)
                        Text(verbatim: status.harness.title).fontWeight(.medium)
                        Text(verbatim: status.state.title).foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: "\(status.processes) process\(status.processes == 1 ? "" : "es") · \(Int(status.cpu.rounded()))% CPU")
                            .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                    }
                    ForEach(status.sessions) { session in
                        HStack(spacing: 6) {
                            Text(verbatim: session.source == .hook ? "Session \(session.session.prefix(8))" : "hodl-run \(session.session.prefix(12))")
                                .font(.caption.monospaced())
                            Text(verbatim: session.working ? "working" : "idle")
                                .font(.caption).foregroundStyle(session.working ? .green : .secondary)
                            Spacer()
                            Text(session.since, style: .relative).font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.leading, 34)
                    }
                }
                if !HookInstaller.toolsInstalled {
                    Text("Tip: install agent hooks in Settings so HODL knows exactly when each session works.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var assertionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Power assertions").font(.headline)
                    Spacer()
                    Button(loadingAssertions ? "Reading…" : "Refresh") { Task { await loadAssertions() } }
                        .disabled(loadingAssertions)
                }
                Text("What `pmset -g assertions` reports right now. Scheduled battery events from macOS can still put the Mac to sleep.")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    Text(verbatim: assertions.isEmpty ? "—" : assertions)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            .padding(6)
        }
        .task { await loadAssertions() }
    }

    private func loadAssertions() async {
        loadingAssertions = true
        assertions = await SleepGuard.pmsetAssertions().trimmingCharacters(in: .whitespacesAndNewlines)
        loadingAssertions = false
    }

    private var history: some View {
        GroupBox("History") {
            VStack(alignment: .leading, spacing: 6) {
                if Ledger.shared.entries.isEmpty {
                    Text("Nothing yet.").foregroundStyle(.secondary)
                }
                ForEach(Ledger.shared.entries.prefix(30)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            .frame(width: 110, alignment: .leading)
                        Text(verbatim: entry.event.capitalized).font(.caption.weight(.semibold)).frame(width: 74, alignment: .leading)
                        Text(verbatim: entry.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}
