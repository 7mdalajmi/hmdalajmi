import Foundation
import SwiftUI

// Scenarios for what build 4 changed (the coordinator's list of 9 Oct 2026, items 2–10). Items 2, 3, 9 (صكة) and 10
// also changed Baloot 1, 4b, 10, 13 and 14, and item 6 changed the board flow main_joker_undo in Hand 4.
// Expected values: the boards and cards, with build 4's decisions as the coordinator stated them.

func runBuild4Scenarios() {
    balootLeaveDropsWinLine()
    handLeaveDropsWinLine()
    voiceOverEscape()
    handTypedRoundKept()
    handEditKeepsItsDowns()
    handFinisherWithTieOrLastRound()
    handAlertClearedByARound()
    handDamagedSaves()
    voiceChip()
}

// MARK: Item 4, صكة: leaving drops a win line not yet said

private func balootLeaveDropsWinLine() {
    Report.begin("Baloot 17 · leaving for the home page drops a win line not yet said (build 4); the win screen's parts still come in")
    do {
        let d = freshDefaults("b17a")
        let app = launch(d)
        let s = BalootScreen(app: app)
        let b = app.baloot
        s.recordHand(94, 95)
        s.wait(1100)
        let m = app.speaker.mark
        let t0 = VirtualClock.now
        s.recordHand(0, 60)
        s.wait(1900)
        let tapped = s.tapHome()
        s.wait(3000)
        step("the chevron on the win screen at +1900 ms (its voice due at +2370): nothing is said, then or later") { c in
            c.eq(tapped, true, "chevron on the win screen")
            c.eq(app.speaker.spoken(since: m).count, 0, "voice")
            c.eq(fired("baloot", from: t0, to: t0 + 5000, keys: ["voice"]), [], "voice timer")
            c.eq(b.posterVisible && b.intro, true, "the win screen with its parts, for when the player comes back")
        }
    }
    do {
        let d = freshDefaults("b17b")
        let app = launch(d)
        let s = BalootScreen(app: app)
        let b = app.baloot
        s.recordHand(94, 95)
        s.wait(1100)
        let m = app.speaker.mark
        let t0 = VirtualClock.now
        s.recordHand(0, 60)
        s.wait(1865)
        let tapped = s.tapHome()
        s.wait(25)
        let introAt1890 = b.intro
        s.wait(3000)
        step("the chevron between the win screen (+1860) and its parts (+1890): the parts still come in at +1890, no voice") { c in
            c.eq(tapped, true, "chevron")
            c.eq(introAt1890, true, "intro at +1890")
            c.eq(app.speaker.spoken(since: m).count, 0, "voice")
            c.eq(VirtualClock.fired.last { $0.owner == "baloot" && $0.key == "intro" }?.time, t0 + 1890, "intro time")
        }
    }
    do {
        let d = freshDefaults("b17c")
        let app = launch(d)
        let s = BalootScreen(app: app)
        s.recordHand(94, 95)
        s.wait(1100)
        let m = app.speaker.mark
        s.recordHand(0, 60)
        s.wait(2500)
        let tapped = s.tapHome()
        step("the chevron after the voice (+2500): the line was said once; leaving changes nothing") { c in
            c.eq(tapped, true, "chevron")
            c.eq(app.speaker.spoken(since: m).map(\.text), ["الصكة لهم"], "voice")
        }
    }
}

// MARK: Item 4, الهند: the same

private func handLeaveDropsWinLine() {
    Report.begin("Hand 20 · leaving for the home page drops a win line not yet said (build 4)")
    let (_, app, s) = handBoardGameReady("h20")
    let h = app.hand
    let m = app.speaker.mark
    let t0 = VirtualClock.now
    s.record(boardRounds[8])
    s.wait(1900)
    let tapped = s.tapHome()
    s.wait(3000)
    step("the chevron on the win screen at +1900 ms: «الفوز لحمد» is never said; the win screen stays with its parts") { c in
        c.eq(tapped, true, "chevron")
        c.eq(app.speaker.spoken(since: m).count, 0, "voice")
        c.eq(fired("hand", from: t0, to: t0 + 5000, keys: ["voice"]), [], "voice timer")
        c.eq(h.posterVisible && h.intro, true, "win screen")
    }
}

/// The board's first eight rounds, recorded and settled: the next one (boardRounds[8]) wins for حمد.
private func handBoardGameReady(_ tag: String) -> (UserDefaults, AppModel, HandScreen) {
    let d = freshDefaults(tag)
    let app = launch(d)
    let s = HandScreen(app: app)
    s.open()
    for (i, n) in boardNames.enumerated() { s.setupName(i, n) }
    s.setupStart()
    for r in boardRounds.prefix(8) {
        s.record(r)
        s.wait(3300)
    }
    return (d, app, s)
}

private func playBoardMidgame(_ tag: String) -> (UserDefaults, AppModel, HandScreen) {
    let d = freshDefaults(tag)
    let app = launch(d)
    let s = HandScreen(app: app)
    s.open()
    for (i, n) in boardNames.enumerated() { s.setupName(i, n) }
    s.setupStart()
    for r in boardRounds.prefix(3) {
        s.record(r)
        s.wait(3300)
    }
    return (d, app, s)
}

// MARK: Item 4 through VoiceOver's escape

/// RootView.swift:114 (commit 131e012): `.accessibilityAction(.escape) { leaveGame() }`, and leaveGame() calls the open
/// game's store.leave(), puts the keyboard down, then goHome(). RootView is not compiled here: the screens' escape()
/// is that path (store.leave(), keyboard down; the page closing calls nothing more).
private func voiceOverEscape() {
    Report.begin("Leaving 2 · VoiceOver's escape (two-finger Z) leaves a game as the chevron does (RootView.leaveGame, commit 131e012)")
    do {
        let d = freshDefaults("esc-b")
        let app = launch(d)
        let s = BalootScreen(app: app)
        s.recordHand(94, 95)
        s.wait(1100)
        let m = app.speaker.mark
        s.recordHand(0, 60)
        s.wait(1900)
        s.escape()
        s.wait(3000)
        step("صكة: escape on the win screen at +1900 ms (its voice due at +2370): nothing is said on the home page") { c in
            c.eq(app.speaker.spoken(since: m).map(\.text), [], "voice after leaving")
            c.eq(app.baloot.posterVisible && app.baloot.intro, true, "the win screen, for when the player comes back")
        }
    }
    do {
        let d = freshDefaults("esc-b2")
        let app = launch(d)
        let s = BalootScreen(app: app)
        let b = app.baloot
        s.recordHand(94, 95)
        s.wait(1100)
        let m = app.speaker.mark
        let t0 = VirtualClock.now
        s.recordHand(0, 60)
        s.wait(500)
        s.escape()
        s.wait(4000)
        step("صكة: escape 500 ms into the win sequence (the chevron is hidden then, the escape is not): the sequence runs on to its win screen, and its line is never said") { c in
            c.eq(VirtualClock.fired.first { $0.owner == "baloot" && $0.key == "poster" && $0.time >= t0 }?.time, t0 + 1860, "win screen time")
            c.eq(b.posterVisible && b.intro, true, "win screen with its parts")
            c.eq(app.speaker.spoken(since: m).map(\.text), [], "voice")
        }
    }
    do {
        let d = freshDefaults("esc-b3")
        let app = launch(d)
        let s = BalootScreen(app: app)
        let b = app.baloot
        s.recordHand(10, 6)
        s.recordHand(0, 26)
        s.wait(1100)
        s.tapNewGame()
        s.tapTrash(s.rows[0])
        s.tapField(.us)
        s.type("5")
        s.escape()
        step("صكة: escape with «متأكد؟», «احذف؟» and the keyboard up: all three go, the صكة stays") { c in
            c.eq(b.confirmNew, false, "«متأكد؟»")
            c.eq(b.confirmId == nil, true, "«احذف؟»")
            c.eq(s.focus == nil, true, "keyboard")
            c.eq(b.hands.count, 2, "hands")
        }
    }
    do {
        let (_, app, s) = playBoardMidgame("esc-h")
        let h = app.hand
        s.tapField(1)
        s.digits("4")
        s.escape()
        step("الهند: escape with the keypad up: the keypad goes, the typed round stays") { c in
            c.eq(h.padOn, false, "keypad")
            c.eq(h.entry[s.id(1)], EntryCell(kind: .exact, digits: "4"), "typed round")
        }
        s.tapRow(h.rounds[2])
        s.tapDelete(h.rounds[2])
        s.escape()
        step("الهند: escape with a row open on «احذف؟»: the row closes, the round stays") { c in
            c.eq(h.selected == nil && h.confirmId == nil, true, "row")
            c.eq(h.rounds.count, 3, "rounds")
        }
    }
    do {
        let (_, app, s) = handBoardGameReady("esc-h2")
        let m = app.speaker.mark
        s.record(boardRounds[8])
        s.wait(1900)
        s.escape()
        s.wait(3000)
        step("الهند: escape on the win screen at +1900 ms: «الفوز لحمد» is never said") { c in
            c.eq(app.speaker.spoken(since: m).map(\.text), [], "voice")
            c.eq(app.hand.posterVisible, true, "win screen")
        }
    }
}

// MARK: Item 5: the round being typed is kept as it changes

private func handTypedRoundKept() {
    Report.begin("Hand 21 · the round being typed is saved with every key (build 4): a relaunch brings the fields back as they were left, never an edited round as a new one")
    do {
        let (d, app, s) = playBoardMidgame("h21a")
        s.tapField(0)
        s.press(.finish(.out))
        s.digits("25")
        let typed = entryText(app.hand.entry, app.hand.players)
        s.tapHome()
        let app2 = launch(d)
        step("حمد خلّص, أنور 25, the app closed: the next launch shows the same fields") { c in
            c.eq(entryText(app2.hand.entry, app2.hand.players), typed, "fields")
            c.eq(app2.hand.rounds.count, 3, "rounds")
        }
        let s2 = HandScreen(app: app2)
        s2.tapField(1)
        s2.press(.notDown)
        let before = app2.hand.rounds.count
        s2.press(.record)
        step("…and that round can be finished and recorded once") { c in
            c.eq(app2.hand.rounds.count, before + 1, "rounds")
            c.eq(s2.totals, [70, 175, 370, 422], "totals")
        }
    }
    do {
        let (d, app, s) = playBoardMidgame("h21b")
        s.tapField(1)
        s.digits("4")
        let r2 = app.hand.rounds[2]
        s.tapRow(r2)
        s.tapEdit(r2)
        s.tapField(2)
        s.press(.finish(.joker))
        let editing = app.hand.editId
        let app2 = launch(d)
        step("the app closed in the middle of «تعديل» (round 3 changed but not saved): the rounds as they were, the fields hold the round typed before, أنور 4") { c in
            c.eq(editing, r2.id, "was editing")
            c.eq(app2.hand.rounds, app.hand.rounds, "rounds unchanged")
            c.eq(entryText(app2.hand.entry, app2.hand.players), "حمد — · أنور 4 · فهد — · سالم —", "fields")
            c.eq(app2.hand.editId == nil, true, "no edit open")
        }
    }
    do {
        let (d, app, s) = handBoardGameReady("h21c")
        s.record(boardRounds[8])
        s.wait(3000)
        s.tapPosterEdit()
        s.tapField(0)
        s.digits("12")
        s.tapField(0)
        s.digits("0")
        let app2 = launch(d)
        step("«تعديل» on the win screen and a number typed, then the app closed: it reopens on the win screen with empty fields, not round 9 again") { c in
            c.eq(app2.hand.rounds.count, 9, "rounds")
            c.eq(app2.hand.posterVisible, true, "win screen")
            c.eq(entryText(app2.hand.entry, app2.hand.players), "حمد — · أنور — · فهد — · سالم —", "fields")
        }
        _ = app
    }
}

// MARK: Item 6: an edit refuses only a نزول it adds

private func handEditKeepsItsDowns() {
    Report.begin("Hand 22 · an edit refuses only a نزول it adds (build 4): after the جيكر is deleted, a round with a second نزول can still be corrected")
    let d = freshDefaults("h22")
    let app = launch(d)
    let s = HandScreen(app: app)
    let h = app.hand
    s.open()
    for (i, n) in boardNames.enumerated() { s.setupName(i, n) }
    s.setupStart()
    for r in [[Cell.n(20), .out, .nd, .nd], [.nd, .nd, .out, .n(40)], [.nd, .joker, .nd, .nd], [.n(15), .nd, .out, .nd]] {
        s.record(r)
        s.wait(3300)
    }
    step("setup: حمد down 20 in round 1, سالم down 40 in round 2, أنور جيكر in round 3, حمد down 15 in round 4 (allowed with the جيكر)") { c in
        c.eq(h.rounds.count, 4, "rounds")
        c.eq(s.downs, [2, 0, 0, 1], "downs")
    }
    let joker = h.rounds[2]
    s.tapRow(joker)
    s.tapDelete(joker)
    s.tapConfirmDelete(joker)
    s.wait(3300)
    step("round 3 deleted: back to 7 rounds and one نزول; حمد keeps his two (a delete is never refused)") { c in
        c.eq(h.target, 7, "target")
        c.eq(s.downs, [2, 0, 0, 1], "downs")
        c.eq(s.totals, [135, 170, 40, 240], "totals")
    }
    let r4 = h.rounds[2]
    s.tapRow(r4)
    s.tapEdit(r4)
    s.tapField(3)
    s.digits("12")
    s.tapField(3)
    s.digits("0")
    step("«تعديل» on round 4, سالم «ما نزل» → 120 cards: حمد's 15 was already in the round, so nothing is marked past the cap") { c in
        c.eq(h.status.over, [], "over")
        c.eq(h.status.ready, true, "ready")
    }
    let m = app.speaker.mark
    s.press(.record)
    step("«حفظ» goes in: 135, 170, 40, 260, nothing refused") { c in
        c.eq(h.editId == nil, true, "edit closed")
        c.eq(s.totals, [135, 170, 40, 260], "totals")
        c.eq(app.speaker.spoken(since: m).count, 0, "voice")
        c.eq(h.bannerDanger, false, "no alert")
    }
    s.wait(3300)
    let r4b = h.rounds[2]
    s.tapRow(r4b)
    s.tapEdit(r4b)
    s.tapField(3)
    for _ in 0..<3 { s.press(.erase) }
    s.digits("30")
    let m2 = app.speaker.mark
    s.press(.record)
    step("the same round with سالم down 30 (his second; one is the most now): «حفظ» refuses «سالم عنده نزول»") { c in
        c.eq(h.status.over, [s.id(3)], "over")
        c.eq(h.banner, "سالم عنده نزول", "banner")
        c.eq(app.speaker.spoken(since: m2).map(\.text), ["سالم عنده نزول"], "voice")
        c.eq(h.editId, r4b.id, "still editing")
        c.eq(h.rounds[2], r4b, "round unchanged")
    }
    s.tapCancelEdit()
    s.wait(3300)
    s.tapField(1)
    s.press(.finish(.out))
    s.tapField(0)
    s.digits("10")
    let m3 = app.speaker.mark
    s.press(.record)
    step("a new round with حمد down again is refused: «حمد عنده نزول» (he has two in a 7-round game)") { c in
        c.eq(app.speaker.spoken(since: m3).map(\.text), ["حمد عنده نزول"], "voice")
        c.eq(h.rounds.count, 3, "rounds")
    }
    _ = d
}

// MARK: Item 7: a هند or جيكر round that brings the tie or the last round says both

private func handFinisherWithTieOrLastRound() {
    Report.begin("Hand 23 · a هند or جيكر round that brings «آخر جولة» or the tie says both (build 4); one that grows the game to 9 keeps its line")
    do {
        let (_, app, s) = playBoardMidgame("h23a")
        let h = app.hand
        for r in [[Cell.nd, .nd, .n(31), .out], [.nd, .nd, .out, .nd]] {
            s.record(r)
            s.wait(3300)
        }
        let m = app.speaker.mark
        s.record([.nd, .hand, .nd, .nd])
        step("round 6 of 7 by أنور هند: «أنور نزل هند · آخر جولة», said «أنور نزل هند، وآخر جولة»") { c in
            c.eq(h.rounds.count, 6, "rounds")
            c.eq(h.banner, "أنور نزل هند · آخر جولة", "banner")
            c.eq(app.speaker.spoken(since: m).map(\.text), ["أنور نزل هند، وآخر جولة"], "voice")
            c.eq(h.roundLine, "آخر جولة", "status line")
        }
    }
    do {
        let (_, app, s) = playBoardMidgame("h23b")
        let h = app.hand
        for r in [[Cell.nd, .nd, .n(31), .out], [.nd, .nd, .out, .nd]] {
            s.record(r)
            s.wait(3300)
        }
        let m = app.speaker.mark
        s.record([.joker, .nd, .nd, .nd])
        step("round 6 of 7 by حمد جيكر: the game grows to 9, so it keeps «حمد نزل جيكر · صارت 9 جولات ونزولين» (no «آخر جولة»)") { c in
            c.eq(h.banner, "حمد نزل جيكر · صارت 9 جولات ونزولين", "banner")
            c.eq(app.speaker.spoken(since: m).map(\.text), ["حمد نزل جيكر، وصارت تسع جولات ونزولين"], "voice")
            c.eq(h.roundLine, "الجولة 7 من 9", "status line")
        }
    }
    for (tag, third) in [("h23c", "سالم"), ("h23d", "عبدالعزيز سعد")] {
        let d = freshDefaults(tag)
        let app = launch(d)
        let s = HandScreen(app: app)
        let h = app.hand
        s.open()
        s.setupRemove(3)
        for (i, n) in ["حمد", "فهد", third].enumerated() { s.setupName(i, n) }
        s.setupStart()
        let six: [[Cell]] = [[.out, .n(150), .nd], [.n(150), .out, .nd], [.out, .n(150), .nd],
                             [.n(150), .out, .nd], [.out, .n(150), .nd], [.n(150), .out, .nd]]
        for r in six {
            s.record(r)
            s.wait(3300)
        }
        step("\(third): six rounds, حمد 360, فهد 360, \(third) 600; «آخر جولة» shown") { c in
            c.eq(s.totals, [360, 360, 600], "totals")
            c.eq(h.roundLine, "آخر جولة", "status line")
        }
        let m = app.speaker.mark
        s.record([.n(55), .n(55), .hand])
        let full = third + " نزل هند · تعادل، وجولة فاصلة"
        let banner = full.utf16.count > 36 ? "هند · تعادل، وجولة فاصلة" : full
        step("round 7 by \(third) هند, حمد and فهد down 55 ×2 → level on 470: «\(banner)», said in full") { c in
            c.eq(s.totals, [470, 470, 540], "totals")
            c.eq(h.outcome, .tie([s.id(0), s.id(1)], at: 470), "outcome")
            c.eq(h.banner, banner, "banner")
            c.eq(app.speaker.spoken(since: m).map(\.text), [third + " نزل هند، وتعادل، وجولة فاصلة"], "voice")
            c.eq(h.roundLine, "جولة فاصلة", "status line")
        }
    }
}

// MARK: Item 8: a round that goes in clears the refusal's alert

private func handAlertClearedByARound() {
    Report.begin("Hand 24 · after a refusal, a round that goes in (or a saved edit) clears the red alert at once, and its own announcement can take the place (build 4)")
    do {
        let (_, app, s) = playBoardMidgame("h24a")
        let h = app.hand
        s.tapField(0)
        s.press(.finish(.out))
        s.digits("25")
        s.press(.record)
        let t0 = VirtualClock.now
        step("setup: حمد خلّص, أنور 25 refused «أنور عنده نزول» in the alert colour") { c in
            c.eq(h.bannerOn && h.bannerDanger, true, "alert")
        }
        s.wait(1000)
        s.tapField(1)
        s.press(.notDown)
        s.press(.record)
        step("أنور «ما نزل» and «سجّل» 1 s later: the round goes in and the alert is gone at once (no announcement for خلّص)") { c in
            c.eq(h.rounds.count, 4, "rounds")
            c.eq(h.bannerOn, false, "banner")
            c.eq(h.bannerDanger, false, "alert colour")
        }
        s.wait(3000)
        step("…and the refusal's timer does not come back to anything") { c in
            c.eq(h.bannerOn, false, "banner")
            c.eq(fired("hand", from: t0, to: t0 + 4000, keys: ["banner"]), [], "the refusal's banner timer was cancelled")
        }
    }
    do {
        let (_, app, s) = playBoardMidgame("h24b")
        let h = app.hand
        s.tapField(0)
        s.press(.finish(.hand))
        s.digits("25")
        s.press(.record)
        let t0 = VirtualClock.now
        s.wait(1000)
        s.tapField(1)
        s.press(.notDown)
        let m = app.speaker.mark
        s.press(.record)
        step("حمد هند after the refusal: «حمد نزل هند» takes the alert's place, in gold") { c in
            c.eq(h.banner, "حمد نزل هند", "banner")
            c.eq(h.bannerOn, true, "banner on")
            c.eq(h.bannerDanger, false, "gold, not the alert colour")
            c.eq(app.speaker.spoken(since: m).map(\.text), ["حمد نزل هند"], "voice")
        }
        s.wait(2300)
        let onAtRefusalEnd = h.bannerOn
        s.wait(1000)
        step("…and stays its own 3.2 s: still on when the refusal's 3.2 s would have ended, off at +1000+3200") { c in
            c.eq(onAtRefusalEnd, true, "on at the refusal's +3300")
            c.eq(h.bannerOn, false, "off at +4300")
            c.eq(VirtualClock.fired.last { $0.owner == "hand" && $0.key == "banner" }?.time, t0 + 1000 + 3200, "banner timer")
        }
    }
    do {
        let (_, app, s) = playBoardMidgame("h24c")
        let h = app.hand
        let r3 = h.rounds[2]
        s.tapRow(r3)
        s.tapEdit(r3)
        s.tapField(3)
        s.digits("30")
        s.press(.record)
        step("setup: «تعديل» on round 3 with سالم down 30 (his second; the edit adds it) is refused") { c in
            c.eq(h.bannerOn && h.bannerDanger, true, "alert")
            c.eq(h.banner, "سالم عنده نزول", "banner")
            c.eq(h.editId, r3.id, "still editing")
        }
        s.wait(800)
        s.tapField(3)
        s.press(.notDown)
        s.press(.record)
        step("سالم back on «ما نزل» and «حفظ»: the edit goes in and the alert is gone at once") { c in
            c.eq(h.editId == nil, true, "edit closed")
            c.eq(h.bannerDanger, false, "alert colour")
            c.eq(h.bannerOn, false, "banner")
        }
    }
}

// MARK: Item 9: damaged saves, الهند

private func handDamagedSaves() {
    Report.begin("Hand 25 · a damaged save (build 4): a bad round or field is dropped, not the game; missing values take defaults; the save as it was is kept under «hand.v1.damaged»")
    let players = #"[{"id":"p1","name":"حمد"},{"id":"p2","name":"أنور"},{"id":"p3","name":"فهد"}]"#
    let r1 = #"{"id":101,"cells":{"p1":{"kind":"out","cards":0},"p2":{"kind":"num","cards":35},"p3":{"kind":"nd","cards":0}}}"#
    let r2bad = #"{"id":102,"cells":{"p1":{"kind":"nd","cards":0},"p2":{"kind":"hand1","cards":0},"p3":{"kind":"out","cards":0}}}"#
    let r3 = #"{"id":103,"cells":{"p1":{"kind":"nd","cards":0},"p2":{"kind":"nd","cards":0},"p3":{"kind":"out","cards":0}}}"#
    do {
        let d = freshDefaults("h25a")
        let json = "{\"players\":\(players),\"rounds\":[\(r1),\(r2bad),\(r3)],\"entry\":{},\"uid\":103,\"started\":true}"
        d.set(Data(json.utf8), forKey: "hand.v1")
        let app = launch(d)
        let s = HandScreen(app: app)
        s.open()
        step("a round with an unknown kind («hand1»): only that round goes; the game, its players and the other rounds stay") { c in
            c.eq(app.hand.players.map(\.name), ["حمد", "أنور", "فهد"], "players")
            c.eq(app.hand.rounds.map(\.id), [101, 103], "rounds")
            c.eq(app.hand.setupOpen, false, "no «مين يلعب؟»")
            c.eq(damagedCopy(d, "hand.v1"), json, "the save as it was, kept aside")
        }
        s.record([.out, .nd, .nd])
        step("the next round gets a new id and the mended game replaces the damaged save; the damaged copy stays") { c in
            c.eq(Set(app.hand.rounds.map(\.id)).count, 3, "ids unique")
            c.eq(savedHand(d)?.rounds.map(\.id) ?? [], app.hand.rounds.map(\.id), "saved")
            c.eq(damagedCopy(d, "hand.v1"), json, "damaged copy")
        }
    }
    do {
        let d = freshDefaults("h25b")
        let json = "{\"players\":\(players),\"rounds\":[\(r1),\(r3)]}"
        d.set(Data(json.utf8), forKey: "hand.v1")
        let app = launch(d)
        let s = HandScreen(app: app)
        s.open()
        s.tapNewGame()
        s.setupAdd()
        let newId = app.hand.setup.players.last?.id
        s.setupCancel()
        step("«entry», «uid» and «started» missing: started (no «مين يلعب؟» by itself), empty fields, and new ids past every id in use") { c in
            c.eq(app.hand.started, true, "started")
            c.eq(app.hand.rounds.map(\.id), [101, 103], "rounds")
            c.eq(entryText(app.hand.entry, app.hand.players), "حمد — · أنور — · فهد —", "fields")
            c.eq(newId.map { Int($0.dropFirst()) ?? 0 }.map { $0 > 103 }, true, "a new player's id is past round 103")
            c.eq(damagedCopy(d, "hand.v1"), json, "damaged copy")
        }
        s.record([.out, .nd, .nd])
        step("the next round's id is past 103") { c in c.eq((app.hand.rounds.last?.id ?? 0) > 103, true, "id") }
    }
    do {
        let d = freshDefaults("h25c")
        let seven = "[" + (1...7).map { "{\"id\":\"p\($0)\",\"name\":\"\"}" }.joined(separator: ",") + "]"
        let json = "{\"players\":\(seven),\"rounds\":[],\"entry\":{},\"uid\":100,\"started\":true}"
        d.set(Data(json.utf8), forKey: "hand.v1")
        let app = launch(d)
        let s = HandScreen(app: app)
        s.open()
        step("seven players cannot be played: the save is set aside and «مين يلعب؟» opens on a fresh game") { c in
            c.eq(app.hand.players.count, 4, "players")
            c.eq(app.hand.setupOpen, true, "sheet")
            c.eq(damagedCopy(d, "hand.v1"), json, "damaged copy")
        }
    }
    do {
        let d = freshDefaults("h25d")
        let four = #"[{"id":"p1","name":"حمد"},{"id":"p2","name":"أنور"},{"id":"p3","name":"فهد"},{"id":"p4","name":"سالم"}]"#
        let entry = #"{"p1":{"kind":"out","digits":""},"p2":{"kind":"num","digits":"0x9"},"p3":{"kind":"num","digits":"012"},"p4":{"kind":"zz","digits":""}}"#
        let json = "{\"players\":\(four),\"rounds\":[],\"entry\":\(entry),\"uid\":100,\"started\":true}"
        d.set(Data(json.utf8), forKey: "hand.v1")
        let app = launch(d)
        step("bad fields in the round being typed («0x9», «012», an unknown kind) are emptied; a good one (حمد خلّص) stays") { c in
            c.eq(entryText(app.hand.entry, app.hand.players), "حمد خلّص · أنور — · فهد — · سالم —", "fields")
            c.eq(damagedCopy(d, "hand.v1"), json, "damaged copy")
        }
    }
    do {
        let d = freshDefaults("h25g")
        let json = "{\"players\":\(players),\"entry\":{},\"uid\":100,\"started\":true}"
        d.set(Data(json.utf8), forKey: "hand.v1")
        let app = launch(d)
        step("«rounds» missing: the players are kept, with no rounds") { c in
            c.eq(app.hand.players.map(\.name), ["حمد", "أنور", "فهد"], "players")
            c.eq(app.hand.rounds.count, 0, "rounds")
            c.eq(app.hand.started, true, "started")
        }
    }
    do {
        let d = freshDefaults("h25e")
        let json = #"{"players":[{"id":"p1","name":"حمد"},{"id":"p101","name":"بدر"}],"rounds":[],"entry":{},"uid":100,"started":true}"#
        d.set(Data(json.utf8), forKey: "hand.v1")
        let app = launch(d)
        let s = HandScreen(app: app)
        s.open()
        s.tapNewGame()
        s.setupAdd()
        let ids = app.hand.setup.players.map(\.id)
        s.setupStart()
        step("uid 100 below player p101 (the old crash): «إضافة لاعب» takes a new id and «ابدأ» starts with three players") { c in
            c.eq(Set(ids).count, 3, "unique ids in «مين يلعب؟»: \(ids)")
            c.eq(app.hand.players.count, 3, "players")
        }
    }
    do {
        let (d, app, s) = playBoardMidgame("h25f")
        s.tapField(0)
        s.press(.finish(.out))
        _ = launch(d)
        step("a good save is read as it is: no damaged copy") { c in c.eq(damagedCopy(d, "hand.v1") == nil, true, "damaged copy") }
        _ = app
    }
}

// MARK: The voice chip

private func voiceChip() {
    Report.begin("Settings 2 · the voice chip off silences the line being said at once (build 4, HomeView)")
    let d = freshDefaults("chip")
    let app = launch(d)
    let s = BalootScreen(app: app)
    s.recordHand(101, 0)
    let stops = app.speaker.log.filter { $0.kind == .stopped }.count
    tapVoiceChip(app)
    step("«لنا فوق المئة» being said, the chip turned off: the voice is stopped") { c in
        c.eq(app.speaker.spoken().map(\.text), ["لنا فوق المئة"], "said before")
        c.eq(app.speaker.log.filter { $0.kind == .stopped }.count, stops + 1, "stopped")
        c.eq(app.settings.voice, false, "setting")
    }
}
