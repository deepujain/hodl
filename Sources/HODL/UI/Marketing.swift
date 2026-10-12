#if DEBUG
import AppKit
import SwiftUI

/// `HODL --marketing <folder>` renders the website images from staged state. Nothing is held while rendering.
@MainActor
enum Marketing {
    static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        output = folder
        MenuPanel.drawsFlat = true
        UserDefaults.standard.register(defaults: [Prefs.lidPack: true, Prefs.adaptive: false])
        let engine = HoldEngine.shared, agents = AgentMonitor.shared, power = PowerMonitor.shared

        engine.stage(endsIn: 7 * 3600 + 42 * 60)
        power.stage(percent: 82, onAC: false, lidClosed: false)
        agents.stage(["claude": .active, "codex": .active, "cursor": .active, "aider": .idle, "pi": .off])
        let holding = MenuPanel(engine: engine, agents: agents, power: power)
        write(Stage(photo: .detail) { holding.panelChrome(dark: false) }, name: "shot-menu", size: CGSize(width: 560, height: 620))
        write(Stage(photo: .evening, alignment: .trailing) { holding.panelChrome(dark: true) },
              name: "shot-hold", size: CGSize(width: 800, height: 600))
        write(Poster(panel: holding.panelChrome(dark: true)), name: "hodl-poster", size: CGSize(width: 1280, height: 800))

        write(Stage(photo: .icon, alignment: .bottom) { LidPill() }, name: "shot-lid", size: CGSize(width: 800, height: 600))
        write(Stage(photo: .sunrise, alignment: .top) { Banners() }, name: "shot-done", size: CGSize(width: 800, height: 600))
        write(Stage(photo: .detail, alignment: .bottom) { LedgerCard() }, name: "shot-ledger", size: CGSize(width: 760, height: 420))
        write(AppIconArtwork(), name: "hodl-icon", size: nil, scale: 1)
    }

    private static func write(_ view: some View, name: String, size: CGSize?, scale: CGFloat = 2) {
        let content = view.frame(width: size?.width, height: size?.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: output.appending(path: "\(name).png"))
    }

    private static var output = URL(fileURLWithPath: ".")
}

private extension MenuPanel {
    func panelChrome(dark: Bool, shadow: Bool = true) -> some View {
        self
            .background(dark ? Color(white: 0.15) : Color(white: 0.97))
            .environment(\.colorScheme, dark ? .dark : .light)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(dark ? 0.12 : 0.6), lineWidth: 1))
            .shadow(color: .black.opacity(shadow ? 0.45 : 0), radius: 30, y: 16)
    }
}

/// A photograph filling the frame behind the real UI.
private struct Backdrop: View {
    let photo: Photo

    var body: some View {
        Color.black.overlay { photo.image.resizable().interpolation(.high).scaledToFill() }.clipped()
    }
}

private struct Stage<Content: View>: View {
    let photo: Photo
    var alignment: Alignment = .center
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: alignment) {
            Backdrop(photo: photo)
            content.padding(40)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// The status a closed-lid hold shows, over the photo of the lid.
private struct LidPill: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill").foregroundStyle(Color(red: 0.45, green: 0.98, blue: 0.80))
            Text(verbatim: "Holding · lid closed · 3 agents working")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .background(Capsule().fill(Color(white: 0.12).opacity(0.92)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }
}

/// Two notifications from a night of holding, newest first.
private struct Banners: View {
    var body: some View {
        VStack(spacing: 14) {
            banner(time: "6:12 AM", title: "Agents finished",
                   body: "Every agent finished and stayed idle past the timeout. The Mac can sleep normally now.")
            banner(time: "11:48 PM", title: "HODL is holding",
                   body: "Holding until 7:00 AM. Keep the Mac on a desk or stand, not in a closed bag.")
                .opacity(0.85)
                .scaleEffect(0.96)
        }
        .frame(width: 560)
    }

    private func banner(time: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AppIconArtwork().scaleEffect(54 / 824).frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(verbatim: title).font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text(verbatim: time).font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Text(verbatim: body).font(.system(size: 15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(white: 0.17).opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }
}

/// The history a night leaves behind: every change, and every undo.
private struct LedgerCard: View {
    private let rows: [(String, String, String)] = [
        ("11:48 PM", "Hold", "Holding until 7:00 AM · from menu"),
        ("12:03 AM", "Lid pack", "dimmed · keyboard light off · muted · paused Slack"),
        ("2:41 AM", "Low power", "Turned on Low Power Mode (battery at 40%)."),
        ("6:12 AM", "Release", "Every agent finished and stayed idle past the timeout."),
        ("6:12 AM", "Restore", "Resumed apps and restored sound and brightness."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AppIconArtwork().scaleEffect(34 / 824).frame(width: 28, height: 28)
                Text("History").font(.system(size: 17, weight: .semibold))
            }
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: row.0).font(.system(size: 13).monospacedDigit()).foregroundStyle(.tertiary).frame(width: 70, alignment: .leading)
                    Text(verbatim: row.1).font(.system(size: 13, weight: .semibold)).frame(width: 74, alignment: .leading)
                    Text(verbatim: row.2).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(width: 600, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }
}

/// A night desktop: menu bar with HODL holding, the panel open under it, and the laptop scene.
private struct Poster<Panel: View>: View {
    let panel: Panel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Backdrop(photo: .hero)
            menuBar
            panel
                .scaleEffect(0.98, anchor: .topTrailing)
                .padding(.top, 36)
                .padding(.trailing, 150)
        }
        .frame(width: 1280, height: 800)
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    private var menuBar: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo")
            Text("Finder").fontWeight(.bold)
            ForEach(["File", "Edit", "View", "Go", "Window"], id: \.self) { Text(verbatim: $0) }
            Spacer()
            Image(systemName: "moon.zzz.fill")
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.22)))
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text(verbatim: "Sat 2:14 AM")
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 28)
        .background(Color.black.opacity(0.35))
    }
}
#endif
