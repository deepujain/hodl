import Foundation

/// Keeps agent desktop apps out of App Nap, so a backgrounded Cursor or Codex window isn’t throttled overnight.
/// This is the documented `NSAppSleepDisabled` preference; it applies the next time each app launches.
enum AppNap {
    static var bundleIDs: [String] { Harness.all.flatMap(\.bundleIDs) }

    static var isDisabledForAgents: Bool {
        bundleIDs.contains { CFPreferencesCopyAppValue("NSAppSleepDisabled" as CFString, $0 as CFString) as? Bool == true }
    }

    static func setDisabledForAgents(_ disabled: Bool) {
        for id in bundleIDs {
            CFPreferencesSetAppValue("NSAppSleepDisabled" as CFString, disabled ? kCFBooleanTrue : nil, id as CFString)
            CFPreferencesAppSynchronize(id as CFString)
        }
    }
}
