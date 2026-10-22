import SwiftUI
import Observation

/// A key of the Hand keypad.
enum PadKey: Hashable {
    case digit(Character)
    /// خلّص, هند, جيكر, جيكرين or زات for the focused field.
    case finish(HandKind)
    case notDown
    /// «من إيده» on the focused field, on or off.
    case fromHand
    /// «معلن» on the focused field: جيكر, جيكرين, off.
    case declared
    /// ± on the focused field's number.
    case sign
    case erase
    case record
}

/// The names typed on «مين يلعب؟» before «ابدأ».
struct SetupDraft: Equatable {
    var players: [HandPlayer]
}

/// الهند: players, rounds, the round being typed, and the sequence from «سجّل» to the win screen.
/// The rules are in `HandRules`; this keeps the state and times the motion like the board.
@Observable
final class HandStore {
    // MARK: Saved
    private(set) var players: [HandPlayer]
    private(set) var rounds: [HandRound] = []
    private(set) var entry: [String: EntryCell]
    /// False until a game has been set up on «مين يلعب؟»: the first visit opens it.
    private(set) var started = false
    @ObservationIgnored private var uid = 100

    // MARK: Typing
    private(set) var focus: String
    private(set) var padOn = false
    private(set) var editId: Int?
    @ObservationIgnored private var stash: [String: EntryCell]?
    private(set) var selected: Int?
    private(set) var confirmId: Int?
    private(set) var pressKey: PadKey?

    // MARK: Banner and refusal
    private(set) var banner = ""
    private(set) var bannerOn = false
    private(set) var bannerDanger = false
    private(set) var shakeIds: [String] = []
    private(set) var shakeTick = 0

    // MARK: The end
    private(set) var reviewing = false
    private(set) var holdPoster = false
    private(set) var intro = false
    private(set) var fromExpand = false
    private(set) var lift = false
    private(set) var grow: GrowStage = .off
    private(set) var growPlayer: String?
    @ObservationIgnored private var pendingSpeech: String?

    // MARK: Motion
    private(set) var freshId: Int?
    private(set) var freshOn = false
    /// The points of the round just recorded, shown lifting out of the fields and rising into the boxes.
    private(set) var ghost: [String: String]?
    private(set) var ghostOn = false
    private(set) var pulse: Set<String> = []
    private(set) var display: [String: Int]?
    private(set) var countStart: Date?
    @ObservationIgnored private(set) var countDuration = 0.7
    /// Rounds added to the progress line by a جيكر fade in.
    private(set) var segFrom: Int?
    private(set) var segOn = true
    /// New نزول circles come in once the numbers have risen into the boxes.
    private(set) var pipPrev: [String: Int]?
    private(set) var pipOn = true

    // MARK: Setup
    private(set) var setupOpen = false
    private(set) var setup = SetupDraft(players: [])

    // MARK: Haptics
    private(set) var feedback: Feedback = .none
    private(set) var feedbackTick = 0

    @ObservationIgnored private let schedule = Schedule()
    @ObservationIgnored private let speaker: Speaker
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let saveKey = "hand.v1"

    init(speaker: Speaker, defaults: UserDefaults = .standard) {
        self.speaker = speaker
        self.defaults = defaults
        let fresh = (1...4).map { HandPlayer(id: "p\($0)", name: "") }
        players = fresh
        entry = HandRules.emptyEntry(fresh)
        focus = fresh[0].id
        restore()
    }

    // MARK: Reading

    var totals: [String: Int] { HandRules.totals(players: players, rounds: rounds) }
    var outcome: HandOutcome { HandRules.outcome(players: players, rounds: rounds) }
    var target: Int { HandRules.target(rounds) }
    var downs: [String: Int] { HandRules.downs(players: players, rounds: rounds) }
    var status: EntryStatus { HandRules.status(players: players, rounds: rounds, entry: entry, editing: editId) }
    var isWon: Bool { outcome.winner != nil }
    /// Nothing can be typed on the win screen, during the win sequence, or while «مين يلعب؟» is open.
    var locked: Bool { setupOpen || (isWon && editId == nil) || holdPoster }
    var padUp: Bool { padOn && !locked }
    var posterVisible: Bool { isWon && !reviewing && !holdPoster && editId == nil }
    var topVisible: Bool { !isWon || reviewing || editId != nil }
    var counting: Bool { countStart != nil }
    /// زات goes in a new round or the newest one being edited.
    var zatOpen: Bool { HandRules.zatOpen(rounds: rounds, editing: editId) }
    /// The game ended with زات.
    var wonByZat: Bool { HandRules.zatWinner(players: players, rounds: rounds) != nil }

    func name(_ id: String) -> String { HandRules.name(of: id, in: players) }

    /// The totals on screen at `date`: counting from the old totals to the new ones, cubic ease-out.
    func shown(at date: Date) -> [String: Int] {
        let t = totals
        guard let from = display else { return t }
        guard let start = countStart else { return from }
        let k = min(1, max(0, date.timeIntervalSince(start) / countDuration))
        let e = 1 - pow(1 - k, 3)
        var out: [String: Int] = [:]
        for (id, to) in t {
            let a = from[id] ?? 0
            out[id] = Int((Double(a) + Double(to - a) * e).rounded())
        }
        return out
    }

    /// The status line: the round, «تعديل الجولة N» while editing, or the banner on top of it.
    var roundLine: String { HandRules.roundLine(rounds: rounds, outcome: outcome) }

    /// آخر جولة, or the جولة فاصلة after a tie: the الفرق line sits under the round line there.
    var showsGap: Bool { HandRules.isLastRound(rounds: rounds, outcome: outcome) }

    /// How far each player is above the first, from the totals given — `shown(at:)` while they count, so the
    /// الفرق line settles with the boxes.
    func gaps(_ totals: [String: Int]) -> [String: Int] { HandRules.gaps(players: players, totals: totals) }

    var editLine: String {
        guard let id = editId, let i = rounds.firstIndex(where: { $0.id == id }) else { return "" }
        return "تعديل الجولة \(i + 1)"
    }

    /// The home card.
    var homeStatus: String { HandRules.homeLine(players: players, rounds: rounds) }

    // MARK: Keypad

    func press(_ key: PadKey) {
        guard !locked else { return }
        pressKey = key
        schedule.after("pressKey", 140) { [weak self] in self?.pressKey = nil }
        switch key {
        case .digit(let d):
            // The digits stay in the field: the next one is a tap away.
            guard let e = HandRules.typing(d, entry: entry, focus: focus) else { return }
            entry = e
            selected = nil
            confirmId = nil
        case .finish(let kind):
            if kind == .zat && !zatOpen { return }
            choose(kind)
        case .notDown:
            choose(.notDown)
        case .fromHand:
            guard let e = HandRules.togglingFromHand(entry: entry, focus: focus) else { return }
            entry = e
            selected = nil
            confirmId = nil
        case .declared:
            guard let e = HandRules.declaring(entry: entry, focus: focus) else { return }
            entry = e
            selected = nil
            confirmId = nil
        case .sign:
            guard let e = HandRules.signing(entry: entry, focus: focus) else { return }
            entry = e
            selected = nil
            confirmId = nil
        case .erase:
            entry = HandRules.erasing(entry: entry, focus: focus, players: players, rounds: rounds, editing: editId)
        case .record:
            record()
            return
        }
        // The round being typed is kept as it changes, so a phone that closes the app mid-round loses nothing.
        save()
    }

    private func choose(_ kind: HandKind) {
        let r = HandRules.choosing(kind, entry: entry, focus: focus, players: players)
        entry = r.entry
        focus = r.focus
        selected = nil
        confirmId = nil
    }

    /// A tap on a player's field brings the keypad up for that field.
    func focusField(_ id: String) {
        guard !locked else { return }
        focus = id
        padOn = true
        selected = nil
        confirmId = nil
    }

    /// A tap anywhere but the fields and the keypad puts the keypad away.
    func hidePad() {
        if padOn { padOn = false }
    }

    // MARK: Recording

    func record() {
        let st = status
        guard st.ready else { return }
        // Past the نزول the game allows: nothing goes in, and the alert says who.
        if !st.over.isEmpty {
            refuse(st)
            return
        }
        if editId != nil {
            saveEdit()
            return
        }
        guard !isWon else { return }
        uid += 1
        let round = HandRules.round(from: entry, players: players, id: uid)
        let points = HandRules.points(round)
        let rm = Motion.reduced
        // A round of زات adds nothing to anyone: no number lifts out of the fields, and the win sequence follows.
        ghost = HandRules.hasZat(round) ? nil : points.mapValues { Digits.signed($0) }
        ghostOn = false
        entry = HandRules.emptyEntry(players)
        focus = players[0].id
        padOn = false
        selected = nil
        confirmId = nil
        freshId = round.id
        freshOn = false
        poke(.record)
        commit(rounds + [round], gained: round)
        schedule.after("ghostOn", 40) { [weak self] in self?.ghostOn = true }
        schedule.after("ghostOff", 600) { [weak self] in
            self?.ghost = nil
            self?.ghostOn = false
        }
        schedule.after("fresh", rm ? 0 : 30) { [weak self] in self?.freshOn = true }
    }

    private func refuse(_ st: EntryStatus) {
        let line = HandRules.overLine(names: st.over.map { name($0) }, cap: st.cap)
        speaker.say(line)
        banner = line
        bannerOn = true
        bannerDanger = true
        shakeIds = st.over
        shakeTick &+= 1
        focus = st.over[0]
        padOn = true
        selected = nil
        confirmId = nil
        poke(.refuse)
        schedule.after("banner", 3200) { [weak self] in self?.bannerOn = false }
    }

    private func commit(_ next: [HandRound], gained: HandRound?, apply: (() -> Void)? = nil) {
        let rm = Motion.reduced
        let before = rounds
        let prevTarget = HandRules.target(before), nextTarget = HandRules.target(next)
        let po = outcome, no = HandRules.outcome(players: players, rounds: next)
        let nextT = HandRules.totals(players: players, rounds: next)
        var winner: String? = nil
        if let w = no.winner, po.winner != w { winner = w }
        let from = shown(at: Date())
        let prevD = downs, nextD = HandRules.downs(players: players, rounds: next)
        let more = nextD.contains { $0.value > (prevD[$0.key] ?? 0) }
        let pipAnim = gained != nil && more && !rm

        // A refusal's alert has done its job once a round goes in.
        if bannerDanger {
            bannerOn = false
            bannerDanger = false
            schedule.cancel("banner")
        }
        // A change during the win sequence stops what is left of it; a win that still stands plays again.
        schedule.cancel("countEnd", "growBox", "growFull", "poster", "growOff", "intro", "voice")
        pendingSpeech = nil
        rounds = next
        editId = nil
        stash = nil
        reviewing = false
        intro = false
        fromExpand = false
        display = from
        countStart = nil
        lift = false
        grow = .off
        holdPoster = false
        apply?()
        shakeIds = []
        pipPrev = pipAnim ? prevD : nil
        pipOn = !pipAnim
        if pipAnim { schedule.after("pipOn", 560) { [weak self] in self?.pipOn = true } }

        if let winner {
            bannerOn = false
            holdPoster = true
            pendingSpeech = HandRules.winSpeech(players: players, rounds: next, winner: winner)
        } else {
            if nextTarget > prevTarget {
                // The two new rounds fade into the progress line.
                segFrom = prevTarget
                segOn = false
                schedule.after("segOn", 40) { [weak self] in self?.segOn = true }
            }
            if let a = HandRules.announcement(players: players, before: before, after: next, gained: gained) {
                speaker.say(a.speech)
                banner = a.banner
                bannerOn = true
                bannerDanger = false
                schedule.after("banner", 3200) { [weak self] in self?.bannerOn = false }
            }
        }
        save()

        let lead = (gained != nil && !rm) ? 360 : 0
        // The boxes take the round's numbers with a small pulse; a round of زات brings none.
        if let gained, !rm, !HandRules.hasZat(gained) {
            let everyone = Set(players.map(\.id))
            schedule.after("pulseOn", 380) { [weak self] in self?.pulse = everyone }
            schedule.after("pulseOff", 640) { [weak self] in self?.pulse = [] }
        }
        schedule.after("count", lead) { [weak self] in
            self?.runCount(to: nextT, milliseconds: rm ? 0 : 700) { [weak self] in
                if let winner { self?.finale(winner) }
            }
        }
        if winner == nil, no.winner != nil { playIntro(40) }
    }

    private func runCount(to target: [String: Int], milliseconds: Int, done: @escaping @MainActor () -> Void) {
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

    private func finale(_ id: String) {
        if Motion.reduced {
            holdPoster = false
            intro = false
            fromExpand = false
            poke(.win)
            playIntro(20)
            return
        }
        growPlayer = id
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

    // MARK: The log

    /// Only the two newest rounds open for edit or delete, and not on the win screen.
    func canTouch(_ round: HandRound) -> Bool {
        guard !(isWon && editId == nil) else { return false }
        return rounds.suffix(2).contains { $0.id == round.id }
    }

    func tapRow(_ round: HandRound) {
        padOn = false
        guard editId == nil, !locked else { return }
        schedule.cancel("confirmId")
        selected = selected == round.id ? nil : round.id
        confirmId = nil
    }

    func startEdit(_ round: HandRound) {
        schedule.cancel("confirmId")
        stash = entry
        editId = round.id
        entry = HandRules.entry(from: round, players: players)
        focus = players[0].id
        padOn = true
        selected = nil
        confirmId = nil
    }

    private func saveEdit() {
        guard status.ready, let id = editId else { return }
        let round = HandRules.round(from: entry, players: players, id: id)
        let next = rounds.map { $0.id == id ? round : $0 }
        let keep = stash ?? HandRules.emptyEntry(players)
        commit(next, gained: nil) { [self] in
            entry = keep
            focus = HandRules.firstEmpty(players: players, entry: keep) ?? players[0].id
            padOn = false
        }
    }

    func cancelEdit() {
        let won = isWon
        let keep = stash ?? HandRules.emptyEntry(players)
        editId = nil
        stash = nil
        entry = keep
        focus = HandRules.firstEmpty(players: players, entry: keep) ?? players[0].id
        padOn = false
        reviewing = false
        intro = false
        fromExpand = false
        if won { playIntro(40) }
    }

    /// «تعديل» on the win screen: back to the board with the last round in the fields.
    func reviewLast() {
        guard let last = rounds.last else { return }
        schedule.cancel("intro", "voice")
        editId = last.id
        stash = HandRules.emptyEntry(players)
        entry = HandRules.entry(from: last, players: players)
        focus = players[0].id
        padOn = true
        reviewing = true
        intro = false
        fromExpand = false
        selected = nil
        confirmId = nil
    }

    func askDelete(_ round: HandRound) {
        padOn = false
        confirmId = round.id
        schedule.after("confirmId", 3000) { [weak self] in self?.confirmId = nil }
    }

    func delete(_ round: HandRound) {
        schedule.cancel("confirmId")
        commit(rounds.filter { $0.id != round.id }, gained: nil) { [self] in
            confirmId = nil
            selected = nil
        }
    }

    // MARK: «مين يلعب؟»

    func openSetup() {
        setup = SetupDraft(players: players)
        setupOpen = true
        selected = nil
        confirmId = nil
        padOn = false
    }

    func closeSetup() {
        setupOpen = false
        // «إلغاء» on the first visit keeps the players as they are, and «مين يلعب؟» stops opening by itself.
        if !started {
            started = true
            save()
        }
    }

    func setName(at index: Int, _ text: String) {
        guard setup.players.indices.contains(index) else { return }
        setup.players[index].name = String(text.prefix(HandRules.nameLimit))
    }

    func addPlayer() {
        guard setup.players.count < HandRules.maxPlayers else { return }
        let taken = Set(setup.players.map(\.id) + players.map(\.id))
        repeat { uid += 1 } while taken.contains("p\(uid)")
        setup.players.append(HandPlayer(id: "p\(uid)", name: ""))
    }

    func removePlayer(at index: Int) {
        guard setup.players.count > HandRules.minPlayers, setup.players.indices.contains(index) else { return }
        setup.players.remove(at: index)
    }

    /// «ابدأ»: a new game with these players; an empty name becomes «لاعب N».
    func startGame() {
        let next = setup.players.enumerated().map { i, p in
            let n = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return HandPlayer(id: p.id, name: n.isEmpty ? "لاعب \(i + 1)" : n)
        }
        guard next.count >= HandRules.minPlayers else { return }
        schedule.cancelAll()
        speaker.stop()
        pendingSpeech = nil
        players = next
        rounds = []
        entry = HandRules.emptyEntry(next)
        focus = next[0].id
        started = true
        padOn = false
        editId = nil
        stash = nil
        selected = nil
        confirmId = nil
        pressKey = nil
        banner = ""
        bannerOn = false
        bannerDanger = false
        shakeIds = []
        reviewing = false
        holdPoster = false
        intro = false
        fromExpand = false
        lift = false
        grow = .off
        growPlayer = nil
        freshId = nil
        freshOn = false
        ghost = nil
        ghostOn = false
        pulse = []
        display = nil
        countStart = nil
        segFrom = nil
        segOn = true
        pipPrev = nil
        pipOn = true
        setupOpen = false
        save()
    }

    /// Leaving for the home page: the keypad and any open question go away, and a win line not yet said stays
    /// unsaid; the game stays as it is.
    func leave() {
        padOn = false
        selected = nil
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

    /// The game, and the round being typed. While a round is open for «تعديل» the fields hold that round,
    /// so what is kept is the round that was being typed before it.
    private func save() {
        let typing = editId != nil ? (stash ?? HandRules.emptyEntry(players)) : entry
        let saved = HandSave(players: players, rounds: rounds, entry: typing, uid: uid, started: started)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.saveKey) }
    }

    /// A damaged save is mended as it is read (`HandSave`): a bad round or field is dropped, not the game.
    /// The save as it was is kept under its own key before the mended one replaces it.
    private func restore() {
        guard let data = defaults.data(forKey: Self.saveKey) else { return }
        guard let saved = HandSave.read(data) else {
            defaults.set(data, forKey: Self.saveKey + ".damaged")
            return
        }
        if saved.mended { defaults.set(data, forKey: Self.saveKey + ".damaged") }
        players = saved.players
        rounds = saved.rounds
        // Cards typed before the update come back as the number they come to.
        entry = HandRules.typedCards(saved.entry)
        focus = HandRules.firstEmpty(players: saved.players, entry: entry) ?? saved.players[0].id
        uid = saved.uid
        started = saved.started
        intro = HandRules.outcome(players: saved.players, rounds: saved.rounds).winner != nil
    }
}
