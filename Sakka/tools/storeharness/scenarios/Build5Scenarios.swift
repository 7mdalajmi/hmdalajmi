import Foundation
import SwiftUI

// Scenarios for build 5 (21 Oct 2026), as build 6 (22 Oct) has them: «من إيده» in الهند, and «حر», which became
// the way every number is typed. «من إيده» adds 25 × the multiplier on top of a player's score (50 هند, 100 جيكر,
// 200 جيكرين), not with خلّص, one player a round; ما نزل in a هند is 200 + 50 = 250. A number is typed as it is,
// plus or minus, up to four digits, and stays in its field; from 1 up to below ما نزل it is a نزول.

func runBuild5Scenarios() {
    handFromHand()
    handFree()
    handFieldsKept()
}

private func startBoardPlayers(_ tag: String) -> (UserDefaults, AppModel, HandScreen) {
    let d = freshDefaults(tag)
    let app = launch(d)
    let s = HandScreen(app: app)
    s.open()
    for (i, n) in boardNames.enumerated() { s.setupName(i, n) }
    s.setupStart()
    return (d, app, s)
}

private func fromHandMarks(_ h: HandStore) -> [Bool] { h.players.map { h.entry[$0.id]?.fromHand == true } }

private func handFromHand() {
    Report.begin("Hand 26 · «من إيده» (build 5): 25 × the multiplier on top, only with هند, جيكر or جيكرين, one player a round, kept through a relaunch and dropped by an edit to خلّص; numbers typed as they are (build 6)")
    let (d, app, s) = startBoardPlayers("h26")
    let h = app.hand
    s.tapField(1)
    let offWithoutFinisher = !s.canPress(.fromHand)
    s.tapField(0)
    s.press(.finish(.hand))
    s.tapField(0)
    let offOnFinisher = !s.canPress(.fromHand)
    s.tapField(1)
    s.digits("70")
    s.press(.fromHand)
    let caption = HandRules.points(h.entry[s.id(1)] ?? .empty, multiplier: h.status.multiplier)
    step("حمد هند, أنور 70 (his 35 cards × 2) with «من إيده»: the field comes to 70 + 50 = 120; the key is off before a finisher and on the finisher") { c in
        c.eq(offWithoutFinisher, true, "off with no finisher")
        c.eq(offOnFinisher, true, "off on حمد's field")
        c.eq(fromHandMarks(h), [false, true, false, false], "marks")
        c.eq(caption, 120, "أنور's caption")
    }
    s.press(.record)
    s.wait(3300)
    step("…recorded: −60, 120, 200, 200, and أنور's نزول still counts") { c in
        c.eq(h.rounds.count, 1, "rounds")
        c.eq(s.totals, [-60, 120, 200, 200], "totals")
        c.eq(s.downs, [0, 1, 0, 0], "downs")
    }

    s.tapField(3)
    s.press(.finish(.hand))
    s.tapField(2)
    s.press(.fromHand)
    s.tapField(1)
    s.press(.fromHand)
    let moved = fromHandMarks(h)
    s.tapField(1)
    s.press(.fromHand)
    let none = fromHandMarks(h)
    s.tapField(2)
    s.press(.fromHand)
    s.press(.record)
    s.wait(3300)
    step("سالم هند, «من إيده» to فهد then to أنور (one player a round), off, back on فهد on ما نزل: 200 + 50 = 250") { c in
        c.eq(moved, [false, true, false, false], "moved to أنور")
        c.eq(none, [false, false, false, false], "off again")
        c.eq(HandRules.points(h.rounds[1]).sorted { $0.key < $1.key }.map(\.value), [200, 200, 250, -60], "round 2")
        c.eq(s.totals, [140, 320, 450, 140], "totals")
    }

    s.tapField(0)
    s.press(.finish(.out))
    s.tapField(1)
    let offWithOut = !s.canPress(.fromHand)
    s.press(.record)
    s.wait(3300)
    s.tapField(1)
    s.press(.finish(.joker))
    s.tapField(2)
    s.digits("80")
    s.press(.fromHand)
    s.press(.record)
    s.wait(3300)
    step("حمد خلّص: «من إيده» is off; then أنور جيكر and فهد 80 with «من إيده»: 80 + 100 = 180, and 9 rounds") { c in
        c.eq(offWithOut, true, "off with خلّص")
        c.eq(HandRules.points(h.rounds[3]).sorted { $0.key < $1.key }.map(\.value), [400, -120, 180, 400], "round 4")
        c.eq(s.totals, [510, 300, 730, 640], "totals")
        c.eq(HandRules.target(h.rounds), 9, "rounds in the game")
    }

    let app2 = launch(d)
    let s2 = HandScreen(app: app2)
    step("a relaunch brings the rounds back with their «من إيده»") { c in
        c.eq(app2.hand.rounds, h.rounds, "rounds")
        c.eq(s2.totals, [510, 300, 730, 640], "totals")
    }

    let r4 = app2.hand.rounds[3]
    s2.tapRow(r4)
    s2.tapEdit(r4)
    s2.tapField(1)
    s2.press(.finish(.out))
    let dropped = fromHandMarks(app2.hand)
    s2.press(.record)
    s2.wait(3300)
    step("«تعديل» on round 4 from جيكر to خلّص drops فهد's «من إيده»: his 80 stays 80, typed as it is, and back to 7 rounds") { c in
        c.eq(dropped, [false, false, false, false], "marks in the edit")
        c.eq(HandRules.points(app2.hand.rounds[3]).sorted { $0.key < $1.key }.map(\.value), [100, -30, 80, 100], "round 4")
        c.eq(s2.totals, [210, 390, 630, 340], "totals")
        c.eq(HandRules.target(app2.hand.rounds), 7, "rounds in the game")
    }
}

private func handFree() {
    Report.begin("Hand 27 · numbers as typed (build 6, was «حر»): plus or minus, four digits, the focus stays, a نزول below ما نزل; ± off on the finisher")
    let (d, app, s) = startBoardPlayers("h27")
    let h = app.hand
    s.tapField(0)
    s.press(.finish(.hand))
    s.tapField(0)
    let offOnFinisher = !s.canPress(.sign)
    s.tapField(1)
    s.digits("150")
    let stayed = h.focus == s.id(1)
    s.digits("49")
    let four = h.entry[s.id(1)]?.digits
    s.press(.erase)
    s.tapField(2)
    s.digits("15")
    s.press(.sign)
    let minus = h.entry[s.id(2)]?.typedValue
    s.press(.record)
    s.wait(3300)
    step("حمد هند, أنور 150, فهد 15 then ±: −60, 150, −15, 200; 150 is below ما نزل's 200, a نزول, and −15 is not") { c in
        c.eq(offOnFinisher, true, "± off on حمد's field")
        c.eq(stayed, true, "three digits stay in أنور's field")
        c.eq(four, "1504", "a fifth digit is not taken")
        c.eq(minus, -15, "± turns فهد's sign")
        c.eq(s.totals, [-60, 150, -15, 200], "totals")
        c.eq(s.downs, [0, 1, 0, 0], "downs")
    }

    let r1 = h.rounds[0]
    s.tapRow(r1)
    s.tapEdit(r1)
    let inFields = (h.entry[s.id(1)]?.typedValue, h.entry[s.id(2)]?.typedValue)
    s.tapField(2)
    s.press(.sign)
    s.press(.record)
    s.wait(3300)
    step("«تعديل» opens the numbers as typed, and ± there makes فهد +15, now a نزول too") { c in
        c.eq(inFields.0, 150, "أنور in the edit")
        c.eq(inFields.1, -15, "فهد in the edit")
        c.eq(s.totals, [-60, 150, 15, 200], "totals")
        c.eq(s.downs, [0, 1, 1, 0], "downs")
    }

    s.tapField(0)
    s.press(.finish(.joker2))
    s.tapField(1)
    s.press(.sign)
    s.digits("15")
    s.tapField(2)
    s.press(.fromHand)
    s.tapField(3)
    s.digits("0")
    s.press(.record)
    s.wait(3300)
    let app2 = launch(d)
    step("حمد جيكرين, أنور ± then 15, فهد ما نزل with «من إيده», سالم 0: −240, −15, 800 + 200, 0; all back after a relaunch") { c in
        c.eq(HandRules.points(h.rounds[1]).sorted { $0.key < $1.key }.map(\.value), [-240, -15, 1000, 0], "round 2")
        c.eq(s.totals, [-300, 135, 1015, 200], "totals")
        c.eq(app2.hand.rounds, h.rounds, "rounds after the relaunch")
    }
}

private func handFieldsKept() {
    Report.begin("Hand 28 · build 5 after the review, as build 6 has it: a sign waiting for digits stays when the finisher is chosen; «من إيده» stays through ⌫ on the finisher and can come off; a relaunch and «إلغاء» bring back the numbers and «من إيده» in the fields")
    let (d, app, s) = startBoardPlayers("h28")
    let h = app.hand
    s.tapField(1)
    s.press(.sign)
    s.tapField(0)
    s.press(.finish(.hand))
    let kept = h.entry[s.id(1)]
    let focusOnHim = h.focus == s.id(1)
    s.digits("15")
    s.press(.record)
    s.wait(3300)
    step("أنور ± before any digit, then حمد هند: أنور keeps the minus, the focus goes to him, and 15 records −15, no نزول") { c in
        c.eq(kept, EntryCell(kind: .exact, negative: true), "أنور's field")
        c.eq(focusOnHim, true, "focus")
        c.eq(s.totals, [-60, -15, 200, 200], "totals")
        c.eq(s.downs, [0, 0, 0, 0], "downs")
    }

    s.tapField(2)
    s.press(.finish(.hand))
    s.tapField(3)
    s.press(.fromHand)
    s.tapField(2)
    s.press(.erase)
    let noFinisher = h.status.finisher == nil
    let stillMarked = h.entry[s.id(3)]?.fromHand == true
    s.tapField(3)
    let canTakeOff = s.canPress(.fromHand)
    s.tapField(2)
    s.press(.finish(.joker))
    s.press(.record)
    s.wait(3300)
    step("فهد هند, «من إيده» on سالم, ⌫ on فهد and then جيكر: the mark stays (and could come off) and goes in as 400 + 100 = 500") { c in
        c.eq(noFinisher, true, "no finisher after ⌫")
        c.eq(stillMarked, true, "سالم keeps the mark")
        c.eq(canTakeOff, true, "the key can take it off")
        c.eq(HandRules.points(h.rounds[1]).sorted { $0.key < $1.key }.map(\.value), [400, 400, -120, 500], "round 2")
        c.eq(s.totals, [340, 385, 80, 700], "totals")
    }

    s.tapField(0)
    s.press(.finish(.joker2))
    s.tapField(1)
    s.digits("7")
    let focusStays = h.focus == s.id(1)
    s.tapField(2)
    s.press(.fromHand)
    let typed = h.entry
    let app2 = launch(d)
    let s2 = HandScreen(app: app2)
    let h2 = app2.hand
    let back = h2.entry
    step("حمد جيكرين, أنور 7, «من إيده» on فهد, and the app closed: a relaunch brings the fields back as they were") { c in
        c.eq(focusStays, true, "the focus stays on أنور after his digit")
        c.eq(back, typed, "fields after the relaunch")
        c.eq(h2.status.ready, true, "ready")
    }

    s2.tapField(0)
    s2.press(.record)
    s2.wait(3300)
    step("…and it goes in: −240, 7 (a نزول, below 800), 800 + 200 = 1000, 800") { c in
        c.eq(HandRules.points(h2.rounds[2]).sorted { $0.key < $1.key }.map(\.value), [-240, 7, 1000, 800], "round 3")
        c.eq(s2.totals, [100, 392, 1080, 1500], "totals")
    }

    s2.tapField(3)
    s2.press(.finish(.hand))
    s2.tapField(0)
    s2.press(.fromHand)
    let typing = h2.entry
    let r3 = h2.rounds[2]
    s2.tapRow(r3)
    s2.tapEdit(r3)
    let editing = h2.entry
    s2.tapCancelEdit()
    step("سالم هند with «من إيده» on حمد being typed, then «تعديل» of round 3 and «إلغاء»: the edit shows round 3's number and mark, and the round being typed comes back with حمد's mark") { c in
        c.eq(editing[s2.id(1)], EntryCell(kind: .exact, digits: "7"), "أنور in the edit")
        c.eq(editing[s2.id(2)], EntryCell(kind: .notDown, fromHand: true), "فهد in the edit")
        c.eq(h2.entry, typing, "the round being typed after «إلغاء»")
        c.eq(h2.entry[s2.id(0)]?.fromHand, true, "حمد's mark")
    }
}
