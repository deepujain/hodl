import Foundation

/// UserDefaults keys and defaults. Views read these with `@AppStorage`; the engine reads them directly.
enum Prefs {
    static let sessionHours = "sessionHours"
    static let maxHours = "maxHours"
    static let allowUnlimited = "allowUnlimited"
    static let adaptive = "adaptive"
    static let idleMinutes = "idleMinutes"
    static let powerMode = "powerMode"
    static let lidPolicy = "lidPolicy"
    static let batteryFloor = "batteryFloor"
    static let softFloor = "softFloor"
    static let engageAbove = "engageAbove"
    static let thermalGuard = "thermalGuard"
    static let keepDisplayAwake = "keepDisplayAwake"
    static let displayOff = "displayOff"
    static let displayOffAfterAgents = "displayOffAfterAgents"
    static let lidPack = "lidPack"
    static let packDim = "packDim"
    static let packMute = "packMute"
    static let packPauseChat = "packPauseChat"
    static let packLowPower = "packLowPower"
    static let packLock = "packLock"
    static let packPauseApps = "packPauseApps"
    static let preventLock = "preventLock"
    static let watchedApps = "watchedApps"
    static let closedLidOnBattery = "closedLidOnBattery"
    static let caffeinateAlways = "caffeinateAlways"
    static let playSounds = "playSounds"
    static let notifications = "notifications"
    static let hotkey = "hotkey"
    static let hasOnboarded = "hasOnboarded"
    static let nightAuto = "nightAuto"
    static let nightStartHour = "nightStartHour"
    /// Night sessions started by `nightAuto` end at this hour.
    static let morningHour = 7

    static func register() {
        UserDefaults.standard.register(defaults: [
            sessionHours: 8.0,
            maxHours: 12.0,
            allowUnlimited: false,
            adaptive: true,
            idleMinutes: 10,
            powerMode: PowerMode.adaptive.rawValue,
            lidPolicy: LidPolicy.either.rawValue,
            batteryFloor: 15,
            softFloor: 40,
            engageAbove: 0,
            thermalGuard: true,
            keepDisplayAwake: false,
            displayOff: false,
            displayOffAfterAgents: 0,
            lidPack: false,
            packDim: true,
            packMute: true,
            packPauseChat: true,
            packLowPower: false,
            packLock: false,
            packPauseApps: false,
            preventLock: false,
            watchedApps: [String](),
            closedLidOnBattery: false,
            caffeinateAlways: false,
            playSounds: false,
            notifications: true,
            hotkey: true,
            nightAuto: true,
            nightStartHour: 22,
        ])
    }

    private static var store: UserDefaults { .standard }

    static func bool(_ key: String) -> Bool { store.bool(forKey: key) }
    static func int(_ key: String) -> Int { store.integer(forKey: key) }
    static func double(_ key: String) -> Double { store.double(forKey: key) }
    static func set(_ value: Any, _ key: String) { store.set(value, forKey: key) }

    static var powerModeValue: PowerMode { PowerMode(rawValue: store.string(forKey: powerMode) ?? "") ?? .adaptive }
    static var lidPolicyValue: LidPolicy { LidPolicy(rawValue: store.string(forKey: lidPolicy) ?? "") ?? .either }

    /// Bundle IDs that start a hold while they run.
    static var watchedAppIDs: [String] {
        get { store.stringArray(forKey: watchedApps) ?? [] }
        set { store.set(newValue, forKey: watchedApps) }
    }

    /// The session length a plain "Stay Awake" uses, never beyond the hard maximum.
    static var defaultSession: TimeInterval { min(double(sessionHours), double(maxHours)) * 3600 }
}
