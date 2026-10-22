import Foundation
import SwiftUI

// الهند scenarios. Expected values come from Hand.dc.html's JavaScript (seedConfig, commit, record, refuse, setKind,
// typeDigit, backspace, nextOpen, startEdit, saveEdit, reviewLast, openSetup, startGame…), its click flows in
// tools/hand-flows.json with the totals hand-log.md gives for them, and from hand-card.md, never from the Swift under test.

func runHandScenarios() {
    handFirstVisitAndSetup()
    handFinishers()
    handBoardGame()
    handBoardFlows()
    handTypingAndNextField()
    handJokerDeletedKeepsDowns()
    handLastRoundTieAndPlayoff()
    handEditAndDelete()
    handNewGameFromPoster()
    handVoiceOff()
    handSaveRestore()
    handCorruptedSave()
    handMidSequence()
    handReduceMotion()
    handSixPlayersAndLongNames()
    handEditAfterWin()
    handTwoOverAtOnce()
    handTwoPlayers()
    handSmallThings()
    settingsScenario()
}

/// A game with the board's four names, started from «مين يلعب؟» on the first visit.
private func boardGame(_ tag: String) -> (UserDefaults, AppModel, HandScreen) {
    let d = freshDefaults(tag)
    let app = launch(d)
    let s = HandScreen(app: app)
    s.open()
    for (i, n) in boardNames.enumerated() { s.setupName(i, n) }
    s.setupStart()
    return (d, app, s)
}

/// The board's midgame: its first three rounds, each left to finish its count.
private func playMidgame(_ s: HandScreen) {
    for r in boardRounds.prefix(3) {
        s.record(r)
        s.wait(1100)
    }
}

// MARK: 1. First visit and «مين يلعب؟»

private func handFirstVisitAndSetup() {
    Report.begin("Hand 1 · the first visit opens «مين يلعب؟»: names, 2 to 6 players, «إلغاء» and «ابدأ»")
    let d = freshDefaults("h1")
    let app = launch(d)
    let s = HandScreen(app: app)
    let h = app.hand
    step("a fresh install: not started, four players «لاعب 1» … «لاعب 4», no rounds, home card «لعبة جديدة»") { c in
        c.eq(h.started, false, "started")
        c.eq(s.names, ["لاعب 1", "لاعب 2", "لاعب 3", "لاعب 4"], "names")
        c.eq(h.rounds.count, 0, "rounds")
        c.eq(h.homeStatus, "لعبة جديدة", "home card")
        c.eq(h.setupOpen, false, "sheet before the page opens")
    }
    s.open()
    step("the page opens: «مين يلعب؟» opens by itself with four empty names, and nothing behind it can be typed") { c in
        c.eq(h.setupOpen, true, "sheet")
        c.eq(h.setup.players.map(\.name), ["", "", "", ""], "names")
        c.eq(h.locked, true, "locked")
        c.eq(s.tapField(0), false, "a field behind the sheet")
    }
    s.setupName(0, "حمد")
    s.setupName(1, "عبدالرحمن بن فهد الكويتي")
    s.setupAdd()
    s.setupAdd()
    step("names are cut at 14; «إضافة لاعب» up to six, with new ids") { c in
        c.eq(h.setup.players[1].name, String("عبدالرحمن بن فهد الكويتي".prefix(14)), "long name")
        c.eq(h.setup.players.count, 6, "players")
        c.eq(Set(h.setup.players.map(\.id)).count, 6, "unique ids")
        c.eq(s.setupAdd(), false, "a seventh")
    }
    for _ in 0..<4 { s.setupRemove(h.setup.players.count - 1) }
    step("✕ down to two, not below") { c in
        c.eq(h.setup.players.count, 2, "players")
        c.eq(s.setupRemove(0), false, "below two")
    }
    s.setupCancel()
    step("«إلغاء» on the first visit: the four players stay «لاعب 1» … «لاعب 4», the draft is dropped, and it is saved as started") { c in
        c.eq(h.setupOpen, false, "sheet")
        c.eq(h.started, true, "started")
        c.eq(s.names, ["لاعب 1", "لاعب 2", "لاعب 3", "لاعب 4"], "names")
        c.eq(savedHand(d)?.started, true, "saved started")
        c.eq(h.locked, false, "unlocked")
    }
    let app2 = launch(d)
    let s2 = HandScreen(app: app2)
    s2.open()
    step("the next visit does not open «مين يلعب؟» by itself") { c in c.eq(app2.hand.setupOpen, false, "sheet") }
    s2.tapNewGame()
    s2.setupName(0, "حمد")
    s2.setupName(2, "  فهد  ")
    s2.setupName(3, "سالم")
    s2.setupRemove(0)
    let stops = app2.speaker.log.filter { $0.kind == .stopped }.count
    s2.setupStart()
    step("«ابدأ» after removing حمد: an empty name becomes «لاعب N» by its new place, names are trimmed, saved") { c in
        c.eq(s2.names, ["لاعب 1", "فهد", "سالم"], "names")
        c.eq(app2.hand.players.map(\.name), ["لاعب 1", "فهد", "سالم"], "stored names")
        c.eq(app2.hand.rounds.count, 0, "rounds")
        c.eq(app2.hand.setupOpen, false, "sheet")
        c.eq(savedHand(d)?.players.map(\.name) ?? [], ["لاعب 1", "فهد", "سالم"], "saved")
        c.eq(app2.hand.roundLine, "الجولة 1 من 7", "status line")
        c.eq(app2.speaker.log.filter { $0.kind == .stopped }.count, stops + 1, "voice stopped")
    }
    s2.tapNewGame()
    s2.setupName(0, "بدر")
    s2.setupAdd()
    s2.setupCancel()
    step("«إلغاء» later: the game and its players stay as they were") { c in
        c.eq(s2.names, ["لاعب 1", "فهد", "سالم"], "names")
        c.eq(app2.hand.players.count, 3, "players")
    }
}

// MARK: 2. The four finishers and ما نزل filled in by itself

private func handFinishers() {
    Report.begin("Hand 2 · each finisher (خلّص هند جيكر جيكرين) sets the multiplier and puts the others on «ما نزل» by itself")
    let kinds: [(PadKey, HandKind, Int, String?, String?)] = [
        (.finish(.out), .out, 1, nil, nil),
        (.finish(.hand), .hand, 2, "حمد نزل هند", "حمد نزل هند"),
        (.finish(.joker), .joker, 4, "حمد نزل جيكر · صارت 9 جولات ونزولين", "حمد نزل جيكر، وصارت تسع جولات ونزولين"),
        (.finish(.joker2), .joker2, 8, "حمد نزل جيكرين · 9 جولات ونزولين", "حمد نزل جيكرين، وصارت تسع جولات ونزولين")
    ]
    for (key, kind, m, banner, speech) in kinds {
        let (_, app, s) = boardGame("h2-\(m)")
        let h = app.hand
        s.tapField(0)
        s.press(key)
        step("حمد \(kind.name): the others go on «ما نزل» (\(100 * m) each), the cursor moves to أنور, «سجّل» is on") { c in
            c.eq(h.entry[s.id(0)]?.kind, kind, "حمد")
            c.eq((1...3).map { h.entry[s.id($0)]?.kind }, [.notDown, .notDown, .notDown], "others")
            c.eq(h.status.multiplier, m, "multiplier")
            c.eq(100 * h.status.multiplier, 100 * m, "«ما نزل» value")
            c.eq(h.focus, s.id(1), "cursor")
            c.eq(s.canPress(.record), true, "«سجّل»")
        }
        let t0 = VirtualClock.now
        let mark = app.speaker.mark
        s.press(.record)
        step("«سجّل»: \(-30 * m), \(100 * m), \(100 * m), \(100 * m); the keypad goes down; the numbers rise as «\u{2212}\(30 * m)» and «\(100 * m)»") { c in
            c.eq(s.totals, [-30 * m, 100 * m, 100 * m, 100 * m], "totals")
            c.eq(h.padOn, false, "keypad")
            c.eq(h.ghost?[s.id(0)], "\u{2212}\(30 * m)", "rising number")
            c.eq(h.ghost?[s.id(1)], "\(100 * m)", "rising number")
            c.eq(h.entry.values.allSatisfy { $0 == .empty }, true, "fields cleared")
            c.eq(h.focus, s.id(0), "cursor back to the first player")
            c.eq(app.speaker.spoken(since: mark).map(\.text), speech.map { [$0] } ?? [], "voice")
            if let banner {
                c.eq(h.banner, banner, "banner")
                c.eq(h.bannerOn, true, "banner on")
                c.eq(h.bannerDanger, false, "gold banner")
            } else {
                c.eq(h.bannerOn, false, "no banner")
            }
            c.eq(h.target, m >= 4 ? 9 : 7, "rounds in the game")
        }
        s.wait(1100)
        step("the record sequence for \(kind.name) ran on the board's timings") { c in
            let keys: Set<String> = ["fresh", "ghostOn", "count", "pulseOn", "ghostOff", "pulseOff", "countEnd"]
            c.eq(fired("hand", from: t0, to: t0 + 1100, keys: keys), recordTimeline(owner: "hand", at: t0, press: false), "timers")
            if m >= 4 {
                c.eq(h.segFrom, 7, "two new segments from the 8th")
                c.eq(h.segOn, true, "faded in")
                c.eq(VirtualClock.fired.first { $0.owner == "hand" && $0.key == "segOn" && $0.time >= t0 }?.time, t0 + 40, "segments at +40 ms")
            }
        }
    }
    // The board's auto_fill flow, and choosing another finisher.
    let (_, app, s) = boardGame("h2-change")
    let h = app.hand
    s.tapField(1)
    s.digits("25")
    s.tapField(0)
    s.press(.finish(.hand))
    step("a number typed before the finisher stays, as it is (أنور 25, not multiplied from build 6)") { c in
        c.eq(h.entry[s.id(1)], EntryCell(kind: .exact, digits: "25"), "أنور")
        c.eq([h.entry[s.id(2)]?.kind, h.entry[s.id(3)]?.kind], [.notDown, .notDown], "others")
        c.eq(HandRules.points(h.entry[s.id(1)] ?? .empty, multiplier: h.status.multiplier), 25, "not multiplied")
    }
    s.tapField(2)
    s.press(.finish(.out))
    step("a new finisher sends the old one back to «ما نزل»: فهد خلّص, حمد ما نزل, ×1") { c in
        c.eq(h.entry[s.id(0)]?.kind, .notDown, "حمد")
        c.eq(h.entry[s.id(2)]?.kind, .out, "فهد")
        c.eq(h.status.multiplier, 1, "multiplier")
        c.eq(h.status.finisher, s.id(2), "finisher")
    }
}

// MARK: 3. The board's game, round by round, to حمد's win

private func handBoardGame() {
    Report.begin("Hand 3 · the board's nine rounds: midgame 100 · 75 · 270 · 322, the جيكر in round 5, «آخر جولة», and حمد wins 277 · 648 · 619 · 1022")
    let (d, app, s) = boardGame("h3")
    let h = app.hand
    let totals: [[Int]] = [[-30, 35, 100, 100], [70, 135, 70, 122], [100, 75, 270, 322], [200, 175, 301, 292], [80, 575, 349, 692],
                           [180, 545, 449, 722], [207, 645, 419, 822], [177, 678, 519, 922], [277, 648, 619, 1022]]
    let downs: [[Int]] = [[0, 1, 0, 0], [0, 1, 0, 1], [1, 1, 0, 1], [1, 1, 1, 1], [1, 1, 2, 1], [1, 1, 2, 2], [2, 1, 2, 2], [2, 2, 2, 2], [2, 2, 2, 2]]
    let lines = ["الجولة 2 من 7", "الجولة 3 من 7", "الجولة 4 من 7", "الجولة 5 من 7", "الجولة 6 من 9", "الجولة 7 من 9", "الجولة 8 من 9", "آخر جولة", ""]
    let said: [String?] = [nil, nil, "أنور نزل هند", nil, "حمد نزل جيكر، وصارت تسع جولات ونزولين", nil, nil, "آخر جولة", nil]
    let banners: [String?] = [nil, nil, "أنور نزل هند", nil, "حمد نزل جيكر · صارت 9 جولات ونزولين", nil, nil, "آخر جولة", nil]
    var t0 = 0
    var m0 = 0
    for (i, r) in boardRounds.enumerated() {
        t0 = VirtualClock.now
        m0 = app.speaker.mark
        let prevDowns = s.downs
        let ok = s.record(r)
        step("round \(i + 1) \(r): totals \(totals[i]), نزول \(downs[i]), status «\(lines[i])»") { c in
            c.eq(ok, true, "recorded")
            c.eq(s.totals, totals[i], "totals")
            c.eq(s.downs, downs[i], "downs")
            c.eq(h.roundLine, lines[i], "status line")
            c.eq(app.speaker.spoken(since: m0).map(\.text), said[i].map { [$0] } ?? [], "voice")
            if let b = banners[i] {
                c.eq(h.banner, b, "banner")
                c.eq(h.bannerOn, true, "banner on")
            } else if i < 8 {
                c.eq(h.bannerOn, false, "no banner")
            }
            c.eq(savedHand(d)?.rounds == h.rounds, true, "saved rounds equal the rounds on screen")
            c.eq(savedHand(d)?.rounds.count, i + 1, "saved rounds")
            let more = zip(downs[i], prevDowns).contains { $0 > $1 }
            c.eq(h.pipOn, !more, "new نزول circles wait for the count")
            c.eq(h.pipPrev.map { p in h.players.map { p[$0.id] ?? 0 } }, more ? prevDowns : nil, "circles before")
        }
        if i < 8 {
            s.wait(1100)
            step("round \(i + 1): the count ended and the circles came in at +560 ms") { c in
                c.eq(h.counting, false, "count")
                c.eq(h.pipOn, true, "circles")
                if zip(downs[i], prevDowns).contains(where: { $0 > $1 }) {
                    c.eq(VirtualClock.fired.first { $0.owner == "hand" && $0.key == "pipOn" && $0.time >= t0 }?.time, t0 + 560, "circles at +560")
                }
            }
            // Let any banner run out (3.2 s) so the next round starts on a clear status line.
            s.wait(2200)
        }
        if i == 2 {
            step("midgame as on the board: 100, 75, 270, 322, round 4 of 7, home card «الجولة 4 من 7»") { c in
                c.eq(s.totals, [100, 75, 270, 322], "totals")
                c.eq(h.homeStatus, "الجولة 4 من 7", "home card")
                c.eq(h.target, 7, "target")
            }
        }
    }
    step("round 9 wins: the win screen held back, the keypad locked, the top bar hidden, no banner") { c in
        c.eq(h.outcome, .won(s.id(0)), "winner حمد")
        c.eq(h.holdPoster, true, "held")
        c.eq(h.posterVisible, false, "win screen not yet")
        c.eq(h.locked, true, "locked")
        c.eq(h.padUp, false, "keypad")
        c.eq(h.topVisible, false, "top bar")
        c.eq(h.bannerOn, false, "banner")
        c.eq(h.homeStatus, "الفوز لحمد", "home card")
    }
    s.wait(t0 + 1060 - VirtualClock.now)
    step("t0+1060: حمد's box outlined") { c in
        c.eq(h.lift, true, "lift")
        c.eq(h.growPlayer, s.id(0), "box")
    }
    s.wait(t0 + 1860 - VirtualClock.now)
    step("t0+1860: the win screen, solid, with the success haptic") { c in
        c.eq(h.posterVisible, true, "win screen")
        c.eq(h.fromExpand, true, "solid")
        c.eq(h.feedback, .win, "haptic")
    }
    s.wait(1000)
    step("«الفوز لحمد» said once, at t0+2370; the sequence in the board's order") { c in
        c.eq(app.speaker.spoken(since: m0).map(\.text), ["الفوز لحمد"], "voice")
        c.eq(app.speaker.spoken(since: m0).first.map { "+\($0.time - t0) ms" }, "+2370 ms", "time")
        let keys: Set<String> = ["count", "countEnd", "growBox", "growFull", "poster", "intro", "growOff", "voice"]
        let expected = [VirtualClock.Fired(time: t0 + 360, owner: "hand", key: "count")] + winTimeline(owner: "hand", countEnd: t0 + 1060)
        c.eq(fired("hand", from: t0, to: t0 + 3000, keys: keys), expected, "timers")
    }
    step("the win screen: حمد 277; then فهد 619, أنور 648, سالم 1022; «بعد 9 جولات»; no row can be touched") { c in
        let t = h.totals
        let others = h.players.filter { $0.id != s.id(0) }.sorted { (t[$0.id] ?? 0) < (t[$1.id] ?? 0) }
        c.eq(others.map { h.name($0.id) }, ["فهد", "أنور", "سالم"], "others in order")
        c.eq(t[s.id(0)], 277, "winner's total")
        c.eq(ArabicCount.rounds(h.rounds.count), boardRoundsText(9), "rounds line")
        c.eq(h.rounds.map { h.canTouch($0) }, Array(repeating: false, count: 9), "rows")
        c.eq(s.tapField(0), false, "a field")
    }
}

// MARK: 4. The board's click flows (tools/hand-flows.json) from the midgame

private func handBoardFlows() {
    Report.begin("Hand 4 · the board's click flows from the midgame, with the totals hand-log.md gives for them")
    do {
        let (_, app, s) = boardGame("h4-down_ok")
        let h = app.hand
        playMidgame(s)
        s.tapField(0)
        s.press(.finish(.out))
        s.tapField(2)
        step("down_ok: حمد خلّص, a tap on فهد") { c in c.eq(h.focus, s.id(2), "cursor") }
        s.press(.digit("2"))
        step("«2» stays on فهد") { c in c.eq(h.focus, s.id(2), "cursor") }
        s.press(.digit("5"))
        step("«5»: فهد 25, a نزول (ring), and the cursor stays on him (from build 6)") { c in
            c.eq(h.entry[s.id(2)], EntryCell(kind: .exact, digits: "25"), "فهد")
            c.eq(HandRules.isDown(h.entry[s.id(2)], in: h.entry), true, "نزول")
            c.eq(h.focus, s.id(2), "cursor")
            c.eq(h.status.over, [], "within the cap")
        }
        s.press(.record)
        step("«سجّل» → 70, 175, 295, 422 (hand-log round 6)") { c in c.eq(s.totals, [70, 175, 295, 422], "totals") }
    }
    do {
        let (_, app, s) = boardGame("h4-down_refused")
        let h = app.hand
        playMidgame(s)
        s.tapField(0)
        s.press(.finish(.hand))
        s.digits("50")
        step("down_refused: حمد هند, أنور 50 (his 25 × 2) — a second نزول without a جيكر: his field says «عنده نزول»") { c in
            c.eq(h.entry[s.id(1)], EntryCell(kind: .exact, digits: "50"), "أنور")
            c.eq(h.status.over, [s.id(1)], "over the cap")
            c.eq(h.status.cap, 1, "cap")
            c.eq(s.canPress(.record), true, "«سجّل» is still on")
        }
        let tr = VirtualClock.now
        let mark = app.speaker.mark
        let tick = h.shakeTick
        s.tapField(2)
        s.press(.record)
        step("«سجّل» refuses: «أنور عنده نزول» on the status line in the alert colour and by voice, his field shakes and takes the cursor, the keypad stays") { c in
            c.eq(h.rounds.count, 3, "nothing recorded")
            c.eq(h.banner, "أنور عنده نزول", "banner")
            c.eq(h.bannerOn, true, "banner on")
            c.eq(h.bannerDanger, true, "alert colour")
            c.eq(app.speaker.spoken(since: mark).map(\.text), ["أنور عنده نزول"], "voice")
            c.eq(h.shakeIds, [s.id(1)], "shake")
            c.eq(h.shakeTick, tick + 1, "shake once")
            c.eq(h.focus, s.id(1), "cursor")
            c.eq(h.padUp, true, "keypad")
            c.eq(h.feedback, .refuse, "haptic")
            c.eq(s.totals, [100, 75, 270, 322], "totals")
        }
        s.wait(3199)
        let on = h.bannerOn
        s.wait(1)
        step("the refusal stays 3.2 s") { c in
            c.eq(on, true, "on at 3199")
            c.eq(h.bannerOn, false, "off at 3200")
            c.eq(VirtualClock.fired.last { $0.key == "banner" }?.time, tr + 3200, "timer")
        }
        s.tapField(1)
        s.press(.notDown)
        s.press(.record)
        step("أنور «ما نزل» and «سجّل» → 40, 275, 470, 522 (hand-log round 7)") { c in
            c.eq(s.totals, [40, 275, 470, 522], "totals")
            c.eq(h.shakeIds, [], "shake cleared")
        }
    }
    do {
        let (_, app, s) = boardGame("h4-joker_second")
        let h = app.hand
        playMidgame(s)
        s.tapField(0)
        s.press(.finish(.joker))
        s.digits("100")
        step("joker_second: حمد جيكر, أنور 100 (his 25 × 4) — a second نزول is allowed with the جيكر in the round") { c in
            c.eq(h.status.over, [], "over")
            c.eq(h.status.cap, 2, "cap")
            c.eq(h.status.multiplier, 4, "×4")
        }
        let mark = app.speaker.mark
        s.press(.record)
        step("«سجّل» → −20, 175, 670, 722 (hand-log round 7), «حمد نزل جيكر · صارت 9 جولات ونزولين», round 5 of 9") { c in
            c.eq(s.totals, [-20, 175, 670, 722], "totals")
            c.eq(h.banner, "حمد نزل جيكر · صارت 9 جولات ونزولين", "banner")
            c.eq(app.speaker.spoken(since: mark).map(\.text), ["حمد نزل جيكر، وصارت تسع جولات ونزولين"], "voice")
            c.eq(h.roundLine, "الجولة 5 من 9", "status line")
            c.eq(s.downs, [1, 2, 0, 1], "downs")
        }
        s.wait(3800)
        s.tapField(0)
        s.press(.finish(.out))
        s.digits("18")
        let mark2 = app.speaker.mark
        s.press(.record)
        step("joker_third_refused: a third نزول for أنور is refused, «أنور عنده نزولين»") { c in
            c.eq(h.rounds.count, 4, "nothing recorded")
            c.eq(h.banner, "أنور عنده نزولين", "banner")
            c.eq(app.speaker.spoken(since: mark2).map(\.text), ["أنور عنده نزولين"], "voice")
        }
    }
    do {
        let (_, app, s) = boardGame("h4-main_joker2")
        let h = app.hand
        playMidgame(s)
        s.tapField(2)
        s.press(.finish(.joker2))
        step("main_joker2: فهد جيكرين, the cursor moves to سالم") { c in c.eq(h.focus, s.id(3), "cursor") }
        s.press(.notDown)
        step("«ما نزل» on سالم moves on round the table to حمد") { c in c.eq(h.focus, s.id(0), "cursor") }
        s.digits("240")
        step("حمد 240 (his 30 × 8) stays on him; a tap on أنور") { c in c.eq(h.focus, s.id(0), "cursor") }
        s.tapField(1)
        s.press(.notDown)
        let mark = app.speaker.mark
        s.press(.record)
        step("«سجّل» → 340, 875, 30, 1122, «فهد نزل جيكرين · 9 جولات ونزولين» (cut to fit), by voice in full") { c in
            c.eq(s.totals, [340, 875, 30, 1122], "totals")
            c.eq(h.banner, "فهد نزل جيكرين · 9 جولات ونزولين", "banner")
            c.eq(app.speaker.spoken(since: mark).map(\.text), ["فهد نزل جيكرين، وصارت تسع جولات ونزولين"], "voice")
        }
    }
    do {
        let (d, app, s) = boardGame("h4-main_joker_undo")
        let h = app.hand
        playMidgame(s)
        s.record([.joker, .typed(60), .nd, .nd])
        s.wait(3800)
        let r4 = h.rounds[3]
        s.tapRow(r4)
        s.tapEdit(r4)
        step("main_joker_undo: round 4 opens in the fields with the keypad, «تعديل الجولة 4», the key says «حفظ»") { c in
            c.eq(h.editId, r4.id, "editing")
            c.eq(h.editLine, "تعديل الجولة 4", "status line")
            c.eq(s.recordLabel, "حفظ", "key")
            c.eq(h.padUp, true, "keypad")
            c.eq(h.entry[s.id(1)], EntryCell(kind: .exact, digits: "60"), "أنور")
        }
        s.press(.finish(.out))
        step("حمد خلّص instead of جيكر: the edit takes the جيكر away itself, so أنور's 60 (below 100, still a نزول) is a second نزول past the lower cap and his field says so") { c in
            c.eq(h.status.over, [s.id(1)], "over")
            c.eq(h.status.cap, 1, "cap once the جيكر is gone")
        }
        let mark = app.speaker.mark
        s.press(.record)
        step("«حفظ» refuses «أنور عنده نزول» as on the board: the edit stays open, nothing is saved, the game is still 9 rounds") { c in
            c.eq(h.rounds[3], r4, "round unchanged")
            c.eq(savedHand(d)?.rounds[3], r4, "saved round unchanged")
            c.eq(h.banner, "أنور عنده نزول", "banner")
            c.eq(h.bannerDanger, true, "alert colour")
            c.eq(app.speaker.spoken(since: mark).map(\.text), ["أنور عنده نزول"], "voice")
            c.eq(h.editId, r4.id, "still editing")
            c.eq(h.target, 9, "still 9 rounds")
            c.eq(h.focus, s.id(1), "cursor on أنور")
        }
        s.wait(3300)
        s.tapField(1)
        s.press(.notDown)
        let mark2 = app.speaker.mark
        s.press(.record)
        step("أنور «ما نزل» and «حفظ» → 70, 175, 370, 422, «رجعت 7 جولات ونزول واحد», round 5 of 7") { c in
            c.eq(s.totals, [70, 175, 370, 422], "totals")
            c.eq(h.banner, "رجعت 7 جولات ونزول واحد", "banner")
            c.eq(app.speaker.spoken(since: mark2).map(\.text), ["رجعت سبع جولات ونزول واحد"], "voice")
            c.eq(h.target, 7, "target")
            c.eq(h.roundLine, "الجولة 5 من 7", "status line")
            c.eq(h.editId == nil, true, "edit closed")
            c.eq(s.downs, [1, 1, 0, 1], "downs")
            c.eq(savedHand(d)?.rounds[3].cells[s.id(0)]?.kind, .out, "saved")
        }
    }
}

// MARK: 5. Typing and the next field

private func handTypingAndNextField() {
    Report.begin("Hand 5 · typing (build 6): the number as it is, up to four digits, staying in its field; a lone 0; erase; a نزول from 1 up to below ما نزل")
    let (_, app, s) = boardGame("h5")
    let h = app.hand
    s.tapField(1)
    s.press(.digit("0"))
    step("0 first is a number of its own") { c in c.eq(h.entry[s.id(1)], EntryCell(kind: .exact, digits: "0"), "أنور") }
    s.press(.digit("7"))
    step("«7» after it takes its place, and stays on أنور") { c in
        c.eq(h.entry[s.id(1)], EntryCell(kind: .exact, digits: "7"), "أنور")
        c.eq(h.focus, s.id(1), "cursor")
    }
    s.press(.erase)
    step("erase with no finisher: the field empties") { c in c.eq(h.entry[s.id(1)], .empty, "أنور") }
    s.tapField(0)
    s.press(.finish(.out))
    s.tapField(1)
    s.digits("12")
    step("two digits stay: أنور 12, the cursor on him") { c in
        c.eq(h.entry[s.id(1)], EntryCell(kind: .exact, digits: "12"), "أنور")
        c.eq(h.focus, s.id(1), "cursor")
    }
    s.digits("345")
    step("…up to four digits (1234), a fifth is not taken; 1234 is not a نزول") { c in
        c.eq(h.entry[s.id(1)], EntryCell(kind: .exact, digits: "1234"), "أنور")
        c.eq(h.focus, s.id(1), "cursor")
        c.eq(HandRules.isDown(h.entry[s.id(1)], in: h.entry), false, "1234 is not a نزول")
    }
    s.press(.erase)
    s.press(.erase)
    s.press(.erase)
    step("erase: 1234 → 123 → 12 → 1") { c in c.eq(h.entry[s.id(1)], EntryCell(kind: .exact, digits: "1"), "أنور") }
    s.press(.erase)
    step("erasing the last digit with a finisher chosen goes back to «ما نزل»") { c in c.eq(h.entry[s.id(1)], .notDown, "أنور") }
    s.tapField(0)
    s.press(.notDown)
    step("«ما نزل» on the finisher's own field takes the finish away: no finisher, «سجّل» off") { c in
        c.eq(h.status.finisher == nil, true, "finisher")
        c.eq(s.canPress(.record), false, "«سجّل»")
        c.eq(s.press(.record), false, "tap")
    }
    s.tapField(1)
    s.digits("99")
    step("99 is a نزول (below what «ما نزل» scores, 100 with no finisher)") { c in
        c.eq(HandRules.isDown(h.entry[s.id(1)], in: h.entry), true, "down")
        c.eq(h.status.over, [], "first one")
    }
    s.press(.erase)
    s.press(.erase)
    s.digits("100")
    step("100 is not a نزول") { c in
        c.eq(h.entry[s.id(1)], EntryCell(kind: .exact, digits: "100"), "أنور")
        c.eq(HandRules.isDown(h.entry[s.id(1)], in: h.entry), false, "down")
    }
    s.tapField(2)
    s.press(.finish(.hand))
    step("…until a هند makes «ما نزل» 200: then أنور's 100 is a نزول") { c in
        c.eq(HandRules.isDown(h.entry[s.id(1)], in: h.entry), true, "down")
    }
    s.tapBackground()
    step("a tap outside puts the keypad away") { c in
        c.eq(h.padOn, false, "keypad")
        c.eq(s.press(.digit("1")), false, "a key")
    }
}

// MARK: 6. A deleted جيكر: back to 7, the downs stay, and no more

private func handJokerDeletedKeepsDowns() {
    Report.begin("Hand 6 · deleting the جيكر round takes the game back to 7 and one نزول; a second نزول already in stays, and no more goes in")
    let (_, app, s) = boardGame("h6")
    let h = app.hand
    playMidgame(s)
    s.record([.nd, .nd, .joker, .nd])
    s.wait(3300)
    s.record([.out, .n(40), .nd, .nd])
    s.wait(1100)
    step("setup: فهد جيكر in round 4, then أنور's second نزول in round 5 (allowed, 9 rounds)") { c in
        c.eq(s.downs, [1, 2, 0, 1], "downs")
        c.eq(h.target, 9, "target")
    }
    let joker = h.rounds[3]
    s.tapRow(joker)
    s.tapDelete(joker)
    let mark = app.speaker.mark
    s.tapConfirmDelete(joker)
    step("the delete is not refused: back to 7 rounds and one نزول, «رجعت 7 جولات ونزول واحد»; أنور keeps his two") { c in
        c.eq(h.rounds.count, 4, "rounds")
        c.eq(h.target, 7, "target")
        c.eq(h.banner, "رجعت 7 جولات ونزول واحد", "banner")
        c.eq(app.speaker.spoken(since: mark).map(\.text), ["رجعت سبع جولات ونزول واحد"], "voice")
        c.eq(s.downs, [1, 2, 0, 1], "downs")
    }
    s.wait(3300)
    s.tapField(0)
    s.press(.finish(.out))
    s.digits("30")
    let mark2 = app.speaker.mark
    s.press(.record)
    step("…and he cannot go down again: «أنور عنده نزول»") { c in
        c.eq(h.rounds.count, 4, "nothing recorded")
        c.eq(app.speaker.spoken(since: mark2).map(\.text), ["أنور عنده نزول"], "voice")
    }
}

// MARK: 7. The last round, a tie, and the جولة فاصلة

private let tieRounds: [[Cell]] = [
    [.nd, .out, .nd], [.nd, .out, .nd], [.nd, .nd, .out], [.out, .nd, .nd], [.nd, .out, .nd], [.out, .nd, .nd], [.out, .nd, .nd]
]

private func handLastRoundTieAndPlayoff() {
    Report.begin("Hand 7 · «آخر جولة», a tie on the lowest after round 7 and its «جولة فاصلة», then the win")
    let d = freshDefaults("h7")
    let app = launch(d)
    let s = HandScreen(app: app)
    let h = app.hand
    s.open()
    s.setupRemove(3)
    for (i, n) in ["حمد", "أنور", "فهد"].enumerated() { s.setupName(i, n) }
    s.setupStart()
    let expect7: [[Int]] = [[100, -30, 100], [200, -60, 200], [300, 40, 170], [270, 140, 270], [370, 110, 370], [340, 210, 470], [310, 310, 570]]
    for (i, r) in tieRounds.enumerated() {
        let mark = app.speaker.mark
        s.record(r)
        if i == 5 {
            step("round 6 of 7: «آخر جولة» on the status line, as a banner and by voice") { c in
                c.eq(s.totals, expect7[i], "totals")
                c.eq(h.banner, "آخر جولة", "banner")
                c.eq(app.speaker.spoken(since: mark).map(\.text), ["آخر جولة"], "voice")
                c.eq(h.roundLine, "آخر جولة", "status line")
                c.eq(h.homeStatus, "آخر جولة", "home card")
            }
        }
        if i == 6 {
            step("round 7: حمد and أنور level on the lowest, 310: «تعادل، وجولة فاصلة», and the game goes on") { c in
                c.eq(s.totals, expect7[i], "totals")
                c.eq(h.outcome, .tie([s.id(0), s.id(1)], at: 310), "outcome")
                c.eq(h.isWon, false, "won")
                c.eq(h.banner, "تعادل، وجولة فاصلة", "banner")
                c.eq(app.speaker.spoken(since: mark).map(\.text), ["تعادل، وجولة فاصلة"], "voice")
                c.eq(h.roundLine, "جولة فاصلة", "status line")
                c.eq(h.homeStatus, "تعادل، وجولة فاصلة", "home card")
                c.eq(h.locked, false, "keypad open")
            }
        }
        s.wait(3300)
    }
    let mark = app.speaker.mark
    s.record([.nd, .nd, .out])
    step("round 8, still level (410 each): nothing said, «جولة فاصلة» again") { c in
        c.eq(s.totals, [410, 410, 540], "totals")
        c.eq(app.speaker.spoken(since: mark).count, 0, "voice")
        c.eq(h.roundLine, "جولة فاصلة", "status line")
    }
    s.wait(3300)
    let t0 = VirtualClock.now
    let mark2 = app.speaker.mark
    s.record([.nd, .out, .nd])
    s.wait(3000)
    step("round 9: أنور lowest alone, 380: «الفوز لأنور» after the sequence, «بعد 9 جولات»") { c in
        c.eq(h.outcome, .won(s.id(1)), "winner")
        c.eq(app.speaker.spoken(since: mark2).map(\.text), ["الفوز لأنور"], "voice")
        c.eq(app.speaker.spoken(since: mark2).first.map { "+\($0.time - t0) ms" }, "+2370 ms", "time")
        c.eq(h.posterVisible, true, "win screen")
        c.eq(ArabicCount.rounds(h.rounds.count), boardRoundsText(9), "rounds line")
    }
}

// MARK: 8. Edit and delete of the two newest rounds

private func handEditAndDelete() {
    Report.begin("Hand 8 · edit and delete: the two newest rounds only, «احذف؟» for 3 s, a typed round kept through an edit")
    let (d, app, s) = boardGame("h8")
    let h = app.hand
    playMidgame(s)
    let rows = s.rows
    step("only the two newest rows open") { c in
        c.eq(rows.map { h.canTouch($0) }, [true, true, false], "rows")
        c.eq(s.tapRow(rows[2]), false, "the oldest")
        c.eq(h.selected == nil, true, "nothing selected")
    }
    s.tapRow(rows[0])
    step("a tap opens «تعديل» and «حذف» under the newest; a second tap closes them") { c in
        c.eq(s.isSelected(rows[0]), true, "open")
        s.tapRow(rows[0])
        c.eq(s.isSelected(rows[0]), false, "closed")
    }
    s.tapRow(rows[0])
    let t0 = VirtualClock.now
    s.tapDelete(rows[0])
    step("«حذف» turns into «احذف؟»") { c in c.eq(h.confirmId, rows[0].id, "confirm") }
    s.wait(2999)
    let still = h.confirmId
    s.wait(1)
    step("«احذف؟» goes back to «حذف» after exactly 3 s") { c in
        c.eq(still, rows[0].id, "at 2999")
        c.eq(h.confirmId == nil, true, "at 3000")
        c.eq(VirtualClock.fired.last { $0.key == "confirmId" }?.time, t0 + 3000, "timer")
    }
    s.tapDelete(rows[0])
    s.wait(1000)
    let td = VirtualClock.now
    let mark = app.speaker.mark
    s.tapConfirmDelete(rows[0])
    step("«احذف؟»: round 3 goes, totals back to 70, 135, 70, 122, saved, the count starts at once, nothing said") { c in
        c.eq(h.rounds.count, 2, "rounds")
        c.eq(s.totals, [70, 135, 70, 122], "totals")
        c.eq(savedHand(d)?.rounds.count, 2, "saved")
        c.eq(h.counting, true, "counting at once")
        c.eq(h.shown(at: Date()).map { $0 }.sorted { $0.key < $1.key }.map(\.value), [100, 75, 270, 322], "from the old totals")
        c.eq(h.selected == nil && h.confirmId == nil, true, "row closed")
        c.eq(app.speaker.spoken(since: mark).count, 0, "voice")
    }
    s.wait(3100)
    step("the delete's count took 700 ms, and the cancelled «احذف؟» timer never fired") { c in
        c.eq(fired("hand", from: td, to: td + 3100, keys: ["count", "countEnd", "confirmId"]), [
            .init(time: td, owner: "hand", key: "count"),
            .init(time: td + 700, owner: "hand", key: "countEnd")
        ], "timers")
    }
    // A typed round survives an edit of another round.
    s.tapField(1)
    s.digits("4")
    let r2 = h.rounds[1]
    s.tapRow(r2)
    s.tapEdit(r2)
    step("«تعديل» on round 2 while أنور 4 is typed: round 2 in the fields, the typed round put aside") { c in
        c.eq(h.editLine, "تعديل الجولة 2", "status line")
        c.eq(h.entry[s.id(3)], EntryCell(kind: .exact, digits: "22"), "سالم")
        c.eq(h.entry[s.id(2)]?.kind, .out, "فهد")
        c.eq(h.topVisible, true, "top bar")
        c.eq(s.tapRow(h.rounds[0]), true, "rows still tappable")
        c.eq(h.selected == nil, true, "but nothing opens while editing")
    }
    s.tapField(3)
    s.press(.erase)
    s.press(.erase)
    s.digits("23")
    s.press(.record)
    step("سالم 22 → 23 and «حفظ»: totals 70, 135, 70, 123, and أنور's 4 is back in the fields") { c in
        c.eq(s.totals, [70, 135, 70, 123], "totals")
        c.eq(h.entry[s.id(1)], EntryCell(kind: .exact, digits: "4"), "typed round back")
        c.eq(h.editId == nil, true, "edit closed")
        c.eq(h.padOn, false, "keypad down")
        c.eq(h.focus, s.id(0), "cursor on the first empty field")
    }
    s.tapRow(h.rounds[1])
    s.tapEdit(h.rounds[1])
    s.tapField(3)
    s.digits("9")
    s.tapCancelEdit()
    step("«إلغاء» drops the change and brings the typed round back") { c in
        c.eq(s.totals, [70, 135, 70, 123], "totals")
        c.eq(h.entry[s.id(1)], EntryCell(kind: .exact, digits: "4"), "typed round")
        c.eq(h.editId == nil, true, "edit closed")
    }
}

// MARK: 9. New game from the win screen

private func handNewGameFromPoster() {
    Report.begin("Hand 9 · the win screen's «لعبة جديدة»: «مين يلعب؟» with the same names; «إلغاء» goes back, «ابدأ» starts")
    let (d, app, s) = boardGame("h9")
    let h = app.hand
    for r in boardRounds { s.record(r); s.wait(1100) }
    s.wait(3000)
    s.tapPosterNewGame()
    step("«لعبة جديدة» on the win screen: «مين يلعب؟» with حمد, أنور, فهد, سالم") { c in
        c.eq(h.setupOpen, true, "sheet")
        c.eq(h.setup.players.map(\.name), boardNames, "names")
    }
    s.setupCancel()
    step("«إلغاء»: back on the win screen, the game as it was") { c in
        c.eq(h.posterVisible, true, "win screen")
        c.eq(h.rounds.count, 9, "rounds")
    }
    s.tapPosterNewGame()
    s.setupStart()
    step("«ابدأ»: a new game with the same names, saved, round 1 of 7") { c in
        c.eq(h.rounds.count, 0, "rounds")
        c.eq(s.names, boardNames, "names")
        c.eq(h.posterVisible, false, "win screen")
        c.eq(h.roundLine, "الجولة 1 من 7", "status line")
        c.eq(h.homeStatus, "لعبة جديدة", "home card")
        c.eq(savedHand(d)?.rounds.count, 0, "saved")
        c.eq(h.topVisible, true, "top bar")
        c.eq(s.tapField(0), true, "fields open")
    }
}

// MARK: 10. Voice off

private func handVoiceOff() {
    Report.begin("Hand 10 · sound off on the home page: the banners show, nothing is said")
    let (_, app, s) = boardGame("h10")
    let h = app.hand
    tapVoiceChip(app)
    playMidgame(s)
    s.tapField(0)
    s.press(.finish(.hand))
    s.digits("25")
    s.press(.record)
    step("«أنور نزل هند» and the refusal «أنور عنده نزول» show; neither is said") { c in
        c.eq(h.banner, "أنور عنده نزول", "banner")
        c.eq(app.speaker.spoken().count, 0, "said")
        c.eq(app.speaker.log.filter { $0.kind == .muted }.map(\.text), ["أنور نزل هند", "أنور عنده نزول"], "asked while muted")
    }
    s.tapField(1)
    s.press(.notDown)
    s.press(.record)
    for r in [[Cell.nd, .nd, .n(31), .out], [.nd, .nd, .out, .nd], [.nd, .out, .nd, .nd]] {
        s.wait(3300)
        s.record(r)
    }
    s.wait(3000)
    step("the win comes and is not said") { c in
        c.eq(h.isWon, true, "won")
        c.eq(app.speaker.spoken().count, 0, "said")
    }
}

// MARK: 11. Save and restore

private func handSaveRestore() {
    Report.begin("Hand 11 · saved and restored: players, rounds, totals; a won game reopens on its win screen; the typed round")
    let (d, app, s) = boardGame("h11")
    playMidgame(s)
    let ids = app.hand.rounds.map(\.id)
    let app2 = launch(d)
    let h2 = app2.hand
    let s2 = HandScreen(app: app2)
    s2.open()
    step("relaunch: the names, the three rounds (ids too), 100 · 75 · 270 · 322, the نزول, no sheet, nothing said") { c in
        c.eq(s2.names, boardNames, "names")
        c.eq(h2.rounds.map(\.id), ids, "rounds")
        c.eq(s2.totals, [100, 75, 270, 322], "totals")
        c.eq(s2.downs, [1, 1, 0, 1], "downs")
        c.eq(h2.setupOpen, false, "sheet")
        c.eq(app2.speaker.log.count, 0, "voice")
    }
    s2.record([.out, .nd, .nd, .nd])
    step("the next round gets a new id") { c in c.eq(Set(h2.rounds.map(\.id)).count, 4, "unique ids") }
    s2.wait(1100)
    for r in [[Cell.nd, .nd, .n(31), .out], [.nd, .nd, .out, .nd], [.nd, .out, .nd, .nd]] { s2.record(r); s2.wait(3300) }
    let app3 = launch(d)
    let h3 = app3.hand
    VirtualClock.advance(by: 4000)
    step("relaunch after the win: on the win screen at once, parts in, nothing runs, nothing said") { c in
        c.eq(h3.isWon, true, "won")
        c.eq(h3.posterVisible, true, "win screen")
        c.eq(h3.intro, true, "parts in")
        c.eq(app3.speaker.log.count, 0, "voice")
        c.eq(VirtualClock.fired.filter { $0.owner == "hand" }.count, 0, "timers")
    }
    // The round being typed is part of the saved state (HandStore.Saved.entry).
    let (d4, app4, s4) = boardGame("h11-typed")
    playMidgame(s4)
    s4.tapField(0)
    s4.press(.finish(.out))
    s4.digits("25")
    let typed = app4.hand.entry
    let r = app4.hand.rounds[2]
    s4.tapRow(r)
    s4.tapDelete(r)
    s4.tapConfirmDelete(r)
    s4.wait(1100)
    s4.tapField(1)
    for _ in 0..<3 { s4.press(.erase) }
    s4.tapField(0)
    s4.press(.erase)
    let onScreen = app4.hand.entry
    s4.tapHome()
    let app5 = launch(d4)
    step("a round typed, a row deleted, the typed round then cleared, the app closed: the next launch shows the fields as they were left") { c in
        c.eq(typed[s4.id(1)], EntryCell(kind: .exact, digits: "25"), "typed before the delete")
        c.eq(onScreen.values.filter { $0 != .empty && $0 != .notDown }.count, 0, "cleared before closing")
        c.eq(entryText(app5.hand.entry, app5.hand.players), entryText(onScreen, app4.hand.players), "the fields after the relaunch")
    }
}

// MARK: 12. Corrupted save

private func handCorruptedSave() {
    Report.begin("Hand 12 · a damaged save: unreadable data starts over; bad players and rounds are dropped")
    let d = freshDefaults("h12")
    d.set(Data("{broken".utf8), forKey: "hand.v1")
    let app = launch(d)
    let s = HandScreen(app: app)
    s.open()
    step("unreadable bytes: a fresh start, so «مين يلعب؟» opens, no crash; the bytes kept under «hand.v1.damaged» (build 4)") { c in
        c.eq(app.hand.rounds.count, 0, "rounds")
        c.eq(app.hand.setupOpen, true, "sheet")
        c.eq(app.hand.players.count, 4, "players")
        c.eq(damagedCopy(d, "hand.v1"), "{broken", "damaged copy")
    }
    let d2 = freshDefaults("h12b")
    let one = #"{"players":[{"id":"p1","name":"حمد"}],"rounds":[],"entry":{},"uid":100,"started":true}"#
    d2.set(Data(one.utf8), forKey: "hand.v1")
    let app2 = launch(d2)
    step("a single player: not a game, a fresh start; the save kept aside") { c in
        c.eq(app2.hand.players.count, 4, "players")
        c.eq(app2.hand.started, false, "started")
        c.eq(damagedCopy(d2, "hand.v1"), one, "damaged copy")
    }
    let d3 = freshDefaults("h12c")
    let json = """
    {"players":[{"id":"p1","name":"حمد"},{"id":"p2","name":"أنور"},{"id":"p2","name":"نسخة"},{"id":"p3","name":"فهد"}],
     "rounds":[
      {"id":101,"cells":{"p1":{"kind":"out","cards":0},"p2":{"kind":"num","cards":35},"p3":{"kind":"nd","cards":0}}},
      {"id":101,"cells":{"p1":{"kind":"nd","cards":0},"p2":{"kind":"out","cards":0},"p3":{"kind":"nd","cards":0}}},
      {"id":102,"cells":{"p1":{"kind":"nd","cards":0},"p2":{"kind":"out","cards":0}}},
      {"id":103,"cells":{"p1":{"kind":"num","cards":1000},"p2":{"kind":"out","cards":0},"p3":{"kind":"nd","cards":0}}},
      {"id":104,"cells":{"p1":{"kind":"nd","cards":0},"p2":{"kind":"nd","cards":0},"p3":{"kind":"out","cards":0}}}
     ],
     "entry":{"p1":{"kind":"out","digits":""}},"uid":104,"started":true}
    """
    d3.set(Data(json.utf8), forKey: "hand.v1")
    let app3 = launch(d3)
    let h3 = app3.hand
    step("the duplicate player dropped; the duplicate round, the round missing a player and the one with 1000 cards dropped") { c in
        c.eq(h3.players.map(\.name), ["حمد", "أنور", "فهد"], "players")
        c.eq(h3.rounds.map(\.id), [101, 104], "rounds")
        c.eq(h3.players.map { h3.totals[$0.id] ?? 0 }, [70, 135, 70], "totals")
        c.eq(h3.entry["p1"]?.kind, .out, "typed field kept")
        c.eq(damagedCopy(d3, "hand.v1"), json, "the save as it was, kept aside (build 4)")
    }
    let s3 = HandScreen(app: app3)
    s3.record([.out, .nd, .nd])
    step("the next round gets a new id") { c in c.eq(Set(h3.rounds.map(\.id)).count, 3, "unique ids") }
}

/// Probes that may crash the process run in their own process (run.sh): true is PASS.
let probes: [String: () -> Bool] = [
    // A save whose uid is below a player's number (p101 with uid 100): «إضافة لاعب» then «ابدأ».
    "hand-uid-below-player-id": {
        let d = freshDefaults("probe-uid")
        let json = #"{"players":[{"id":"p1","name":"حمد"},{"id":"p101","name":"بدر"}],"rounds":[],"entry":{},"uid":100,"started":true}"#
        d.set(Data(json.utf8), forKey: "hand.v1")
        let app = launch(d)
        let s = HandScreen(app: app)
        s.tapNewGame()
        s.setupAdd()
        let ids = app.hand.setup.players.map(\.id)
        FileHandle.standardError.write(Data("probe: setup ids after «إضافة لاعب»: \(ids)\n".utf8))
        s.setupStart()
        FileHandle.standardError.write(Data("probe: started with \(app.hand.players.map(\.id))\n".utf8))
        return Set(app.hand.players.map(\.id)).count == app.hand.players.count
    }
]

// MARK: 13. A new action in the middle of a running sequence

private func handMidSequence() {
    Report.begin("Hand 13 · a new action in the middle of a running sequence")
    do {
        let (_, app, s) = boardGame("h13a")
        let h = app.hand
        playMidgame(s)
        let t0 = VirtualClock.now
        s.record([.out, .nd, .n(25), .nd])
        s.wait(500)
        let at500 = s.store.shown(at: Date())
        s.record([.out, .nd, .nd, .nd])
        step("a round 500 ms after the last: the boxes keep the numbers they had reached, then count on") { c in
            c.eq(at500[s.id(0)], boardCount(100, 70, elapsed: 140), "حمد at 500 ms")
            c.eq(h.shown(at: Date())[s.id(0)], at500[s.id(0)], "right after")
        }
        s.wait(2000)
        step("…with one count end, at 500+1060") { c in
            c.eq(fired("hand", from: t0, to: t0 + 3000, keys: ["countEnd"]).map(\.time), [t0 + 1560], "count ends")
            c.eq(s.totals, [40, 275, 395, 522], "totals")
        }
    }
    do {
        let (_, app, s) = boardGame("h13b")
        let h = app.hand
        for r in boardRounds.prefix(8) { s.record(r); s.wait(1100) }
        step("setup: «آخر جولة» shows after round 8") { c in c.eq(h.bannerOn, true, "banner") }
        s.record(boardRounds[8])
        step("the winning round while «آخر جولة» is still up: the banner goes at once") { c in c.eq(h.bannerOn, false, "banner") }
        s.wait(3000)
        step("…and the win sequence ends on the win screen with «الفوز لحمد»") { c in
            c.eq(h.posterVisible, true, "win screen")
            c.eq(app.speaker.spoken().last?.text, "الفوز لحمد", "voice")
        }
    }
    do {
        let (_, app, s) = boardGame("h13c")
        let h = app.hand
        playMidgame(s)
        s.record([.out, .nd, .n(25), .nd])
        s.wait(400)
        s.tapNewGame()
        s.setupStart()
        s.wait(3000)
        step("«لعبة جديدة» and «ابدأ» in the middle of a count: clean, nothing from the old game runs after") { c in
            c.eq(h.rounds.count, 0, "rounds")
            c.eq(h.display == nil && h.countStart == nil, true, "count")
            c.eq(h.pulse.isEmpty && h.ghost == nil, true, "motion")
            c.eq(VirtualClock.pendingKeys.filter { $0.hasPrefix("hand.") }, [], "pending")
        }
    }
    do {
        let (_, app, s) = boardGame("h13d")
        let h = app.hand
        playMidgame(s)
        s.record([.out, .nd, .n(25), .nd])
        s.wait(300)
        let mark = app.speaker.mark
        s.tapField(0)
        s.press(.finish(.hand))
        s.digits("25")
        s.press(.record)
        s.wait(2000)
        step("a refused round 300 ms into a count: the refusal shows, the count still ends on the recorded totals") { c in
            c.eq(app.speaker.spoken(since: mark).map(\.text), ["أنور عنده نزول"], "voice")
            c.eq(s.totals, [70, 175, 295, 422], "totals")
            c.eq(h.counting, false, "count over")
        }
    }
    do {
        let (_, app, s) = boardGame("h13f")
        let h = app.hand
        playMidgame(s)
        s.record([.out, .nd, .n(25), .nd])
        s.wait(500)
        let at500 = h.shown(at: Date())[s.id(0)]
        let r = h.rounds[3]
        s.tapRow(r)
        s.tapDelete(r)
        let td = VirtualClock.now
        s.tapConfirmDelete(r)
        step("deleting the round 500 ms into its own count: the boxes start back at once from where they were") { c in
            c.eq(h.shown(at: Date())[s.id(0)], at500, "حمد on screen")
            c.eq(h.counting, true, "counting at once")
        }
        s.wait(1000)
        step("…and end 700 ms later on the midgame totals") { c in
            c.eq(fired("hand", from: td, to: td + 1000, keys: ["countEnd"]).map(\.time), [td + 700], "count end")
            c.eq(s.totals, [100, 75, 270, 322], "totals")
            c.eq(h.shown(at: Date())[s.id(0)], 100, "on screen")
        }
    }
    do {
        let (_, app, s) = boardGame("h13g")
        let h = app.hand
        playMidgame(s)
        s.record([.out, .nd, .n(25), .nd])
        s.wait(200)
        let r = h.rounds[3]
        s.tapRow(r)
        s.tapEdit(r)
        s.tapField(2)
        s.press(.erase)
        s.press(.erase)
        s.press(.notDown)
        s.press(.record)
        s.wait(2000)
        step("editing the round 200 ms into its count (فهد 25 → «ما نزل»): the count settles on the edited totals, نزول back to 0") { c in
            c.eq(s.totals, [70, 175, 370, 422], "totals")
            c.eq(s.downs, [1, 1, 0, 1], "downs")
            c.eq(h.counting, false, "count over")
            c.eq(h.editId == nil, true, "edit closed")
        }
    }
    do {
        let (_, app, s) = boardGame("h13e")
        let h = app.hand
        for r in boardRounds { s.record(r); s.wait(1100) }
        s.wait(900)
        let mark = app.speaker.mark
        s.tapPosterEdit()
        s.tapCancelEdit()
        s.wait(3000)
        step("«تعديل» right as the win screen comes (before its voice), then «إلغاء»: the win screen comes back without the voice (as the board)") { c in
            c.eq(h.posterVisible, true, "win screen")
            c.eq(app.speaker.spoken(since: mark).count, 0, "voice")
        }
    }
}

// MARK: 14. Reduce Motion

private func handReduceMotion() {
    Report.begin("Hand 14 · Reduce Motion: the totals and the نزول circles at once; the voice about 100 ms after the win")
    let (_, app, s) = boardGame("h14")
    Motion.reduceMotionSwitch = true
    let h = app.hand
    s.record([.out, .n(35), .nd, .nd])
    step("a round: totals final at once, the circle at once, no breathing") { c in
        c.eq(h.counting, false, "count")
        c.eq(h.pipOn, true, "circles")
        c.eq(h.pulse.isEmpty, true, "pulse")
        c.eq(h.shown(at: Date())[s.id(0)], -30, "shown")
    }
    for r in boardRounds.dropFirst().prefix(7) { s.record(r) }
    let t0 = VirtualClock.now
    let mark = app.speaker.mark
    s.record(boardRounds[8])
    s.wait(1000)
    step("the win: no box, the win screen at once, «الفوز لحمد» at +70 ms") { c in
        c.eq(h.posterVisible, true, "win screen")
        c.eq(app.speaker.spoken(since: mark).map(\.text), ["الفوز لحمد"], "voice")
        c.eq(app.speaker.spoken(since: mark).first.map { "+\($0.time - t0) ms" }, "+70 ms", "time")
        c.eq(fired("hand", from: t0, to: t0 + 1000, keys: ["growBox", "growFull", "growOff"]), [], "no growing box")
    }
}

// MARK: 15. Six players and long names (board flows six_big, six_downs, long_names)

private func handSixPlayersAndLongNames() {
    Report.begin("Hand 15 · six players and long names (board flows six_big, six_downs, long_names)")
    do {
        let d = freshDefaults("h15a")
        let app = launch(d)
        let s = HandScreen(app: app)
        s.open()
        for (i, n) in boardNames.enumerated() { s.setupName(i, n) }
        s.setupAdd()
        s.setupAdd()
        s.setupStart()
        step("six_big: six players, «لاعب 5» and «لاعب 6»") { c in c.eq(s.names, boardNames + ["لاعب 5", "لاعب 6"], "names") }
        s.record([.joker2, .nd, .nd, .nd, .nd, .nd])
        s.wait(1600)
        let mark = app.speaker.mark
        s.record([.nd, .joker2, .nd, .nd, .nd, .nd])
        step("two جيكرين: 560, 560, 1600 × 4; the second one says only «أنور نزل جيكرين»") { c in
            c.eq(s.totals, [560, 560, 1600, 1600, 1600, 1600], "totals")
            c.eq(app.speaker.spoken(since: mark).map(\.text), ["أنور نزل جيكرين"], "voice")
            c.eq(app.hand.banner, "أنور نزل جيكرين", "banner")
        }
    }
    do {
        let d = freshDefaults("h15b")
        let app = launch(d)
        let s = HandScreen(app: app)
        s.open()
        for (i, n) in boardNames.enumerated() { s.setupName(i, n) }
        s.setupAdd()
        s.setupAdd()
        s.setupStart()
        s.tapField(0)
        s.press(.finish(.joker))
        s.digits("40")
        s.press(.record)
        s.wait(3800)
        s.tapField(0)
        s.press(.finish(.out))
        s.digits("45")
        s.tapField(2)
        s.digits("33")
        s.press(.record)
        step("six_downs: أنور 40 (his 10 × 4) in the جيكر round, then أنور 45 and فهد 33") { c in
            c.eq(s.totals, [-150, 85, 433, 500, 500, 500], "totals")
            c.eq(s.downs, [0, 2, 1, 0, 0, 0], "downs")
        }
        s.wait(1500)
        s.tapField(0)
        s.press(.finish(.out))
        s.digits("20")
        let mark = app.speaker.mark
        s.press(.record)
        step("…a third for أنور is refused: «أنور عنده نزولين»") { c in
            c.eq(app.speaker.spoken(since: mark).map(\.text), ["أنور عنده نزولين"], "voice")
            c.eq(app.hand.rounds.count, 2, "rounds")
        }
    }
    do {
        let d = freshDefaults("h15c")
        let app = launch(d)
        let s = HandScreen(app: app)
        s.open()
        for (i, n) in ["حمد", "أنور", "عبدالرحمن", "عبدالعزيز"].enumerated() { s.setupName(i, n) }
        s.setupStart()
        let mark = app.speaker.mark
        s.record([.nd, .nd, .joker, .nd])
        step("«عبدالرحمن نزل جيكر · 9 جولات ونزولين» (the board's first cut)") { c in
            c.eq(app.hand.banner, "عبدالرحمن نزل جيكر · 9 جولات ونزولين", "banner")
            c.eq(app.speaker.spoken(since: mark).map(\.text), ["عبدالرحمن نزل جيكر، وصارت تسع جولات ونزولين"], "voice")
        }
        let d2 = freshDefaults("h15d")
        let app2 = launch(d2)
        let s2 = HandScreen(app: app2)
        s2.open()
        for (i, n) in ["حمد", "أنور", "عبدالرحمن", "عبدالعزيز"].enumerated() { s2.setupName(i, n) }
        s2.setupStart()
        s2.record([.nd, .nd, .nd, .joker2])
        step("«جيكرين · صارت 9 جولات ونزولين» (the board's second cut, for عبدالعزيز)") { c in
            c.eq(app2.hand.banner, "جيكرين · صارت 9 جولات ونزولين", "banner")
        }
        s2.wait(3300)
        s2.tapField(0)
        s2.press(.finish(.joker2))
        s2.digits("96")
        s2.tapField(2)
        s2.press(.erase)
        s2.tapField(3)
        s2.press(.erase)
        step("long_names: أنور 96 (his 12 × 8) → erase on عبدالرحمن («ما نزل») empties it, and on عبدالعزيز; «سجّل» off") { c in
            c.eq(app2.hand.entry[s2.id(1)], EntryCell(kind: .exact, digits: "96"), "أنور")
            c.eq(app2.hand.entry[s2.id(2)], .empty, "عبدالرحمن")
            c.eq(app2.hand.entry[s2.id(3)], .empty, "عبدالعزيز")
            c.eq(app2.hand.status.ready, false, "ready")
            c.eq(HandRules.points(app2.hand.entry[s2.id(1)] ?? .empty, multiplier: app2.hand.status.multiplier), 96, "أنور 96, as typed")
        }
    }
}

// MARK: 19. Small things

private func handSmallThings() {
    Report.begin("Hand 19 · the keypad with the sheet or the win screen, leaving for home, the home card, haptics")
    let (_, app, s) = boardGame("h16")
    let h = app.hand
    playMidgame(s)
    s.tapField(0)
    s.tapHome()
    step("leaving for the home page puts the keypad away, the game stays") { c in
        c.eq(h.padOn, false, "keypad")
        c.eq(h.rounds.count, 3, "rounds")
    }
    s.tapRow(h.rounds[2])
    s.tapDelete(h.rounds[2])
    s.tapHome()
    step("…and closes an open row with its «احذف؟»") { c in
        c.eq(h.selected == nil && h.confirmId == nil, true, "row")
        c.eq(h.rounds.count, 3, "rounds")
    }
    s.tapNewGame()
    step("with «مين يلعب؟» open the keypad is locked") { c in
        c.eq(h.locked, true, "locked")
        c.eq(h.padUp, false, "pad")
    }
    s.setupCancel()
    let tick = h.feedbackTick
    s.record([.out, .nd, .nd, .nd])
    step("a round is a light impact") { c in
        c.eq(h.feedback, .record, "haptic")
        c.eq(h.feedbackTick, tick + 1, "once")
    }
    step("home card lines from the board's reportUp") { c in
        c.eq(HandRules.homeLine(players: h.players, rounds: []), "لعبة جديدة", "no rounds")
        c.eq(h.homeStatus, "الجولة 5 من 7", "four rounds")
    }
}

// MARK: 16. «تعديل» after a win

private func handEditAfterWin() {
    Report.begin("Hand 16 · «تعديل» on the win screen: the last round in the fields; the same winner is silent, a new winner plays the sequence again, a جيكر added reopens the game")
    let (_, app, s) = boardGame("h17")
    let h = app.hand
    for r in boardRounds { s.record(r); s.wait(1100) }
    s.wait(3000)
    let last = h.rounds[8]
    s.tapPosterEdit()
    step("«تعديل»: round 9 in the fields with the keypad up, «تعديل الجولة 9», the top bar back, the win screen gone") { c in
        c.eq(h.editId, last.id, "editing")
        c.eq(h.reviewing, true, "review")
        c.eq(h.editLine, "تعديل الجولة 9", "status line")
        c.eq(h.padUp, true, "keypad")
        c.eq(h.topVisible, true, "top bar")
        c.eq(h.posterVisible, false, "win screen")
        c.eq(h.entry[s.id(1)]?.kind, .out, "أنور خلّص")
        c.eq(s.recordLabel, "حفظ", "key")
    }
    let mark = app.speaker.mark
    s.tapCancelEdit()
    s.wait(3000)
    step("«إلغاء»: the win screen comes back with its entrance and no voice") { c in
        c.eq(h.posterVisible, true, "win screen")
        c.eq(h.intro, true, "parts in")
        c.eq(app.speaker.spoken(since: mark).count, 0, "voice")
    }
    s.tapPosterEdit()
    s.tapField(0)
    s.digits("12")
    s.tapField(0)
    s.digits("0")
    let mark2 = app.speaker.mark
    s.press(.record)
    s.wait(3000)
    step("حمد 120 instead of «ما نزل» in round 9 (277 → 297), still the lowest: «حفظ» is silent and the win screen comes back") { c in
        c.eq(s.totals[0], 297, "حمد")
        c.eq(h.posterVisible, true, "win screen")
        c.eq(app.speaker.spoken(since: mark2).count, 0, "voice")
        c.eq(h.entry.values.allSatisfy { $0 == .empty }, true, "fields cleared")
    }
    s.tapPosterEdit()
    s.tapField(0)
    s.press(.finish(.out))
    s.tapField(1)
    s.press(.notDown)
    s.tapField(2)
    s.press(.notDown)
    let te = VirtualClock.now
    let mark3 = app.speaker.mark
    s.press(.record)
    step("round 9 as حمد خلّص and أنور «ما نزل» (حمد 147, أنور 778): حمد still wins; silent") { c in
        c.eq(s.totals, [147, 778, 619, 1022], "totals")
        c.eq(h.outcome, .won(s.id(0)), "winner")
    }
    s.wait(3000)
    step("…no voice, win screen back") { c in
        c.eq(app.speaker.spoken(since: mark3).count, 0, "voice")
        c.eq(h.posterVisible, true, "win screen")
        c.eq(fired("hand", from: te, to: te + 3000, keys: ["growBox", "poster", "voice"]), [], "no sequence")
    }
    // A new winner: round 9 with فهد خلّص ×… make فهد the lowest.
    s.tapPosterEdit()
    s.tapField(2)
    s.press(.finish(.joker2))
    let tw = VirtualClock.now
    let mark4 = app.speaker.mark
    s.press(.record)
    step("round 9 as فهد جيكرين (−240; the rest 800 each): فهد 279 is now the lowest, so the whole sequence plays again") { c in
        c.eq(s.totals, [977, 1478, 279, 1722], "totals")
        c.eq(h.outcome, .won(s.id(2)), "winner")
        c.eq(h.holdPoster, true, "held")
    }
    s.wait(3000)
    step("…«الفوز لفهد» at +2010 (edits count at once: 700 + 800 + 30 + 480)") { c in
        c.eq(app.speaker.spoken(since: mark4).map(\.text), ["الفوز لفهد"], "voice")
        c.eq(app.speaker.spoken(since: mark4).first.map { "+\($0.time - tw) ms" }, "+2010 ms", "time")
        c.eq(h.posterVisible, true, "win screen")
    }

    // A 7-round game won without a جيكر; «تعديل» puts a جيكر in round 7: the game grows to 9 and reopens.
    let (_, app2, s2) = boardGame("h17b")
    let h2 = app2.hand
    let seven: [[Cell]] = [[.out, .nd, .nd, .nd], [.nd, .out, .nd, .nd], [.nd, .nd, .out, .nd], [.nd, .nd, .nd, .out],
                           [.out, .nd, .nd, .nd], [.nd, .out, .nd, .nd], [.out, .nd, .nd, .nd]]
    for r in seven { s2.record(r); s2.wait(1100) }
    s2.wait(3000)
    step("setup: seven rounds, حمد wins 310 · 440 · 570 · 570") { c in
        c.eq(s2.totals, [310, 440, 570, 570], "totals")
        c.eq(h2.outcome, .won(s2.id(0)), "winner")
        c.eq(h2.posterVisible, true, "win screen")
    }
    s2.tapPosterEdit()
    s2.tapField(0)
    s2.press(.finish(.joker))
    let mark5 = app2.speaker.mark
    s2.press(.record)
    step("round 7 as حمد جيكر: 9 rounds now, so the game reopens with «صارت 9 جولات ونزولين», round 8 of 9") { c in
        c.eq(s2.totals, [220, 740, 870, 870], "totals")
        c.eq(h2.isWon, false, "won")
        c.eq(h2.target, 9, "target")
        c.eq(h2.banner, "صارت 9 جولات ونزولين", "banner")
        c.eq(app2.speaker.spoken(since: mark5).map(\.text), ["صارت تسع جولات ونزولين"], "voice")
        c.eq(h2.roundLine, "الجولة 8 من 9", "status line")
        c.eq(h2.posterVisible || h2.reviewing, false, "win screen or review")
        c.eq(h2.topVisible, true, "top bar")
        c.eq(h2.segFrom, 7, "two new segments")
        c.eq(s2.tapField(1), true, "fields open")
    }
}

private func handTwoPlayers() {
    Report.begin("Hand 18 · two players: the finisher puts the other on «ما نزل», and the cursor goes to him")
    let d = freshDefaults("h19")
    let app = launch(d)
    let s = HandScreen(app: app)
    s.open()
    s.setupRemove(3)
    s.setupRemove(2)
    s.setupName(0, "حمد")
    s.setupName(1, "Sam")
    s.setupStart()
    s.tapField(0)
    s.press(.finish(.hand))
    step("حمد هند: Sam «ما نزل» 200, the cursor on Sam") { c in
        c.eq(app.hand.entry[s.id(1)]?.kind, .notDown, "Sam")
        c.eq(app.hand.focus, s.id(1), "cursor")
    }
    s.digits("70")
    s.press(.record)
    step("Sam 70 (his 35 × 2) → −60 and 70") { c in c.eq(s.totals, [-60, 70], "totals") }
    for r in [[Cell.nd, .out], [.out, .nd], [.nd, .out], [.out, .nd], [.nd, .out], [.nd, .out]] { s.wait(3300); s.record(r) }
    s.wait(3000)
    step("seven rounds: Sam wins, «الفوز لـ Sam» (a name in Latin letters)") { c in
        c.eq(app.hand.outcome, .won(s.id(1)), "winner")
        c.eq(app.speaker.spoken().last?.text, "الفوز لـ Sam", "voice")
    }
}

private func handTwoOverAtOnce() {
    Report.begin("Hand 17 · two players past the cap in one round: «حمد وأنور عندهم نزول», both fields shake")
    let (_, app, s) = boardGame("h18")
    let h = app.hand
    playMidgame(s)
    s.tapField(2)
    s.press(.finish(.out))
    s.tapField(0)
    s.digits("15")
    s.tapField(1)
    s.digits("20")
    let mark = app.speaker.mark
    s.press(.record)
    step("refused with both names, the cursor on the first, both shaking") { c in
        c.eq(h.banner, "حمد وأنور عندهم نزول", "banner")
        c.eq(app.speaker.spoken(since: mark).map(\.text), ["حمد وأنور عندهم نزول"], "voice")
        c.eq(h.shakeIds, [s.id(0), s.id(1)], "shake")
        c.eq(h.focus, s.id(0), "cursor")
        c.eq(h.rounds.count, 3, "rounds")
    }
}

/// The settings on the home page (Settings.swift, compiled as is).
private func settingsScenario() {
    Report.begin("Settings · theme تلقائي → نوار → عاجي → تلقائي, voice and haptics, kept across launches")
    let d = freshDefaults("settings")
    let app = launch(d)
    let st = app.settings
    step("defaults: تلقائي, voice on, haptics on") { c in
        c.eq(st.theme, .auto, "theme")
        c.eq(st.theme.label, "تلقائي", "label")
        c.eq(st.voice && st.haptics, true, "voice and haptics")
    }
    st.cycleTheme()
    let first = st.theme
    st.cycleTheme()
    let second = st.theme
    st.toggleHaptics()
    step("the theme cycles نوار then عاجي; haptics off") { c in
        c.eq([first.label, second.label], ["نوار", "عاجي"], "themes")
        c.eq(st.haptics, false, "haptics")
    }
    let app2 = launch(d)
    step("kept after a relaunch") { c in
        c.eq(app2.settings.theme, .ivory, "theme")
        c.eq(app2.settings.haptics, false, "haptics")
        c.eq(app2.settings.voice, true, "voice")
    }
    app2.settings.cycleTheme()
    step("…and عاجي goes back to تلقائي") { c in c.eq(app2.settings.theme, .auto, "theme") }
}

/// The fields as a line: «حمد خلّص · أنور 25 · فهد ما نزل · سالم —».
func entryText(_ entry: [String: EntryCell], _ players: [HandPlayer]) -> String {
    players.map { p in
        let x = entry[p.id] ?? .empty
        let v: String
        if let k = x.kind, k.isFinish || k == .notDown {
            v = k.name + (x.declared > 0 ? " " + HandRules.declaredName(x.declared) : "")
        } else if x.kind == .cards || x.kind == .exact || x.kind == .free, !x.digits.isEmpty || x.negative {
            v = (x.negative ? "−" : "") + x.digits
        } else { v = "—" }
        return HandRules.name(of: p.id, in: players) + " " + v
    }.joined(separator: " · ")
}
