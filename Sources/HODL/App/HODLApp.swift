import AppKit
import SwiftUI

@main
struct HODLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let arguments = CommandLine.arguments
        if arguments.contains(Backstop.flag) { Backstop.run() }
        if let flag = arguments.firstIndex(of: "--render-icon"), arguments.indices.contains(flag + 1) {
            do {
                try AppIconRenderer.writeIconset(to: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Icon rendering failed: \(error)\n".utf8))
                exit(1)
            }
        }
        #if DEBUG
        if let flag = arguments.firstIndex(of: "--snapshots"), arguments.indices.contains(flag + 1) {
            Prefs.register()
            Snapshots.render(to: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true))
            exit(0)
        }
        if arguments.contains("--install-hooks") || arguments.contains("--uninstall-hooks") {
            let report = arguments.contains("--install-hooks") ? HookInstaller.installAll() : HookInstaller.uninstallAll()
            print(report.joined(separator: "\n"))
            exit(0)
        }
        #endif
        Prefs.register()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(engine: HoldEngine.shared, agents: AgentMonitor.shared, power: PowerMonitor.shared)
        } label: {
            MenuBarLabel(engine: HoldEngine.shared)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(engine: HoldEngine.shared)
        }
    }
}

private struct MenuBarLabel: View {
    let engine: HoldEngine

    var body: some View {
        Image(systemName: engine.menuSymbol)
            .accessibilityLabel(Text(verbatim: "HODL · \(engine.statusLine)"))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Notifier.start()
        HoldEngine.shared.start()
        ControlServer.shared.start()
        Hotkey.action = { HoldEngine.shared.toggle(source: "⌥⌘L") }
        Hotkey.setEnabled(Prefs.bool(Prefs.hotkey))
        if !Prefs.bool(Prefs.hasOnboarded) {
            Prefs.set(true, Prefs.hasOnboarded)
            AppWindows.shared.showSession()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HoldEngine.shared.shutdown()
        ControlServer.shared.stop()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(Commands.handle)
    }
}

@MainActor
final class AppWindows {
    static let shared = AppWindows()
    private var session: NSWindow?
    private var about: NSWindow?

    func showSession() {
        if session == nil {
            session = makeWindow(title: "HODL Session", content: SessionView(engine: .shared, agents: .shared, power: .shared))
            session?.setContentSize(NSSize(width: 560, height: 640))
            session?.center()
        }
        present(session)
    }

    func showAbout() {
        if about == nil {
            about = makeWindow(title: "About HODL", content: AboutView())
            about?.center()
        }
        present(about)
    }

    private func makeWindow(title: String, content: some View) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = title
        window.contentView = NSHostingView(rootView: content)
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

enum AppLinks {
    static let repository = URL(string: "https://github.com/deepujain/hodl")!
    static let repositoryLabel = "github.com/deepujain/hodl"
}

extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
}
