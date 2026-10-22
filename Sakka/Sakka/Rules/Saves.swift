import Foundation

/// One element of a saved list, read on its own: a damaged element is dropped, not the whole list.
nonisolated struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// Reads the lists of a save leniently and remembers whether anything had to be dropped or filled in.
nonisolated private struct LenientReader<Key: CodingKey> {
    let container: KeyedDecodingContainer<Key>
    var mended = false

    mutating func list<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        guard let items = try? container.decodeIfPresent([Lossy<T>].self, forKey: key) else {
            mended = true
            return []
        }
        let kept = items.compactMap(\.value)
        if kept.count != items.count { mended = true }
        return kept
    }

    mutating func table<T: Decodable>(_ type: T.Type, _ key: Key) -> [String: T] {
        guard let items = try? container.decodeIfPresent([String: Lossy<T>].self, forKey: key) else {
            mended = true
            return [:]
        }
        let kept = items.compactMapValues(\.value)
        if kept.count != items.count { mended = true }
        return kept
    }

    mutating func value<T: Decodable>(_ type: T.Type, _ key: Key, default fallback: T) -> T {
        guard let v = try? container.decodeIfPresent(T.self, forKey: key) else {
            mended = true
            return fallback
        }
        return v
    }
}

/// A saved game of الهند. Reading it never loses the whole game to one bad part: a damaged round or field
/// is dropped, a missing value takes its default, and the rest is mended as in `repaired()`.
nonisolated struct HandSave: Codable, Equatable, Sendable {
    var players: [HandPlayer]
    var rounds: [HandRound]
    var entry: [String: EntryCell]
    var uid: Int
    var started: Bool
    /// Not saved: true when reading had to drop, fill in or change anything.
    var mended = false

    private enum CodingKeys: String, CodingKey {
        case players, rounds, entry, uid, started
    }

    init(players: [HandPlayer], rounds: [HandRound], entry: [String: EntryCell], uid: Int, started: Bool) {
        self.players = players
        self.rounds = rounds
        self.entry = entry
        self.uid = uid
        self.started = started
    }

    init(from decoder: any Decoder) throws {
        var r = LenientReader(container: try decoder.container(keyedBy: CodingKeys.self))
        players = r.list(HandPlayer.self, .players)
        rounds = r.list(HandRound.self, .rounds)
        entry = r.table(EntryCell.self, .entry)
        uid = r.value(Int.self, .uid, default: 100)
        started = r.value(Bool.self, .started, default: true)
        mended = r.mended
    }

    /// The saved game as it can be played, or nil when it can't be (no JSON, or not 2 to 6 players).
    static func read(_ data: Data) -> HandSave? {
        (try? JSONDecoder().decode(HandSave.self, from: data))?.repaired()
    }

    /// Players: unique, non-empty ids, names within the limit, 2 to 6 of them. Rounds: unique positive ids,
    /// a cell for every player with cards in 0…999 and a typed number within four digits; one «من إيده» only where
    /// it can be, and «معلن» (1 or 2) only on ما نزل. The round being typed: only well-formed cells, one finisher
    /// (زات included) and one «من إيده». The id counter: past every id in use, so a new player or round never takes
    /// an old id.
    func repaired() -> HandSave? {
        var out = self
        var ids = Set<String>()
        out.players = players.compactMap { p in
            guard !p.id.isEmpty, ids.insert(p.id).inserted else { return nil }
            return HandPlayer(id: p.id, name: String(p.name.prefix(HandRules.nameLimit)))
        }
        guard (HandRules.minPlayers...HandRules.maxPlayers).contains(out.players.count) else { return nil }
        var roundIds = Set<Int>()
        let freeRange = -9999...9999
        out.rounds = rounds.filter { r in
            r.id > 0 && out.players.allSatisfy { p in
                guard let c = r.cells[p.id] else { return false }
                return (0...999).contains(c.cards) && freeRange.contains(c.free)
            } && roundIds.insert(r.id).inserted
        }.map { r in
            // One «من إيده» in a round, the first in seat order where it can be: not with خلّص, not on the
            // finisher, not on «حر».
            var r = r
            let m = HandRules.multiplier(r)
            let keep = out.players.first { p in
                guard let c = r.cells[p.id] else { return false }
                return c.fromHand && m >= 2 && !c.kind.isFinish && c.kind != .free
            }?.id
            for (id, c) in r.cells where c.fromHand && id != keep { r.cells[id]?.fromHand = false }
            // «معلن» is 1 or 2, on ما نزل only.
            for (id, c) in r.cells where c.declared != 0 && (c.kind != .notDown || !(1...2).contains(c.declared)) {
                r.cells[id]?.declared = 0
            }
            return r
        }
        var e = HandRules.emptyEntry(out.players)
        for p in out.players {
            guard let x = entry[p.id] else { continue }
            let numeric = x.digits.allSatisfy { $0.isASCII && $0.isNumber }
            switch x.kind {
            case .cards?:
                let ok = (1...3).contains(x.digits.count) && numeric && !x.digits.hasPrefix("0")
                if ok { e[p.id] = EntryCell(kind: .cards, digits: x.digits, fromHand: x.fromHand) }
            case .free?, .exact?:
                // A number within four digits, a lone 0, or no digits yet (a sign waiting for them).
                let ok = x.digits.count <= HandRules.maxDigits && numeric && (x.digits == "0" || !x.digits.hasPrefix("0"))
                if ok { e[p.id] = EntryCell(kind: x.kind, digits: x.digits, negative: x.negative, fromHand: x.fromHand) }
            case .notDown?:
                e[p.id] = EntryCell(kind: .notDown, fromHand: x.fromHand, declared: (1...2).contains(x.declared) ? x.declared : 0)
            default:
                e[p.id] = EntryCell(kind: x.kind, fromHand: x.fromHand)
            }
        }
        // One finisher and one «من إيده» in the round being typed: the first in seat order keeps it.
        var finisher = false
        for p in out.players where e[p.id]?.kind?.isFinish == true {
            if finisher { e[p.id] = .empty } else { finisher = true }
        }
        e = HandRules.settled(e)
        var marked = false
        for p in out.players where e[p.id]?.fromHand == true {
            if marked { e[p.id]?.fromHand = false } else { marked = true }
        }
        out.entry = e
        let playerNumbers = out.players.compactMap { Int($0.id.dropFirst()) }
        out.uid = max(uid, out.rounds.map(\.id).max() ?? 0, playerNumbers.max() ?? 0, 100)
        out.mended = mended || out.players != players || out.rounds != rounds || out.entry != entry || out.uid != uid
        return out
    }
}

/// A saved صكة, read and mended the same way: points out of 0…999 or empty hands are dropped, ids made unique,
/// and «فوق المية» kept for every team that is above 100.
nonisolated struct BalootSave: Codable, Equatable, Sendable {
    var hands: [BalootHand]
    var said: [Team]
    /// Not saved: true when reading had to drop, fill in or change anything.
    var mended = false

    private enum CodingKeys: String, CodingKey {
        case hands, said
    }

    init(hands: [BalootHand], said: [Team]) {
        self.hands = hands
        self.said = said
    }

    init(from decoder: any Decoder) throws {
        var r = LenientReader(container: try decoder.container(keyedBy: CodingKeys.self))
        hands = r.list(BalootHand.self, .hands)
        said = r.list(Team.self, .said)
        mended = r.mended
    }

    static func read(_ data: Data) -> BalootSave? {
        (try? JSONDecoder().decode(BalootSave.self, from: data))?.repaired()
    }

    func repaired() -> BalootSave {
        var out = self
        var seen = Set<Int>()
        out.hands = []
        for h in hands where (0...999).contains(h.us) && (0...999).contains(h.them) && (h.us > 0 || h.them > 0) {
            var hand = h
            if seen.contains(hand.id) || hand.id <= 0 { hand.id = (seen.max() ?? 0) + 1 }
            seen.insert(hand.id)
            out.hands.append(hand)
        }
        let kept = BalootRules.saidAfter(Set(said), totals: BalootRules.totals(out.hands))
        out.said = Team.allCases.filter { kept.contains($0) }
        out.mended = mended || out.hands != hands || Set(out.said) != Set(said)
        return out
    }
}
