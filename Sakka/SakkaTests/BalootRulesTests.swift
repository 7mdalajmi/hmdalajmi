import Testing
#if canImport(SakkaRules)
@testable import SakkaRules
#else
@testable import Sakka
#endif

/// The صكة on the board: 11 hands, لنا 94 and لهم 138.
private let boardHands: [BalootHand] = [[10, 6], [0, 26], [18, 8], [16, 0], [4, 12], [0, 32], [22, 4], [9, 7], [0, 26], [12, 4], [3, 13]]
    .enumerated().map { BalootHand(id: $0.offset + 1, us: $0.element[0], them: $0.element[1]) }

@Suite("صكة")
struct BalootRulesTests {
    @Test("Arabic-Indic and Eastern Arabic digits become Western, three at most")
    func digits() {
        #expect(Digits.clean("١٢٣٤") == "123")
        #expect(Digits.clean("۴۵") == "45")
        #expect(Digits.clean("a1-b2 ") == "12")
        #expect(Digits.clean("") == "")
        #expect(Digits.value("") == 0)
        #expect(Digits.value("٢٦") == 26)
        #expect(Digits.clean("12345", limit: 2) == "12")
    }

    @Test("A صكة field drops a 0 in front of another digit, so an edited 0 takes one digit as one digit")
    func fieldDigits() {
        #expect(Digits.field("01") == "1")
        #expect(Digits.field("0") == "0")
        #expect(Digits.field("00") == "0")
        #expect(Digits.field("") == "")
        #expect(Digits.field("٠٥") == "5")
        #expect(Digits.field("0012") == "12")
        #expect(Digits.field("100") == "100")
        #expect(Digits.field("1234") == "123")
        #expect(Digits.field("a7b") == "7")
    }

    @Test("The board's صكة adds up to 94 and 138 and is still running")
    func boardTotals() {
        let t = BalootRules.totals(boardHands)
        #expect(t == Score(us: 94, them: 138))
        #expect(BalootRules.outcome(t) == .playing)
        #expect(BalootRules.status(boardHands) == "صكة جارية · بعد 11 لعبة")
    }

    @Test("152 ends the صكة, the higher total wins, and a tie at or above 152 goes on")
    func outcome() {
        #expect(BalootRules.outcome(Score(us: 151, them: 100)) == .playing)
        #expect(BalootRules.outcome(Score(us: 152, them: 100)) == .won(.us))
        #expect(BalootRules.outcome(Score(us: 150, them: 152)) == .won(.them))
        #expect(BalootRules.outcome(Score(us: 160, them: 160)) == .tie(160))
        #expect(BalootRules.outcome(Score(us: 152, them: 152)) == .tie(152))
        #expect(BalootRules.outcome(Score(us: 170, them: 160)) == .won(.us))
    }

    @Test("Passing 100 counts above 100 only, once per team")
    func hundred() {
        let said: Set<Team> = [.them]
        #expect(BalootRules.event(from: Score(us: 94, them: 138), to: Score(us: 100, them: 138), said: said) == nil)
        let ev = BalootRules.event(from: Score(us: 94, them: 138), to: Score(us: 101, them: 138), said: said)
        #expect(ev == .hundred([.us]))
        #expect(ev?.banner == "لنا فوق المية")
        #expect(ev?.speech == "لنا فوق المئة")
        // Already said: back under 100 and over again says nothing.
        #expect(BalootRules.event(from: Score(us: 90, them: 120), to: Score(us: 110, them: 120), said: [.us, .them]) == nil)
    }

    @Test("Both teams in one hand are announced together")
    func bothTeams() {
        let ev = BalootRules.event(from: Score(us: 90, them: 95), to: Score(us: 105, them: 110), said: [])
        #expect(ev == .hundred([.us, .them]))
        #expect(ev?.banner == "لنا ولهم فوق المية")
        #expect(ev?.speech == "لنا ولهم فوق المئة")
    }

    @Test("Passing 100 and winning in one hand announces only the win, and marks the 100 as said")
    func winOverHundred() {
        let next = Score(us: 160, them: 60)
        #expect(BalootRules.event(from: Score(us: 94, them: 60), to: next, said: []) == .won(.us))
        #expect(BalootRules.saidAfter([], totals: next) == [.us])
        #expect(BalootEvent.won(.us).speech == "الصكة لنا")
        #expect(BalootEvent.won(.them).banner == "الصكة لهم")
    }

    @Test("Edits after a win: the same winner says nothing, a new winner wins again, under 152 reopens")
    func editsAfterWin() {
        #expect(BalootRules.event(from: Score(us: 160, them: 60), to: Score(us: 158, them: 60), said: [.us]) == nil)
        #expect(BalootRules.event(from: Score(us: 160, them: 150), to: Score(us: 150, them: 160), said: [.us, .them]) == .won(.them))
        // The loser passing 100 in that edit is not announced either; it is counted as said.
        #expect(BalootRules.event(from: Score(us: 160, them: 90), to: Score(us: 160, them: 110), said: [.us]) == nil)
        #expect(BalootRules.saidAfter([.us], totals: Score(us: 160, them: 110)) == [.us, .them])
        let reopened = Score(us: 140, them: 60)
        #expect(BalootRules.event(from: Score(us: 160, them: 60), to: reopened, said: [.us]) == nil)
        #expect(BalootRules.outcome(reopened) == .playing)
    }

    @Test("Hands counted in Arabic")
    func handsText() {
        #expect(ArabicCount.hands(1) == "بعد لعبة وحدة")
        #expect(ArabicCount.hands(2) == "بعد لعبتين")
        #expect(ArabicCount.hands(3) == "بعد 3 لعبات")
        #expect(ArabicCount.hands(10) == "بعد 10 لعبات")
        #expect(ArabicCount.hands(11) == "بعد 11 لعبة")
    }

    @Test("The home card's line")
    func status() {
        #expect(BalootRules.status([]) == "صكة جديدة")
        let won = boardHands + [BalootHand(id: 20, us: 60, them: 0)]
        #expect(BalootRules.status(won) == "الصكة لنا")
        let tie = [BalootHand(id: 1, us: 152, them: 152)]
        #expect(BalootRules.status(tie) == "تعادل على 152")
        #expect(BalootRules.tieNote(158) == "تعادل على 158، واللعبة الجاية تحسم")
    }

    @Test("The track fills toward 152")
    func track() {
        #expect(BalootRules.trackFill(0) == 0)
        #expect(BalootRules.trackFill(76) == 0.5)
        #expect(BalootRules.trackFill(200) == 1)
    }
}
