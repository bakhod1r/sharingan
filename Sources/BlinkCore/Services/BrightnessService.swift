import Foundation
import AppKit

/// BrightnessService — break vaqtida ekran'ni gamma ramp orqali dim qiladi
/// (private DisplayServices API'siz, public CGSetDisplayTransferByFormula).
///
/// Dim qilish uchun gamma'ni ko'paytirishning o'rniga, chiqish qiymatlarini
/// minValues bilan kamaytiramiz. Asl system gamma'ni restore'ga saqlaymiz
/// (1.0 olduğu'da hech narsa o'zgarmaydi).
@MainActor
public final class BrightnessService: ObservableObject {
    public static let shared = BrightnessService()

    @Published public private(set) var isDimming: Bool = false
    @Published public var enabled: Bool = false
    @Published public var levelPercent: Float = 35  // 5..100, break'da dim level
    @Published public var smooth: Bool = true

    private var dimTask: Task<Void, Never>?
    private var currentFactor: Double = 1.0

    public init() {
        // Gamma is process-global system state: if the app quits while dimmed,
        // the display stays dark. Restore the system color settings on terminate
        // as a fail-safe so a break can never leave the screen darkened.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { _ in
            CGDisplayRestoreColorSyncSettings()
        }
    }

    // MARK: - Dim / Restore

    public func dimToBreak() {
        guard enabled else { return }
        guard !isDimming else { return }
        isDimming = true
        let target = max(0.05, min(1.0, Double(levelPercent) / 100.0))
        if smooth { animate(to: target) } else { applyFactor(target) }
    }

    public func restore() {
        guard isDimming else { return }
        isDimming = false
        if smooth { animate(to: 1.0) } else { applyFactor(1.0) }
    }

    public func cancel() {
        dimTask?.cancel()
        dimTask = nil
        applyFactor(1.0)
        isDimming = false
    }

    // MARK: - Gamma apply

    private func applyFactor(_ factor: Double) {
        let gamma: CGGammaValue = CGGammaValue(max(0.1, 1.0 / max(0.05, factor)))
        let mainID = CGMainDisplayID()
        let zero: CGGammaValue = 0.0
        let one: CGGammaValue = 1.0
        CGSetDisplayTransferByFormula(mainID,
                                       zero, one, gamma,
                                       zero, one, gamma,
                                       zero, one, gamma)
        currentFactor = factor
    }

    private func animate(to target: Double) {
        dimTask?.cancel()
        let start = currentFactor
        let dur: Double = 1.2
        let steps = 40
        dimTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for i in 0...steps {
                if Task.isCancelled { return }
                let t = Double(i) / Double(steps)
                let eased = start + (target - start) * (1 - pow(1 - t, 3))
                self.applyFactor(eased)
                try? await Task.sleep(for: .milliseconds(Int(dur * 1000) / steps))
            }
        }
    }
}