import Foundation
import SwiftUI

// Baloot (صكة) scenarios. Expected values come from Baloot.dc.html's JavaScript (seedHands, changeEvent, commit,
// record, finale, playIntro, newGame, askDelete…), from the design spec (§2 rules, §7 motion) and from sakka-card.md,
// never from the Swift under test.

private let seedHands: [(Int, Int)] = [(10, 6), (0, 26), (18, 8), (16, 0), (4, 12), (0, 32), (22, 4), (9, 7), (0, 26), (12, 4), (3, 13)]

func runBalootScenarios() {
    balootSeedAndWin()
    balootThresholds()
    balootBothPass100()
    balootPass100AndWin()
    balootEditAfterWinSameWinner()
    balootReviewTrash()
    balootEditHandsWinToOther()
    balootEditDropsUnder152()
    balootDelete()
    balootNewGame()
    balootTie()
    balootTyping()
    balootVoiceOff()
    balootSaveRestore()
    balootCorruptedSave()
    balootMidSequence()
    balootReduceMotion()
    balootSmallThings()
}

/// Score as an array for messages.
private func sc(_ s: Score) -> [Int] { [s.us, s.them] }

// MARK: 1. The board's hands, 100, and the win sequence

private func balootSeedAndWin() {
    Report.begin("Baloot 1 · the board's 11 hands to لنا 94 · لهم 138, «لنا فوق المية» at 120, then the win «الصكة لهم» and its sequence")
    let d = freshDefaults("b1")
    let app = launch(d)
    let s = BalootScreen(app: app)
    let b = app.baloot

    step("a fresh صكة: no hands, home card «صكة جديدة», «سجل النتيجة» disabled") { c in
        c.eq(b.hands.count, 0, "hands")
        c.eq(b.homeStatus, "صكة جديدة", "home card")
        c.eq(b.canRecord, false, "canRecord")
        c.eq(s.tapRecord(), false, "tap on the disabled button reaches the store")
        c.eq(b.topVisible, true, "top bar")
        c.eq(b.showEntry, true, "fields")
    }

    var us = 0, them = 0
    var said: Set<Team> = []
    for (i, h) in seedHands.enumerated() {
        let t0 = VirtualClock.now
        let mark = app.speaker.mark
        let tick = b.feedbackTick
        let prev = Score(us: us, them: them)
        us += h.0
        them += h.1
        let crossed = Team.allCases.filter { !said.contains($0) && (($0 == .us ? us : them) > 100) }
        said.formUnion(crossed)
        let recorded = s.recordHand(h.0, h.1)
        step("hand \(i + 1) [\(h.0), \(h.1)] → \(us)/\(them): recorded, fields cleared, keyboard closed, copy of the numbers kept, totals still \(prev.us)/\(prev.them) on screen, saved") { c in
            c.eq(recorded, true, "recorded")
            c.eq(b.hands.count, i + 1, "hands")
            c.eq(b.hands.last.map { [$0.us, $0.them] } ?? [], [h.0, h.1], "the new hand")
            c.eq(sc(b.totals), [us, them], "totals")
            c.eq([b.inUs, b.inThem], ["", ""], "fields")
            c.eq(s.focus == nil, true, "keyboard closed")
            c.eq(b.pressing, true, "button pressed")
            c.eq(b.ghost, BalootStore.Ghost(us: h.0 > 0 ? "\(h.0)" : "", them: h.1 > 0 ? "\(h.1)" : ""), "copy of the typed numbers")
            c.eq(b.freshId, b.hands.last?.id, "fresh row")
            c.eq(b.freshOn, false, "fresh row not in yet")
            c.eq(sc(b.shown(at: Date())), [prev.us, prev.them], "totals on screen during the 360 ms lead")
            c.eq(b.feedback, .record, "haptic")
            c.eq(b.feedbackTick, tick + 1, "haptic fired once")
            c.eq(savedBaloot(d)?.hands.map { [$0.us, $0.them] } ?? [], seedHands.prefix(i + 1).map { [$0.0, $0.1] }, "saved hands")
            c.eq(Set(savedBaloot(d)?.said ?? []), said, "saved «فوق المية» teams")
            if crossed.isEmpty {
                c.eq(app.speaker.spoken(since: mark).map(\.text), [], "voice")
            } else {
                let who = crossed.count == 2 ? "لنا ولهم" : (crossed[0] == .us ? "لنا" : "لهم")
                c.eq(b.banner, who + " فوق المية", "banner text")
                c.eq(b.bannerOn, true, "banner on")
                c.eq(app.speaker.spoken(since: mark).map(\.text), [who + " فوق المئة"], "voice at once")
                c.eq(app.speaker.spoken(since: mark).first.map { "+\($0.time - t0) ms" }, "+0 ms", "voice time")
            }
        }
        if i == 1 {
            // Only the box that received points breathes: [0, 26] → لهم.
            s.wait(380)
            let on = b.pulse
            s.wait(260)
            step("hand 2 [0, 26]: only لهم's box breathes, from 380 ms to 640 ms") { c in
                c.eq(on, [.them], "pulse at 380")
                c.eq(b.pulse, [], "pulse at 640")
            }
            s.wait(t0 + 1100 - VirtualClock.now)
        } else if i == 0 {
            // The count, sampled half way: 360 ms lead, then 700 ms cubic ease-out (board runCount).
            s.wait(360 + 350)
            step("hand 1: half way through the count (t0+710) the totals read the board's cubic ease-out") { c in
                c.eq(b.counting, true, "counting")
                c.eq(sc(b.shown(at: Date())), [boardCount(0, 10, elapsed: 350), boardCount(0, 6, elapsed: 350)], "shown totals")
            }
            s.wait(t0 + 1100 - VirtualClock.now)
        } else {
            s.wait(1100)
        }
        step("hand \(i + 1): the record sequence ran on the board's timings and ended clean") { c in
            let keys: Set<String> = ["fresh", "ghostOn", "press", "count", "pulseOn", "ghostOff", "pulseOff", "countEnd"]
            c.eq(fired("baloot", from: t0, to: t0 + 1100, keys: keys), recordTimeline(owner: "baloot", at: t0, press: true), "timers")
            c.eq(b.display == nil && b.countStart == nil, true, "count finished")
            c.eq(b.pressing, false, "button back")
            c.eq(b.ghost == nil, true, "copies removed")
            c.eq(b.pulse.isEmpty, true, "boxes back")
            c.eq(b.freshOn, true, "row in")
        }
        if i == 8 {
            // «لهم فوق المية» at hand 9: the banner stays 3.2 s.
            s.wait(t0 + 3199 - VirtualClock.now)
            let onBefore = b.bannerOn
            s.wait(1)
            step("hand 9's banner «لهم فوق المية» stays 3.2 s and goes") { c in
                c.eq(onBefore, true, "on at 3199 ms")
                c.eq(b.bannerOn, false, "off at 3200 ms")
            }
        }
    }

    step("after the board's 11 hands: لنا 94 · لهم 138, home card «صكة جارية · بعد 11 لعبة», لهم gold, لنا ink, only the two newest rows open") { c in
        c.eq(sc(b.totals), [94, 138], "totals")
        c.eq(b.homeStatus, "صكة جارية · " + boardHandsText(11), "home card")
        c.eq(b.tone(.us, value: 94), .ink, "لنا colour")
        c.eq(b.tone(.them, value: 138), .gold, "لهم colour")
        c.eq(s.rows.map { s.hasIcons($0) }, [true, true] + Array(repeating: false, count: 9), "pencil and trash on the rows")
        c.eq(b.isWon, false, "running")
    }

    // The board's flow baloot_round_home: 26 in لنا → 120 against 138, and «لنا فوق المية».
    let t1 = VirtualClock.now
    let m1 = app.speaker.mark
    s.recordHand(26, 0)
    step("[26, 0] → 120/138 (board flow baloot_round_home): «لنا فوق المية» on the banner, «لنا فوق المئة» by voice") { c in
        c.eq(sc(b.totals), [120, 138], "totals")
        c.eq(b.banner, "لنا فوق المية", "banner")
        c.eq(b.bannerOn, true, "banner on")
        c.eq(app.speaker.spoken(since: m1).map(\.text), ["لنا فوق المئة"], "voice")
        c.eq(app.speaker.spoken(since: m1).first.map { "+\($0.time - t1) ms" }, "+0 ms", "voice with the banner")
    }
    s.wait(3300)

    // The winning hand: [0, 16] → 120/154, «الصكة لهم».
    let t0 = VirtualClock.now
    let m0 = app.speaker.mark
    s.recordHand(0, 16)
    step("[0, 16] → 154: the win holds the win screen back; fields still shown but «سجل النتيجة» off; top bar hidden; banner off") { c in
        c.eq(sc(b.totals), [120, 154], "totals")
        c.eq(b.outcome, .won(.them), "outcome")
        c.eq(b.holdPoster, true, "win screen held")
        c.eq(b.posterVisible, false, "win screen not yet")
        c.eq(b.showEntry, true, "fields shown during the sequence")
        c.eq(b.topVisible, false, "top bar hidden from the winning hand on")
        c.eq(b.bannerOn, false, "banner")
        c.eq(b.homeStatus, "الصكة لهم", "home card")
        c.eq(b.tone(.us, value: 120), .gold, "loser's total not muted during the sequence")
        c.eq(app.speaker.spoken(since: m0).count, 0, "no voice yet")
    }
    step("during the sequence nothing takes a tap (build 4): fields disabled, no pencil or trash, «سجل النتيجة» off") { c in
        c.eq(s.tapField(.us), false, "tap on «لنا»")
        c.eq(s.key("5"), false, "a key")
        c.eq(s.tapField(.them), false, "tap on «لهم»")
        c.eq(s.pressReturn(), false, "Return")
        c.eq(b.canRecord, false, "canRecord")
        c.eq(s.tapRecord(), false, "«سجل النتيجة»")
        c.eq(s.rows.map { s.hasIcons($0) }.contains(true), false, "pencil or trash on a row")
        c.eq(s.focus == nil, true, "keyboard closed")
        c.eq(b.hands.count, 13, "hands")
    }

    // Step by step through the board's finale.
    s.wait(t0 + 1060 - VirtualClock.now)
    step("t0+1060, the count ends: the winner's box outlined (lift), no copy yet") { c in
        c.eq(b.lift, true, "lift")
        c.eq(b.growTeam, .them, "box of لهم")
        c.eq(b.grow, .off, "copy")
        c.eq(b.counting, false, "count over")
    }
    s.wait(180)
    step("t0+1240: the copy is laid over the box") { c in c.eq(b.grow, .box, "grow") }
    let animationsBefore = AnimationLog.calls.count
    s.wait(40)
    step("t0+1280: the copy grows to the full screen, 560 ms on (0.65, 0, 0.35, 1)") { c in
        c.eq(b.grow, .full, "grow")
        c.eq(AnimationLog.calls.dropFirst(animationsBefore).map { $0?.description ?? "nil" }, [Animation.timingCurve(0.65, 0, 0.35, 1, duration: 0.56).description], "animation")
    }
    s.wait(t0 + 1859 - VirtualClock.now)
    let heldAt1859 = b.holdPoster
    s.wait(1)
    step("t0+1860: the win screen is in place, solid (fromExpand), with the success haptic; its parts not in yet") { c in
        c.eq(heldAt1859, true, "still held at 1859 ms")
        c.eq(b.holdPoster, false, "released")
        c.eq(b.posterVisible, true, "win screen")
        c.eq(b.fromExpand, true, "solid at once")
        c.eq(b.intro, false, "parts not in yet")
        c.eq(b.feedback, .win, "haptic")
        c.eq(b.tone(.us, value: 120), .muted, "loser muted once the win screen shows")
        c.eq(b.showEntry, false, "fields hidden")
        c.eq(b.topVisible, false, "top bar hidden")
    }
    s.wait(30)
    step("t0+1890: the parts come in") { c in c.eq(b.intro, true, "intro") }
    s.wait(t0 + 2060 - VirtualClock.now)
    step("t0+2060: the copy is gone") { c in
        c.eq(b.grow, .off, "grow")
        c.eq(b.lift, false, "lift")
    }
    s.wait(t0 + 2369 - VirtualClock.now)
    let beforeVoice = app.speaker.spoken(since: m0).count
    s.wait(1)
    step("t0+2370: the voice says «الصكة لهم» as the name lands, once") { c in
        c.eq(beforeVoice, 0, "nothing said before 2370 ms")
        c.eq(app.speaker.spoken(since: m0).map(\.text), ["الصكة لهم"], "voice")
        c.eq(app.speaker.spoken(since: m0).first.map { "+\($0.time - t0) ms" }, "+2370 ms", "time")
    }
    s.wait(5000)
    step("the whole winning hand ran the board's sequence in order: record, count, outline, copy, grow, win screen, parts, voice") { c in
        let keys: Set<String> = ["count", "countEnd", "growBox", "growFull", "poster", "intro", "growOff", "voice"]
        let expected = [VirtualClock.Fired(time: t0 + 360, owner: "baloot", key: "count")] + winTimeline(owner: "baloot", countEnd: t0 + 1060)
        c.eq(fired("baloot", from: t0, to: t0 + 8000, keys: keys), expected, "timers")
        c.eq(app.speaker.spoken(since: m0).map(\.text), ["الصكة لهم"], "only the win was said")
    }
    step("the win screen: لهم 154 against 120, «بعد 13 لعبة»") { c in
        c.eq(b.outcome.winner, .them, "winner")
        c.eq([b.totals.them, b.totals.us], [154, 120], "winner's total, loser's total")
        c.eq(ArabicCount.hands(b.hands.count), boardHandsText(13), "hands count line")
    }
}

// MARK: 1b. The two thresholds

private func balootThresholds() {
    Report.begin("Baloot 1b · the thresholds: exactly 100 is not «فوق المية», 101 is; 151 plays on, exactly 152 wins")
    let d = freshDefaults("b1b")
    let app = launch(d)
    let s = BalootScreen(app: app)
    let b = app.baloot
    s.recordHand(100, 0)
    step("لنا exactly 100: no banner, no voice, ink") { c in
        c.eq(b.bannerOn, false, "banner")
        c.eq(app.speaker.spoken().count, 0, "voice")
        c.eq(b.tone(.us, value: 100), .ink, "colour")
    }
    s.wait(1100)
    s.recordHand(1, 0)
    step("101: «لنا فوق المية», gold") { c in
        c.eq(b.banner, "لنا فوق المية", "banner")
        c.eq(b.tone(.us, value: 101), .gold, "colour")
    }
    s.wait(3300)
    s.recordHand(50, 0)
    step("151: still playing") { c in
        c.eq(b.outcome, .playing, "outcome")
        c.eq(b.canRecord, false, "fields empty")
    }
    s.wait(1100)
    let m = app.speaker.mark
    s.recordHand(1, 0)
    s.wait(3000)
    step("exactly 152: the win, «الصكة لنا»") { c in
        c.eq(b.outcome, .won(.us), "outcome")
        c.eq(app.speaker.spoken(since: m).map(\.text), ["الصكة لنا"], "voice")
    }
}

// MARK: 2. Both teams pass 100 in one hand; nothing is repeated

private func balootBothPass100() {
    Report.begin("Baloot 2 · both teams pass 100 in one hand; after a delete or an edit takes them back under, nothing is repeated")
    let d = freshDefaults("b2")
    let app = launch(d)
    let s = BalootScreen(app: app)
    let b = app.baloot
    s.recordHand(94, 95)
    s.wait(1100)
    let t0 = VirtualClock.now
    let m = app.speaker.mark
    s.recordHand(10, 10)
    step("[10, 10] from 94/95: «لنا ولهم فوق المية» on the banner and «لنا ولهم فوق المئة» by voice, together") { c in
        c.eq(sc(b.totals), [104, 105], "totals")
        c.eq(b.banner, "لنا ولهم فوق المية", "banner")
        c.eq(b.bannerOn, true, "banner on")
        c.eq(app.speaker.spoken(since: m).map(\.text), ["لنا ولهم فوق المئة"], "voice")
        c.eq(app.speaker.spoken(since: m).first.map { "+\($0.time - t0) ms" }, "+0 ms", "voice time")
    }
    s.wait(3200)
    step("the banner goes after 3.2 s") { c in c.eq(b.bannerOn, false, "banner") }

    let m2 = app.speaker.mark
    if let last = b.hands.last {
        s.tapTrash(last)
        s.tapConfirmDelete(last)
    }
    s.wait(1000)
    s.recordHand(10, 10)
    s.wait(1100)
    step("deleted and recorded again: back over 100, nothing said or shown") { c in
        c.eq(sc(b.totals), [104, 105], "totals")
        c.eq(app.speaker.spoken(since: m2).count, 0, "voice")
        c.eq(b.bannerOn, false, "banner")
    }
    let m3 = app.speaker.mark
    if let last = b.hands.last {
        s.tapPencil(last)
        s.retype(us: 1, them: 1)
        s.tapSave()
        s.wait(800)
        if let again = b.hands.last {
            s.tapPencil(again)
            s.retype(us: 10, them: 10)
            s.tapSave()
        }
    }
    s.wait(1000)
    step("edited under 100 and back over: nothing said or shown") { c in
        c.eq(sc(b.totals), [104, 105], "totals")
        c.eq(app.speaker.spoken(since: m3).count, 0, "voice")
        c.eq(b.bannerOn, false, "banner")
        c.eq(Set(savedBaloot(d)?.said ?? []), [.us, .them], "saved said")
    }

    // An edit that takes a team over 100 for the first time announces it, as a record does (board commit).
    let d2 = freshDefaults("b2b")
    let app2 = launch(d2)
    let s2 = BalootScreen(app: app2)
    s2.recordHand(50, 20)
    s2.recordHand(40, 0)
    s2.wait(1100)
    let m4 = app2.speaker.mark
    if let last = app2.baloot.hands.last {
        s2.tapPencil(last)
        s2.retype(us: 60, them: 0)
        s2.tapSave()
    }
    step("an edit that takes لنا over 100 for the first time (90 → 110) says «لنا فوق المئة» with the banner") { c in
        c.eq(sc(app2.baloot.totals), [110, 20], "totals")
        c.eq(app2.speaker.spoken(since: m4).map(\.text), ["لنا فوق المئة"], "voice")
        c.eq(app2.baloot.banner, "لنا فوق المية", "banner")
    }
}

// MARK: 3. Passing 100 and winning in one hand

private func balootPass100AndWin() {
    Report.begin("Baloot 3 · passing 100 and winning in one hand: only the win is announced, the 100 is marked silently")
    let d = freshDefaults("b3")
    let app = launch(d)
    let s = BalootScreen(app: app)
    let b = app.baloot
    s.recordHand(94, 95)
    s.wait(1100)
    let t0 = VirtualClock.now
    let m = app.speaker.mark
    s.recordHand(60, 10)
    step("[60, 10] from 94/95 → 154/105: no banner, no «فوق المئة»; both teams marked as said") { c in
        c.eq(b.outcome, .won(.us), "outcome")
        c.eq(b.bannerOn, false, "banner")
        c.eq(app.speaker.spoken(since: m).count, 0, "voice")
        c.eq(Set(savedBaloot(d)?.said ?? []), [.us, .them], "saved said")
    }
    s.wait(4000)
    step("the only line said is the win, «الصكة لنا», at t0+2370") { c in
        c.eq(app.speaker.spoken(since: m).map(\.text), ["الصكة لنا"], "voice")
        c.eq(app.speaker.spoken(since: m).first.map { "+\($0.time - t0) ms" }, "+2370 ms", "time")
    }
}

// MARK: 4. «تعديل» after a win, same winner

private func balootEditAfterWinSameWinner() {
    Report.begin("Baloot 4 · «تعديل» after a win with the same winner: silent, the win screen comes back with its entrance")
    let d = freshDefaults("b4")
    let app = launch(d)
    let s = BalootScreen(app: app)
    let b = app.baloot
    s.recordHand(94, 95)
    s.recordHand(0, 60)
    s.wait(3000)
    step("setup: لهم won 155 to 94, the win screen is up, «الصكة لهم» said once") { c in
        c.eq(b.outcome, .won(.them), "outcome")
        c.eq(b.posterVisible, true, "win screen")
        c.eq(app.speaker.spoken().map(\.text), ["الصكة لهم"], "voice")
    }
    let m = app.speaker.mark
    s.tapPosterEdit()
    step("«تعديل»: review mode, the last hand open with its numbers, «لنا» field focused, top bar and log back, fields hidden, loser muted") { c in
        c.eq(b.reviewing, true, "reviewing")
        c.eq(b.editId, b.hands.last?.id, "last hand open")
        c.eq([b.edUs, b.edThem], ["0", "60"], "edit fields")
        c.eq(s.focus, .editUs, "focus")
        c.eq(b.posterVisible, false, "win screen hidden")
        c.eq(b.topVisible, true, "top bar")
        c.eq(b.showEntry, false, "entry lane hidden in review")
        c.eq(b.tone(.us, value: 94), .muted, "loser muted in review")
        c.eq(b.tone(.them, value: 155), .gold, "winner gold")
    }
    let tc = VirtualClock.now
    s.tapCancel()
    step("«إلغاء»: the win screen is back at once, its parts come in after 40 ms") { c in
        c.eq(b.posterVisible, true, "win screen")
        c.eq(b.intro, false, "parts reset")
        c.eq(b.editId == nil, true, "edit closed")
    }
    s.wait(40)
    step("…and in at +40 ms") { c in
        c.eq(b.intro, true, "intro")
        c.eq(VirtualClock.fired.last { $0.owner == "baloot" && $0.key == "intro" }?.time, tc + 40, "intro time")
    }
    s.wait(3000)
    step("no voice after «إلغاء»") { c in c.eq(app.speaker.spoken(since: m).count, 0, "voice") }

    // Save an edit that keeps لهم the winner and takes لنا over 100 for the first time: still nothing said (card).
    s.tapPosterEdit()
    s.retype(us: 10, them: 60)
    let ts = VirtualClock.now
    let m2 = app.speaker.mark
    s.tapSave()
    step("«حفظ» [10, 60]: لنا 104 for the first time, لهم still wins: no «فوق المية», no voice, win screen back") { c in
        c.eq(sc(b.totals), [104, 155], "totals")
        c.eq(b.bannerOn, false, "banner")
        c.eq(b.posterVisible, true, "win screen")
        c.eq(b.reviewing, false, "review over")
        c.eq(b.holdPoster, false, "no sequence")
        c.eq(Set(savedBaloot(d)?.said ?? []), [.us, .them], "the 100 counted silently")
        c.eq(savedBaloot(d)?.hands == b.hands, true, "the edit saved")
    }
    s.wait(3000)
    step("…the count ran at once with no finale, the parts came in at +40, and nothing was said") { c in
        let keys: Set<String> = ["count", "countEnd", "growBox", "growFull", "poster", "intro", "growOff", "voice"]
        c.eq(fired("baloot", from: ts, to: ts + 3000, keys: keys), [
            .init(time: ts, owner: "baloot", key: "count"),
            .init(time: ts + 40, owner: "baloot", key: "intro"),
            .init(time: ts + 700, owner: "baloot", key: "countEnd")
        ], "timers")
        c.eq(app.speaker.spoken(since: m2).count, 0, "voice")
        c.eq(b.intro, true, "parts in")
    }
}

// MARK: 4b. Review mode: trash on the other row

private func balootReviewTrash() {
    Report.begin("Baloot 4b · in review, «احذف؟» on the other row closes the open hand; left alone for 3 s it brings the win screen back (build 4), with no voice")
    let d = freshDefaults("b4b")
    let app = launch(d)
    let s = BalootScreen(app: app)
    let b = app.baloot
    s.recordHand(94, 95)
    s.recordHand(0, 60)
    s.wait(3000)
    s.tapPosterEdit()
    let second = s.rows[1]
    let m = app.speaker.mark
    let tt = VirtualClock.now
    s.tapTrash(second)
    step("trash on the second row in review: the open hand closes and «احذف؟» shows; still in review") { c in
        c.eq(b.editId == nil, true, "edit closed")
        c.eq(b.confirmId, second.id, "chip")
        c.eq(b.reviewing, true, "review")
        c.eq(b.posterVisible, false, "win screen")
    }
    s.wait(2999)
    let still = b.reviewing
    s.wait(1)
    step("left alone: at 3 s the chip goes and the win screen comes back, its parts in 40 ms later, as «إلغاء» does") { c in
        c.eq(still, true, "review at 2999 ms")
        c.eq(b.confirmId == nil, true, "chip gone")
        c.eq(b.reviewing, false, "review over")
        c.eq(b.posterVisible, true, "win screen")
        c.eq(b.topVisible, false, "top bar hidden again")
    }
    s.wait(40)
    step("…parts in at 3040 ms") { c in
        c.eq(b.intro, true, "intro")
        c.eq(VirtualClock.fired.last { $0.owner == "baloot" && $0.key == "intro" }?.time, tt + 3040, "intro time")
    }
    s.wait(3000)
    step("…and no voice") { c in c.eq(app.speaker.spoken(since: m).count, 0, "voice") }
    s.tapPosterEdit()
    s.tapTrash(s.rows[1])
    s.wait(1000)
    s.tapPencil(s.rows[0])
    s.wait(3000)
    step("trash on the other row, then the pencil within 3 s: the chip's timer is gone, the hand stays open in review") { c in
        c.eq(b.editId, s.rows[0].id, "editing")
        c.eq(b.reviewing, true, "review")
        c.eq(b.posterVisible, false, "win screen")
    }
    s.tapCancel()
    s.tapPosterEdit()
    s.tapTrash(s.rows[1])
    let m2 = app.speaker.mark
    s.tapConfirmDelete(s.rows[1])
    s.wait(3000)
    step("deleting the second row in review (لهم 60 · لنا 0 left, under 152): the game reopens, nothing said") { c in
        c.eq(sc(b.totals), [0, 60], "totals")
        c.eq(b.isWon, false, "won")
        c.eq(b.reviewing, false, "review")
        c.eq(app.speaker.spoken(since: m2).count, 0, "voice")
    }
}

// MARK: 5. An edit that hands the win to the other team

private func balootEditHandsWinToOther() {
    Report.begin("Baloot 5 · an edit after the win that hands it to the other team plays the whole sequence again")
    let d = freshDefaults("b5")
    let app = launch(d)
    let s = BalootScreen(app: app)
    let b = app.baloot
    s.recordHand(94, 95)
    s.recordHand(0, 60)
    s.wait(3000)
    s.tapPosterEdit()
    s.retype(us: 70, them: 0)
    let t1 = VirtualClock.now
    let m = app.speaker.mark
    s.tapSave()
    step("«حفظ» [70, 0]: لنا 164 · لهم 95, the win passes to لنا: the sequence holds the win screen, top bar hidden") { c in
        c.eq(sc(b.totals), [164, 95], "totals")
        c.eq(b.outcome, .won(.us), "outcome")
        c.eq(b.holdPoster, true, "held")
        c.eq(b.posterVisible, false, "win screen not yet")
        c.eq(b.topVisible, false, "top bar")
        c.eq(b.bannerOn, false, "no «فوق المية» for لنا (passing 100 and winning in one change)")
        c.eq(savedBaloot(d)?.hands.last.map { [$0.us, $0.them] } ?? [], [70, 0], "the edit saved")
    }
    s.wait(4000)
    step("the whole sequence again (edits count at once: count at t1, outline at t1+700, …), and the voice says «الصكة لنا» once") { c in
        let keys: Set<String> = ["count", "countEnd", "growBox", "growFull", "poster", "intro", "growOff", "voice"]
        let expected = [VirtualClock.Fired(time: t1, owner: "baloot", key: "count")] + winTimeline(owner: "baloot", countEnd: t1 + 700)
        c.eq(fired("baloot", from: t1, to: t1 + 4000, keys: keys), expected, "timers")
        c.eq(app.speaker.spoken(since: m).map(\.text), ["الصكة لنا"], "voice")
        c.eq(b.posterVisible, true, "win screen")
        c.eq(b.fromExpand, true, "grew from the box")
    }
}

// MARK: 6. An edit that drops the winner under 152

private func balootEditDropsUnder152() {
    Report.begin("Baloot 6 · an edit that drops the winner under 152 reopens the game")
    let d = freshDefaults("b6")
    let app = launch(d)
    let s = BalootScreen(app: app)
    let b = app.baloot
    s.recordHand(94, 95)
    s.recordHand(0, 60)
    s.wait(3000)
    s.tapPosterEdit()
    s.retype(us: 0, them: 50)
    let m = app.speaker.mark
    s.tapSave()
    s.wait(3000)
    step("«حفظ» [0, 50] → لهم 145: playing again, no win screen, top bar and fields back, nothing said") { c in
        c.eq(sc(b.totals), [94, 145], "totals")
        c.eq(b.outcome, .playing, "outcome")
        c.eq(b.posterVisible, false, "win screen")
        c.eq(b.topVisible, true, "top bar")
        c.eq(b.showEntry, true, "fields")
        c.eq(b.reviewing, false, "review over")
        c.eq(b.holdPoster, false, "held")
        c.eq(b.intro, false, "intro")
        c.eq(b.homeStatus, "صكة جارية · " + boardHandsText(2), "home card")
        c.eq(b.tone(.us, value: 94), .ink, "لنا no longer muted")
        c.eq(app.speaker.spoken(since: m).count, 0, "voice")
        c.eq(savedBaloot(d)?.hands.last.map { [$0.us, $0.them] } ?? [], [0, 50], "the edit saved")
    }
    let m2 = app.speaker.mark
    s.recordHand(0, 10)
    s.wait(3000)
    step("a new hand that wins again plays the sequence and says «الصكة لهم» again") { c in
        c.eq(b.outcome, .won(.them), "outcome")
        c.eq(b.posterVisible, true, "win screen")
        c.eq(app.speaker.spoken(since: m2).map(\.text), ["الصكة لهم"], "voice")
    }
}

// MARK: 7. Delete

private func balootDelete() {
    Report.begin("Baloot 7 · delete: the two newest only, «احذف؟» for 3 s, then the hand goes and the totals count at once")
    let d = freshDefaults("b7")
    let app = launch(d)
    let s = BalootScreen(app: app)
    let b = app.baloot
    s.recordHand(10, 6)
    s.recordHand(0, 26)
    s.recordHand(18, 8)
    s.wait(1100)
    let rows = s.rows
    step("pencil and trash on the two newest rows only") { c in
        c.eq(rows.map { s.hasIcons($0) }, [true, true, false], "icons")
        c.eq(s.tapTrash(rows[2]), false, "trash on the oldest row")
    }
    let t0 = VirtualClock.now
    s.tapTrash(rows[0])
    step("trash on the newest: «احذف؟» on that row, the other row keeps its icons") { c in
        c.eq(b.confirmId, rows[0].id, "confirm")
        c.eq(s.isConfirming(rows[0]), true, "chip")
        c.eq(s.hasIcons(rows[1]), true, "other row")
    }
    s.wait(2999)
    let still = b.confirmId
    s.wait(1)
    step("«احذف؟» goes back to the icons by itself after exactly 3 s") { c in
        c.eq(still, rows[0].id, "still at 2999 ms")
        c.eq(b.confirmId == nil, true, "gone at 3000 ms")
        c.eq(VirtualClock.fired.last { $0.key == "confirmId" }?.time, t0 + 3000, "timer")
    }
    s.tapTrash(rows[0])
    s.wait(1500)
    s.tapTrash(rows[1])
    let tB = VirtualClock.now
    step("trash on the other row moves «احذف؟» there and restarts its 3 s") { c in
        c.eq(b.confirmId, rows[1].id, "confirm")
        c.eq(VirtualClock.pendingDue(owner: "baloot", key: "confirmId"), tB + 3000, "timer")
    }
    s.tapPencil(rows[0])
    step("the pencil on the other row closes «احذف؟» and opens that row") { c in
        c.eq(b.confirmId == nil, true, "confirm")
        c.eq(b.editId, rows[0].id, "edit")
        c.eq(VirtualClock.pendingDue(owner: "baloot", key: "confirmId") == nil, true, "timer cancelled")
    }
    s.tapCancel()
    s.tapTrash(rows[0])
    s.wait(1000)
    let td = VirtualClock.now
    s.tapConfirmDelete(rows[0])
    step("«احذف؟» tapped: the newest hand goes, totals 10/32, saved, the count starts at once from 28/40") { c in
        c.eq(b.hands.map { [$0.us, $0.them] }, [[10, 6], [0, 26]], "hands")
        c.eq(sc(b.totals), [10, 32], "totals")
        c.eq(savedBaloot(d)?.hands.map { [$0.us, $0.them] } ?? [], [[10, 6], [0, 26]], "saved")
        c.eq(b.confirmId == nil, true, "confirm")
        c.eq(b.counting, true, "counting at once")
        c.eq(sc(b.shown(at: Date())), [28, 40], "from the old totals")
        c.eq(b.pulse.isEmpty && b.ghost == nil, true, "no rising number, no breathing")
    }
    s.wait(3100)
    step("the delete's count took 700 ms and the cancelled «احذف؟» timer never fired") { c in
        c.eq(fired("baloot", from: td, to: td + 3100, keys: ["count", "countEnd", "confirmId"]), [
            .init(time: td, owner: "baloot", key: "count"),
            .init(time: td + 700, owner: "baloot", key: "countEnd")
        ], "timers")
        c.eq(rows.count, 3, "rows")
    }
}

// MARK: 8. «صكة جديدة»

private func balootNewGame() {
    Report.begin("Baloot 8 · «صكة جديدة»: «متأكد؟» for 3 s while a صكة runs; one tap when empty or after a win")
    let d = freshDefaults("b8")
    let app = launch(d)
    let s = BalootScreen(app: app)
    let b = app.baloot
    s.tapNewGame()
    step("empty: one tap, no «متأكد؟»") { c in
        c.eq(b.confirmNew, false, "confirm")
        c.eq(s.newGameTitle, "صكة جديدة", "title")
        c.eq(b.hands.count, 0, "hands")
    }
    s.recordHand(10, 6)
    s.recordHand(0, 26)
    s.wait(1100)
    s.tapField(.us)
    s.type("12")
    let t0 = VirtualClock.now
    s.tapNewGame()
    step("running: the first tap asks «متأكد؟» and clears nothing") { c in
        c.eq(b.confirmNew, true, "confirm")
        c.eq(s.newGameTitle, "متأكد؟", "title")
        c.eq(b.hands.count, 2, "hands")
        c.eq(s.focus == nil, true, "keyboard closed")
    }
    s.wait(2999)
    let still = b.confirmNew
    s.wait(1)
    step("«متأكد؟» goes back to «صكة جديدة» after exactly 3 s") { c in
        c.eq(still, true, "still at 2999 ms")
        c.eq(b.confirmNew, false, "gone at 3000 ms")
        c.eq(VirtualClock.fired.last { $0.key == "confirmNew" }?.time, t0 + 3000, "timer")
    }
    s.tapNewGame()
    s.wait(1500)
    let stops = app.speaker.log.filter { $0.kind == .stopped }.count
    s.tapNewGame()
    step("second tap within 3 s: everything cleared and saved empty, the voice stopped, no timer left") { c in
        c.eq(b.hands.count, 0, "hands")
        c.eq(sc(b.totals), [0, 0], "totals")
        c.eq([b.inUs, b.inThem], ["", ""], "fields")
        c.eq(b.confirmNew, false, "confirm")
        c.eq(b.homeStatus, "صكة جديدة", "home card")
        c.eq(savedBaloot(d), SavedBaloot(hands: [], said: []), "saved")
        c.eq(app.speaker.log.filter { $0.kind == .stopped }.count, stops + 1, "voice stopped")
        c.eq(VirtualClock.pendingKeys.filter { $0.hasPrefix("baloot.") }, [], "pending timers")
    }
    s.recordHand(90, 0)
    s.recordHand(70, 20)
    s.wait(3000)
    step("after a win the top bar is hidden; «صكة جديدة» on the win screen clears with one tap") { c in
        c.eq(s.tapNewGame(), false, "top bar tap")
        c.eq(s.tapPosterNewGame(), true, "win screen tap")
        c.eq(b.hands.count, 0, "hands")
        c.eq(b.posterVisible, false, "win screen")
        c.eq(b.isWon, false, "won")
    }
    s.recordHand(90, 0)
    s.recordHand(70, 20)
    s.wait(3000)
    s.tapPosterEdit()
    step("in review after a win, «صكة جديدة» in the top bar also clears with one tap") { c in
        c.eq(s.newGameTitle, "صكة جديدة", "title")
        c.eq(s.tapNewGame(), true, "tap")
        c.eq(b.hands.count, 0, "hands")
        c.eq(b.reviewing, false, "review")
        c.eq(b.editId == nil, true, "edit")
    }
    s.recordHand(90, 0)
    s.recordHand(70, 20)
    s.wait(500)
    step("during the win sequence the top bar cannot be tapped") { c in c.eq(s.tapNewGame(), false, "tap") }
}

// MARK: 9. Tie

private func balootTie() {
    Report.begin("Baloot 9 · a tie at or above 152 goes on with «تعادل على N، واللعبة الجاية تحسم», and the next lead wins")
    let d = freshDefaults("b9")
    let app = launch(d)
    let s = BalootScreen(app: app)
    let b = app.baloot
    s.recordHand(94, 95)
    let m = app.speaker.mark
    s.recordHand(58, 57)
    step("[58, 57] → 152/152: a tie, not a win; the banner «لنا ولهم فوق المية» first, over the tie note") { c in
        c.eq(b.outcome, .tie(152), "outcome")
        c.eq(b.tieAt, 152, "tie")
        c.eq(b.isWon, false, "won")
        c.eq(b.statusOpen, true, "status line open")
        c.eq(b.bannerOn, true, "banner over the note")
        c.eq(b.banner, "لنا ولهم فوق المية", "banner")
        c.eq(app.speaker.spoken(since: m).map(\.text), ["لنا ولهم فوق المئة"], "voice")
        c.eq(b.homeStatus, "تعادل على 152", "home card")
        c.eq(BalootRules.tieNote(152), "تعادل على 152، واللعبة الجاية تحسم", "tie note")
        c.eq(b.topVisible && b.showEntry, true, "top bar and fields")
    }
    s.wait(3300)
    step("after the banner the tie note stays") { c in
        c.eq(b.bannerOn, false, "banner")
        c.eq(b.statusOpen, true, "status line")
    }
    let m2 = app.speaker.mark
    s.recordHand(5, 5)
    s.wait(1100)
    step("[5, 5] → 157/157: still a tie, nothing said") { c in
        c.eq(b.outcome, .tie(157), "outcome")
        c.eq(app.speaker.spoken(since: m2).count, 0, "voice")
        c.eq(b.homeStatus, "تعادل على 157", "home card")
    }
    s.recordHand(0, 3)
    s.wait(3000)
    step("[0, 3] → 157/160: لهم leads after a hand and wins, «الصكة لهم»") { c in
        c.eq(b.outcome, .won(.them), "outcome")
        c.eq(b.posterVisible, true, "win screen")
        c.eq(app.speaker.spoken(since: m2).map(\.text), ["الصكة لهم"], "voice")
    }
}

// MARK: 10. Typing

private func balootTyping() {
    Report.begin("Baloot 10 · typing: digits only, Arabic-Indic and Eastern Arabic become Western, 3 at most, two in «لنا» move on")
    let d = freshDefaults("b10")
    let app = launch(d)
    let s = BalootScreen(app: app)
    let b = app.baloot
    s.tapField(.us)
    s.key("1")
    step("«1» in لنا: stays") { c in
        c.eq(b.inUs, "1", "لنا")
        c.eq(s.focus, .us, "focus")
    }
    s.key("2")
    step("«2»: two digits move the cursor to لهم") { c in
        c.eq(b.inUs, "12", "لنا")
        c.eq(s.focus, .them, "focus")
    }
    s.type("3456")
    step("«3456» in لهم: three digits at most, and two digits in لهم move nothing") { c in
        c.eq(b.inThem, "345", "لهم")
        c.eq(s.focus, .them, "focus")
    }
    s.tapField(.us)
    s.type("49")
    step("back in لنا, «4» makes 124 and stays; a fourth digit is dropped") { c in
        c.eq(b.inUs, "124", "لنا")
        c.eq(s.focus, .us, "focus")
    }
    s.deleteBackward()
    step("a deletion (124 → 12) does not move") { c in
        c.eq(b.inUs, "12", "لنا")
        c.eq(s.focus, .us, "focus")
    }
    s.deleteBackward()
    s.key("5")
    step("1 then «5» → 15 moves on again") { c in
        c.eq(b.inUs, "15", "لنا")
        c.eq(s.focus, .them, "focus")
    }
    s.tapField(.us)
    s.clear(.us)
    s.paste("١٢")
    step("pasting Arabic-Indic «١٢» gives 12 and moves on") { c in
        c.eq(b.inUs, "12", "لنا")
        c.eq(s.focus, .them, "focus")
    }
    s.clear(.them)
    s.paste("۳۴")
    step("Eastern Arabic «۳۴» gives 34") { c in c.eq(b.inThem, "34", "لهم") }
    s.clear(.them)
    s.paste("7a-8 9")
    step("anything else is dropped: «7a-8 9» → 789") { c in c.eq(b.inThem, "789", "لهم") }
    s.tapField(.us)
    s.clear(.us)
    s.tapField(.them)
    s.clear(.them)
    s.tapField(.us)
    s.key("0")
    step("0 alone counts as 0: «سجل النتيجة» stays off") { c in
        c.eq(b.inUs, "0", "لنا")
        c.eq(b.canRecord, false, "canRecord")
    }
    s.key("0")
    step("«00» reads 0, a lone 0 (build 4, Digits.field)") { c in
        c.eq(b.inUs, "0", "لنا")
        c.eq(s.focus, .us, "focus")
    }
    s.key("5")
    step("a 0 in front of another digit is dropped (build 4): «0» then «5» reads 5, stays in لنا (one real digit), and is on") { c in
        c.eq(b.inUs, "5", "لنا")
        c.eq(s.focus, .us, "focus")
        c.eq(b.canRecord, true, "canRecord")
    }
    s.clear(.us)
    s.paste("٠٠٧")
    step("pasting «٠٠٧» gives 7 and stays") { c in
        c.eq(b.inUs, "7", "لنا")
        c.eq(s.focus, .us, "focus")
    }
    s.clear(.us)
    s.type("0")
    s.type("5")
    s.tapField(.us)
    s.pressReturn()
    step("Return in لنا goes to لهم") { c in c.eq(s.focus, .them, "focus") }
    s.pressReturn()
    step("Return in لهم records [5, 0]") { c in
        c.eq(b.hands.last.map { [$0.us, $0.them] } ?? [], [5, 0], "hand")
        c.eq(s.focus == nil, true, "keyboard closed")
    }
    s.wait(1100)
    if let h = b.hands.last { s.tapPencil(h) }
    step("the pencil opens the row with «لنا» focused") { c in
        c.eq(s.focus, .editUs, "focus")
        c.eq([b.edUs, b.edThem], ["5", "0"], "fields")
    }
    s.key("1")
    step("the same rule in an edited row: 5 → 51 moves to «لهم»") { c in
        c.eq(b.edUs, "51", "لنا")
        c.eq(s.focus, .editThem, "focus")
    }
    s.clear(.editThem)
    s.paste("٤٢")
    step("Arabic-Indic in the edited row: «٤٢» → 42") { c in c.eq(b.edThem, "42", "لهم") }
    s.tapCancel()
    s.recordHand(0, 26)
    s.wait(1100)
    if let h = b.hands.last { s.tapPencil(h) }
    step("a hand whose «لنا» is 0 opens with «0» in its field") { c in
        c.eq([b.edUs, b.edThem], ["0", "26"], "fields")
        c.eq(s.focus, .editUs, "focus")
    }
    s.key("1")
    step("typing 1 there reads 1 and does not jump to «لهم» (build 4)") { c in
        c.eq(b.edUs, "1", "لنا")
        c.eq(s.focus, .editUs, "focus")
    }
    s.key("2")
    step("…and a second digit (12) moves on") { c in
        c.eq(b.edUs, "12", "لنا")
        c.eq(s.focus, .editThem, "focus")
    }
    s.retype(us: 0, them: 0)
    step("both edited fields at 0: «حفظ» is off") { c in
        c.eq(b.canSave, false, "canSave")
        c.eq(s.tapSave(), false, "tap")
    }
    s.retype(us: 104, them: 3)
    s.tapSave()
    step("a three-digit edit [104, 3] saves") { c in c.eq(b.hands.last.map { [$0.us, $0.them] } ?? [], [104, 3], "hand") }
}

// MARK: 11. Voice off

private func balootVoiceOff() {
    Report.begin("Baloot 11 · the home page's sound off: banners still show, nothing is said; the setting is kept")
    let d = freshDefaults("b11")
    let app = launch(d)
    let s = BalootScreen(app: app)
    let b = app.baloot
    tapVoiceChip(app)
    s.recordHand(94, 95)
    s.recordHand(10, 10)
    step("«لنا ولهم فوق المية» shows, the voice is not used") { c in
        c.eq(b.bannerOn, true, "banner")
        c.eq(app.speaker.spoken().count, 0, "said")
        c.eq(app.speaker.log.filter { $0.kind == .muted }.map(\.text), ["لنا ولهم فوق المئة"], "asked while muted")
    }
    s.wait(1100)
    s.recordHand(60, 0)
    s.wait(3000)
    step("the win sequence plays, the win screen shows, and nothing is said") { c in
        c.eq(b.posterVisible, true, "win screen")
        c.eq(app.speaker.spoken().count, 0, "said")
    }
    let app2 = launch(d)
    step("the sound setting is kept after a relaunch") { c in c.eq(app2.settings.voice, false, "voice") }
    tapVoiceChip(app2)
    let s2 = BalootScreen(app: app2)
    s2.tapPosterNewGame()
    s2.recordHand(101, 0)
    step("sound back on: «لنا فوق المئة» is said") { c in c.eq(app2.speaker.spoken().map(\.text), ["لنا فوق المئة"], "said") }
}

// MARK: 12. Save and restore

private func balootSaveRestore() {
    Report.begin("Baloot 12 · saved on every change and restored at launch; a finished صكة reopens on its win screen")
    let d = freshDefaults("b12")
    let app = launch(d)
    let s = BalootScreen(app: app)
    s.recordHand(10, 6)
    s.recordHand(0, 26)
    s.recordHand(18, 80)
    s.wait(1100)
    let ids = app.baloot.hands.map(\.id)
    let app2 = launch(d)
    let b2 = app2.baloot
    let s2 = BalootScreen(app: app2)
    step("relaunch: the same hands (ids too), totals 28/112, nothing said or shown, no win screen") { c in
        c.eq(b2.hands.map { [$0.us, $0.them] }, [[10, 6], [0, 26], [18, 80]], "hands")
        c.eq(b2.hands.map(\.id), ids, "ids")
        c.eq(sc(b2.totals), [28, 112], "totals")
        c.eq(app2.speaker.log.count, 0, "voice")
        c.eq(b2.bannerOn || b2.posterVisible || b2.confirmNew, false, "banner, win screen, confirm")
    }
    let m = app2.speaker.mark
    s2.recordHand(0, 5)
    step("لهم's 100 was kept: passing again says nothing; the new hand gets a new id") { c in
        c.eq(app2.speaker.spoken(since: m).count, 0, "voice")
        c.eq(Set(b2.hands.map(\.id)).count, 4, "ids unique")
    }
    s2.wait(1100)
    s2.recordHand(140, 0)
    s2.wait(3000)
    let app3 = launch(d)
    let b3 = app3.baloot
    step("relaunch after a win: on the win screen at once, its parts in, no sequence, no voice") { c in
        c.eq(b3.outcome, .won(.us), "outcome")
        c.eq(b3.posterVisible, true, "win screen")
        c.eq(b3.intro, true, "parts in")
        c.eq(b3.holdPoster, false, "held")
        c.eq(b3.topVisible || b3.showEntry, false, "top bar or fields")
        c.eq(b3.tone(.them, value: b3.totals.them), .muted, "loser muted")
    }
    VirtualClock.advance(by: 5000)
    step("…and nothing runs after it") { c in
        c.eq(app3.speaker.log.count, 0, "voice")
        c.eq(VirtualClock.fired.filter { $0.owner == "baloot" }.count, 0, "timers")
    }
    let s3 = BalootScreen(app: app3)
    s3.tapPosterEdit()
    s3.tapCancel()
    VirtualClock.advance(by: 100)
    step("«تعديل» and «إلغاء» work on the restored win screen") { c in
        c.eq(b3.posterVisible && b3.intro, true, "back")
    }
    // Killed during the win sequence: the save was made at the record, so the next launch shows the win screen.
    let d2 = freshDefaults("b12b")
    let app4 = launch(d2)
    let s4 = BalootScreen(app: app4)
    s4.recordHand(90, 0)
    s4.recordHand(70, 0)
    s4.wait(500)
    let app5 = launch(d2)
    step("killed half way through the win sequence: the next launch opens on the win screen") { c in
        c.eq(app5.baloot.posterVisible, true, "win screen")
    }
}

// MARK: 13. Corrupted save

private func balootCorruptedSave() {
    Report.begin("Baloot 13 · a damaged save (build 4): a bad hand or value is dropped, not the صكة; the save as it was is kept under «baloot.v1.damaged»")
    let d = freshDefaults("b13")
    d.set(Data("not json at all".utf8), forKey: "baloot.v1")
    let app = launch(d)
    let s = BalootScreen(app: app)
    step("unreadable bytes: an empty صكة, no crash, the bytes kept aside") { c in
        c.eq(app.baloot.hands.count, 0, "hands")
        c.eq(app.baloot.homeStatus, "صكة جديدة", "home card")
        c.eq(damagedCopy(d, "baloot.v1"), "not json at all", "damaged copy")
    }
    s.recordHand(10, 6)
    step("…and the next hand writes a good save over it; the damaged copy stays") { c in
        c.eq(savedBaloot(d)?.hands.map { [$0.us, $0.them] } ?? [], [[10, 6]], "saved")
        c.eq(damagedCopy(d, "baloot.v1"), "not json at all", "damaged copy")
    }
    let d2 = freshDefaults("b13b")
    d2.set(Data(#"{"hands":"x","said":[]}"#.utf8), forKey: "baloot.v1")
    let app2 = launch(d2)
    step("the wrong shape: an empty صكة, the save kept aside") { c in
        c.eq(app2.baloot.hands.count, 0, "hands")
        c.eq(damagedCopy(d2, "baloot.v1"), #"{"hands":"x","said":[]}"#, "damaged copy")
    }

    let d3 = freshDefaults("b13c")
    let json = #"{"hands":[{"id":1,"us":10,"them":5},{"id":1,"us":20,"them":0},{"id":0,"us":5,"them":5},{"id":4,"us":1000,"them":0},{"id":5,"us":0,"them":0},{"id":6,"us":-3,"them":4},{"id":7,"us":30,"them":30},{"id":8,"us":"x","them":3}],"said":[]}"#
    d3.set(Data(json.utf8), forKey: "baloot.v1")
    let app3 = launch(d3)
    let b3 = app3.baloot
    step("out-of-range, empty, negative and unreadable hands dropped one by one; the duplicate id and id 0 renumbered; ids unique") { c in
        c.eq(b3.hands.map { [$0.us, $0.them] }, [[10, 5], [20, 0], [5, 5], [30, 30]], "hands kept")
        c.eq(Set(b3.hands.map(\.id)).count, 4, "ids unique")
        c.eq(b3.hands.allSatisfy { $0.id > 0 }, true, "ids positive")
        c.eq(sc(b3.totals), [65, 40], "totals")
        c.eq(damagedCopy(d3, "baloot.v1"), json, "the save as it was, kept aside")
    }
    let s3 = BalootScreen(app: app3)
    s3.recordHand(1, 1)
    step("the next hand gets an id no other hand has, and the mended صكة replaces the damaged save") { c in
        c.eq(Set(b3.hands.map(\.id)).count, 5, "ids unique")
        c.eq(savedBaloot(d3)?.hands == b3.hands, true, "saved")
        c.eq(damagedCopy(d3, "baloot.v1"), json, "damaged copy kept")
    }

    let d4 = freshDefaults("b13d")
    let json4 = #"{"hands":[{"id":1,"us":10,"them":5}],"said":["both","them"]}"#
    d4.set(Data(json4.utf8), forKey: "baloot.v1")
    let app4 = launch(d4)
    step("an unknown team in «said»: only that value goes, the hand stays, لهم stays said") { c in
        c.eq(app4.baloot.hands.map { [$0.us, $0.them] }, [[10, 5]], "hands")
        c.eq(damagedCopy(d4, "baloot.v1"), json4, "damaged copy")
    }
    let s4 = BalootScreen(app: app4)
    s4.recordHand(0, 100)
    step("…so لهم passing 100 later says nothing (it was said)") { c in
        c.eq(app4.baloot.totals.them, 105, "لهم")
        c.eq(app4.speaker.spoken().count, 0, "voice")
    }

    let d5 = freshDefaults("b13e")
    let json5 = #"{"hands":[{"id":1,"us":120,"them":10}]}"#
    d5.set(Data(json5.utf8), forKey: "baloot.v1")
    let app5 = launch(d5)
    let s5 = BalootScreen(app: app5)
    s5.recordHand(5, 0)
    step("«said» missing: the hand kept, and لنا (above 100) counted as said, so nothing is repeated") { c in
        c.eq(app5.baloot.hands.count, 2, "hands")
        c.eq(app5.speaker.spoken().count, 0, "voice")
        c.eq(damagedCopy(d5, "baloot.v1"), json5, "damaged copy")
    }

    let d6 = freshDefaults("b13f")
    let app6 = launch(d6)
    let s6 = BalootScreen(app: app6)
    s6.recordHand(10, 6)
    s6.recordHand(120, 0)
    _ = launch(d6)
    step("a good save is read as it is: no damaged copy") { c in c.eq(damagedCopy(d6, "baloot.v1") == nil, true, "damaged copy") }
}

// MARK: 14. A new action in the middle of a running sequence

private func balootMidSequence() {
    Report.begin("Baloot 14 · a new action in the middle of a running sequence (record, edit or delete while a count or the win sequence runs)")
    do {
        let d = freshDefaults("b14a")
        let app = launch(d)
        let s = BalootScreen(app: app)
        let b = app.baloot
        let t0 = VirtualClock.now
        s.recordHand(10, 0)
        s.wait(500)
        let shownAt500 = b.shown(at: Date())
        s.recordHand(20, 0)
        step("a second hand 500 ms after the first: the box keeps the number it had reached (board: from = display)") { c in
            c.eq(shownAt500.us, boardCount(0, 10, elapsed: 140), "shown at 500 ms")
            c.eq(b.shown(at: Date()).us, shownAt500.us, "shown right after the second record")
        }
        s.wait(360 + 350)
        step("…then counts from there to 30 on the board's curve") { c in
            c.eq(b.shown(at: Date()).us, boardCount(shownAt500.us, 30, elapsed: 350), "half way")
        }
        s.wait(2000)
        step("…one count end only, at 500+1060; the first hand's count end was cancelled") { c in
            c.eq(fired("baloot", from: t0, to: t0 + 3000, keys: ["countEnd"]).map(\.time), [t0 + 1560], "count ends")
            c.eq(b.shown(at: Date()).us, 30, "final")
        }
    }
    do {
        let d = freshDefaults("b14b")
        let app = launch(d)
        let s = BalootScreen(app: app)
        let b = app.baloot
        s.recordHand(10, 0)
        s.wait(500)
        let shownAt500 = b.shown(at: Date()).us
        if let h = b.hands.last {
            s.tapPencil(h)
            s.retype(us: 20, them: 0)
            s.tapSave()
        }
        let te = VirtualClock.now
        step("an edit 500 ms into the count: the count restarts at once from the number on screen") { c in
            c.eq(b.shown(at: Date()).us, shownAt500, "shown")
            c.eq(b.counting, true, "counting")
        }
        s.wait(1000)
        step("…and ends 700 ms later at 20") { c in
            c.eq(fired("baloot", from: te, to: te + 1000, keys: ["countEnd"]).map(\.time), [te + 700], "count end")
            c.eq(b.shown(at: Date()).us, 20, "final")
        }
    }
    do {
        // Build 4: the win sequence is modal. Every action a player could try, at six moments of it, is a no-op,
        // and the sequence runs to its end on the board's timings with the win said once.
        let d = freshDefaults("b14c")
        let app = launch(d)
        let s = BalootScreen(app: app)
        let b = app.baloot
        s.recordHand(10, 10)
        s.recordHand(84, 85)
        s.wait(1100)
        let m = app.speaker.mark
        let t0 = VirtualClock.now
        s.recordHand(0, 60)
        var reached: [String] = []
        // During the lead, the count, the outline, the copy on the box, the copy grown, and just before the win screen.
        for at in [300, 700, 1100, 1250, 1500, 1800] {
            s.wait(t0 + at - VirtualClock.now)
            let rows = s.rows
            let tries: [(String, Bool)] = [
                ("pencil on the newest row", s.tapPencil(rows[0])),
                ("trash on the newest row", s.tapTrash(rows[0])),
                ("pencil on the second row", s.tapPencil(rows[1])),
                ("trash on the second row", s.tapTrash(rows[1])),
                ("«لنا» field", s.tapField(.us)),
                ("«لهم» field", s.tapField(.them)),
                ("a key", s.key("7")),
                ("Return", s.pressReturn()),
                ("«سجل النتيجة»", s.tapRecord()),
                ("«صكة جديدة»", s.tapNewGame()),
                ("the home chevron", s.tapHome()),
                ("«حفظ»", s.tapSave()),
                ("«إلغاء»", s.tapCancel())
            ]
            reached += tries.filter { $0.1 }.map { "\($0.0) at +\(at) ms" }
        }
        s.wait(5000)
        step("every tap tried during the win sequence (at 300, 700, 1100, 1250, 1500 and 1800 ms) is a no-op: the sequence is modal (build 4)") { c in
            c.eq(reached, [], "taps that reached the store")
            c.eq(b.hands.map { [$0.us, $0.them] }, [[10, 10], [84, 85], [0, 60]], "hands")
            c.eq(b.editId == nil && b.confirmId == nil && !b.confirmNew, true, "nothing opened")
            c.eq([b.inUs, b.inThem], ["", ""], "fields")
        }
        step("…so the sequence runs on the board's timings and «الصكة لهم» is said once, at +2370 ms") { c in
            let keys: Set<String> = ["count", "countEnd", "growBox", "growFull", "poster", "intro", "growOff", "voice"]
            let expected = [VirtualClock.Fired(time: t0 + 360, owner: "baloot", key: "count")] + winTimeline(owner: "baloot", countEnd: t0 + 1060)
            c.eq(fired("baloot", from: t0, to: t0 + 6000, keys: keys), expected, "timers")
            c.eq(app.speaker.spoken(since: m).map(\.text), ["الصكة لهم"], "voice")
            c.eq(app.speaker.spoken(since: m).first.map { "+\($0.time - t0) ms" }, "+2370 ms", "voice time")
            c.eq(b.posterVisible, true, "win screen")
        }
    }
    do {
        // The same after «تعديل» hands the win to the other team: that sequence is modal too.
        let d = freshDefaults("b14d")
        let app = launch(d)
        let s = BalootScreen(app: app)
        let b = app.baloot
        s.recordHand(94, 95)
        s.recordHand(0, 60)
        s.wait(3000)
        s.tapPosterEdit()
        s.retype(us: 70, them: 0)
        let m = app.speaker.mark
        let t1 = VirtualClock.now
        s.tapSave()
        s.wait(500)
        let rows = s.rows
        let tried = [s.tapPencil(rows[0]), s.tapTrash(rows[1]), s.tapField(.us), s.tapNewGame()]
        s.wait(4000)
        step("«تعديل» that hands the win to لنا: during its sequence nothing takes a tap, and «الصكة لنا» comes once at +2010 ms") { c in
            c.eq(tried, [false, false, false, false], "taps")
            c.eq(app.speaker.spoken(since: m).map(\.text), ["الصكة لنا"], "voice")
            c.eq(app.speaker.spoken(since: m).first.map { "+\($0.time - t1) ms" }, "+2010 ms", "voice time")
            c.eq(b.posterVisible, true, "win screen")
        }
    }
    do {
        // «صكة جديدة» twice during a count.
        let d = freshDefaults("b14f")
        let app = launch(d)
        let s = BalootScreen(app: app)
        let b = app.baloot
        s.recordHand(94, 95)
        s.wait(1100)
        s.recordHand(10, 10)
        s.wait(400)
        s.tapNewGame()
        s.tapNewGame()
        s.wait(4000)
        step("«صكة جديدة» twice in the middle of a count with the banner on: clean, nothing left running") { c in
            c.eq(b.hands.count, 0, "hands")
            c.eq(b.display == nil && b.countStart == nil, true, "count")
            c.eq(b.bannerOn, false, "banner")
            c.eq(b.pulse.isEmpty && b.ghost == nil, true, "motion")
        }
    }
}

// MARK: 15. Reduce Motion

private func balootReduceMotion() {
    Report.begin("Baloot 15 · Reduce Motion: no wait before the count, no count, no breathing, no growing box; the voice about 100 ms after the win")
    let d = freshDefaults("b15")
    let app = launch(d)
    Motion.reduceMotionSwitch = true
    let s = BalootScreen(app: app)
    let b = app.baloot
    let t0 = VirtualClock.now
    s.recordHand(94, 95)
    step("a hand: the totals are final at once") { c in
        c.eq(sc(b.shown(at: Date())), [94, 95], "shown")
        c.eq(b.counting, false, "counting")
    }
    s.wait(1100)
    step("no breathing and no count timers") { c in
        c.eq(fired("baloot", from: t0, to: t0 + 1100, keys: ["pulseOn", "pulseOff", "countEnd"]), [], "timers")
    }
    let t1 = VirtualClock.now
    let m = app.speaker.mark
    s.recordHand(60, 0)
    step("the winning hand: no hold, no box; the win screen is up at once") { c in
        c.eq(b.holdPoster, false, "held")
        c.eq(b.posterVisible, true, "win screen")
        c.eq(b.lift, false, "outline")
        c.eq(b.grow, .off, "copy")
        c.eq(b.feedback, .win, "haptic")
    }
    s.wait(3000)
    step("parts in at +10 ms and «الصكة لنا» at +70 ms (board: playIntro 10, voice 60)") { c in
        c.eq(VirtualClock.fired.first { $0.owner == "baloot" && $0.key == "intro" && $0.time >= t1 }?.time, t1 + 10, "intro")
        c.eq(app.speaker.spoken(since: m).map(\.text), ["الصكة لنا"], "voice")
        c.eq(app.speaker.spoken(since: m).first.map { "+\($0.time - t1) ms" }, "+70 ms", "voice time")
        c.eq(fired("baloot", from: t1, to: t1 + 3000, keys: ["growBox", "growFull", "growOff"]), [], "no growing box")
    }
}

// MARK: 16. Small things

private func balootSmallThings() {
    Report.begin("Baloot 16 · the home card lines, leaving for the home page, the haptics, the track")
    let d = freshDefaults("b16")
    let app = launch(d)
    let s = BalootScreen(app: app)
    let b = app.baloot
    s.recordHand(10, 6)
    step("one hand: «صكة جارية · بعد لعبة وحدة»") { c in c.eq(b.homeStatus, "صكة جارية · بعد لعبة وحدة", "home card") }
    s.recordHand(10, 6)
    step("two hands: «صكة جارية · بعد لعبتين»") { c in c.eq(b.homeStatus, "صكة جارية · بعد لعبتين", "home card") }
    s.wait(1100)
    s.tapNewGame()
    if let h = b.hands.last { s.tapTrash(h) }
    s.tapHome()
    step("leaving for the home page closes «متأكد؟» and «احذف؟» and keeps the صكة") { c in
        c.eq(b.confirmNew, false, "confirm new")
        c.eq(b.confirmId == nil, true, "confirm delete")
        c.eq(b.hands.count, 2, "hands")
    }
    step("haptics: a hand is a light impact, the win a success, a refusal an error") { c in
        c.eq(Feedback.record.sensory, SensoryFeedback.impact(weight: .light), "record")
        c.eq(Feedback.win.sensory, SensoryFeedback.success, "win")
        c.eq(Feedback.refuse.sensory, SensoryFeedback.error, "refuse")
        c.eq(Feedback.none.sensory == nil, true, "none")
    }
    step("the track fills toward 152 (board pct: min(100, v/152))") { c in
        c.eq(BalootRules.trackFill(76), 0.5, "76")
        c.eq(BalootRules.trackFill(200), 1, "200")
    }
}
