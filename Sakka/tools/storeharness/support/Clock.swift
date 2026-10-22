import Foundation

/// The harness's clock, in milliseconds. Nothing moves until a scenario advances it, so every timer of both
/// stores (through the fake `Schedule`) and every `Date()` the stores read (through `Date` below) is exact.
enum VirtualClock {
    struct Timer {
        let id: Int
        let due: Int
        let seq: Int
        let owner: String
        let key: String
        let work: () -> Void
    }

    /// A timer that ran: when, which store's schedule, and under which key.
    struct Fired: Equatable, CustomStringConvertible {
        let time: Int
        let owner: String
        let key: String
        var description: String { "\(owner).\(key)@\(time)" }
    }

    private(set) static var now = 0
    private static var pending: [Timer] = []
    private static var nextId = 0
    private(set) static var fired: [Fired] = []

    static func schedule(after milliseconds: Int, owner: String, key: String, _ work: @escaping () -> Void) -> Int {
        nextId += 1
        pending.append(Timer(id: nextId, due: now + max(0, milliseconds), seq: nextId, owner: owner, key: key, work: work))
        return nextId
    }

    static func cancel(_ id: Int) {
        pending.removeAll { $0.id == id }
    }

    /// Runs every timer due up to `now + milliseconds`, in time order (then in the order they were set),
    /// including timers that the ones running set for that span. A 0 ms advance is one turn of the run loop.
    static func advance(by milliseconds: Int) {
        let target = now + max(0, milliseconds)
        var budget = 10_000
        while let next = pending.filter({ $0.due <= target }).min(by: { ($0.due, $0.seq) < ($1.due, $1.seq) }) {
            budget -= 1
            if budget < 0 {
                // A timer that keeps setting itself again would hang the run: report it and drop what is left.
                Report.fail("timers keep firing", "more than 10000 timers in one advance; still pending: \(pendingKeys.prefix(5))")
                pending.removeAll()
                break
            }
            pending.removeAll { $0.id == next.id }
            now = max(now, next.due)
            fired.append(Fired(time: now, owner: next.owner, key: next.key))
            next.work()
        }
        now = target
    }

    static func advance(to time: Int) {
        advance(by: max(0, time - now))
    }

    /// Lets every pending timer run, however far away (up to a limit, so a timer loop cannot hang the run).
    static func runAll(limit: Int = 60_000) {
        advance(by: limit)
    }

    static var pendingKeys: [String] { pending.sorted { ($0.due, $0.seq) < ($1.due, $1.seq) }.map { "\($0.owner).\($0.key)@\($0.due)" } }

    static func pendingDue(owner: String, key: String) -> Int? {
        pending.first { $0.owner == owner && $0.key == key }?.due
    }

    /// A fresh clock for the next scenario. Timers still pending from the last one are dropped.
    static func reset() {
        now = 0
        pending = []
        fired = []
    }

    static func firedSince(_ start: Int, owner: String) -> [Fired] {
        fired.filter { $0.time >= start && $0.owner == owner }
    }
}

/// Shadows Foundation's `Date` inside this module, so `Date()` in the stores reads the virtual clock.
/// The stores only use `Date()`, `timeIntervalSince(_:)` and optional `Date?` storage.
struct Date: Equatable, Comparable, CustomStringConvertible {
    /// Milliseconds on the virtual clock.
    let ms: Double

    init() { ms = Double(VirtualClock.now) }
    init(ms: Double) { self.ms = ms }

    func timeIntervalSince(_ other: Date) -> TimeInterval { (ms - other.ms) / 1000 }
    func addingMilliseconds(_ d: Double) -> Date { Date(ms: ms + d) }

    static func < (a: Date, b: Date) -> Bool { a.ms < b.ms }
    var description: String { "t=\(Int(ms))ms" }
}
