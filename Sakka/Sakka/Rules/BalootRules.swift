import Foundation

/// The two Baloot teams. «لنا» sits on the right, «لهم» on the left.
nonisolated enum Team: String, Codable, CaseIterable, Sendable {
    case us, them

    var name: String { self == .us ? "لنا" : "لهم" }
    var other: Team { self == .us ? .them : .us }
}

/// One recorded hand of صكة.
nonisolated struct BalootHand: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var us: Int
    var them: Int

    func points(_ team: Team) -> Int { team == .us ? us : them }
}

/// A pair of totals.
nonisolated struct Score: Codable, Equatable, Sendable {
    var us: Int
    var them: Int

    static let zero = Score(us: 0, them: 0)

    subscript(team: Team) -> Int {
        get { team == .us ? us : them }
        set { if team == .us { us = newValue } else { them = newValue } }
    }
}

nonisolated enum BalootOutcome: Equatable, Sendable {
    case playing
    /// Level at or above 152: the next hand decides.
    case tie(Int)
    case won(Team)

    var winner: Team? {
        if case .won(let team) = self { return team }
        return nil
    }
}

/// What a change to the hands has to announce.
nonisolated enum BalootEvent: Equatable, Sendable {
    case won(Team)
    /// The teams that went above 100 for the first time in this صكة.
    case hundred([Team])

    /// The banner («لنا فوق المية»), or the win line.
    var banner: String {
        switch self {
        case .won(let team): return "الصكة " + team.name
        case .hundred(let teams): return BalootRules.who(teams) + " فوق المية"
        }
    }

    /// What the voice says («لنا فوق المئة», «الصكة لنا»).
    var speech: String {
        switch self {
        case .won(let team): return "الصكة " + team.name
        case .hundred(let teams): return BalootRules.who(teams) + " فوق المئة"
        }
    }
}

/// صكة's rules: the game ends at 152, the higher total wins, a tie at or above 152 goes on,
/// and passing 100 is announced once per team.
nonisolated enum BalootRules {
    static let target = 152
    static let hundred = 100

    static func totals(_ hands: [BalootHand]) -> Score {
        hands.reduce(into: Score.zero) { t, h in
            t.us += h.us
            t.them += h.them
        }
    }

    static func outcome(_ t: Score) -> BalootOutcome {
        guard max(t.us, t.them) >= target else { return .playing }
        if t.us == t.them { return .tie(t.us) }
        return .won(t.us > t.them ? .us : .them)
    }

    /// A win that is new (or passes to the other team) comes first; otherwise the teams that
    /// went strictly above 100 and have not been announced yet.
    static func event(from prev: Score, to next: Score, said: Set<Team>) -> BalootEvent? {
        let before = outcome(prev), after = outcome(next)
        if let winner = after.winner, before.winner != winner {
            return .won(winner)
        }
        // An edit after a win that keeps the same winner says nothing, not even «فوق المية»; the 100 is counted silently.
        if let winner = before.winner, after.winner == winner { return nil }
        let crossed = Team.allCases.filter { !said.contains($0) && next[$0] > hundred }
        return crossed.isEmpty ? nil : .hundred(crossed)
    }

    /// The teams above 100, to keep them from being announced again.
    static func saidAfter(_ said: Set<Team>, totals: Score) -> Set<Team> {
        said.union(Team.allCases.filter { totals[$0] > hundred })
    }

    static func who(_ teams: [Team]) -> String {
        teams.count >= 2 ? "لنا ولهم" : (teams.first?.name ?? "")
    }

    /// The fill of the track under a total, from 0 to 1.
    static func trackFill(_ total: Int) -> Double {
        min(1, max(0, Double(total) / Double(target)))
    }

    /// The home card's line for this صكة.
    static func status(_ hands: [BalootHand]) -> String {
        let t = totals(hands)
        if hands.isEmpty { return "صكة جديدة" }
        switch outcome(t) {
        case .won(let team): return "الصكة " + team.name
        case .tie(let at): return "تعادل على \(at)"
        case .playing: return "صكة جارية · " + ArabicCount.hands(hands.count)
        }
    }

    /// «تعادل على 158، واللعبة الجاية تحسم».
    static func tieNote(_ at: Int) -> String {
        "تعادل على \(at)، واللعبة الجاية تحسم"
    }
}
