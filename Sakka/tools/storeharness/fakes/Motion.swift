// Replaces Sakka/Design/Motion.swift for the Linux harness (the whole file, same API).
// The real file mixes three things: the board's animation curves (kept here, the same four lines),
// `Motion.reduced` (UIKit's UIAccessibility, which Linux lacks; here a switch the scenarios flip), and
// `Schedule` (keyed timers on real Task.sleep; here the same keyed timers on the virtual clock, so the
// order and the delay of every step can be checked exactly).
import SwiftUI

/// The curves of the boards, copied from the real Motion.swift.
extension Animation {
    static func settle(_ seconds: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: seconds) }
    static func inOut(_ seconds: Double) -> Animation { .timingCurve(0.65, 0, 0.35, 1, duration: seconds) }
    static func opening(_ seconds: Double) -> Animation { .timingCurve(0.4, 0, 0.2, 1, duration: seconds) }
    static func sinking(_ seconds: Double) -> Animation { .timingCurve(0.4, 0, 1, 1, duration: seconds) }
}

enum Motion {
    /// The phone's Reduce Motion. The scenarios set it through `Motion.reduceMotionSwitch`.
    static var reduced: Bool { reduceMotionSwitch }
    static var reduceMotionSwitch = false
}

/// Named timers: a new one under a name cancels the one before it, as in the real `Schedule`.
/// A 0 ms timer runs on the next turn (the next `VirtualClock.advance`), never inside `after` itself,
/// as the real one runs its Task on a later turn of the main actor.
final class Schedule {
    /// The label of the next schedule made, so the timeline says which store a timer belongs to.
    static var nextOwner = "store"

    private let owner: String
    private var tasks: [String: Int] = [:]

    init() {
        owner = Schedule.nextOwner
    }

    func after(_ key: String, _ milliseconds: Int, _ work: @escaping @MainActor () -> Void) {
        if let old = tasks[key] { VirtualClock.cancel(old) }
        tasks[key] = VirtualClock.schedule(after: milliseconds, owner: owner, key: key) { work() }
    }

    func cancel(_ keys: String...) {
        for key in keys {
            if let id = tasks[key] { VirtualClock.cancel(id) }
            tasks[key] = nil
        }
    }

    func cancelAll() {
        for id in tasks.values { VirtualClock.cancel(id) }
        tasks.removeAll()
    }
}
