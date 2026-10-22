import Testing
#if canImport(SakkaRules)
@testable import SakkaRules
#else
@testable import Sakka
#endif

/// The four players of the board.
let boardPlayers = [
    HandPlayer(id: "p1", name: "حمد"), HandPlayer(id: "p2", name: "أنور"),
    HandPlayer(id: "p3", name: "فهد"), HandPlayer(id: "p4", name: "سالم")
]

/// One cell from the board's shorthand: "out", "hand", "joker", "joker2", "nd", or the cards left.
func cell(_ s: String) -> HandCell {
    if let n = Int(s) { return HandCell(kind: .cards, cards: n) }
    return HandCell(kind: HandKind(rawValue: s) ?? .notDown)
}

func round(_ id: Int, _ spec: [String], players: [HandPlayer] = boardPlayers) -> HandRound {
    var cells: [String: HandCell] = [:]
    for (p, s) in zip(players, spec) { cells[p.id] = cell(s) }
    return HandRound(id: id, cells: cells)
}

/// The board's rounds: everyone goes down once before the جيكر of round 5, and once more after it.
let boardRounds: [HandRound] = [
    ["out", "35", "nd", "nd"], ["nd", "nd", "out", "22"], ["15", "hand", "nd", "nd"],
    ["nd", "nd", "31", "out"], ["joker", "nd", "12", "nd"], ["nd", "out", "nd", "30"],
    ["27", "nd", "out", "nd"], ["out", "33", "nd", "nd"], ["nd", "out", "nd", "nd"]
].enumerated().map { round($0.offset + 1, $0.element) }

@Suite("الهند")
struct HandRulesTests {
    @Test("The finisher sets the multiplier, and it multiplies everything in the round")
    func multipliers() {
        #expect(HandKind.out.multiplier == 1)
        #expect(HandKind.hand.multiplier == 2)
        #expect(HandKind.joker.multiplier == 4)
        #expect(HandKind.joker2.multiplier == 8)
        let r = round(1, ["hand", "15", "nd", "nd"])
        #expect(HandRules.multiplier(r) == 2)
        #expect(HandRules.points(r) == ["p1": -60, "p2": 30, "p3": 200, "p4": 200])
        let j2 = round(2, ["nd", "joker2", "10", "nd"])
        #expect(HandRules.points(j2) == ["p1": 800, "p2": -240, "p3": 80, "p4": 800])
    }

    @Test("Midgame on the board: 100, 75, 270 and 322, round 4 of 7")
    func midgame() {
        let rounds = Array(boardRounds.prefix(3))
        #expect(HandRules.totals(players: boardPlayers, rounds: rounds) == ["p1": 100, "p2": 75, "p3": 270, "p4": 322])
        #expect(HandRules.downs(players: boardPlayers, rounds: rounds) == ["p1": 1, "p2": 1, "p3": 0, "p4": 1])
        #expect(HandRules.target(rounds) == 7)
        #expect(HandRules.allowedDowns(rounds) == 1)
        let o = HandRules.outcome(players: boardPlayers, rounds: rounds)
        #expect(o == .playing)
        #expect(HandRules.roundLine(rounds: rounds, outcome: o) == "الجولة 4 من 7")
        #expect(HandRules.homeLine(players: boardPlayers, rounds: rounds) == "الجولة 4 من 7")
    }

    @Test("The جيكر makes it 9 rounds and two downs; حمد wins with 277")
    func boardGame() {
        #expect(HandRules.target(Array(boardRounds.prefix(4))) == 7)
        #expect(HandRules.target(Array(boardRounds.prefix(5))) == 9)
        let almost = Array(boardRounds.prefix(8))
        #expect(HandRules.outcome(players: boardPlayers, rounds: almost) == .playing)
        #expect(HandRules.roundLine(rounds: almost, outcome: .playing) == "آخر جولة")
        let t = HandRules.totals(players: boardPlayers, rounds: boardRounds)
        #expect(t == ["p1": 277, "p2": 648, "p3": 619, "p4": 1022])
        #expect(HandRules.downs(players: boardPlayers, rounds: boardRounds) == ["p1": 2, "p2": 2, "p3": 2, "p4": 2])
        let o = HandRules.outcome(players: boardPlayers, rounds: boardRounds)
        #expect(o == .won("p1"))
        #expect(HandRules.roundLine(rounds: boardRounds, outcome: o) == "")
        #expect(HandRules.homeLine(players: boardPlayers, rounds: boardRounds) == "الفوز لحمد")
    }

    @Test("آخر جولة counts the distance from the first: 0 for him, and what the others have over him")
    func gapsToTheFirst() {
        // Nothing before the last round: the الفرق line is not there in round 8 of 9.
        let seven = Array(boardRounds.prefix(7))
        #expect(HandRules.roundLine(rounds: seven, outcome: .playing) == "الجولة 8 من 9")
        #expect(!HandRules.isLastRound(rounds: seven, outcome: .playing))
        // آخر جولة on the board: 177, 678, 519 and 922, so حمد is the first and the rest are 501, 342 and 745 over him.
        let almost = Array(boardRounds.prefix(8))
        let o = HandRules.outcome(players: boardPlayers, rounds: almost)
        #expect(HandRules.roundLine(rounds: almost, outcome: o) == "آخر جولة")
        #expect(HandRules.isLastRound(rounds: almost, outcome: o))
        let t = HandRules.totals(players: boardPlayers, rounds: almost)
        #expect(t == ["p1": 177, "p2": 678, "p3": 519, "p4": 922])
        let g = HandRules.gaps(players: boardPlayers, totals: t)
        #expect(g == ["p1": 0, "p2": 501, "p3": 342, "p4": 745])
        #expect(boardPlayers.map { Digits.gap(g[$0.id] ?? 0) } == ["0", "+501", "+342", "+745"])
        #expect(HandRules.gapSpeech(name: "حمد", gap: 0) == "حمد الأول")
        #expect(HandRules.gapSpeech(name: "أنور", gap: 501) == "أنور فوق الأول بـ 501")
        // The line goes with the win: the game is over, and the win screen says it.
        let won = HandRules.outcome(players: boardPlayers, rounds: boardRounds)
        #expect(!HandRules.isLastRound(rounds: boardRounds, outcome: won))
        // The totals as they count: the distance follows them, from where they were to where they land.
        let before = HandRules.totals(players: boardPlayers, rounds: Array(boardRounds.prefix(7)))
        #expect(HandRules.gaps(players: boardPlayers, totals: before) == ["p1": 0, "p2": 438, "p3": 212, "p4": 615])
    }

    @Test("The جولة فاصلة keeps the الفرق line, and the players level on the lowest are both the first")
    func gapsInTheDeciderRound() {
        let three = [HandPlayer(id: "a", name: "حمد"), HandPlayer(id: "b", name: "فهد"), HandPlayer(id: "c", name: "سالم")]
        let specs = [["out", "150", "nd"], ["150", "out", "nd"], ["out", "150", "nd"], ["150", "out", "nd"],
                     ["out", "150", "nd"], ["150", "out", "nd"], ["110", "110", "out"]]
        let seven = specs.enumerated().map { round($0.offset + 1, $0.element, players: three) }
        let o = HandRules.outcome(players: three, rounds: seven)
        #expect(o == .tie(["a", "b"], at: 470))
        #expect(HandRules.roundLine(rounds: seven, outcome: o) == "جولة فاصلة")
        #expect(HandRules.isLastRound(rounds: seven, outcome: o))
        #expect(HandRules.gaps(players: three, totals: HandRules.totals(players: three, rounds: seven))
                == ["a": 0, "b": 0, "c": 100])
    }

    @Test("A second down without a جيكر is refused; with one in the round it goes in")
    func downCap() {
        let mid = Array(boardRounds.prefix(3))
        let second = round(10, ["hand", "25", "nd", "nd"])
        #expect(HandRules.overDowns(players: boardPlayers, next: mid + [second], round: second) == ["p2"])
        // Everyone else on ما نزل with حمد هند: 40, 275, 470, 522.
        let fixed = round(10, ["hand", "nd", "nd", "nd"])
        #expect(HandRules.overDowns(players: boardPlayers, next: mid + [fixed], round: fixed).isEmpty)
        #expect(HandRules.totals(players: boardPlayers, rounds: mid + [fixed]) == ["p1": 40, "p2": 275, "p3": 470, "p4": 522])
        // A جيكر in the same round allows two: −20, 175, 670, 722.
        let joker = round(11, ["joker", "25", "nd", "nd"])
        #expect(HandRules.overDowns(players: boardPlayers, next: mid + [joker], round: joker).isEmpty)
        #expect(HandRules.totals(players: boardPlayers, rounds: mid + [joker]) == ["p1": -20, "p2": 175, "p3": 670, "p4": 722])
        // Editing that جيكر back to خلّص takes the second down away again.
        let undone = round(11, ["out", "25", "nd", "nd"])
        #expect(HandRules.overDowns(players: boardPlayers, next: mid + [undone], round: undone) == ["p2"])
        let undoneFixed = round(11, ["out", "nd", "nd", "nd"])
        #expect(HandRules.totals(players: boardPlayers, rounds: mid + [undoneFixed]) == ["p1": 70, "p2": 175, "p3": 370, "p4": 422])
    }

    @Test("A down is a number from 1 up to below ما نزل; an old round's cards from 1 to 99")
    func isDown() {
        // Old rounds: cards, whatever the multiplier.
        #expect(HandRules.isDown(HandCell(kind: .cards, cards: 1), multiplier: 1))
        #expect(HandRules.isDown(HandCell(kind: .cards, cards: 99), multiplier: 8))
        #expect(!HandRules.isDown(HandCell(kind: .cards, cards: 100), multiplier: 2))
        #expect(!HandRules.isDown(HandCell(kind: .cards, cards: 0), multiplier: 1))
        #expect(!HandRules.isDown(HandCell(kind: .notDown), multiplier: 1))
        // Typed numbers: below 100 × the multiplier, from 1 up.
        #expect(HandRules.isDown(HandCell(kind: .exact, free: 99), multiplier: 1))
        #expect(!HandRules.isDown(HandCell(kind: .exact, free: 100), multiplier: 1))
        #expect(HandRules.isDown(HandCell(kind: .exact, free: 150), multiplier: 2))
        #expect(!HandRules.isDown(HandCell(kind: .exact, free: 0), multiplier: 2))
        #expect(!HandRules.isDown(HandCell(kind: .exact, free: -20), multiplier: 2))
        #expect(!HandRules.isDown(HandCell(kind: .free, free: 35), multiplier: 1))
        // In the round being typed, the multiplier is the finisher's as it stands.
        var e = HandRules.emptyEntry(boardPlayers)
        e["p2"] = EntryCell(kind: .exact, digits: "150")
        #expect(!HandRules.isDown(e["p2"], in: e))
        e["p1"] = EntryCell(kind: .hand)
        #expect(HandRules.isDown(e["p2"], in: e))
        #expect(HandRules.isDown(EntryCell(kind: .cards, digits: "35"), in: e))
        #expect(!HandRules.isDown(EntryCell(kind: .cards, digits: "120"), in: e))
    }

    @Test("A tie on the lowest total after the last round plays a جولة فاصلة")
    func tie() {
        let three = [HandPlayer(id: "a", name: "حمد"), HandPlayer(id: "b", name: "فهد"), HandPlayer(id: "c", name: "سالم")]
        // Cards of 100 or more are not downs, so no cap gets in the way.
        let specs = [["out", "150", "nd"], ["150", "out", "nd"], ["out", "150", "nd"], ["150", "out", "nd"],
                     ["out", "150", "nd"], ["150", "out", "nd"], ["110", "110", "out"]]
        let seven = specs.enumerated().map { round($0.offset + 1, $0.element, players: three) }
        #expect(HandRules.totals(players: three, rounds: seven) == ["a": 470, "b": 470, "c": 570])
        let o = HandRules.outcome(players: three, rounds: seven)
        #expect(o == .tie(["a", "b"], at: 470))
        #expect(HandRules.roundLine(rounds: seven, outcome: o) == "جولة فاصلة")
        #expect(HandRules.homeLine(players: three, rounds: seven) == "تعادل، وجولة فاصلة")
        let six = Array(seven.prefix(6))
        #expect(HandRules.announcement(players: three, before: six, after: seven, gained: seven[6])?.banner == "تعادل، وجولة فاصلة")
        // The جولة فاصلة decides.
        let eight = seven + [round(8, ["out", "nd", "nd"], players: three)]
        #expect(HandRules.outcome(players: three, rounds: eight) == .won("a"))
    }

    @Test("Names in the announcements")
    func words() {
        #expect(HandRules.winLine("حمد") == "الفوز لحمد")
        #expect(HandRules.winLine("الشيخ") == "الفوز للشيخ")
        #expect(HandRules.winLine("Sam") == "الفوز لـ Sam")
        #expect(HandRules.joinNames(["حمد"]) == "حمد")
        #expect(HandRules.joinNames(["حمد", "فهد"]) == "حمد وفهد")
        #expect(HandRules.joinNames(["حمد", "أنور", "فهد"]) == "حمد، أنور وفهد")
        #expect(HandRules.overLine(names: ["أنور"], cap: 2) == "أنور عنده نزولين")
        #expect(HandRules.overLine(names: ["أنور", "فهد"], cap: 1) == "أنور وفهد عندهم نزول")
        #expect(ArabicCount.rounds(9) == "بعد 9 جولات")
        #expect(ArabicCount.rounds(2) == "بعد جولتين")
        #expect(ArabicCount.downs(2) == "نزولين")
        #expect(ArabicCount.downs(12) == "12 نزول")
        #expect(Digits.signed(-60) == "\u{2212}60")
        #expect(Digits.signed(100) == "100")
        #expect(HandRules.name(of: "p9", in: boardPlayers) == "")
        #expect(HandRules.name(of: "x", in: [HandPlayer(id: "x", name: "  ")]) == "لاعب 1")
    }

    @Test("What a round announces")
    func announcements() {
        let mid = Array(boardRounds.prefix(3))
        let joker = round(10, ["joker", "25", "nd", "nd"])
        let a = HandRules.announcement(players: boardPlayers, before: mid, after: mid + [joker], gained: joker)
        #expect(a == HandAnnouncement(banner: "حمد نزل جيكر · صارت 9 جولات ونزولين", speech: "حمد نزل جيكر، وصارت تسع جولات ونزولين"))
        let hand = round(11, ["nd", "nd", "hand", "nd"])
        #expect(HandRules.announcement(players: boardPlayers, before: mid, after: mid + [hand], gained: hand)?.banner == "فهد نزل هند")
        // Deleting the جيكر takes the game back to 7.
        #expect(HandRules.announcement(players: boardPlayers, before: mid + [joker], after: mid, gained: nil)?.banner == "رجعت 7 جولات ونزول واحد")
        // A plain خلّص says nothing, until the round before the last.
        let plain = round(12, ["out", "nd", "nd", "nd"])
        #expect(HandRules.announcement(players: boardPlayers, before: mid, after: mid + [plain], gained: plain) == nil)
        let five = Array(boardRounds.prefix(4)).map { r -> HandRound in var x = r; x.cells = x.cells.mapValues { $0.kind == .joker ? HandCell(kind: .out) : $0 }; return x }
        let sixth = round(13, ["nd", "out", "nd", "nd"])
        let fifth = round(14, ["nd", "nd", "out", "nd"])
        let before = five + [fifth]
        #expect(HandRules.announcement(players: boardPlayers, before: before, after: before + [sixth], gained: sixth)?.banner == "آخر جولة")
        // A long name shortens the banner.
        let long = [HandPlayer(id: "p1", name: "عبدالرحمن الكبير")] + Array(boardPlayers.dropFirst())
        let b = HandRules.announcement(players: long, before: mid, after: mid + [joker], gained: joker)
        #expect((b?.banner.utf16.count ?? 99) <= 36)
        // After the win, an edit that keeps the same winner says nothing, even when it takes the game back to 7.
        let two = [HandPlayer(id: "a", name: "حمد"), HandPlayer(id: "b", name: "فهد")]
        let tail = (2...9).map { round($0, ["out", "nd"], players: two) }
        let withJoker = [round(1, ["joker", "nd"], players: two)] + tail
        let withoutJoker = [round(1, ["out", "nd"], players: two)] + tail
        #expect(HandRules.outcome(players: two, rounds: withJoker) == .won("a"))
        #expect(HandRules.outcome(players: two, rounds: withoutJoker) == .won("a"))
        #expect(HandRules.announcement(players: two, before: withJoker, after: withoutJoker, gained: nil) == nil)
        // The win itself is not announced here.
        let last = boardRounds[8]
        #expect(HandRules.announcement(players: boardPlayers, before: Array(boardRounds.prefix(8)), after: boardRounds, gained: last) == nil)
    }

    @Test("A هند that brings the tie or the last round says it too")
    func finisherWithTieOrLastRound() {
        let three = [HandPlayer(id: "a", name: "حمد"), HandPlayer(id: "b", name: "فهد"), HandPlayer(id: "c", name: "سالم")]
        let specs = [["out", "150", "nd"], ["150", "out", "nd"], ["out", "150", "nd"], ["150", "out", "nd"],
                     ["out", "150", "nd"], ["150", "out", "nd"]]
        let six = specs.enumerated().map { round($0.offset + 1, $0.element, players: three) }
        // سالم هند in the last round: حمد and فهد go down 55 each, ×2, and tie on 470.
        let seventh = round(7, ["55", "55", "hand"], players: three)
        #expect(HandRules.outcome(players: three, rounds: six + [seventh]) == .tie(["a", "b"], at: 470))
        let tie = HandRules.announcement(players: three, before: six, after: six + [seventh], gained: seventh)
        #expect(tie == HandAnnouncement(banner: "سالم نزل هند · تعادل، وجولة فاصلة", speech: "سالم نزل هند، وتعادل، وجولة فاصلة"))
        // أنور هند in round 6 of 7.
        let five = Array(boardRounds.prefix(4)) + [round(14, ["nd", "nd", "out", "nd"])]
        let sixth = round(15, ["nd", "hand", "nd", "nd"])
        let last = HandRules.announcement(players: boardPlayers, before: five, after: five + [sixth], gained: sixth)
        #expect(last == HandAnnouncement(banner: "أنور نزل هند · آخر جولة", speech: "أنور نزل هند، وآخر جولة"))
        // A long name (14 letters, the most a name takes) keeps the banner short; the voice still says it all.
        let longThree = [three[0], three[1], HandPlayer(id: "c", name: "عبدالرحمن الكب")]
        let short = HandRules.announcement(players: longThree, before: six, after: six + [seventh], gained: seventh)
        #expect(short?.banner == "هند · تعادل، وجولة فاصلة")
        #expect(short?.speech == "عبدالرحمن الكب نزل هند، وتعادل، وجولة فاصلة")
    }

    @Test("Editing a round keeps the downs it already had, and still refuses a new one past the cap")
    func editKeepsItsDowns() {
        let r1 = round(1, ["20", "out", "nd", "nd"])
        let r2 = round(2, ["nd", "nd", "out", "40"])
        let r3 = round(3, ["nd", "joker", "nd", "nd"])
        let r4 = round(4, ["15", "nd", "out", "nd"])
        // With the جيكر, حمد's second down went in.
        #expect(HandRules.overDowns(players: boardPlayers, next: [r1, r2, r3, r4], round: r4).isEmpty)
        // The جيكر is deleted: حمد keeps two downs, and round 4 can still be corrected.
        let rounds = [r1, r2, r4]
        var entry = HandRules.entry(from: r4, players: boardPlayers)
        entry["p4"] = EntryCell(kind: .cards, digits: "120")
        let fixed = HandRules.status(players: boardPlayers, rounds: rounds, entry: entry, editing: 4)
        #expect(fixed.ready && fixed.over.isEmpty)
        // A down the edit adds is still held to the cap: سالم already went down in round 2.
        entry["p4"] = EntryCell(kind: .cards, digits: "30")
        #expect(HandRules.status(players: boardPlayers, rounds: rounds, entry: entry, editing: 4).over == ["p4"])
        // A new round gets no such allowance.
        let fresh = HandRules.entry(from: round(9, ["35", "nd", "out", "nd"]), players: boardPlayers)
        #expect(HandRules.status(players: boardPlayers, rounds: rounds, entry: fresh, editing: nil).over == ["p1"])
        // An edit that takes the جيكر away itself is held to the lower cap, as on the board: أنور's 25 in that
        // round becomes his second down in a 7-round game, and «حفظ» is refused.
        let mid = Array(boardRounds.prefix(3))
        let joker = round(11, ["joker", "25", "nd", "nd"])
        let swapped = HandRules.entry(from: round(11, ["out", "25", "nd", "nd"]), players: boardPlayers)
        #expect(HandRules.status(players: boardPlayers, rounds: mid + [joker], entry: swapped, editing: 11).over == ["p2"])
    }

    @Test("Two players with one id never trap")
    func duplicateIds() {
        let twice = [HandPlayer(id: "p1", name: "حمد"), HandPlayer(id: "p1", name: "فهد")]
        #expect(HandRules.emptyEntry(twice).count == 1)
    }
}

@Suite("الهند: تعبئة الجولة")
struct HandEntryTests {
    @Test("Choosing a finisher puts the rest on ما نزل and moves on to the next one to type")
    func finisherFills() {
        let empty = HandRules.emptyEntry(boardPlayers)
        let (e, f) = HandRules.choosing(.hand, entry: empty, focus: "p1", players: boardPlayers)
        #expect(e["p1"] == EntryCell(kind: .hand))
        #expect(e["p2"] == .notDown && e["p3"] == .notDown && e["p4"] == .notDown)
        #expect(f == "p2")
        let st = HandRules.status(players: boardPlayers, rounds: [], entry: e, editing: nil)
        #expect(st.finisher == "p1" && st.multiplier == 2 && st.ready)
    }

    @Test("A new finisher sends the old one back to ما نزل, and typed numbers stay")
    func secondFinisher() {
        var e = HandRules.emptyEntry(boardPlayers)
        e["p2"] = EntryCell(kind: .cards, digits: "25")
        e["p1"] = EntryCell(kind: .out)
        let (n, _) = HandRules.choosing(.joker, entry: e, focus: "p3", players: boardPlayers)
        #expect(n["p1"] == .notDown)
        #expect(n["p2"] == EntryCell(kind: .cards, digits: "25"))
        #expect(n["p3"] == EntryCell(kind: .joker))
        #expect(n["p4"] == .notDown)
    }

    @Test("Digits stay in their field, up to four, as typed; a lone 0 is a number and the next digit takes its place")
    func typing() {
        let (start, _) = HandRules.choosing(.out, entry: HandRules.emptyEntry(boardPlayers), focus: "p1", players: boardPlayers)
        var e = start
        for d in "2500" { e = HandRules.typing(d, entry: e, focus: "p2") ?? e }
        #expect(e["p2"] == EntryCell(kind: .exact, digits: "2500"))
        #expect(HandRules.typing("1", entry: e, focus: "p2") == nil)
        // ما نزل turns into the number typed; 0 first is a number of its own, and a digit after it replaces it.
        var z = HandRules.typing("0", entry: start, focus: "p3") ?? start
        #expect(z["p3"] == EntryCell(kind: .exact, digits: "0"))
        #expect(HandRules.typing("0", entry: z, focus: "p3") == nil)
        z = HandRules.typing("7", entry: z, focus: "p3") ?? z
        #expect(z["p3"] == EntryCell(kind: .exact, digits: "7"))
        #expect(HandRules.typing("x", entry: start, focus: "p3") == nil)
    }

    @Test("Erasing takes one digit, then back to ما نزل once a finisher is chosen")
    func erasing() {
        var e = HandRules.emptyEntry(boardPlayers)
        e["p1"] = EntryCell(kind: .out)
        e["p2"] = EntryCell(kind: .cards, digits: "25")
        let a = HandRules.erasing(entry: e, focus: "p2", players: boardPlayers, rounds: [], editing: nil)
        #expect(a["p2"] == EntryCell(kind: .cards, digits: "2"))
        let b = HandRules.erasing(entry: a, focus: "p2", players: boardPlayers, rounds: [], editing: nil)
        #expect(b["p2"] == .notDown)
        let c = HandRules.erasing(entry: b, focus: "p2", players: boardPlayers, rounds: [], editing: nil)
        #expect(c["p2"] == .empty)
        var lone = HandRules.emptyEntry(boardPlayers)
        lone["p3"] = EntryCell(kind: .cards, digits: "7")
        #expect(HandRules.erasing(entry: lone, focus: "p3", players: boardPlayers, rounds: [], editing: nil)["p3"] == .empty)
    }

    @Test("The round is ready with a finisher and nobody missing, and the cap is held while typing")
    func status() {
        var e = HandRules.emptyEntry(boardPlayers)
        #expect(!HandRules.status(players: boardPlayers, rounds: [], entry: e, editing: nil).ready)
        e["p1"] = EntryCell(kind: .out)
        e["p2"] = EntryCell(kind: .cards, digits: "25")
        let st = HandRules.status(players: boardPlayers, rounds: [], entry: e, editing: nil)
        #expect(st.missing == ["p3", "p4"])
        #expect(!st.ready)
        e["p3"] = .notDown
        e["p4"] = .notDown
        let mid = Array(boardRounds.prefix(3))
        let over = HandRules.status(players: boardPlayers, rounds: mid, entry: e, editing: nil)
        #expect(over.ready && over.over == ["p2"] && over.cap == 1)
        // Editing round 1 (where أنور already went down) does not count that round twice.
        let edit = HandRules.status(players: boardPlayers, rounds: mid, entry: HandRules.entry(from: mid[0], players: boardPlayers), editing: mid[0].id)
        #expect(edit.over.isEmpty)
    }

    @Test("A round goes to the fields and back with the same points and نزول; its cards as the number they came to")
    func roundTrip() {
        for r in boardRounds {
            let e = HandRules.entry(from: r, players: boardPlayers)
            let back = HandRules.round(from: e, players: boardPlayers, id: r.id)
            #expect(HandRules.points(back) == HandRules.points(r))
            #expect(boardPlayers.map { HandRules.isDown(back.cells[$0.id], in: back) }
                    == boardPlayers.map { HandRules.isDown(r.cells[$0.id], in: r) })
            #expect(!back.cells.values.contains { $0.kind == .cards && $0.cards > 0 })
        }
    }

    @Test("The next field: an empty one first, then one on ما نزل, round the table")
    func nextOpen() {
        var e = HandRules.emptyEntry(boardPlayers)
        e["p2"] = .notDown
        e["p3"] = EntryCell(kind: .cards, digits: "12")
        #expect(HandRules.nextOpen(players: boardPlayers, from: "p1", entry: e) == "p4")
        e["p4"] = EntryCell(kind: .out)
        e["p1"] = .notDown
        #expect(HandRules.nextOpen(players: boardPlayers, from: "p4", entry: e) == "p1")
    }
}
