import Foundation

/// How a player ended a round of الهند.
nonisolated enum HandKind: String, Codable, Sendable {
    /// خلّص ×1, هند ×2, جيكر ×4, جيكرين ×8: the finisher sets the round's multiplier.
    case out, hand, joker, joker2
    /// زات: the game ends there and this player wins it, whatever the totals.
    case zat
    /// ما نزل: never went down.
    case notDown = "nd"
    /// A number typed as it is, plus or minus: not multiplied (from build 6).
    case exact
    /// Before build 6: the cards left in hand, multiplied by the round. Old rounds still score this way.
    case cards = "num"
    /// Build 5's «حر»: a score as it is, never a نزول. Old rounds still score this way.
    case free

    /// The finishes with a multiplier, as the scoring table lists them.
    static let finishes: [HandKind] = [.out, .hand, .joker, .joker2]
    /// The keypad's top row: the finishes, then زات.
    static let ladder: [HandKind] = finishes + [.zat]

    /// The round's multiplier when this is the finisher, 0 for anyone else. زات is 1: its round multiplies nothing.
    var multiplier: Int {
        switch self {
        case .out, .zat: return 1
        case .hand: return 2
        case .joker: return 4
        case .joker2: return 8
        case .notDown, .exact, .cards, .free: return 0
        }
    }

    /// The finisher's kinds: خلّص, هند, جيكر, جيكرين and زات.
    var isFinish: Bool { multiplier > 0 }

    /// «خلّص» «هند» «جيكر» «جيكرين» «زات».
    var name: String {
        switch self {
        case .out: return "خلّص"
        case .hand: return "هند"
        case .joker: return "جيكر"
        case .joker2: return "جيكرين"
        case .zat: return "زات"
        case .notDown: return "ما نزل"
        case .exact, .cards: return ""
        case .free: return "حر"
        }
    }
}

nonisolated struct HandPlayer: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
}

/// A recorded cell: the kind, the cards when the kind is `.cards`, the number as typed when it is `.exact` or
/// `.free`, «من إيده» on top of a number or ما نزل, and «معلن» on top of ما نزل. Older saves read as they were.
nonisolated struct HandCell: Codable, Equatable, Sendable {
    var kind: HandKind
    var cards: Int = 0
    /// The number as typed, signed, for `.exact` and `.free` (saved under "free", the key «حر» had).
    var free: Int = 0
    /// «من إيده»: 25 × the round's multiplier on top of the player's score, in a round of هند, جيكر or جيكرين.
    var fromHand = false
    /// «معلن»: 1 for معلن جيكر (+100), 2 for معلن جيكرين (+200), on top of ما نزل; 0 for none.
    var declared = 0

    init(kind: HandKind, cards: Int = 0, free: Int = 0, fromHand: Bool = false, declared: Int = 0) {
        self.kind = kind
        self.cards = cards
        self.free = free
        self.fromHand = fromHand
        self.declared = declared
    }

    private enum CodingKeys: String, CodingKey {
        case kind, cards, free, fromHand, declared
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(HandKind.self, forKey: .kind)
        cards = try c.decodeIfPresent(Int.self, forKey: .cards) ?? 0
        free = try c.decodeIfPresent(Int.self, forKey: .free) ?? 0
        fromHand = try c.decodeIfPresent(Bool.self, forKey: .fromHand) ?? false
        declared = try c.decodeIfPresent(Int.self, forKey: .declared) ?? 0
    }

    /// Only the keys a cell has: a plain cell is saved as it was before any of them.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(cards, forKey: .cards)
        if kind == .free || kind == .exact { try c.encode(free, forKey: .free) }
        if fromHand { try c.encode(true, forKey: .fromHand) }
        if declared != 0 { try c.encode(declared, forKey: .declared) }
    }
}

nonisolated struct HandRound: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var cells: [String: HandCell]
}

/// A field being typed: no kind yet, a kind, or a number's digits and sign. «من إيده» is a mark on the field
/// that stays whatever its number becomes; «معلن» goes with ما نزل.
nonisolated struct EntryCell: Codable, Equatable, Sendable {
    var kind: HandKind?
    var digits: String = ""
    /// The number below zero (± before or after its digits).
    var negative = false
    /// «من إيده».
    var fromHand = false
    /// «معلن»: 1 جيكر, 2 جيكرين, on a field on ما نزل.
    var declared = 0

    init(kind: HandKind?, digits: String = "", negative: Bool = false, fromHand: Bool = false, declared: Int = 0) {
        self.kind = kind
        self.digits = digits
        self.negative = negative
        self.fromHand = fromHand
        self.declared = declared
    }

    static let empty = EntryCell(kind: nil)
    static let notDown = EntryCell(kind: .notDown)

    /// The cards of an old round's field, 0 when none.
    var cards: Int { kind == .cards ? (Int(digits) ?? 0) : 0 }

    /// The number of a typed field (or an old round's «حر»), signed; nil for any other field or no digits yet.
    var typedValue: Int? {
        guard kind == .exact || kind == .free, let n = Int(digits) else { return nil }
        return negative ? -n : n
    }

    private enum CodingKeys: String, CodingKey {
        case kind, digits, negative, fromHand, declared
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(HandKind.self, forKey: .kind)
        digits = try c.decodeIfPresent(String.self, forKey: .digits) ?? ""
        negative = try c.decodeIfPresent(Bool.self, forKey: .negative) ?? false
        fromHand = try c.decodeIfPresent(Bool.self, forKey: .fromHand) ?? false
        declared = try c.decodeIfPresent(Int.self, forKey: .declared) ?? 0
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encode(digits, forKey: .digits)
        if negative { try c.encode(true, forKey: .negative) }
        if fromHand { try c.encode(true, forKey: .fromHand) }
        if declared != 0 { try c.encode(declared, forKey: .declared) }
    }
}

nonisolated enum HandOutcome: Equatable, Sendable {
    case playing
    case won(String)
    /// Level on the lowest total after the last round: a جولة فاصلة follows.
    case tie([String], at: Int)

    var winner: String? {
        if case .won(let id) = self { return id }
        return nil
    }

    var isTie: Bool {
        if case .tie = self { return true }
        return false
    }
}

/// Where the round being typed stands.
nonisolated struct EntryStatus: Equatable, Sendable {
    /// The finisher, if one is chosen.
    var finisher: String?
    /// The multiplier of the round as typed (1 until a finisher is chosen).
    var multiplier: Int
    /// Players still without a number, a finish or ما نزل.
    var missing: [String]
    /// Players down in this round past what the game allows.
    var over: [String]
    /// How many downs the game allows once this round is in.
    var cap: Int

    var ready: Bool { finisher != nil && missing.isEmpty }
}

/// What a recorded or edited round announces (not the win, which has its own sequence).
nonisolated struct HandAnnouncement: Equatable, Sendable {
    var banner: String
    var speech: String
}

/// Kuwaiti Hand, as the board plays it.
/// The finisher sets the round's multiplier (خلّص ×1, هند ×2, جيكر ×4, جيكرين ×8): the finisher scores −30 × it, and
/// whoever never went down 100 × it. Anything else is the number typed, as it is, plus or minus (from build 6;
/// before it the cards typed were multiplied, and old rounds still score that way).
/// A number from 1 up to below what ما نزل scores is a نزول. A player may go down once in the game, or twice once it
/// has a جيكر or جيكرين; past that the round is refused.
/// «من إيده» adds 25 × the multiplier on top of a player's score (50 with هند, 100 with جيكر, 200 with جيكرين); a round
/// finished with خلّص has none, and one player has it in a round. It goes with a نزول or ما نزل: ما نزل in a هند is
/// 200 + 50 = 250.
/// «معلن» is a player who declared a جيكر, or جيكرين, and did not finish: a جيكر in hand means he never went down,
/// so he is on ما نزل, and 100 (جيكر) or 200 (جيكرين) go on top: 200 + 100 = 300 in a هند. Any number of players.
/// «زات» ends the game: whoever gets it wins, whatever the totals, and nothing in its round counts. While it is typed
/// the other fields stay as they are, faded, and take nothing more; a finish chosen instead brings them back. They go
/// in empty.
/// 7 rounds, 9 once a جيكر or جيكرين is in; the lowest total wins, and a tie on it plays a جولة فاصلة.
/// In آخر جولة, and the جولة فاصلة after it, every player's distance from the first is counted: 0 for the first
/// himself and what each of the others has over him, written on a line of its own under the round (build 7).
nonisolated enum HandRules {
    static let minPlayers = 2
    static let maxPlayers = 6
    static let nameLimit = 14
    /// «من إيده» is this × the round's multiplier.
    static let fromHandBase = 25
    /// A typed number takes up to this many digits.
    static let maxDigits = 4

    // MARK: Scoring

    static func multiplier(_ round: HandRound) -> Int {
        round.cells.values.reduce(1) { max($0, $1.kind.multiplier) }
    }

    /// The finisher, in seat order.
    static func finisher(_ round: HandRound, players: [HandPlayer]) -> String? {
        players.first { round.cells[$0.id]?.kind.isFinish == true }?.id
    }

    static func hasZat(_ round: HandRound) -> Bool {
        round.cells.values.contains { $0.kind == .zat }
    }

    static func hasZat(_ entry: [String: EntryCell]) -> Bool {
        entry.values.contains { $0.kind == .zat }
    }

    /// A round of زات being typed, and `focus` is another field: it counts nothing and takes nothing (no digit, ±,
    /// ⌫, ما نزل, «معلن» or «من إيده»); only a finish key, which moves the finish there.
    static func zatElsewhere(_ entry: [String: EntryCell], focus: String) -> Bool {
        hasZat(entry) && entry[focus]?.kind != .zat
    }

    static func points(_ cell: HandCell, multiplier m: Int) -> Int {
        if cell.kind == .zat { return 0 }
        if cell.kind.isFinish { return -30 * m }
        var p: Int
        switch cell.kind {
        case .notDown: p = 100 * m + declaredPoints(cell.declared)
        case .exact, .free: p = cell.free
        default: p = cell.cards * m
        }
        // Build 5's «حر» was the score as it is, so «من إيده» never goes on top of it.
        if cell.fromHand, cell.kind != .free, let extra = fromHandPoints(multiplier: m) { p += extra }
        return p
    }

    /// What «من إيده» adds in a round with this multiplier: nothing in a round finished with خلّص.
    static func fromHandPoints(multiplier m: Int) -> Int? {
        m >= 2 ? fromHandBase * m : nil
    }

    /// What «معلن» adds on top of ما نزل: 100 for معلن جيكر, 200 for معلن جيكرين, whatever the finish.
    static func declaredPoints(_ declared: Int) -> Int {
        switch declared {
        case 1: return 100
        case 2: return 200
        default: return 0
        }
    }

    /// «معلن جيكر», «معلن جيكرين».
    static func declaredName(_ declared: Int) -> String {
        declared == 2 ? "معلن جيكرين" : "معلن جيكر"
    }

    /// The score a field would give as typed, for its caption; nil for a finisher or a field still empty.
    static func points(_ x: EntryCell, multiplier m: Int) -> Int? {
        guard let kind = x.kind, !kind.isFinish, !isEmpty(x) else { return nil }
        let cell = HandCell(kind: kind, cards: x.cards, free: x.typedValue ?? 0, fromHand: x.fromHand, declared: x.declared)
        return points(cell, multiplier: m)
    }

    /// The multiplier of a round being typed: its finisher's, 1 until one is chosen.
    static func multiplier(_ entry: [String: EntryCell]) -> Int {
        entry.values.reduce(1) { max($0, $1.kind?.multiplier ?? 0) }
    }

    /// Each player's points in a round. A round of زات counts nothing, whatever a damaged save may hold in it.
    static func points(_ round: HandRound) -> [String: Int] {
        if hasZat(round) { return round.cells.mapValues { _ in 0 } }
        let m = multiplier(round)
        return round.cells.mapValues { points($0, multiplier: m) }
    }

    /// A نزول in a round with this multiplier: a typed number from 1 up to below what ما نزل scores (100 × it),
    /// or, in an old round, cards from 1 to 99.
    static func isDown(_ cell: HandCell?, multiplier m: Int) -> Bool {
        guard let cell else { return false }
        switch cell.kind {
        case .exact: return cell.free > 0 && cell.free < 100 * m
        case .cards: return cell.cards > 0 && cell.cards < 100
        default: return false
        }
    }

    /// A نزول in this round; a round of زات has none.
    static func isDown(_ cell: HandCell?, in round: HandRound) -> Bool {
        !hasZat(round) && isDown(cell, multiplier: multiplier(round))
    }

    /// A نزول in the round being typed, as it stands.
    static func isDown(_ x: EntryCell?, in entry: [String: EntryCell]) -> Bool {
        guard let x, !hasZat(entry) else { return false }
        let m = multiplier(entry)
        switch x.kind {
        case .exact?:
            guard let v = x.typedValue else { return false }
            return v > 0 && v < 100 * m
        case .cards?: return x.cards > 0 && x.cards < 100
        default: return false
        }
    }

    static func downs(players: [HandPlayer], rounds: [HandRound]) -> [String: Int] {
        var d: [String: Int] = [:]
        for p in players { d[p.id] = 0 }
        for r in rounds {
            for p in players where isDown(r.cells[p.id], in: r) { d[p.id, default: 0] += 1 }
        }
        return d
    }

    /// 7 rounds; 9 once any round has a جيكر or جيكرين.
    static func target(_ rounds: [HandRound]) -> Int {
        rounds.contains { multiplier($0) >= 4 } ? 9 : 7
    }

    static func allowedDowns(_ rounds: [HandRound]) -> Int {
        target(rounds) == 9 ? 2 : 1
    }

    /// Players down in `round` who would pass what the game allows, counting every round in `next`.
    static func overDowns(players: [HandPlayer], next: [HandRound], round: HandRound) -> [String] {
        let d = downs(players: players, rounds: next), cap = allowedDowns(next)
        return players.filter { isDown(round.cells[$0.id], in: round) && (d[$0.id] ?? 0) > cap }.map(\.id)
    }

    static func totals(players: [HandPlayer], rounds: [HandRound]) -> [String: Int] {
        var t: [String: Int] = [:]
        for p in players { t[p.id] = 0 }
        for r in rounds {
            for (id, v) in points(r) where t[id] != nil { t[id, default: 0] += v }
        }
        return t
    }

    /// How far each player is above the first: 0 for whoever leads (the lowest total wins الهند), and what every
    /// other player has over him — what he still has to make up. `totals` is the totals as they stand, so the
    /// numbers follow the count on screen.
    static func gaps(players: [HandPlayer], totals: [String: Int]) -> [String: Int] {
        guard let low = players.map({ totals[$0.id] ?? 0 }).min() else { return [:] }
        var g: [String: Int] = [:]
        for p in players { g[p.id] = (totals[p.id] ?? 0) - low }
        return g
    }

    /// Whoever got زات, in the first round that has one: the game ended there.
    static func zatWinner(players: [HandPlayer], rounds: [HandRound]) -> String? {
        for r in rounds {
            if let p = players.first(where: { r.cells[$0.id]?.kind == .zat }) { return p.id }
        }
        return nil
    }

    static func outcome(players: [HandPlayer], rounds: [HandRound]) -> HandOutcome {
        guard !players.isEmpty else { return .playing }
        if let z = zatWinner(players: players, rounds: rounds) { return .won(z) }
        guard rounds.count >= target(rounds) else { return .playing }
        let t = totals(players: players, rounds: rounds)
        let low = players.map { t[$0.id] ?? 0 }.min() ?? 0
        let lead = players.filter { (t[$0.id] ?? 0) == low }.map(\.id)
        if lead.count == 1 { return .won(lead[0]) }
        return .tie(lead, at: low)
    }

    /// Long totals step down so they stay inside their box.
    static func fitScale(_ text: String) -> Double {
        switch text.count {
        case ...3: return 1
        case 4: return 0.82
        case 5: return 0.68
        default: return 0.58
        }
    }

    // MARK: Words

    static func name(of id: String, in players: [HandPlayer]) -> String {
        guard let i = players.firstIndex(where: { $0.id == id }) else { return "" }
        let n = players[i].name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "لاعب \(i + 1)" : n
    }

    /// «الفوز لحمد», «الفوز للشيخ», «الفوز لـ Sam».
    static func winLine(_ name: String) -> String {
        if name.hasPrefix("ال") { return "الفوز لل" + String(name.dropFirst(2)) }
        if let first = name.unicodeScalars.first, (0x0600...0x06FF).contains(first.value) { return "الفوز ل" + name }
        return "الفوز لـ " + name
    }

    /// What is said on the win screen: «الفوز لحمد», or «حمد جاب زات، والفوز لحمد».
    static func winSpeech(players: [HandPlayer], rounds: [HandRound], winner: String) -> String {
        let n = name(of: winner, in: players)
        if zatWinner(players: players, rounds: rounds) == winner { return n + " جاب زات، و" + winLine(n) }
        return winLine(n)
    }

    /// «حمد»، «حمد وفهد»، «حمد، أنور وفهد».
    static func joinNames(_ names: [String]) -> String {
        guard names.count > 1 else { return names.joined() }
        return names.dropLast().joined(separator: "، ") + " و" + names[names.count - 1]
    }

    /// What a number of the الفرق line says: «حمد الأول», «أنور فوق الأول بـ 501».
    static func gapSpeech(name: String, gap: Int) -> String {
        gap == 0 ? name + " الأول" : name + " فوق الأول بـ \(gap)"
    }

    /// «أنور عنده نزولين», «أنور وفهد عندهم نزول».
    static func overLine(names: [String], cap: Int) -> String {
        joinNames(names) + (names.count > 1 ? " عندهم " : " عنده ") + (cap > 1 ? "نزولين" : "نزول")
    }

    /// The status line: the round and nothing else. Empty once the game is won.
    static func roundLine(rounds: [HandRound], outcome: HandOutcome) -> String {
        if outcome.winner != nil { return "" }
        let tgt = target(rounds), k = rounds.count + 1
        if k > tgt { return "جولة فاصلة" }
        if k == tgt { return "آخر جولة" }
        return "الجولة \(k) من \(tgt)"
    }

    /// The round the game ends with: «آخر جولة», or the «جولة فاصلة» a tie plays after it. The الفرق line,
    /// how far each player is from the first, shows under the round line there.
    static func isLastRound(rounds: [HandRound], outcome: HandOutcome) -> Bool {
        outcome.winner == nil && rounds.count + 1 >= target(rounds)
    }

    /// The home card's line.
    static func homeLine(players: [HandPlayer], rounds: [HandRound]) -> String {
        let k = rounds.count, tgt = target(rounds)
        if k == 0 { return "لعبة جديدة" }
        switch outcome(players: players, rounds: rounds) {
        case .won(let id): return winLine(name(of: id, in: players))
        case .tie: return "تعادل، وجولة فاصلة"
        case .playing:
            if k + 1 > tgt { return "جولة فاصلة" }
            if k + 1 == tgt { return "آخر جولة" }
            return "الجولة \(k + 1) من \(tgt)"
        }
    }

    /// The banner and voice after a round goes in, is edited or deleted (the win is announced apart).
    /// `gained` is the new round when one was recorded.
    static func announcement(players: [HandPlayer], before: [HandRound], after next: [HandRound], gained: HandRound?) -> HandAnnouncement? {
        let prevTarget = target(before), nextTarget = target(next)
        let po = outcome(players: players, rounds: before), no = outcome(players: players, rounds: next)
        if let w = no.winner, po.winner != w { return nil }
        // As in صكة: an edit after the win that keeps the same winner says nothing.
        if let w = po.winner, no.winner == w { return nil }
        let grew = nextTarget > prevTarget, shrank = nextTarget < prevTarget
        let tie = gained != nil && no.isTie && !po.isTie
        let last = gained != nil && no == .playing && next.count == nextTarget - 1
        if let gained, multiplier(gained) > 1, let fid = finisher(gained, players: players), let kind = gained.cells[fid]?.kind {
            let who = name(of: fid, in: players)
            var line = who + " نزل " + kind.name
            var speech = line
            if grew {
                line += " · صارت 9 جولات ونزولين"
                if line.utf16.count > 36 { line = who + " نزل " + kind.name + " · 9 جولات ونزولين" }
                if line.utf16.count > 36 { line = kind.name + " · صارت 9 جولات ونزولين" }
                speech += "، وصارت تسع جولات ونزولين"
            } else if tie || last {
                // The هند or جيكر comes first, and the tie or the last round is said with it, not lost.
                let tail = tie ? "تعادل، وجولة فاصلة" : "آخر جولة"
                line += " · " + tail
                if line.utf16.count > 36 { line = kind.name + " · " + tail }
                speech += "، و" + tail
            }
            return HandAnnouncement(banner: line, speech: speech)
        }
        if grew { return HandAnnouncement(banner: "صارت 9 جولات ونزولين", speech: "صارت تسع جولات ونزولين") }
        if shrank { return HandAnnouncement(banner: "رجعت 7 جولات ونزول واحد", speech: "رجعت سبع جولات ونزول واحد") }
        if tie { return HandAnnouncement(banner: "تعادل، وجولة فاصلة", speech: "تعادل، وجولة فاصلة") }
        if last { return HandAnnouncement(banner: "آخر جولة", speech: "آخر جولة") }
        return nil
    }

    // MARK: Typing a round

    static func isEmpty(_ cell: EntryCell?) -> Bool {
        guard let cell, let kind = cell.kind else { return true }
        if kind == .exact || kind == .free { return cell.typedValue == nil }
        return kind == .cards && cell.cards <= 0
    }

    /// The marks only where they can be. «من إيده»: never on the finisher or an old «حر», and it goes once the
    /// round is finished with خلّص; a moment with no finisher (⌫ on him on the way from هند to جيكر) leaves it, and so
    /// does زات, whose round counts nothing and may give way again to the finish it replaced.
    /// «معلن»: only on ما نزل.
    static func settled(_ entry: [String: EntryCell]) -> [String: EntryCell] {
        let m = multiplier(entry)
        let finished = entry.values.contains { $0.kind?.isFinish == true && $0.kind != .zat }
        var e = entry
        for (id, x) in entry {
            if x.fromHand && ((finished && m < 2) || x.kind?.isFinish == true || x.kind == .free) {
                e[id]?.fromHand = false
            }
            if x.declared != 0 && x.kind != .notDown { e[id]?.declared = 0 }
        }
        return e
    }

    static func emptyEntry(_ players: [HandPlayer]) -> [String: EntryCell] {
        // Never traps, even if a damaged save ever brought two players with one id.
        Dictionary(players.map { ($0.id, EntryCell.empty) }, uniquingKeysWith: { first, _ in first })
    }

    static func firstEmpty(players: [HandPlayer], entry: [String: EntryCell]) -> String? {
        players.first { isEmpty(entry[$0.id]) }?.id
    }

    /// The next field after `from` still to fill: an empty one first, then one on ما نزل,
    /// since that is where the number of whoever went down gets typed.
    static func nextOpen(players: [HandPlayer], from: String, entry: [String: EntryCell]) -> String {
        guard let i0 = players.firstIndex(where: { $0.id == from }) else { return from }
        let n = players.count
        for j in 1..<max(n, 1) {
            let p = players[(i0 + j) % n]
            if isEmpty(entry[p.id]) { return p.id }
        }
        for j in 1..<max(n, 1) {
            let p = players[(i0 + j) % n]
            if entry[p.id]?.kind == .notDown { return p.id }
        }
        return from
    }

    static func round(from entry: [String: EntryCell], players: [HandPlayer], id: Int) -> HandRound {
        var cells: [String: HandCell] = [:]
        let zat = hasZat(entry)
        for p in players {
            let x = entry[p.id] ?? .empty
            // In a round of زات only the زات goes in: the other fields, faded while it was typed, go in empty.
            if zat && x.kind != .zat {
                cells[p.id] = HandCell(kind: .cards, cards: 0)
                continue
            }
            switch x.kind {
            case .cards?: cells[p.id] = HandCell(kind: .cards, cards: x.cards, fromHand: x.fromHand)
            case .free?: cells[p.id] = HandCell(kind: .free, free: x.typedValue ?? 0)
            case .exact?:
                if let v = x.typedValue {
                    cells[p.id] = HandCell(kind: .exact, free: v, fromHand: x.fromHand)
                } else {
                    cells[p.id] = HandCell(kind: .cards, cards: 0, fromHand: x.fromHand)
                }
            case .notDown?: cells[p.id] = HandCell(kind: .notDown, fromHand: x.fromHand, declared: x.declared)
            case let kind?: cells[p.id] = HandCell(kind: kind)
            // Nothing typed: no points.
            case nil: cells[p.id] = HandCell(kind: .cards, cards: 0, fromHand: x.fromHand)
            }
        }
        return HandRound(id: id, cells: cells)
    }

    /// A recorded round back in the fields, for «تعديل». An old round's cards come back as the number they came to,
    /// × the round, since from build 6 a number is typed as it is; nothing typed comes back empty.
    static func entry(from round: HandRound, players: [HandPlayer]) -> [String: EntryCell] {
        let m = multiplier(round)
        var en: [String: EntryCell] = [:]
        for p in players {
            guard let c = round.cells[p.id] else { en[p.id] = .empty; continue }
            switch c.kind {
            case .cards: en[p.id] = typedCards(c.cards, multiplier: m, fromHand: c.fromHand)
            case .free: en[p.id] = EntryCell(kind: .free, digits: "\(abs(c.free))", negative: c.free < 0)
            case .exact: en[p.id] = EntryCell(kind: .exact, digits: "\(abs(c.free))", negative: c.free < 0, fromHand: c.fromHand)
            case .notDown: en[p.id] = EntryCell(kind: .notDown, fromHand: c.fromHand, declared: c.declared)
            default: en[p.id] = EntryCell(kind: c.kind)
            }
        }
        return en
    }

    /// Cards as the number they come to, × the round, in a field: build 6 has no cards to type.
    static func typedCards(_ cards: Int, multiplier m: Int, fromHand: Bool) -> EntryCell {
        let v = cards * m
        return v > 0 ? EntryCell(kind: .exact, digits: "\(v)", fromHand: fromHand) : EntryCell(kind: nil, fromHand: fromHand)
    }

    /// A round being typed when the app updated to build 6 may hold cards: they come back as the number they come
    /// to, × its finisher (1 before one is chosen), so every key treats them as any number typed.
    static func typedCards(_ entry: [String: EntryCell]) -> [String: EntryCell] {
        let m = multiplier(entry)
        return entry.mapValues { $0.kind == .cards ? typedCards($0.cards, multiplier: m, fromHand: $0.fromHand) : $0 }
    }

    /// The round as typed, held against what the game allows. `editing` is the round being edited, if any.
    /// With زات the others need nothing: the game ends with the round.
    static func status(players: [HandPlayer], rounds: [HandRound], entry: [String: EntryCell], editing: Int?) -> EntryStatus {
        var fin: String? = nil, mult = 1
        var missing: [String] = []
        for p in players {
            let x = entry[p.id]
            if let k = x?.kind, k.isFinish {
                fin = p.id
                mult = max(mult, k.multiplier)
            } else if x?.kind != .notDown && isEmpty(x) {
                missing.append(p.id)
            }
        }
        if hasZat(entry) { missing = [] }
        let r = round(from: entry, players: players, id: editing ?? 0)
        let next: [HandRound]
        if let editing { next = rounds.map { $0.id == editing ? r : $0 } } else { next = rounds + [r] }
        var over = overDowns(players: players, next: next, round: r)
        // An edit that leaves the cap as it is refuses only a نزول it adds: one the round already had stays allowed,
        // as it stays after a delete takes the جيكر away, so that round can still be corrected. An edit that takes
        // the جيكر away itself is held to the lower cap, as on the board.
        if let editing, let old = rounds.first(where: { $0.id == editing }), allowedDowns(next) >= allowedDowns(rounds) {
            over.removeAll { isDown(old.cells[$0], in: old) }
        }
        return EntryStatus(finisher: fin, multiplier: mult, missing: missing, over: over, cap: allowedDowns(next))
    }

    /// زات can go in a new round, or in the newest round being edited: an older round can't end the game, with
    /// rounds after it.
    static func zatOpen(rounds: [HandRound], editing: Int?) -> Bool {
        editing == nil || editing == rounds.last?.id
    }

    /// A digit typed into the focused field: the number as it is, up to four digits, and the focus stays (the next
    /// field is a tap away). A lone 0 is a number of its own, and a digit after it takes its place.
    /// A field on ما نزل, a finish or an old round's cards starts a new number. «من إيده» stays; «معلن» goes, as a
    /// number means the player went down or has his score typed. Nil when the digit is not taken (as on the others
    /// in a round of زات).
    static func typing(_ digit: Character, entry: [String: EntryCell], focus: String) -> [String: EntryCell]? {
        guard digit.isASCII, digit.isNumber, !zatElsewhere(entry, focus: focus) else { return nil }
        let x = entry[focus] ?? .empty
        var e = entry
        if x.kind == .exact || x.kind == .free {
            if x.digits == "0" {
                if digit == "0" { return nil }
                e[focus]?.digits = String(digit)
            } else {
                if x.digits.count >= maxDigits { return nil }
                e[focus]?.digits = x.digits + String(digit)
            }
        } else {
            e[focus] = EntryCell(kind: .exact, digits: String(digit), fromHand: x.fromHand)
        }
        return settled(e)
    }

    /// ± on the focused field: its number turns sign; a field with no number yet takes the sign and waits for the
    /// digits, and ± again takes the sign back: the field is as before it, on ما نزل once a finisher is chosen, else
    /// empty. Nil on the finisher, and on the others in a round of زات.
    static func signing(entry: [String: EntryCell], focus: String) -> [String: EntryCell]? {
        let x = entry[focus] ?? .empty
        if x.kind?.isFinish == true || zatElsewhere(entry, focus: focus) { return nil }
        var e = entry
        let typed = x.kind == .exact || x.kind == .free
        if typed && x.digits.isEmpty && x.negative {
            let finished = entry.values.contains { $0.kind?.isFinish == true }
            e[focus] = EntryCell(kind: finished ? .notDown : nil, fromHand: x.fromHand)
        } else if typed {
            e[focus]?.negative.toggle()
        } else {
            e[focus] = EntryCell(kind: .exact, negative: true, fromHand: x.fromHand)
        }
        return settled(e)
    }

    /// A finish or ما نزل chosen for the focused field. Choosing a finisher puts everyone not typed yet
    /// (and a finisher chosen before) on ما نزل: حمد هند gives the rest 200 by itself. A field with a number, or
    /// a minus waiting for one, keeps it. زات leaves the other fields as they are, faded, since nothing else counts
    /// in its round, and a finish chosen after it brings them back; a finisher chosen before it goes on ما نزل.
    /// «من إيده» and «معلن» stay on a field put on ما نزل, and go from the finisher. ما نزل does nothing on the
    /// others in a round of زات.
    static func choosing(_ kind: HandKind, entry: [String: EntryCell], focus: String, players: [HandPlayer]) -> (entry: [String: EntryCell], focus: String) {
        var e = entry
        let old = entry[focus]
        if kind == .zat {
            for p in players where p.id != focus && e[p.id]?.kind?.isFinish == true { e[p.id] = EntryCell(kind: .notDown) }
            e[focus] = EntryCell(kind: .zat)
            return (settled(e), focus)
        }
        if !kind.isFinish && zatElsewhere(entry, focus: focus) { return (entry, focus) }
        if kind.isFinish {
            for p in players where p.id != focus {
                let x = e[p.id]
                let typed = (x?.kind == .exact || x?.kind == .free) && (x?.digits.isEmpty == false || x?.negative == true)
                if x?.kind?.isFinish == true || (isEmpty(x) && !typed) {
                    e[p.id] = EntryCell(kind: .notDown, fromHand: x?.fromHand ?? false)
                }
            }
            e[focus] = EntryCell(kind: kind)
        } else {
            e[focus] = EntryCell(kind: kind, fromHand: old?.fromHand ?? false,
                                 declared: old?.kind == .notDown ? (old?.declared ?? 0) : 0)
        }
        e = settled(e)
        return (e, nextOpen(players: players, from: focus, entry: e))
    }

    /// «من إيده» on the focused field, on or off. One player has it in a round, so it leaves anyone else.
    /// It goes on once the finisher is هند, جيكر or جيكرين, never on the finisher himself or an old «حر» field,
    /// and a mark the field has can always come off. Nothing while the round has زات: a faded field keeps its mark
    /// for the finish that may come back.
    static func togglingFromHand(entry: [String: EntryCell], focus: String) -> [String: EntryCell]? {
        let x = entry[focus] ?? .empty
        guard x.kind?.isFinish != true, x.kind != .free, !hasZat(entry), x.fromHand || multiplier(entry) >= 2 else { return nil }
        var e = entry
        let on = !x.fromHand
        for id in Array(e.keys) { e[id]?.fromHand = false }
        if e[focus] == nil { e[focus] = .empty }
        e[focus]?.fromHand = on
        return e
    }

    /// «معلن» on the focused field: معلن جيكر (+100), then معلن جيكرين (+200), then off. A جيكر in hand means the
    /// player never went down, so the field goes to ما نزل; «من إيده» stays. Never on the finisher, nor on the others
    /// in a round of زات.
    static func declaring(entry: [String: EntryCell], focus: String) -> [String: EntryCell]? {
        let x = entry[focus] ?? .empty
        if x.kind?.isFinish == true || zatElsewhere(entry, focus: focus) { return nil }
        var e = entry
        let next = (x.kind == .notDown ? x.declared : 0) + 1
        e[focus] = EntryCell(kind: .notDown, fromHand: x.fromHand, declared: next > 2 ? 0 : next)
        return settled(e)
    }

    /// The erase key: one digit off; the last digit goes back to ما نزل once a finisher is chosen, else the field
    /// empties. «من إيده» stays on the field, «معلن» goes. Nothing on the others in a round of زات; on the زات itself
    /// the field empties and the others count again.
    static func erasing(entry: [String: EntryCell], focus: String, players: [HandPlayer], rounds: [HandRound], editing: Int?) -> [String: EntryCell] {
        if zatElsewhere(entry, focus: focus) { return entry }
        var e = entry
        let x = entry[focus] ?? .empty
        let typed = x.kind == .cards || x.kind == .free || x.kind == .exact
        if typed && x.digits.count > 1 {
            e[focus]?.digits = String(x.digits.dropLast())
        } else if typed && !hasZat(entry) && status(players: players, rounds: rounds, entry: entry, editing: editing).finisher != nil {
            e[focus] = EntryCell(kind: .notDown, fromHand: x.fromHand)
        } else {
            e[focus] = EntryCell(kind: nil, fromHand: x.fromHand && x.kind?.isFinish != true)
        }
        return settled(e)
    }
}
