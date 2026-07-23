import Foundation
import UIKit

/// Battery monitoring via `UIDevice`.
final class BatteryMonitor: ObservableObject {
    @Published var level: Int = 100

    private var observer: NSObjectProtocol?

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    func refresh() {
        let raw = UIDevice.current.batteryLevel
        // -1.0 = unknown on simulator.
        level = raw >= 0 ? Int((raw * 100).rounded()) : 100
    }
}

/// Trigger a strong haptic buzz (used by the "Buzz" feature).
enum Buzz {
    static func trigger() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
        // A second pulse, slightly delayed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            generator.impactOccurred(intensity: 1.0)
        }
    }
}
