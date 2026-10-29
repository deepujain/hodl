#if DEBUG
import AppKit
import SwiftUI

/// `HODL --snapshots <folder>` renders the panel and windows to PNGs for checking layout.
@MainActor
enum Snapshots {
    static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        PowerMonitor.shared.refresh()
        PowerMonitor.shared.refreshLid()
        AgentMonitor.shared.refresh()
        Thread.sleep(forTimeInterval: 1)
        AgentMonitor.shared.refresh()
        MenuPanel.drawsFlat = true
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .light ? "light" : "dark"
            write(MenuPanel(engine: .shared, agents: .shared, power: .shared), name: "panel-\(suffix)", scheme: scheme, folder: folder)
        }
        write(AboutView(), name: "about", scheme: .light, folder: folder)
        for (tab, name) in [(SettingsView.Tab.awake, "awake"), (.safety, "safety"), (.lid, "lid"), (.agents, "agents"), (.general, "general")] {
            SettingsView.initialTab = tab
            write(SettingsView(engine: .shared), name: "settings-\(name)", scheme: .light, folder: folder)
        }
        SettingsView.initialTab = .lid
        write(SettingsView(engine: .shared), name: "settings-lid-dark", scheme: .dark, folder: folder)
        SettingsView.initialTab = nil
        write(AppIconArtwork(), name: "icon", scheme: .light, folder: folder, scale: 0.5)
    }

    private static func write(_ view: some View, name: String, scheme: ColorScheme, folder: URL, scale: CGFloat = 2) {
        let content = view
            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: folder.appending(path: "\(name).png"))
    }
}
#endif
