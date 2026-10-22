import SwiftUI
import UIKit

/// The curves of the boards. Calm: no overshoot or bounce anywhere.
extension Animation {
    /// cubic-bezier(.22, 1, .36, 1): things settling into place.
    static func settle(_ seconds: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: seconds) }
    /// cubic-bezier(.65, 0, .35, 1): a box growing to the whole screen, a page shrinking home.
    static func inOut(_ seconds: Double) -> Animation { .timingCurve(0.65, 0, 0.35, 1, duration: seconds) }
    /// cubic-bezier(.4, 0, .2, 1): a page opening, slow at first so it is seen small.
    static func opening(_ seconds: Double) -> Animation { .timingCurve(0.4, 0, 0.2, 1, duration: seconds) }
    /// cubic-bezier(.4, 0, 1, 1): the keypad going down.
    static func sinking(_ seconds: Double) -> Animation { .timingCurve(0.4, 0, 1, 1, duration: seconds) }
}

enum Motion {
    /// The phone's Reduce Motion, read where the stores time their sequences.
    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }
}

/// Named timers on the main actor: a new one under a name cancels the one before it,
/// so a sequence restarted halfway never runs twice.
final class Schedule {
    private var tasks: [String: Task<Void, Never>] = [:]

    func after(_ key: String, _ milliseconds: Int, _ work: @escaping @MainActor () -> Void) {
        tasks[key]?.cancel()
        tasks[key] = Task { @MainActor in
            if milliseconds > 0 { try? await Task.sleep(for: .milliseconds(milliseconds)) }
            guard !Task.isCancelled else { return }
            work()
        }
    }

    func cancel(_ keys: String...) {
        for key in keys {
            tasks[key]?.cancel()
            tasks[key] = nil
        }
    }

    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }
}
