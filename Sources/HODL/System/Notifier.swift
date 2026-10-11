import AppKit
import UserNotifications

@MainActor
enum Notifier {
    private final class Presenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
            -> UNNotificationPresentationOptions { [.banner, .list] }
    }

    private static let presenter = Presenter()

    static func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = presenter
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ title: String, _ body: String, important: Bool = false) {
        guard Prefs.bool(Prefs.notifications) || important else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if important { content.interruptionLevel = .timeSensitive }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

@MainActor
enum Sounds {
    private static func play(_ name: String, volume: Float) {
        guard Prefs.bool(Prefs.playSounds), let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    static func hold() { play("Tink", volume: 0.35) }
    static func release() { play("Pop", volume: 0.3) }
    static func warning() { play("Funk", volume: 0.35) }
}
