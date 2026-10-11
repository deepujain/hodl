import Foundation
import IOKit
import IOKit.ps
import Observation

/// Battery, power source, Low Power Mode, thermal state, and the lid.
@MainActor @Observable
final class PowerMonitor {
    static let shared = PowerMonitor()

    private(set) var percent: Int?
    private(set) var onAC = true
    private(set) var hasBattery = false
    private(set) var charging = false
    private(set) var lowPowerMode = false
    private(set) var thermal: ProcessInfo.ThermalState = .nominal
    private(set) var lidClosed = false
    private(set) var lidKnown = false

    /// Called when the power source, thermal state, or lid changes.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var lidTimer: Timer?
    @ObservationIgnored private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        refresh()
        refreshLid()
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            MainActor.assumeIsolated { PowerMonitor.shared.sourceChanged() }
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        let center = NotificationCenter.default
        center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PowerMonitor.shared.sourceChanged() }
        }
        center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PowerMonitor.shared.sourceChanged() }
        }
        // Reading the clamshell flag is a single registry lookup, so poll it often to react to the lid quickly.
        lidTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { PowerMonitor.shared.refreshLid() }
        }
    }

    private func sourceChanged() {
        refresh()
        onChange?()
    }

    func refresh() {
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermal = ProcessInfo.processInfo.thermalState

        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            percent = nil
            return
        }
        let providing = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        onAC = providing != kIOPMBatteryPowerKey
        hasBattery = false
        var reading: Int?
        let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            hasBattery = true
            if let current = info[kIOPSCurrentCapacityKey] as? Int, let max = info[kIOPSMaxCapacityKey] as? Int, max > 0 {
                reading = Int((Double(current) / Double(max) * 100).rounded())
            }
            charging = info[kIOPSIsChargingKey] as? Bool ?? false
        }
        percent = reading
    }

    func refreshLid() {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return lidKnown = false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
        lidKnown = value != nil
        let closed = value ?? false
        if closed != lidClosed {
            lidClosed = closed
            onChange?()
        }
    }

    var batteryLabel: String {
        guard hasBattery else { return "AC" }
        guard let percent else { return "—%" }
        return "\(percent)%"
    }

    var thermalTitle: String {
        switch thermal {
        case .nominal: "Cool"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}
