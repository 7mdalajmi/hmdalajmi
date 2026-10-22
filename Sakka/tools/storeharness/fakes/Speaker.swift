// Replaces Sakka/App/Speaker.swift for the Linux harness (the whole file; AVFoundation does not exist on Linux).
// Same API as the real Speaker: init(isOn:), prepare(), say(_:), stop(). Like the real one, `say` does nothing
// when `isOn()` is false (the home page's sound setting). Instead of speaking it records what it was asked to say,
// with the time on the virtual clock. (The real `static func bestArabicVoice()` returns an AVFoundation type and is
// not used by the stores, so it is left out.) Checked against build 4's Speaker.swift: the same API; the real one now
// speaks once the audio session is on and drops a line that a newer line or a stop overtakes, which the stores
// cannot see; what they asked for is what this records. Checked again against build 5's: only where the voice list
// is read changed (a GCD queue instead of a detached task), the same API.
import Foundation

final class Speaker: NSObject {
    enum Kind: Equatable { case said, muted, stopped }

    struct Line: Equatable, CustomStringConvertible {
        let time: Int
        let kind: Kind
        let text: String
        var description: String { "\(kind)@\(time) «\(text)»" }
    }

    private let isOn: @MainActor () -> Bool
    private var prepared = false
    /// Everything the stores asked of the voice, in order.
    private(set) var log: [Line] = []

    init(isOn: @escaping @MainActor () -> Bool) {
        self.isOn = isOn
        super.init()
    }

    func prepare() {
        prepared = true
    }

    func say(_ text: String) {
        guard isOn() else {
            log.append(Line(time: VirtualClock.now, kind: .muted, text: text))
            return
        }
        prepare()
        log.append(Line(time: VirtualClock.now, kind: .said, text: text))
    }

    func stop() {
        log.append(Line(time: VirtualClock.now, kind: .stopped, text: ""))
    }

    // MARK: For the scenarios

    /// The lines actually spoken (not the muted ones), from `index` on.
    func spoken(since index: Int = 0) -> [Line] {
        Array(log.dropFirst(index)).filter { $0.kind == .said }
    }

    var mark: Int { log.count }
}
