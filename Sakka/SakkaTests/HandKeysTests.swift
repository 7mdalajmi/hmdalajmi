import Foundation
import Testing
#if canImport(SakkaRules)
@testable import SakkaRules
#else
@testable import Sakka
#endif

/// The round being typed, from the board's shorthand: a number is typed as it is ("-15" too), "c:35" an old
/// round's cards, "free:-15" build 5's «حر», "nd!" and "nd!!" ما نزل with معلن جيكر or جيكرين, and a "+" in front
/// for «من إيده».
private func typed(_ spec: [String]) -> [String: EntryCell] {
    var e: [String: EntryCell] = [:]
    for (p, s0) in zip(boardPlayers, spec) {
        let fromHand = s0.hasPrefix("+")
        let s = fromHand ? String(s0.dropFirst()) : s0
        var x: EntryCell
        if s.isEmpty { x = .empty }
        else if s.hasPrefix("free:") {
            let n = Int(s.dropFirst(5)) ?? 0
            x = EntryCell(kind: .free, digits: "\(abs(n))", negative: n < 0)
        } else if s.hasPrefix("c:") {
            x = EntryCell(kind: .cards, digits: String(s.dropFirst(2)))
        } else if s.hasPrefix("nd!") {
            x = EntryCell(kind: .notDown, declared: s == "nd!!" ? 2 : 1)
        } else if let n = Int(s) {
            x = EntryCell(kind: .exact, digits: "\(abs(n))", negative: n < 0)
        } else { x = EntryCell(kind: HandKind(rawValue: s)) }
        x.fromHand = fromHand
        e[p.id] = x
    }
    return e
}

private func recorded(_ spec: [String], id: Int = 1) -> HandRound {
    HandRules.round(from: typed(spec), players: boardPlayers, id: id)
}

private func status(_ e: [String: EntryCell], rounds: [HandRound] = [], editing: Int? = nil) -> EntryStatus {
    HandRules.status(players: boardPlayers, rounds: rounds, entry: e, editing: editing)
}

@Suite("الهند: الأرقام كما هي، ومن إيده، ومعلن، وزات")
struct HandKeysTests {
    @Test("A typed number is taken as it is: not multiplied, plus or minus; a نزول below ما نزل")
    func exactScores() {
        let r = recorded(["hand", "35", "-15", "150"])
        #expect(HandRules.points(r) == ["p1": -60, "p2": 35, "p3": -15, "p4": 150])
        // ما نزل in a هند is 200: 35 and 150 are below it, −15 is not a نزول.
        #expect(boardPlayers.map { HandRules.isDown(r.cells[$0.id], in: r) } == [false, true, false, true])
        #expect(HandRules.downs(players: boardPlayers, rounds: [r]) == ["p1": 0, "p2": 1, "p3": 0, "p4": 1])
        // With خلّص, 150 is above ما نزل's 100.
        let out = recorded(["out", "35", "nd", "150"])
        #expect(HandRules.points(out) == ["p1": -30, "p2": 35, "p3": 100, "p4": 150])
        #expect(!HandRules.isDown(out.cells["p4"], in: out))
        // An old round's cards still count × the round, and build 5's «حر» as it is, never a نزول.
        let old = recorded(["hand", "c:35", "free:35", "nd"])
        #expect(HandRules.points(old) == ["p1": -60, "p2": 70, "p3": 35, "p4": 200])
        #expect(HandRules.isDown(old.cells["p2"], in: old) && !HandRules.isDown(old.cells["p3"], in: old))
        // A field's caption: what it comes to.
        #expect(HandRules.points(EntryCell(kind: .exact, digits: "35"), multiplier: 4) == 35)
        #expect(HandRules.points(EntryCell(kind: .exact, negative: true), multiplier: 2) == nil)
        #expect(HandRules.points(EntryCell(kind: .hand), multiplier: 2) == nil)
    }

    @Test("«من إيده» adds 25 × the multiplier on top of a number or ما نزل, only with هند, جيكر or جيكرين")
    func fromHandScores() {
        // ما نزل in a هند is 200 + 50 = 250; a number typed 70 (35 cards × 2, worked out by hand) comes to 120.
        #expect(HandRules.points(recorded(["hand", "+70", "nd", "nd"])) == ["p1": -60, "p2": 120, "p3": 200, "p4": 200])
        #expect(HandRules.points(recorded(["hand", "70", "+nd", "nd"])) == ["p1": -60, "p2": 70, "p3": 250, "p4": 200])
        #expect(HandRules.points(recorded(["joker", "+nd", "80", "nd"]))["p2"] == 500)
        #expect(HandRules.points(recorded(["joker2", "nd", "nd", "+nd"]))["p4"] == 1000)
        // An old round's cards with the mark, as build 5 scored them: 35 × 2 + 50.
        #expect(HandRules.points(recorded(["hand", "+c:35", "nd", "nd"]))["p2"] == 120)
        #expect(HandRules.fromHandPoints(multiplier: 1) == nil)
        #expect([2, 4, 8].map { HandRules.fromHandPoints(multiplier: $0) } == [50, 100, 200])
        // A mark left on a round of خلّص (a damaged save) adds nothing, nor on build 5's «حر».
        var stray = recorded(["out", "nd", "nd", "nd"])
        stray.cells["p2"]?.fromHand = true
        #expect(HandRules.points(stray)["p2"] == 100)
        #expect(HandRules.points(HandCell(kind: .free, free: -15, fromHand: true), multiplier: 2) == -15)
        // The نزول under «من إيده» still counts.
        let r = recorded(["hand", "+70", "nd", "nd"])
        #expect(HandRules.isDown(r.cells["p2"], in: r))
    }

    @Test("«معلن» goes on ما نزل: +100 for جيكر, +200 for جيكرين, whatever the finish, for any number of players")
    func declaredScores() {
        // The owner's example: a هند, the rest take 200, the معلن 200 + 100, and 200 + 200 for جيكرين.
        let r = recorded(["hand", "nd!", "nd!!", "nd"])
        #expect(HandRules.points(r) == ["p1": -60, "p2": 300, "p3": 400, "p4": 200])
        #expect(HandRules.points(recorded(["out", "nd!", "nd", "nd"]))["p2"] == 200)
        #expect(HandRules.points(recorded(["joker", "nd!!", "nd", "nd"]))["p2"] == 600)
        // With «من إيده» as well: 200 + 50 + 100.
        #expect(HandRules.points(recorded(["hand", "+nd!", "nd", "nd"]))["p2"] == 350)
        #expect([0, 1, 2].map(HandRules.declaredPoints) == [0, 100, 200])
        #expect(HandRules.declaredName(1) == "معلن جيكر" && HandRules.declaredName(2) == "معلن جيكرين")
        // It is never a نزول.
        #expect(!HandRules.isDown(r.cells["p2"], in: r))
        #expect(HandRules.points(EntryCell(kind: .notDown, declared: 1), multiplier: 2) == 300)
    }

    @Test("The «معلن» key: جيكر, then جيكرين, then off; the field goes to ما نزل; never on the finisher")
    func declaredKey() {
        var e = HandRules.choosing(.hand, entry: HandRules.emptyEntry(boardPlayers), focus: "p1", players: boardPlayers).entry
        #expect(HandRules.declaring(entry: e, focus: "p1") == nil)
        e = HandRules.typing("3", entry: e, focus: "p2") ?? e
        e = HandRules.declaring(entry: e, focus: "p2") ?? e
        #expect(e["p2"] == EntryCell(kind: .notDown, declared: 1))
        e = HandRules.declaring(entry: e, focus: "p2") ?? e
        #expect(e["p2"] == EntryCell(kind: .notDown, declared: 2))
        let off = HandRules.declaring(entry: e, focus: "p2")
        #expect(off?["p2"] == .notDown)
        // Two players at once, and «من إيده» stays.
        e = HandRules.togglingFromHand(entry: e, focus: "p3") ?? e
        e = HandRules.declaring(entry: e, focus: "p3") ?? e
        #expect(e["p3"] == EntryCell(kind: .notDown, fromHand: true, declared: 1))
        #expect(e["p2"]?.declared == 2)
        #expect(HandRules.points(HandRules.round(from: e, players: boardPlayers, id: 1)) == ["p1": -60, "p2": 400, "p3": 350, "p4": 200])
        // ما نزل again keeps it; a number typed takes it off; ⌫ empties the field and takes it off.
        let again = HandRules.choosing(.notDown, entry: e, focus: "p2", players: boardPlayers).entry
        #expect(again["p2"]?.declared == 2)
        let typedOver = HandRules.typing("5", entry: e, focus: "p2")
        #expect(typedOver?["p2"] == EntryCell(kind: .exact, digits: "5"))
        let erased = HandRules.erasing(entry: e, focus: "p3", players: boardPlayers, rounds: [], editing: nil)
        #expect(erased["p3"] == EntryCell(kind: nil, fromHand: true))
        // Becoming the finisher takes it off.
        let finisher = HandRules.choosing(.out, entry: e, focus: "p2", players: boardPlayers).entry
        #expect(finisher["p2"] == EntryCell(kind: .out))
        #expect(finisher["p1"] == .notDown)
    }

    @Test("Digits stay in the field, ± turns the sign before or after them, and ⌫ takes them off")
    func signKey() {
        var e = HandRules.choosing(.joker, entry: HandRules.emptyEntry(boardPlayers), focus: "p1", players: boardPlayers).entry
        #expect(HandRules.signing(entry: e, focus: "p1") == nil)
        // ± first on ما نزل: the field waits for its digits, and is not ready till then.
        e = HandRules.signing(entry: e, focus: "p2") ?? e
        #expect(e["p2"] == EntryCell(kind: .exact, negative: true))
        #expect(!status(e).ready)
        for d in "45" { e = HandRules.typing(d, entry: e, focus: "p2") ?? e }
        #expect(e["p2"]?.typedValue == -45)
        #expect(status(e).ready)
        e = HandRules.signing(entry: e, focus: "p2") ?? e
        #expect(e["p2"]?.typedValue == 45)
        // A finisher chosen after leaves the sign waiting for digits.
        var w = HandRules.signing(entry: HandRules.emptyEntry(boardPlayers), focus: "p3") ?? [:]
        w = HandRules.choosing(.hand, entry: w, focus: "p1", players: boardPlayers).entry
        #expect(w["p3"] == EntryCell(kind: .exact, negative: true))
        #expect(w["p2"] == .notDown && w["p4"] == .notDown)
        // ± again before a digit takes the sign back: ما نزل once a finisher is chosen, else empty; the mark stays.
        #expect(HandRules.signing(entry: w, focus: "p3")?["p3"] == .notDown)
        var bare = HandRules.emptyEntry(boardPlayers)
        bare["p2"] = EntryCell(kind: nil, fromHand: true)
        bare = HandRules.signing(entry: bare, focus: "p2") ?? bare
        #expect(HandRules.signing(entry: bare, focus: "p2")?["p2"] == EntryCell(kind: nil, fromHand: true))
        // A field with no digits and no sign (a damaged or old save) goes on ما نزل with the finisher, as an empty one.
        var blank = HandRules.emptyEntry(boardPlayers)
        blank["p2"] = EntryCell(kind: .free)
        #expect(HandRules.choosing(.hand, entry: blank, focus: "p1", players: boardPlayers).entry["p2"] == .notDown)
        // ⌫: a digit at a time, then ما نزل once a finisher is chosen.
        e = HandRules.erasing(entry: e, focus: "p2", players: boardPlayers, rounds: [], editing: nil)
        #expect(e["p2"] == EntryCell(kind: .exact, digits: "4"))
        e = HandRules.erasing(entry: e, focus: "p2", players: boardPlayers, rounds: [], editing: nil)
        #expect(e["p2"] == .notDown)
        // «من إيده» on a typed number, as on ما نزل.
        e = HandRules.typing("9", entry: e, focus: "p2") ?? e
        e = HandRules.togglingFromHand(entry: e, focus: "p2") ?? e
        #expect(e["p2"] == EntryCell(kind: .exact, digits: "9", fromHand: true))
        #expect(HandRules.points(e["p2"]!, multiplier: 4) == 109)
    }

    @Test("The «من إيده» key: off with خلّص, زات or no finisher, never on the finisher, one player in a round")
    func fromHandKey() {
        var e = HandRules.emptyEntry(boardPlayers)
        #expect(HandRules.togglingFromHand(entry: e, focus: "p2") == nil)
        e = HandRules.choosing(.out, entry: e, focus: "p1", players: boardPlayers).entry
        #expect(HandRules.togglingFromHand(entry: e, focus: "p2") == nil)
        e = HandRules.choosing(.hand, entry: e, focus: "p1", players: boardPlayers).entry
        #expect(HandRules.togglingFromHand(entry: e, focus: "p1") == nil)
        e = HandRules.togglingFromHand(entry: e, focus: "p2") ?? e
        #expect(e["p2"]?.fromHand == true)
        e = HandRules.togglingFromHand(entry: e, focus: "p3") ?? e
        #expect(e["p3"]?.fromHand == true && e["p2"]?.fromHand == false)
        // ⌫ on the finisher leaves no finisher for a moment: the mark stays; جيكر next counts it, 400 + 100.
        let erased = HandRules.erasing(entry: e, focus: "p1", players: boardPlayers, rounds: [], editing: nil)
        #expect(erased["p3"]?.fromHand == true)
        let joker = HandRules.choosing(.joker, entry: erased, focus: "p1", players: boardPlayers).entry
        #expect(HandRules.points(HandRules.round(from: joker, players: boardPlayers, id: 1))["p3"] == 500)
        // زات leaves the other fields and their mark as they were, faded and closed; none of it goes in.
        let zat = HandRules.choosing(.zat, entry: e, focus: "p4", players: boardPlayers).entry
        #expect(zat["p3"]?.fromHand == true && zat["p1"] == .notDown)
        #expect(HandRules.togglingFromHand(entry: zat, focus: "p3") == nil)
        #expect(!HandRules.round(from: zat, players: boardPlayers, id: 1).cells.values.contains { $0.fromHand })
    }

    @Test("زات: the other fields stay as typed, faded and closed; «سجّل» at once; the round counts nothing and wins")
    func zat() {
        var e = typed(["hand", "35", "nd!", "+nd"])
        let r = HandRules.choosing(.zat, entry: e, focus: "p3", players: boardPlayers)
        e = r.entry
        #expect(r.focus == "p3")
        // The finisher before it goes on ما نزل; the others keep what they had, the mark too.
        #expect(e == ["p1": .notDown, "p2": EntryCell(kind: .exact, digits: "35"), "p3": EntryCell(kind: .zat),
                      "p4": EntryCell(kind: .notDown, fromHand: true)])
        let st = status(e)
        #expect(st.ready && st.finisher == "p3" && st.over.isEmpty && st.multiplier == 1)
        // The other fields take nothing: no digit, ±, ⌫, ما نزل, «معلن» or «من إيده».
        #expect(HandRules.zatElsewhere(e, focus: "p2") && !HandRules.zatElsewhere(e, focus: "p3"))
        #expect(HandRules.typing("7", entry: e, focus: "p2") == nil)
        #expect(HandRules.signing(entry: e, focus: "p2") == nil)
        #expect(HandRules.declaring(entry: e, focus: "p1") == nil)
        #expect(HandRules.togglingFromHand(entry: e, focus: "p4") == nil)
        #expect(HandRules.erasing(entry: e, focus: "p2", players: boardPlayers, rounds: [], editing: nil) == e)
        #expect(HandRules.choosing(.notDown, entry: e, focus: "p2", players: boardPlayers).entry == e)
        #expect(!HandRules.isDown(e["p2"], in: e))
        // It goes in with nothing but the زات, and counts nothing; nor would a number a damaged save put in it.
        let z = HandRules.round(from: e, players: boardPlayers, id: 20)
        #expect(z.cells == ["p1": HandCell(kind: .cards, cards: 0), "p2": HandCell(kind: .cards, cards: 0),
                            "p3": HandCell(kind: .zat), "p4": HandCell(kind: .cards, cards: 0)])
        #expect(HandRules.points(z).values.allSatisfy { $0 == 0 })
        var stray = z
        stray.cells["p2"] = HandCell(kind: .exact, free: 35)
        #expect(HandRules.points(stray)["p2"] == 0)
        // The board's midgame, then فهد gets زات: the game ends there, totals as they were.
        let mid = Array(boardRounds.prefix(3))
        let rounds = mid + [z]
        #expect(HandRules.outcome(players: boardPlayers, rounds: rounds) == .won("p3"))
        #expect(HandRules.totals(players: boardPlayers, rounds: rounds) == ["p1": 100, "p2": 75, "p3": 270, "p4": 322])
        #expect(HandRules.winSpeech(players: boardPlayers, rounds: rounds, winner: "p3") == "فهد جاب زات، والفوز لفهد")
        #expect(HandRules.homeLine(players: boardPlayers, rounds: rounds) == "الفوز لفهد")
        #expect(HandRules.roundLine(rounds: rounds, outcome: .won("p3")) == "")
        #expect(HandRules.announcement(players: boardPlayers, before: mid, after: rounds, gained: z) == nil)
        // A نزول typed before it is none in that round.
        #expect(status(e, rounds: mid).over.isEmpty)
        // ⌫ on زات takes it off, and the others count again.
        let off = HandRules.erasing(entry: e, focus: "p3", players: boardPlayers, rounds: [], editing: nil)
        #expect(off["p3"] == .empty && !HandRules.hasZat(off) && HandRules.isDown(off["p2"], in: off))
        // Another finish chosen after it sends زات back to ما نزل and brings the others back as they were: the mark
        // with هند, not with خلّص.
        let back = HandRules.choosing(.hand, entry: e, focus: "p1", players: boardPlayers).entry
        #expect(back == ["p1": EntryCell(kind: .hand), "p2": EntryCell(kind: .exact, digits: "35"), "p3": .notDown,
                         "p4": EntryCell(kind: .notDown, fromHand: true)])
        let out = HandRules.choosing(.out, entry: e, focus: "p1", players: boardPlayers).entry
        #expect(out["p3"] == .notDown && out["p4"] == .notDown && out["p1"] == EntryCell(kind: .out))
        // Deleting the round of زات plays on; an edit that turns it to خلّص too.
        #expect(HandRules.outcome(players: boardPlayers, rounds: mid) == .playing)
        // زات goes in a new round or the newest one being edited, not in an older one.
        #expect(HandRules.zatOpen(rounds: rounds, editing: nil))
        #expect(HandRules.zatOpen(rounds: rounds, editing: 20))
        #expect(!HandRules.zatOpen(rounds: rounds, editing: mid[2].id))
        // The first round of زات decides, whatever comes after it.
        let second = HandRules.round(from: typed(["zat", "", "", ""]), players: boardPlayers, id: 21)
        #expect(HandRules.zatWinner(players: boardPlayers, rounds: rounds + [second]) == "p3")
    }

    @Test("A round with numbers, signs, زات, «من إيده» and «معلن» goes to the fields and back unchanged")
    func roundTrip() {
        for spec in [["joker", "-15", "0", "+42"], ["hand", "nd!!", "+nd!", "70"], ["zat", "", "", ""], ["out", "free:-15", "nd", "7"]] {
            let e = typed(spec)
            let r = HandRules.round(from: e, players: boardPlayers, id: 7)
            let back = HandRules.entry(from: r, players: boardPlayers)
            #expect(HandRules.round(from: back, players: boardPlayers, id: 7) == r)
        }
        // An old round's cards come back as the number they came to, × the round: the same points and نزول.
        let old = recorded(["hand", "nd!!", "nd!", "+c:35"])
        let fields = HandRules.entry(from: old, players: boardPlayers)
        #expect(fields["p4"] == EntryCell(kind: .exact, digits: "70", fromHand: true))
        let again = HandRules.round(from: fields, players: boardPlayers, id: 1)
        #expect(HandRules.points(again) == HandRules.points(old))
        #expect(HandRules.isDown(again.cells["p4"], in: again) && HandRules.isDown(old.cells["p4"], in: old))
        // So do cards in a round being typed when the app updated (× its finisher), and ± and ⌫ treat them as any
        // number typed.
        let carried = HandRules.typedCards(typed(["joker", "c:12", "c:0", "nd"]))
        #expect(carried == ["p1": EntryCell(kind: .joker), "p2": EntryCell(kind: .exact, digits: "48"), "p3": .empty, "p4": .notDown])
        #expect(HandRules.signing(entry: carried, focus: "p2")?["p2"]?.typedValue == -48)
        let r = recorded(["joker", "-15", "nd!!", "+42"])
        #expect(r.cells["p2"] == HandCell(kind: .exact, free: -15))
        #expect(r.cells["p3"] == HandCell(kind: .notDown, declared: 2))
        #expect(r.cells["p4"] == HandCell(kind: .exact, free: 42, fromHand: true))
        // Nothing typed (the others in a round of زات) is no number.
        #expect(recorded(["zat", "", "", ""]).cells["p2"] == HandCell(kind: .cards, cards: 0))
    }

    @Test("Saves from before build 6 read as they were, new keys only when set, and new ones read back")
    func saves() throws {
        let old = #"{"players":[{"id":"p1","name":"حمد"},{"id":"p2","name":"أنور"}],"rounds":[{"id":1,"cells":{"p1":{"kind":"hand","cards":0},"p2":{"kind":"num","cards":35}}},{"id":2,"cells":{"p1":{"kind":"free","cards":0,"free":-15},"p2":{"kind":"out","cards":0}}}],"entry":{"p1":{"kind":"out","digits":""},"p2":{"kind":"free","digits":"5","negative":true}},"uid":102,"started":true}"#
        let back = try #require(HandSave.read(Data(old.utf8)))
        #expect(back.rounds[0].cells["p2"] == HandCell(kind: .cards, cards: 35))
        #expect(back.rounds[1].cells["p1"] == HandCell(kind: .free, free: -15))
        #expect(back.entry["p2"] == EntryCell(kind: .free, digits: "5", negative: true))
        #expect(!back.mended)
        #expect(HandRules.totals(players: back.players, rounds: back.rounds) == ["p1": -75, "p2": 40])
        // A plain cell is saved as before.
        let plain = String(decoding: try JSONEncoder().encode(HandCell(kind: .notDown)), as: UTF8.self)
        #expect(!plain.contains("free") && !plain.contains("fromHand") && !plain.contains("declared"))
        let number = String(decoding: try JSONEncoder().encode(HandCell(kind: .exact, free: 35)), as: UTF8.self)
        #expect(number.contains("\"free\":35") && number.contains("\"exact\""))
        // Numbers, زات and both marks, in rounds and in the round being typed.
        let rounds = [recorded(["hand", "+70", "nd!", "-15"], id: 1), recorded(["zat", "", "", ""], id: 2)]
        let entry = typed(["joker", "+nd!!", "150", ""])
        let save = HandSave(players: boardPlayers, rounds: rounds, entry: entry, uid: 102, started: true)
        let again = try #require(HandSave.read(try JSONEncoder().encode(save)))
        #expect(again == save)
        #expect(!again.mended)
    }

    @Test("A damaged save keeps the marks where they can be, numbers within four digits, and one finisher")
    func repairs() throws {
        // «معلن» on a number or a finish goes, and so does one that is not 1 or 2.
        var r = recorded(["hand", "35", "nd", "nd"])
        r.cells["p1"]?.declared = 1
        r.cells["p2"]?.declared = 2
        r.cells["p3"]?.declared = 7
        r.cells["p4"]?.declared = 2
        // The round being typed: a second finisher (زات), a number past four digits, a 0 in front, «معلن» on a
        // number and one out of range on ما نزل.
        var e = HandRules.emptyEntry(boardPlayers)
        e["p1"] = EntryCell(kind: .hand)
        e["p2"] = EntryCell(kind: .zat)
        e["p3"] = EntryCell(kind: .exact, digits: "12345", declared: 1)
        e["p4"] = EntryCell(kind: .notDown, declared: 9)
        let fixed = try #require(HandSave(players: boardPlayers, rounds: [r], entry: e, uid: 101, started: true).repaired())
        #expect(fixed.mended)
        #expect(boardPlayers.map { fixed.rounds[0].cells[$0.id]?.declared ?? -1 } == [0, 0, 0, 2])
        #expect(HandRules.points(fixed.rounds[0]) == ["p1": -60, "p2": 35, "p3": 200, "p4": 400])
        #expect(fixed.entry == ["p1": EntryCell(kind: .hand), "p2": .empty, "p3": .empty, "p4": .notDown])
        // A lone 0, a sign waiting for digits, and «معلن» on ما نزل stay.
        var ok = HandRules.emptyEntry(boardPlayers)
        ok["p1"] = EntryCell(kind: .exact, digits: "0")
        ok["p2"] = EntryCell(kind: .exact, negative: true)
        ok["p3"] = EntryCell(kind: .notDown, declared: 2)
        ok["p4"] = EntryCell(kind: .exact, digits: "05")
        let kept = try #require(HandSave(players: boardPlayers, rounds: [], entry: ok, uid: 101, started: true).repaired())
        #expect(kept.entry["p1"] == EntryCell(kind: .exact, digits: "0"))
        #expect(kept.entry["p2"] == EntryCell(kind: .exact, negative: true))
        #expect(kept.entry["p3"] == EntryCell(kind: .notDown, declared: 2))
        #expect(kept.entry["p4"] == .empty)
        // One «من إيده» a round, the first in seat order that can have it.
        var m = recorded(["hand", "free:-15", "nd", "70"])
        for id in ["p1", "p2", "p3", "p4"] { m.cells[id]?.fromHand = true }
        let one = try #require(HandSave(players: boardPlayers, rounds: [m], entry: HandRules.emptyEntry(boardPlayers), uid: 101, started: true).repaired())
        #expect(boardPlayers.map { one.rounds[0].cells[$0.id]?.fromHand == true } == [false, false, true, false])
    }
}
