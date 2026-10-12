import AppKit
import ServiceManagement

/// Removes everything HODL added outside its bundle, then moves the app to the Trash.
/// Refuses while a hold runs or anything is still waiting to be put back.
@MainActor
enum Uninstaller {
    static func run() {
        if let reason = blocker() {
            alert("HODL can’t uninstall yet", reason, buttons: ["OK"])
            return
        }
        let confirmed = alert("Uninstall HODL?",
                              "HODL removes its agent hooks (restoring each file’s backup), its command-line tools, the closed-lid helper, its login item, App Nap settings, and its ledger, then moves itself to the Trash.",
                              buttons: ["Uninstall", "Cancel"]) == .alertFirstButtonReturn
        guard confirmed else { return }

        var problems: [String] = []
        if Privileged.isInstalled, let error = Privileged.removeRule() { problems.append(error) }
        _ = HookInstaller.uninstallAll()
        HookInstaller.removeTools()
        AppNap.setDisabledForAgents(false)
        try? SMAppService.mainApp.unregister()
        Backstop.remove()
        try? FileManager.default.removeItem(at: Recovery.folder)
        if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }

        if !problems.isEmpty {
            alert("HODL couldn’t remove everything", problems.joined(separator: "\n"), buttons: ["OK"])
        }
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
    }

    static func blocker() -> String? {
        if HoldEngine.shared.session != nil { return "HODL is keeping the Mac awake. Turn it off first, so normal sleep comes back before HODL goes." }
        if Recovery.hasPendingChanges {
            return "HODL still has changes to put back (sleep, Low Power Mode, sound, brightness, or paused apps). Choose Retry from the menu until they’re restored."
        }
        return nil
    }

    @discardableResult
    private static func alert(_ title: String, _ message: String, buttons: [String]) -> NSApplication.ModalResponse {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert.runModal()
    }
}
