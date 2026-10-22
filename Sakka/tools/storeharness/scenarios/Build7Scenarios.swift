import Foundation
import SwiftUI

// Scenarios for build 7 (22 Oct 2026), from the owner's words: «في اخر جولة تحسب الفرق بين كل واحد مقارنه في الاول
// ويكون في سطر منفصل». الهند is won on the lowest total, so the first is whoever has it: the line writes 0 over him
// and what each of the others has over him, under the round line, in آخر جولة and in the جولة فاصلة after a tie.

func runBuild7Scenarios() {
    handGapLineInTheLastRound()
    handGapLineInTheDeciderRound()
}

/// The board's game, seven rounds in and settled: the eighth makes it آخر جولة.
private func sevenRoundsIn(_ tag: String) -> (UserDefaults, AppModel, HandScreen) {
    let d = freshDefaults(tag)
    let app = launch(d)
    let s = HandScreen(app: app)
    s.open()
    for (i, n) in boardNames.enumerated() { s.setupName(i, n) }
    s.setupStart()
    for r in boardRounds.prefix(7) {
        s.record(r)
        s.wait(3300)
    }
    return (d, app, s)
}

private func handGapLineInTheLastRound() {
    Report.begin("Hand 34 · the الفرق line of آخر جولة (build 7): a number under each player — 0 over the first and what the others have over him — counting with the boxes, away while a round is edited and once the game is won")
    let (_, app, s) = sevenRoundsIn("h34")
    let h = app.hand
    step("round 8 of 9 on the board (207, 645, 419, 822): no الفرق line yet") { c in
        c.eq(s.totals, [207, 645, 419, 822], "totals")
        c.eq(h.roundLine, "الجولة 8 من 9", "status line")
        c.eq(h.showsGap, false, "the line")
        c.eq(s.gapTexts == nil, true, "the numbers")
    }
    let t0 = VirtualClock.now
    s.record(boardRounds[7])
    s.wait(710)
    step("the round goes in and آخر جولة comes: 350 ms into the count the line counts with the boxes, behind the «آخر جولة» banner") { c in
        c.eq(h.showsGap, true, "the line")
        c.eq(h.banner, "آخر جولة", "banner")
        c.eq(h.bannerOn, true, "the banner hides the two lines for its 3.2 s")
        c.eq(h.counting, true, "counting")
        c.eq(h.players.map { h.shown(at: Date())[$0.id] ?? 0 }, [181, 674, 507, 910], "totals on screen")
        c.eq(s.gapTexts, ["0", "+493", "+326", "+729"], "the numbers on screen")
    }
    s.wait(2590)
    step("the count over and the banner gone (177, 678, 519, 922): حمد is the first, and أنور, فهد and سالم have 501, 342 and 745 to make up") { c in
        c.eq(VirtualClock.now - t0, 3300, "time")
        c.eq(s.totals, [177, 678, 519, 922], "totals")
        c.eq(h.bannerOn, false, "banner")
        c.eq(h.roundLine, "آخر جولة", "status line")
        c.eq(s.gapTexts, ["0", "+501", "+342", "+745"], "the الفرق line")
        c.eq(h.gaps(h.totals), [s.id(0): 0, s.id(1): 501, s.id(2): 342, s.id(3): 745], "the numbers")
    }
    let rows = s.rows
    s.tapRow(rows[0])
    s.tapEdit(rows[0])
    step("«تعديل الجولة 8»: the edit row takes the status line, and the الفرق line goes with it") { c in
        c.eq(h.editLine, "تعديل الجولة 8", "edit line")
        c.eq(h.showsGap, true, "the round is still آخر جولة")
        c.eq(s.gapTexts == nil, true, "the numbers")
    }
    s.tapCancelEdit()
    step("«إلغاء»: the round line and the الفرق line are back as they were") { c in
        c.eq(h.roundLine, "آخر جولة", "status line")
        c.eq(s.gapTexts, ["0", "+501", "+342", "+745"], "the الفرق line")
    }
    s.record(boardRounds[8])
    s.wait(3000)
    step("the last round goes in: حمد wins with 277, and the line is away — the win screen has the game") { c in
        c.eq(h.outcome, .won(s.id(0)), "winner")
        c.eq(s.totals, [277, 648, 619, 1022], "totals")
        c.eq(h.roundLine, "", "status line")
        c.eq(h.showsGap, false, "the line")
        c.eq(s.gapTexts == nil, true, "the numbers")
        c.eq(h.posterVisible, true, "win screen")
    }
}

/// The rounds of Hand 7: three players, and a tie on the lowest after round 7 (310, 310, 570).
private let deciderRounds: [[Cell]] = [
    [.nd, .out, .nd], [.nd, .out, .nd], [.nd, .nd, .out], [.out, .nd, .nd], [.nd, .out, .nd], [.out, .nd, .nd], [.out, .nd, .nd]
]

private func handGapLineInTheDeciderRound() {
    Report.begin("Hand 35 · the الفرق line in the جولة فاصلة (build 7): two players level on the lowest are both the first, 0 each")
    let d = freshDefaults("h35")
    let app = launch(d)
    let s = HandScreen(app: app)
    let h = app.hand
    s.open()
    s.setupRemove(3)
    for (i, n) in ["حمد", "أنور", "فهد"].enumerated() { s.setupName(i, n) }
    s.setupStart()
    for (i, r) in deciderRounds.enumerated() {
        s.record(r)
        s.wait(3300)
        if i == 4 {
            step("round 5 of 7 (370, 110, 370): still no line") { c in
                c.eq(s.totals, [370, 110, 370], "totals")
                c.eq(h.showsGap, false, "the line")
                c.eq(s.gapTexts == nil, true, "the numbers")
            }
        }
        if i == 5 {
            step("آخر جولة (340, 210, 470): أنور is the first, and حمد and فهد have 130 and 260 to make up") { c in
                c.eq(s.totals, [340, 210, 470], "totals")
                c.eq(h.roundLine, "آخر جولة", "status line")
                c.eq(s.gapTexts, ["+130", "0", "+260"], "the الفرق line")
            }
        }
    }
    step("round 7 ties حمد and أنور on 310: the جولة فاصلة keeps the line, with a 0 over each of them") { c in
        c.eq(s.totals, [310, 310, 570], "totals")
        c.eq(h.outcome, .tie([s.id(0), s.id(1)], at: 310), "outcome")
        c.eq(h.roundLine, "جولة فاصلة", "status line")
        c.eq(h.showsGap, true, "the line")
        c.eq(s.gapTexts, ["0", "0", "+260"], "the الفرق line")
    }
    s.record([.nd, .nd, .out])
    s.wait(3300)
    step("the جولة فاصلة ties them again on 410: the line follows the new totals") { c in
        c.eq(s.totals, [410, 410, 540], "totals")
        c.eq(h.roundLine, "جولة فاصلة", "status line")
        c.eq(s.gapTexts, ["0", "0", "+130"], "the الفرق line")
    }
    s.record([.nd, .out, .nd])
    s.wait(3000)
    step("أنور alone on the lowest, 380: the win, and no line") { c in
        c.eq(h.outcome, .won(s.id(1)), "winner")
        c.eq(h.showsGap, false, "the line")
        c.eq(s.gapTexts == nil, true, "the numbers")
    }
}
