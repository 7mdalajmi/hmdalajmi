import Foundation
import SwiftUI

// Scenarios for build 6 (22 Oct 2026), from the owner's words: «عطني حرية تسجيل اي عدد في الصندوق» (answered
// «اكتب اي رقم ثم اختار الصندوق اللي وراه بدون اي ينضرب او يزيد عليه شي»), «زر حق زات وهو عبارة عن انتهاء اللعبه
// والفوز للاعب اللي يجيب زات», and «زر حق معلن جيكر او جيكرين» (answered «اللي معلن ياخذ ٢٠٠+١٠٠ واذا كان معلن
// جيكرين يكون ٢٠٠+٢٠٠», and «مايصير ينزل وعنده جيكر!»). Numbers typed as they are are in Build5Scenarios (27).

func runBuild6Scenarios() {
    handZat()
    handZatInEdits()
    handDeclared()
    handOldSave()
    handOldTyping()
}

private func boardPlayersGame(_ tag: String) -> (UserDefaults, AppModel, HandScreen) {
    let d = freshDefaults(tag)
    let app = launch(d)
    let s = HandScreen(app: app)
    s.open()
    for (i, n) in boardNames.enumerated() { s.setupName(i, n) }
    s.setupStart()
    return (d, app, s)
}

private func midgame(_ s: HandScreen) {
    for r in boardRounds.prefix(3) {
        s.record(r)
        s.wait(3300)
    }
}

private func handZat() {
    Report.begin("Hand 29 · زات (build 6): the other fields stay as typed, faded and closed, «سجّل» at once, the game ends and whoever got it wins, whatever the totals; «حمد جاب زات، والفوز لحمد»")
    let (d, app, s) = boardPlayersGame("h29")
    let h = app.hand
    midgame(s)
    s.tapField(1)
    s.digits("35")
    s.tapField(2)
    s.press(.declared)
    s.tapField(3)
    s.press(.finish(.zat))
    let entry = h.entry
    let ready = s.canPress(.record)
    let focusAfter = h.focus
    step("midgame (100, 75, 270, 322), أنور 35 and فهد معلن typed, then سالم زات: the other fields stay as typed, «سجّل» is on, the focus stays on سالم") { c in
        c.eq(entryText(entry, h.players), "حمد — · أنور 35 · فهد ما نزل معلن جيكر · سالم زات", "fields")
        c.eq(ready, true, "«سجّل»")
        c.eq(focusAfter, s.id(3), "focus")
        c.eq(h.status.over, [], "no نزول in a round of زات")
    }
    s.tapField(1)
    let closed = [PadKey.digit("7"), .sign, .erase, .notDown, .declared, .fromHand].map { s.canPress($0) }
    let open = [PadKey.finish(.hand), .finish(.zat), .record].map { s.canPress($0) }
    s.press(.digit("7"))
    let untouched = entryText(h.entry, h.players)
    s.tapField(3)
    step("a tap on أنور's faded field: only the finish keys and «سجّل»; a digit does nothing") { c in
        c.eq(closed, [false, false, false, false, false, false], "digits, ±, ⌫, ما نزل, معلن, من إيده")
        c.eq(open, [true, true, true], "هند, زات, «سجّل»")
        c.eq(untouched, "حمد — · أنور 35 · فهد ما نزل معلن جيكر · سالم زات", "fields")
    }
    let t0 = VirtualClock.now
    let m = app.speaker.mark
    s.press(.record)
    step("«سجّل»: سالم wins with the highest total, the totals stay, the win sequence holds the screen, no banner") { c in
        c.eq(h.outcome, .won(s.id(3)), "winner")
        c.eq(s.totals, [100, 75, 270, 322], "totals")
        c.eq(s.downs, [1, 1, 0, 1], "downs")
        c.eq(h.holdPoster, true, "held")
        c.eq(h.bannerOn, false, "banner")
        c.eq(h.homeStatus, "الفوز لسالم", "home card")
        c.eq(h.roundLine, "", "status line")
        c.eq(h.wonByZat, true, "won by زات")
        c.eq(h.ghost == nil, true, "no number lifts out of the fields (the review: every field lifted a 0)")
    }
    s.wait(400)
    let pulsed = h.pulse
    s.wait(2600)
    step("the win screen with «زات», and «سالم جاب زات، والفوز لسالم» once, at +1670 ms (no count: the totals did not move)") { c in
        c.eq(h.posterVisible, true, "win screen")
        c.eq(app.speaker.spoken(since: m).map(\.text), ["سالم جاب زات، والفوز لسالم"], "voice")
        c.eq(app.speaker.spoken(since: m).first.map { "+\($0.time - t0) ms" }, "+1670 ms", "time")
        c.eq(h.rounds.map { h.canTouch($0) }, [false, false, false, false], "rows")
        c.eq(pulsed.isEmpty, true, "no pulse on the boxes at +400 ms: nothing landed in them")
    }
    let app2 = launch(d)
    VirtualClock.advance(by: 4000)
    step("a relaunch: the win screen at once, won by زات, nothing said") { c in
        c.eq(app2.hand.outcome, .won(s.id(3)), "winner")
        c.eq(app2.hand.posterVisible, true, "win screen")
        c.eq(app2.hand.wonByZat, true, "زات")
        c.eq(app2.speaker.log.count, 0, "voice")
    }
    let s2 = HandScreen(app: app2)
    let h2 = app2.hand
    s2.tapPosterEdit()
    let inFields = entryText(h2.entry, h2.players)
    let zatKey = s2.canPress(.finish(.zat))
    s2.tapField(3)
    s2.press(.finish(.out))
    let m2 = app2.speaker.mark
    s2.press(.record)
    s2.wait(1200)
    step("«تعديل» on the win screen: the round of زات in the fields; سالم خلّص instead and «حفظ»: the game plays on, 200, 175, 370, 292") { c in
        c.eq(inFields, "حمد — · أنور — · فهد — · سالم زات", "the round in the fields")
        c.eq(zatKey, true, "زات open in the newest round")
        c.eq(h2.outcome, .playing, "playing")
        c.eq(s2.totals, [200, 175, 370, 292], "totals")
        c.eq(h2.roundLine, "الجولة 5 من 7", "status line")
        c.eq(app2.speaker.spoken(since: m2).count, 0, "voice")
        c.eq(h2.posterVisible, false, "win screen")
    }
}

private func handZatInEdits() {
    Report.begin("Hand 30 · زات in edits (build 6): open in a new round and the newest one, not in an older round; ⌫ on زات takes it off")
    let (_, app, s) = boardPlayersGame("h30")
    let h = app.hand
    midgame(s)
    let older = h.rounds[1]
    s.tapRow(older)
    s.tapEdit(older)
    s.tapField(0)
    let offInOlder = !s.canPress(.finish(.zat))
    let pressed = s.press(.finish(.zat))
    s.tapCancelEdit()
    let newest = h.rounds[2]
    s.tapRow(newest)
    s.tapEdit(newest)
    s.tapField(0)
    let onInNewest = s.canPress(.finish(.zat))
    s.tapCancelEdit()
    step("round 2 being edited: زات is off; round 3 (the newest): on") { c in
        c.eq(offInOlder, true, "off in round 2")
        c.eq(pressed, false, "a tap does nothing")
        c.eq(onInNewest, true, "on in round 3")
    }
    s.tapField(2)
    s.press(.finish(.zat))
    s.press(.erase)
    step("a new round: فهد زات, then ⌫ on him: the field empties, nobody finished, «سجّل» off") { c in
        c.eq(h.entry[s.id(2)], .empty, "فهد")
        c.eq(h.status.finisher == nil, true, "finisher")
        c.eq(s.canPress(.record), false, "«سجّل»")
    }
    s.press(.finish(.zat))
    s.tapField(0)
    s.press(.finish(.hand))
    step("فهد زات, then حمد هند: زات goes back to «ما نزل» with the others, ×2") { c in
        c.eq(entryText(h.entry, h.players), "حمد هند · أنور ما نزل · فهد ما نزل · سالم ما نزل", "fields")
        c.eq(h.status.multiplier, 2, "multiplier")
    }
}

private func handDeclared() {
    Report.begin("Hand 31 · «معلن» (build 6): on ما نزل, +100 for جيكر and +200 for جيكرين, for any number of players, with «من إيده» too; off on the finisher; a number typed takes it off")
    let (d, app, s) = boardPlayersGame("h31")
    let h = app.hand
    midgame(s)
    s.tapField(0)
    s.press(.finish(.hand))
    s.tapField(0)
    let offOnFinisher = !s.canPress(.declared)
    s.tapField(1)
    s.digits("35")
    s.press(.declared)
    let first = h.entry[s.id(1)]
    s.press(.declared)
    let caption = HandRules.points(h.entry[s.id(1)] ?? .empty, multiplier: h.status.multiplier)
    s.tapField(2)
    s.press(.declared)
    s.press(.fromHand)
    s.tapField(3)
    s.press(.declared)
    s.digits("4")
    let typedOver = h.entry[s.id(3)]
    s.press(.erase)
    s.press(.notDown)
    step("حمد هند; أنور 35 then «معلن»: ما نزل with معلن جيكر, again: جيكرين, 200 + 200; فهد معلن جيكر and «من إيده»; سالم معلن then 4 typed: the mark goes") { c in
        c.eq(offOnFinisher, true, "off on حمد")
        c.eq(first, EntryCell(kind: .notDown, declared: 1), "أنور after one press")
        c.eq(caption, 400, "أنور comes to 400")
        c.eq(h.entry[s.id(2)], EntryCell(kind: .notDown, fromHand: true, declared: 1), "فهد")
        c.eq(typedOver, EntryCell(kind: .exact, digits: "4"), "سالم")
        c.eq(entryText(h.entry, h.players), "حمد هند · أنور ما نزل معلن جيكرين · فهد ما نزل معلن جيكر · سالم ما نزل", "fields")
    }
    let app2 = launch(d)
    let s2 = HandScreen(app: app2)
    let h2 = app2.hand
    step("the app closed while typing: the fields come back with their marks") { c in
        c.eq(h2.entry, h.entry, "fields")
    }
    s2.tapField(0)
    s2.press(.record)
    step("«سجّل»: −60, 400, 200 + 50 + 100 = 350, 200; no نزول added; «حمد نزل هند»") { c in
        c.eq(HandRules.points(h2.rounds[3]).sorted { $0.key < $1.key }.map(\.value), [-60, 400, 350, 200], "round 4")
        c.eq(s2.totals, [40, 475, 620, 522], "totals")
        c.eq(s2.downs, [1, 1, 0, 1], "downs")
        c.eq(h2.banner, "حمد نزل هند", "banner")
    }
    s2.wait(3300)
    let r4 = h2.rounds[3]
    s2.tapRow(r4)
    s2.tapEdit(r4)
    let editing = entryText(h2.entry, h2.players)
    s2.tapField(1)
    s2.press(.declared)
    s2.press(.record)
    s2.wait(3300)
    step("«تعديل» of round 4: the marks in the fields; «معلن» once more on أنور takes it off: 200, totals 40, 275, 620, 522") { c in
        c.eq(editing, "حمد هند · أنور ما نزل معلن جيكرين · فهد ما نزل معلن جيكر · سالم ما نزل", "in the edit")
        c.eq(s2.totals, [40, 275, 620, 522], "totals")
    }
    s2.tapField(2)
    s2.press(.finish(.out))
    s2.tapField(0)
    s2.press(.declared)
    s2.press(.record)
    step("فهد خلّص, حمد معلن جيكر: 100 + 100 = 200, whatever the finish") { c in
        c.eq(HandRules.points(h2.rounds[4]).sorted { $0.key < $1.key }.map(\.value), [200, 100, -30, 100], "round 5")
    }
}

private func handOldSave() {
    Report.begin("Hand 32 · a save from build 5 (cards × the round, «حر»): the old rounds score as they did, new numbers go in as typed (build 6)")
    let d = freshDefaults("h32")
    let players = #"[{"id":"p1","name":"حمد"},{"id":"p2","name":"أنور"},{"id":"p3","name":"فهد"}]"#
    let r1 = #"{"id":101,"cells":{"p1":{"kind":"hand","cards":0},"p2":{"kind":"num","cards":35,"fromHand":true},"p3":{"kind":"free","cards":0,"free":-15}}}"#
    let entry = #"{"p1":{"kind":"out","digits":""},"p2":{"kind":"free","digits":"7","negative":true},"p3":{"digits":""}}"#
    let json = "{\"players\":\(players),\"rounds\":[\(r1)],\"entry\":\(entry),\"uid\":101,\"started\":true}"
    d.set(Data(json.utf8), forKey: "hand.v1")
    let app = launch(d)
    let s = HandScreen(app: app)
    let h = app.hand
    step("build 5's round: حمد هند −60, أنور 35 cards × 2 + 50 = 120, a نزول, فهد «حر» −15; the round being typed comes back; nothing mended") { c in
        c.eq(s.totals, [-60, 120, -15], "totals")
        c.eq(s.downs, [0, 1, 0], "downs")
        c.eq(h.entry[s.id(1)], EntryCell(kind: .free, digits: "7", negative: true), "أنور's «حر»")
        c.eq(d.data(forKey: "hand.v1.damaged") == nil, true, "nothing put aside")
    }
    let old = h.rounds[0]
    s.tapRow(old)
    s.tapEdit(old)
    let inEdit = h.entry
    s.tapField(1)
    s.press(.sign)
    let signed = h.entry[s.id(1)]
    s.tapCancelEdit()
    step("«تعديل» of build 5's round: أنور's 35 cards come back as 70, the number they came to, with «من إيده»; ± makes it −70; «إلغاء» leaves it as it was") { c in
        c.eq(inEdit[s.id(1)], EntryCell(kind: .exact, digits: "70", fromHand: true), "أنور")
        c.eq(inEdit[s.id(2)], EntryCell(kind: .free, digits: "15", negative: true), "فهد")
        c.eq(signed?.typedValue, -70, "±")
        c.eq(s.totals, [-60, 120, -15], "totals")
        c.eq(h.entry[s.id(1)], EntryCell(kind: .free, digits: "7", negative: true), "the round being typed, back")
    }
    s.tapField(2)
    s.press(.notDown)
    s.press(.record)
    step("…and it goes in as build 5 left it: حمد خلّص, أنور −7, فهد ما نزل") { c in
        c.eq(s.totals, [-90, 113, 85], "totals")
    }
    s.wait(3300)
    s.tapField(0)
    s.press(.finish(.hand))
    s.tapField(2)
    s.digits("35")
    s.press(.record)
    step("a new round: فهد 35 typed as it is in a هند, a نزول below 200: −60, 200, 35") { c in
        c.eq(HandRules.points(h.rounds[2]).sorted { $0.key < $1.key }.map(\.value), [-60, 200, 35], "round 3")
        c.eq(s.totals, [-150, 313, 120], "totals")
        c.eq(s.downs, [0, 1, 1], "downs")
    }
}

private func handOldTyping() {
    Report.begin("Hand 33 · after the review (build 6): cards typed before the update come back as the number they come to; ± twice before a digit takes the sign back")
    let d = freshDefaults("h33")
    let players = #"[{"id":"p1","name":"حمد"},{"id":"p2","name":"أنور"},{"id":"p3","name":"فهد"}]"#
    let entry = #"{"p1":{"kind":"hand","digits":""},"p2":{"kind":"num","digits":"12","fromHand":true},"p3":{"kind":"nd","digits":""}}"#
    let json = "{\"players\":\(players),\"rounds\":[],\"entry\":\(entry),\"uid\":100,\"started\":true}"
    d.set(Data(json.utf8), forKey: "hand.v1")
    let app = launch(d)
    let s = HandScreen(app: app)
    let h = app.hand
    step("build 5's round being typed: أنور's 12 cards in a هند come back as 24 with «من إيده», 24 + 50; nothing put aside") { c in
        c.eq(h.entry[s.id(1)], EntryCell(kind: .exact, digits: "24", fromHand: true), "أنور")
        c.eq(HandRules.points(h.entry[s.id(1)] ?? .empty, multiplier: 2), 74, "what it comes to")
        c.eq(d.data(forKey: "hand.v1.damaged") == nil, true, "nothing put aside")
    }
    s.tapField(1)
    s.press(.sign)
    let negative = h.entry[s.id(1)]?.typedValue
    s.press(.sign)
    s.tapField(2)
    s.press(.sign)
    let waiting = h.entry[s.id(2)]
    s.press(.sign)
    let back = h.entry[s.id(2)]
    let ready = s.canPress(.record)
    step("± on it: −24, again 24; ± twice on فهد's ما نزل before a digit: the sign, then ما نزل again, and «سجّل» on") { c in
        c.eq(negative, -24, "−24")
        c.eq(h.entry[s.id(1)]?.typedValue, 24, "24")
        c.eq(waiting, EntryCell(kind: .exact, negative: true), "the sign waiting")
        c.eq(back, .notDown, "ما نزل")
        c.eq(ready, true, "«سجّل»")
    }
}
