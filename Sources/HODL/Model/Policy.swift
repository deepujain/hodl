import Foundation

enum PowerMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case adaptive, ac, battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adaptive: "Any Power"
        case .ac: "AC Only"
        case .battery: "Battery"
        }
    }

    var detail: String {
        switch self {
        case .adaptive: "Holds on AC or battery, and turns on Low Power Mode as the battery runs down."
        case .ac: "Holds only while plugged in. Unplugging ends the hold."
        case .battery: "Holds on battery down to the floor, with no Low Power Mode step."
        }
    }

    var symbol: String {
        switch self {
        case .adaptive: "bolt.horizontal.circle"
        case .ac: "powerplug"
        case .battery: "battery.75percent"
        }
    }
}

enum LidPolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case either, closed, open

    var id: String { rawValue }

    var title: String {
        switch self {
        case .either: "Either"
        case .closed: "Lid Closed"
        case .open: "Lid Open"
        }
    }

    var detail: String {
        switch self {
        case .either: "Hold with the lid open or closed."
        case .closed: "Hold only while the lid is closed. With the lid open, macOS sleeps as usual."
        case .open: "Hold only while the lid is open. Closing it lets the Mac sleep."
        }
    }

    /// Fits the panel tile.
    var short: String {
        switch self {
        case .either: "Either"
        case .closed: "Closed"
        case .open: "Open"
        }
    }

    func allows(lidClosed: Bool) -> Bool {
        switch self {
        case .either: true
        case .closed: lidClosed
        case .open: !lidClosed
        }
    }
}

/// Why a hold ended. Shown in the menu, the session window, notifications, and the ledger.
enum ReleaseReason: String, Codable, Sendable {
    case user, timer, battery, batteryUnknown, thermal, agentsIdle, unplugged, quit, recovered, appQuit

    /// A few words for the status line: "Released · thermal".
    var short: String {
        switch self {
        case .user: "by you"
        case .timer: "time’s up"
        case .battery: "battery floor"
        case .batteryUnknown: "battery unreadable"
        case .thermal: "thermal"
        case .agentsIdle: "agents finished"
        case .unplugged: "unplugged"
        case .quit: "HODL quit"
        case .recovered: "recovered"
        case .appQuit: "app quit"
        }
    }

    var sentence: String {
        switch self {
        case .user: "You released the hold."
        case .timer: "The session timer ran out."
        case .battery: "The battery reached the floor you set."
        case .batteryUnknown: "The battery level couldn’t be read on battery power, so HODL let go to be safe."
        case .thermal: "The Mac got too hot, so HODL let it rest."
        case .agentsIdle: "Every agent finished and stayed idle past the timeout."
        case .unplugged: "The Mac was unplugged while AC Only was on."
        case .quit: "HODL quit and restored normal sleep."
        case .recovered: "HODL found an unfinished hold from last time and restored normal sleep."
        case .appQuit: "The app this hold was waiting on quit."
        }
    }

    var isSafetyStop: Bool { [.battery, .batteryUnknown, .thermal, .unplugged].contains(self) }
}

struct LedgerEntry: Codable, Identifiable, Sendable {
    var id = UUID()
    var date = Date()
    var event: String
    var detail: String
    var reason: ReleaseReason?
}
