import SwiftUI
import Observation

/// The box that grows from the winner's score to the whole screen before the win screen.
enum GrowStage: Equatable {
    case off, box, full
}

/// A haptic the screen plays, when the home page allows it.
enum Feedback: Equatable {
    case none, record, win, refuse

    var sensory: SensoryFeedback? {
        switch self {
        case .none: return nil
        case .record: return .impact(weight: .light)
        case .win: return .success
        case .refuse: return .error
        }
    }
}

/// صكة: the hands, the totals and the whole sequence from «سجل النتيجة» to the win screen.
/// The rules are in `BalootRules`; this keeps the state and times the motion like the board.
@Observable
final class BalootStore {
    struct Ghost: Equatable {
        var us: String
        var them: String
    }

    // MARK: Saved
    private(set) var hands: [BalootHand] = []
    private(set) var said: Set<Team> = []
    @ObservationIgnored private var uid = 0

    // MARK: Typing and editing
    /// The fields hold what was typed; the screen cleans them right after each change (Western digits, three at most).
    var inUs = ""
    var inThem = ""
    var edUs = ""
    var edThem = ""
    private(set) var editId: Int?
    private(set) var confirmId: Int?
    private(set) var confirmNew = false

    // MARK: Banner
    private(set) var banner = ""
    private(set) var bannerOn = false

    // MARK: The end
    private(set) var reviewing = false
    private(set) var holdPoster = false
    private(set) var intro = false
    private(set) var fromExpand = false
    private(set) var lift = false
    private(set) var grow: GrowStage = .off
    private(set) var growTeam: Team = .us
    @ObservationIgnored private var pendingSpeech: String?

    // MARK: Motion
    private(set) var freshId: Int?
    private(set) var freshOn = false
    private(set) var ghost: Ghost?
    private(set) var ghostOn = false
    private(set) var pressing = false
    private(set) var pulse: Set<Team> = []
    /// The totals shown while they count up to the real ones.
    private(set) var display: Score?
    private(set) var countStart: Date?
    @ObservationIgnored private(set) var countDuration = 0.7

    // MARK: Haptics
    private(set) var feedback: Feedback = .none
    private(set) var feedbackTick = 0

    @ObservationIgnored private let schedule = Schedule()
    @ObservationIgnored private let speaker: Speaker
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let saveKey = "baloot.v1"

    init(speaker: Speaker, defaults: UserDefaults = .standard) {
        self.speaker = speaker
        self.defaults = defaults
        restore()
    }

    // MARK: Reading

    var totals: Score { BalootRules.totals(hands) }
    var outcome: BalootOutcome { BalootRules.outcome(totals) }
    var isWon: Bool { outcome.winner != nil }
    var posterVisible: Bool { isWon && !reviewing && !holdPoster }
    /// The fields show while a صكة runs and during the win sequence, not on the win screen nor in review.
    var showEntry: Bool { !isWon || holdPoster }
    /// From the winning hand on, the top bar keeps its space but hides; it comes back in review.
    var topVisible: Bool { !isWon || reviewing }
    var canRecord: Bool { !isWon && (Digits.value(inUs) > 0 || Digits.value(inThem) > 0) }
    var canSave: Bool { Digits.value(edUs) > 0 || Digits.value(edThem) > 0 }
    var tieAt: Int? {
        if case .tie(let at) = outcome { return at }
        return nil
    }
    var statusOpen: Bool { bannerOn || tieAt != nil }
    var counting: Bool { countStart != nil }

    /// The totals on screen at `date`: counting from the old totals to the new ones, cubic ease-out.
    func shown(at date: Date) -> Score {
        let t = totals
        guard let from = display else { return t }
        guard let start = countStart else { return from }
        let k = min(1, max(0, date.timeIntervalSince(start) / countDuration))
        let e = 1 - pow(1 - k, 3)
        func mix(_ a: Int, _ b: Int) -> Int { Int((Double(a) + Double(b - a) * e).rounded()) }
        return Score(us: mix(from.us, t.us), them: mix(from.them, t.them))
    }

    /// The colour of a total: gold above 100; the loser's is muted once the win screen has been shown.
    func tone(_ team: Team, value: Int) -> TotalTone {
        if let w = outcome.winner, !holdPoster, w != team { return .muted }
        return value > BalootRules.hundred ? .gold : .ink
    }

    enum TotalTone { case ink, gold, muted }

    /// The home card.
    var homeStatus: String { BalootRules.status(hands) }

    // MARK: Recording

    func record() {
        guard !isWon else { return }
        let us = Digits.value(inUs), them = Digits.value(inThem)
        guard us > 0 || them > 0 else { return }
        uid += 1
        let hand = BalootHand(id: uid, us: us, them: them)
        var gained: Set<Team> = []
        if us > 0 { gained.insert(.us) }
        if them > 0 { gained.insert(.them) }
        let rm = Motion.reduced
        // 0 ms: the button presses, the fields clear, and a copy of each number stays where it was typed.
        inUs = ""
        inThem = ""
        freshId = hand.id
        freshOn = false
        pressing = true
        ghost = Ghost(us: us > 0 ? "\(us)" : "", them: them > 0 ? "\(them)" : "")
        ghostOn = false
        poke(.record)
        commit(hands + [hand], gained: gained)
        schedule.after("press", 140) { [weak self] in self?.pressing = false }
        // 40 ms: the copy lifts out of the field while the same number rises into its box from the bottom edge.
        schedule.after("ghostOn", 40) { [weak self] in self?.ghostOn = true }
        schedule.after("ghostOff", 600) { [weak self] in
            self?.ghost = nil
            self?.ghostOn = false
        }
        schedule.after("fresh", rm ? 0 : 30) { [weak self] in self?.freshOn = true }
    }

    private func commit(_ next: [BalootHand], gained: Set<Team>?) {
        let rm = Motion.reduced
        let prevT = totals, nextT = BalootRules.totals(next)
        let event = BalootRules.event(from: prevT, to: nextT, said: said)
        let from = shown(at: Date())
        var won: Team? = nil
        if case .won(let team) = event { won = team }

        // A change during the win sequence stops what is left of it; a win that still stands plays again.
        schedule.cancel("countEnd", "growBox", "growFull", "poster", "growOff", "intro", "voice")
        pendingSpeech = nil
        holdPoster = false
        hands = next
        editId = nil
        confirmId = nil
        confirmNew = false
        reviewing = false
        intro = false
        fromExpand = false
        said = BalootRules.saidAfter(said, totals: nextT)
        display = from
        countStart = nil
        lift = false
        grow = .off

        if let event, case .hundred = event {
            speaker.say(event.speech)
            banner = event.banner
            bannerOn = true
            schedule.after("banner", 3200) { [weak self] in self?.bannerOn = false }
        }
        if let won {
            bannerOn = false
            holdPoster = true
            pendingSpeech = BalootEvent.won(won).speech
        }
        save()

        // The number rises into its box, and the total counts as it arrives.
        let lead = (gained != nil && !rm) ? 360 : 0
        if let gained, !rm {
            schedule.after("pulseOn", 380) { [weak self] in self?.pulse = gained }
            schedule.after("pulseOff", 640) { [weak self] in self?.pulse = [] }
        }
        schedule.after("count", lead) { [weak self] in
            self?.runCount(to: nextT, milliseconds: rm ? 0 : 700) { [weak self] in
                if let won { self?.finale(won) }
            }
        }
        if won == nil, BalootRules.outcome(nextT).winner != nil { playIntro(40) }
    }

    private func runCount(to target: Score, milliseconds: Int, done: @escaping @MainActor () -> Void) {
        let from = display ?? target
        if milliseconds == 0 || from == target || Motion.reduced {
            display = nil
            countStart = nil
            done()
            return
        }
        countDuration = Double(milliseconds) / 1000
        countStart = Date()
        schedule.after("countEnd", milliseconds) { [weak self] in
            self?.display = nil
            self?.countStart = nil
            done()
        }
    }

    /// After the count: the winner's box is outlined in ink, a copy of it grows to the whole screen,
    /// and the win screen is in place, solid, with its parts coming in one after another.
    private func finale(_ team: Team) {
        if Motion.reduced {
            holdPoster = false
            intro = false
            fromExpand = false
            poke(.win)
            playIntro(20)
            return
        }
        growTeam = team
        lift = true
        schedule.after("growBox", 180) { [weak self] in self?.grow = .box }
        schedule.after("growFull", 220) { [weak self] in
            withAnimation(.inOut(0.56)) { self?.grow = .full }
        }
        schedule.after("poster", 800) { [weak self] in
            guard let self else { return }
            self.holdPoster = false
            self.intro = false
            self.fromExpand = true
            self.poke(.win)
            self.playIntro(30)
        }
        schedule.after("growOff", 1000) { [weak self] in
            self?.grow = .off
            self?.lift = false
        }
    }

    private func playIntro(_ milliseconds: Int) {
        let rm = Motion.reduced
        schedule.after("intro", rm ? 10 : milliseconds) { [weak self] in
            guard let self else { return }
            self.intro = true
            if let text = self.pendingSpeech {
                self.pendingSpeech = nil
                self.schedule.after("voice", rm ? 60 : 480) { [weak self] in self?.speaker.say(text) }
            }
        }
    }

    // MARK: New game

    /// While a صكة runs the first tap asks «متأكد؟» for 3 s; with no hands, or after a win, one tap is enough.
    func newGame() {
        if !hands.isEmpty && !isWon && !confirmNew {
            confirmNew = true
            schedule.after("confirmNew", 3000) { [weak self] in self?.confirmNew = false }
            return
        }
        schedule.cancelAll()
        speaker.stop()
        pendingSpeech = nil
        hands = []
        said = []
        uid = 0
        inUs = ""
        inThem = ""
        edUs = ""
        edThem = ""
        editId = nil
        confirmId = nil
        confirmNew = false
        banner = ""
        bannerOn = false
        reviewing = false
        holdPoster = false
        intro = false
        fromExpand = false
        lift = false
        grow = .off
        freshId = nil
        freshOn = false
        ghost = nil
        ghostOn = false
        pressing = false
        pulse = []
        display = nil
        countStart = nil
        save()
    }

    // MARK: Editing and deleting

    /// Only the two newest hands can be edited or deleted, and none while the win sequence runs:
    /// from the winning hand to the win screen nothing on the board takes a tap, as in الهند.
    func canTouch(_ hand: BalootHand) -> Bool {
        !holdPoster && hands.suffix(2).contains { $0.id == hand.id }
    }

    func startEdit(_ hand: BalootHand) {
        schedule.cancel("confirmId")
        editId = hand.id
        edUs = "\(hand.us)"
        edThem = "\(hand.them)"
        confirmId = nil
    }

    /// «تعديل» on the win screen: back to the board with the last hand open.
    func reviewLast() {
        guard let last = hands.last else { return }
        schedule.cancel("confirmId", "intro", "voice")
        editId = last.id
        edUs = "\(last.us)"
        edThem = "\(last.them)"
        confirmId = nil
        reviewing = true
        intro = false
        fromExpand = false
    }

    func cancelEdit() {
        let won = isWon
        editId = nil
        reviewing = false
        intro = false
        fromExpand = false
        if won { playIntro(40) }
    }

    func saveEdit() {
        let us = Digits.value(edUs), them = Digits.value(edThem)
        guard us > 0 || them > 0, let id = editId else { return }
        let next = hands.map { $0.id == id ? BalootHand(id: id, us: us, them: them) : $0 }
        commit(next, gained: nil)
    }

    func askDelete(_ hand: BalootHand) {
        confirmId = hand.id
        editId = nil
        schedule.after("confirmId", 3000) { [weak self] in
            guard let self else { return }
            self.confirmId = nil
            // In review after a win, «احذف؟» left alone goes back to the win screen, as «إلغاء» does.
            if self.reviewing, self.editId == nil, self.isWon {
                self.reviewing = false
                self.playIntro(40)
            }
        }
    }

    func delete(_ hand: BalootHand) {
        schedule.cancel("confirmId")
        commit(hands.filter { $0.id != hand.id }, gained: nil)
    }

    /// Leaving for the home page: any open question goes away, and a win line not yet said stays unsaid;
    /// the صكة stays as it is.
    func leave() {
        confirmNew = false
        confirmId = nil
        pendingSpeech = nil
        schedule.cancel("voice")
    }

    // MARK: Haptics

    private func poke(_ f: Feedback) {
        feedback = f
        feedbackTick &+= 1
    }

    // MARK: Saving

    private func save() {
        let saved = BalootSave(hands: hands, said: Team.allCases.filter { said.contains($0) })
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.saveKey) }
    }

    /// A finished صكة reopens on its win screen. A damaged save is mended as it is read (`BalootSave`):
    /// a bad hand is dropped, not the صكة, and the save as it was is kept under its own key.
    private func restore() {
        guard let data = defaults.data(forKey: Self.saveKey) else { return }
        guard let saved = BalootSave.read(data) else {
            defaults.set(data, forKey: Self.saveKey + ".damaged")
            return
        }
        if saved.mended { defaults.set(data, forKey: Self.saveKey + ".damaged") }
        hands = saved.hands
        uid = saved.hands.map(\.id).max() ?? 0
        said = Set(saved.said)
        intro = BalootRules.outcome(totals).winner != nil
    }
}
