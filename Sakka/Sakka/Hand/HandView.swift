import SwiftUI

/// Sizes for 2 to 6 players, from the board: name, box height, total, field, rising number, log row, gap.
struct HandLayout {
    let nameSize: CGFloat
    let boxHeight: CGFloat
    let totalSize: CGFloat
    let fieldSize: CGFloat
    let riseSize: CGFloat
    let rowSize: CGFloat
    let gap: CGFloat
    /// How many نزول circles fit over a name before it turns into one circle and the number.
    let pipMax: Int

    /// `short`: a screen under 700 points (iPhone SE). Two players there take the three-player sizes,
    /// so the status line stays clear of the keypad.
    init(count: Int, short: Bool = false) {
        let n = max(HandRules.minPlayers, min(HandRules.maxPlayers, count))
        let t: [CGFloat]
        switch short && n == 2 ? 3 : n {
        case 2: t = [30, 118, 72, 34, 34, 26, 12]
        case 3: t = [26, 104, 54, 32, 26, 26, 10]
        case 4: t = [22, 96, 44, 30, 22, 24, 8]
        case 5: t = [19, 88, 36, 26, 18, 22, 8]
        default: t = [17, 84, 31, 24, 16, 20, 6]
        }
        nameSize = t[0]
        boxHeight = t[1]
        totalSize = t[2]
        fieldSize = t[3]
        riseSize = t[4]
        rowSize = t[5]
        gap = t[6]
        pipMax = [2: 9, 3: 9, 4: 8, 5: 6, 6: 5][n] ?? 5
    }
}

/// الهند: «لعبة جديدة» on top, a column per player (نزول circles, name, total), the round's progress,
/// a field per player, the status line (with the الفرق line under it in آخر جولة), the log, and the keypad that
/// comes up for a tapped field.
struct HandView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var c
    @Environment(\.screenInsets) private var insets
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onHome: () -> Void

    @State private var boxFrames: [String: CGRect] = [:]
    @State private var size: CGSize = .zero

    static let space = "hand"
    /// The keypad without its bottom padding: 10 + 48 + 8 + 4 × 46 + 3 × 8.
    static let padContent: CGFloat = 274
    static let keyHeight: CGFloat = 46
    /// The الفرق numbers under the round line: one size at every count, in a line box as tight as the boards give
    /// numerals (54 in 51), so the round line and it together keep the status line's 34 points.
    static let gapSize: CGFloat = 13
    static let gapBox: CGFloat = 12

    /// Under the keypad's last row: 4 points over the home indicator, or 24 on a phone without one. Build 5 had
    /// 28 on top of the indicator's 34, an empty band under the keys.
    static func padBottom(_ insets: EdgeInsets) -> CGFloat {
        max(insets.bottom, 20) + 4
    }

    private var store: HandStore { app.hand }
    private var layout: HandLayout { HandLayout(count: store.players.count, short: size.height > 0 && size.height < 700) }

    var body: some View {
        ZStack(alignment: .top) {
            c.ground
                .contentShape(Rectangle())
                .onTapGesture { store.hidePad() }
            column
            HandKeypad()
                .frame(maxHeight: .infinity, alignment: .bottom)
            if store.grow != .off, let id = store.growPlayer, let frame = boxFrames[id] {
                let total = Digits.signed(store.totals[id] ?? 0)
                GrowingBox(stage: store.grow, from: frame, to: CGRect(origin: .zero, size: size), total: total,
                           totalFont: .numerals((layout.totalSize * HandRules.fitScale(total)).rounded()))
            }
            if store.posterVisible {
                HandPoster(onHome: leave)
            }
        }
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .sensoryFeedback(trigger: store.feedbackTick) { _, _ in
            app.settings.haptics ? store.feedback.sensory : nil
        }
        .fullScreenCover(isPresented: Binding(get: { store.setupOpen }, set: { if !$0 { store.closeSetup() } })) {
            HandSetupView()
                .environment(app)
                .environment(\.palette, c)
                .environment(\.layoutDirection, .rightToLeft)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }

    private func leave() {
        store.leave()
        onHome()
    }

    // MARK: Column

    private var column: some View {
        VStack(spacing: 0) {
            topBar
            header
            lane.padding(.top, 12)
            status.padding(.top, 8)
            log.padding(.top, 8)
        }
        .padding(.top, insets.top + 8)
        .padding(.horizontal, 20)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
    }

    private var topBar: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { store.hidePad() }
            CapsuleButton(title: "لعبة جديدة", padding: 14) { store.openSetup() }
            HStack {
                HomeButton(action: leave).padding(.leading, -10)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 44)
        .opacity(store.topVisible ? 1 : 0)
        .allowsHitTesting(store.topVisible)
        .accessibilityHidden(!store.topVisible)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            names.padding(.top, 4)
            TimelineView(.animation(paused: !store.counting)) { context in
                boxes(store.shown(at: context.date))
            }
            .padding(.top, 4)
            progress.padding(.top, 10)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.hidePad() }
    }

    private var names: some View {
        let downs = store.downs
        return HStack(alignment: .bottom, spacing: layout.gap) {
            ForEach(store.players) { p in
                VStack(spacing: 4) {
                    Pips(count: downs[p.id] ?? 0, before: store.pipPrev?[p.id], on: store.pipOn, max: layout.pipMax)
                        .frame(height: 8)
                    Text(verbatim: store.name(p.id))
                        .font(.amiri(layout.nameSize))
                        .foregroundStyle(c.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .lineBox(layout.nameSize * 1.3)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func boxes(_ shown: [String: Int]) -> some View {
        let won = store.outcome.winner
        let low = store.rounds.isEmpty ? nil : store.players.map { shown[$0.id] ?? 0 }.min()
        return HStack(spacing: layout.gap) {
            ForEach(store.players) { p in
                let v = shown[p.id] ?? 0
                let text = Digits.signed(v)
                let finalText = Digits.signed(store.totals[p.id] ?? 0)
                let fit = HandRules.fitScale(finalText.count > text.count ? finalText : text)
                let color: Color = {
                    // Through the win sequence too when زات won: its winner need not be the lowest.
                    if let won, !store.holdPoster || store.wonByZat { return won == p.id ? c.gold : c.inkMuted }
                    return v == low ? c.gold : c.ink
                }()
                Text(verbatim: text)
                    .font(.numerals((layout.totalSize * fit).rounded()))
                    .foregroundStyle(color)
                    .animation(.easeInOut(duration: 0.3), value: color)
                    .lineLimit(1)
                    // On a narrow window the step-down above may not be enough: never cut a total.
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay { rising(p.id) }
                    .frame(height: layout.boxHeight)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.surface))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(store.lift && store.growPlayer == p.id ? c.ink : c.line, lineWidth: 1)
                            .animation(.easeInOut(duration: 0.2), value: store.lift)
                    }
                    .scaleEffect(store.pulse.contains(p.id) && !reduceMotion ? 1.035 : 1)
                    .animation(.settle(0.24), value: store.pulse.contains(p.id))
                    .reportFrame(in: Self.space) { boxFrames[p.id] = $0 }
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(store.name(p.id)) \(text)"))
            }
        }
    }

    /// The round's points rise into each box from below its bottom edge, about half the size of the total.
    @ViewBuilder
    private func rising(_ id: String) -> some View {
        if let text = store.ghost?[id], !reduceMotion {
            let up = store.ghostOn
            Text(verbatim: text)
                .font(.numerals(layout.riseSize, tabular: false))
                .foregroundStyle(c.ink)
                .animation(.settle(0.52)) { $0.offset(y: up ? 0 : 100) }
                .animation(.easeIn(duration: 0.2).delay(0.32)) { $0.opacity(up ? 0 : 1) }
                .allowsHitTesting(false)
        }
    }

    /// One short segment per round: 7, or 9 once a جيكر is in; played rounds are darker.
    private var progress: some View {
        let target = store.target
        let played = store.rounds.count
        let count = max(target, played + (store.isWon ? 0 : 1))
        let width = max(6, ((217 - 4 * CGFloat(count - 1)) / CGFloat(count)).rounded(.down))
        return HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                let isNew = store.segFrom.map { i >= $0 } == true && !store.segOn
                Capsule()
                    .fill(i < played ? c.inkMuted : c.line)
                    .frame(width: width, height: 3)
                    .opacity(isNew ? 0 : 1)
                    .animation(.easeInOut(duration: 0.4).delay(0.2), value: isNew)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: count)
        .animation(.easeInOut(duration: 0.3), value: played)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: store.roundLine))
    }

    // MARK: Lane

    private var lane: some View {
        let st = store.status
        return HStack(spacing: layout.gap) {
            ForEach(store.players) { p in
                LaneField(player: p, status: st, layout: layout)
            }
        }
    }

    // MARK: Status

    private var status: some View {
        ZStack {
            if store.editId != nil {
                HStack(spacing: 6) {
                    Text(verbatim: store.editLine)
                        .label(14, .bold)
                        .foregroundStyle(c.ink)
                    Button { store.cancelEdit() } label: {
                        Text("إلغاء")
                            .label(14, .semibold)
                            .foregroundStyle(c.inkMuted)
                            .padding(.horizontal, 8)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .opacity(store.bannerOn ? 0 : 1)
            } else {
                VStack(spacing: 1) {
                    Text(verbatim: store.roundLine)
                        .label(14, .medium)
                        .foregroundStyle(c.inkMuted)
                        .lineLimit(1)
                    // آخر جولة: the الفرق line, counting with the boxes while the totals count.
                    if store.showsGap {
                        TimelineView(.animation(paused: !store.counting)) { context in
                            gapLine(store.shown(at: context.date))
                        }
                    }
                }
                .opacity(store.bannerOn ? 0 : 1)
            }
            BannerPill(text: store.banner, danger: store.bannerDanger)
                .opacity(store.bannerOn ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .animation(.easeInOut(duration: 0.24), value: store.bannerOn)
        .contentShape(Rectangle())
        .onTapGesture { store.hidePad() }
        .accessibilityElement(children: .contain)
    }

    /// The الفرق line of آخر جولة: a number under each player's column — 0 over the first, in gold as his total
    /// is, and «+501» over everyone else, what he has to make up before the round goes in.
    private func gapLine(_ shown: [String: Int]) -> some View {
        let gaps = store.gaps(shown)
        return HStack(spacing: layout.gap) {
            ForEach(store.players) { p in
                let gap = gaps[p.id] ?? 0
                Text(verbatim: Digits.gap(gap))
                    .font(.numerals(Self.gapSize))
                    .foregroundStyle(gap == 0 ? c.gold : c.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .lineBox(Self.gapBox)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityLabel(Text(verbatim: HandRules.gapSpeech(name: store.name(p.id), gap: gap)))
            }
        }
    }

    // MARK: Log

    private var log: some View {
        ScrollView {
            VStack(spacing: 0) {
                if store.rounds.isEmpty {
                    Text("الجولات تنكتب هنا")
                        .label(14, .medium)
                        .foregroundStyle(c.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
                ForEach(Array(store.rounds.enumerated().reversed()), id: \.element.id) { index, round in
                    LogRow(round: round, number: index + 1, layout: layout)
                }
            }
            // The rows keep the page's margins; each round's number sits in the margin at its row's start.
            .padding(.horizontal, 20)
            .animation(store.padUp ? .settle(0.34) : .sinking(0.26)) {
                $0.padding(.bottom, store.padUp ? Self.padContent + Self.padBottom(insets) + 1 : 28 + insets.bottom)
            }
        }
        .scrollIndicators(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { store.hidePad() }
        .overlay(alignment: .top) { Rectangle().fill(c.line).frame(height: 1).padding(.horizontal, 20) }
        // Out to the column's edges, so the margins are inside the scroll view and the numbers are not cut off.
        .padding(.horizontal, -20)
    }
}

/// The نزول circles over a name: one small ring per down, in the alert colour; past what fits, one ring and
/// the number. A new one fades in once the numbers have risen into the boxes.
struct Pips: View {
    @Environment(\.palette) private var c
    var count: Int
    var before: Int?
    var on: Bool
    var max: Int

    var body: some View {
        let over = count > max
        let show = over ? 1 : count
        let prev = before ?? count
        HStack(spacing: 4) {
            ForEach(0..<show, id: \.self) { i in
                let fresh = !on && before != nil && (over ? count > prev : i >= prev)
                Circle()
                    .strokeBorder(c.danger, lineWidth: 1.25)
                    .frame(width: 6, height: 6)
                    .animation(.easeInOut(duration: 0.32)) { $0.opacity(fresh ? 0 : 1) }
                    .animation(.settle(0.46)) { $0.scaleEffect(fresh ? 0.4 : 1) }
            }
            if over {
                Text(verbatim: "\(count)")
                    .font(.numerals(12, tabular: false))
                    .foregroundStyle(c.danger)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count > 0 ? Text(verbatim: ArabicCount.downs(count)) : Text(verbatim: ""))
        .accessibilityHidden(count == 0)
    }
}

/// A player's field: the value typed (a ring round a نزول, the alert colour past the cap), what it is under it,
/// a hand in one corner for «من إيده» and a megaphone in the other for «معلن», and the copy that lifts out when
/// the round is recorded; faded while another player has زات. A tap brings the keypad up for it.
struct LaneField: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var c
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var player: HandPlayer
    var status: EntryStatus
    var layout: HandLayout

    private var store: HandStore { app.hand }

    var body: some View {
        let x = store.entry[player.id] ?? .empty
        let focused = store.focus == player.id && store.padUp
        let down = HandRules.isDown(x, in: store.entry)
        let over = status.over.contains(player.id)
        let shaking = store.shakeIds.contains(player.id) && !reduceMotion
        let zat = x.kind == .zat
        // In a round of زات the other fields count nothing: they stay as typed, faded, for a finish that may come back.
        let faded = HandRules.zatElsewhere(store.entry, focus: player.id)
        var value = ""
        var caption = ""
        let m = status.multiplier
        if zat {
            value = "زات"
            caption = "الفوز"
        } else if let k = x.kind, k.isFinish {
            value = Digits.signed(-30 * k.multiplier)
            caption = k.name
        } else if x.kind == .notDown {
            value = "\(100 * m)"
            caption = "ما نزل"
        } else if x.kind == .cards, !x.digits.isEmpty {
            // An old round's cards, while it is edited.
            value = x.digits
            if m > 1, x.cards > 0 { caption = "تصير \(m * x.cards)" }
        } else if x.kind == .exact || x.kind == .free {
            // The number as typed, the sign as pressed, before a digit too (−, then −45).
            value = (x.negative ? "\u{2212}" : "") + x.digits
            if x.kind == .free { caption = "حر" }
        }
        // «من إيده» and «معلن»: a badge each and, once they count, what the field comes to.
        let handCounts = x.fromHand && x.kind != .free && HandRules.fromHandPoints(multiplier: m) != nil
        let declared = x.kind == .notDown ? x.declared : 0
        let marked = (handCounts || declared > 0) && !faded ? HandRules.points(x, multiplier: m) : nil
        let said = marked != nil && (x.kind == .cards || x.kind == .exact) ? "" : caption
        // The number isolated, so a sign stays in front of it in the right-to-left line.
        if let marked { caption = "تصير " + Digits.isolated(Digits.signed(marked)) }
        if over { caption = status.cap > 1 ? "عنده نزولين" : "عنده نزول" }
        let name = store.name(player.id)
        let spoken = over ? caption : said
        var aria = "نقاط " + name + (value.isEmpty ? "" : " " + value) + (spoken.isEmpty ? "" : "، " + spoken)
        if down && !over { aria += "، نزل" }
        if x.fromHand { aria += "، من إيده" }
        if declared > 0 { aria += "، " + HandRules.declaredName(declared) }
        if let marked { aria += "، تصير " + Digits.signed(marked) }
        if faded { aria += "، ما تنحسب مع الزات" }

        return Button { store.focusField(player.id) } label: {
            VStack(spacing: 4) {
                Text(verbatim: value)
                    .font(zat ? .system(size: (layout.fieldSize * 0.72).rounded(), weight: .bold) : .numerals(layout.fieldSize, tabular: false))
                    .foregroundStyle(zat ? c.gold : c.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, value.isEmpty ? 0 : 6)
                    .padding(.vertical, 1)
                    .overlay {
                        Capsule()
                            .strokeBorder(over ? c.danger : (down ? c.gold : .clear), lineWidth: 1)
                            .animation(.easeInOut(duration: 0.2), value: down || over)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                if !caption.isEmpty {
                    Text(verbatim: caption)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(over ? c.danger : c.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .opacity(faded ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.2), value: faded)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.surface))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(focused ? c.ink : c.lineStrong, lineWidth: focused ? 2 : 1)
            }
            // «من إيده»: a small badge with the hand on the field's corner, clear of the number at any width.
            .overlay(alignment: .topLeading) {
                if x.fromHand { badge("hand.raised.fill").alignmentGuide(.leading) { _ in 4 }.opacity(faded ? 0.35 : 1) }
            }
            // «معلن»: a megaphone on the other corner.
            .overlay(alignment: .topTrailing) {
                if declared > 0 { badge("megaphone.fill").alignmentGuide(.trailing) { d in d.width - 4 }.opacity(faded ? 0.35 : 1) }
            }
            .overlay { ghost }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyframeAnimator(initialValue: CGFloat(0), trigger: store.shakeTick) { content, dx in
            content.offset(x: shaking ? dx : 0)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(CGFloat(-6), duration: 0.076)
                LinearKeyframe(CGFloat(5), duration: 0.076)
                LinearKeyframe(CGFloat(-3), duration: 0.076)
                LinearKeyframe(CGFloat(2), duration: 0.076)
                LinearKeyframe(CGFloat(0), duration: 0.076)
            }
        }
        .accessibilityLabel(Text(verbatim: aria))
        .accessibilityAddTraits(focused ? .isSelected : [])
    }

    private func badge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .regular))
            .foregroundStyle(c.ink)
            .frame(width: 18, height: 18)
            .background(Circle().fill(c.surface))
            .overlay(Circle().strokeBorder(c.lineStrong, lineWidth: 1))
            .alignmentGuide(.top) { _ in 4 }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var ghost: some View {
        if let text = store.ghost?[player.id] {
            let lifted = store.ghostOn
            Text(verbatim: text)
                .font(.numerals(layout.fieldSize, tabular: false))
                .foregroundStyle(c.ink)
                .environment(\.layoutDirection, .leftToRight)
                .animation(.easeOut(duration: 0.22)) { $0.offset(y: lifted && !reduceMotion ? -10 : 0) }
                .animation(.easeOut(duration: reduceMotion ? 0.2 : 0.18)) { $0.opacity(lifted ? 0 : 1) }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// A round in the log: each player's points, the lowest in ink, a ring on whoever went down, a hand for
/// «من إيده» and a megaphone for «معلن», زات in gold, and the round's number, very small, in the margin at the row's
/// start.
/// The two newest open on a tap for «تعديل» and «حذف».
struct LogRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var c
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var round: HandRound
    var number: Int
    var layout: HandLayout

    private var store: HandStore { app.hand }

    var body: some View {
        let selected = store.selected == round.id && store.editId == nil
        let editing = store.editId == round.id
        let fresh = store.freshId == round.id && !store.freshOn
        let moving = store.freshId == round.id && store.freshOn
        VStack(spacing: 0) {
            if store.canTouch(round) {
                Button { store.tapRow(round) } label: { cells(highlight: selected || editing) }
                    .buttonStyle(.plain)
                    .accessibilityHint(selected ? "" : "تعديل أو حذف")
            } else {
                cells(highlight: editing)
                    .onTapGesture { store.hidePad() }
            }
            if selected { actions }
        }
        .animation(moving ? .easeOut(duration: reduceMotion ? 0.2 : 0.26).delay(reduceMotion ? 0 : 0.16) : nil) {
            $0.opacity(fresh ? 0 : 1)
        }
        .animation(moving ? .settle(0.32).delay(0.16) : nil) {
            $0.offset(y: fresh && !reduceMotion ? -8 : 0)
        }
    }

    /// The cell of someone who typed nothing in a round of زات: nothing to show.
    private func blank(_ cell: HandCell?) -> Bool {
        guard let cell else { return true }
        return cell.kind == .cards && cell.cards == 0 && !cell.fromHand
    }

    private func cells(highlight: Bool) -> some View {
        let pts = HandRules.points(round)
        let zat = HandRules.hasZat(round)
        let low = store.players.map { pts[$0.id] ?? 0 }.min() ?? 0
        let aria = "الجولة \(number): " + store.players.map { p in
            let cell = round.cells[p.id]
            if cell?.kind == .zat { return store.name(p.id) + " زات" }
            if zat && blank(cell) { return store.name(p.id) }
            let v = pts[p.id] ?? 0
            return store.name(p.id) + " " + Digits.signed(v) + (HandRules.isDown(cell, in: round) ? "، نزل" : "")
                + (cell?.fromHand == true ? "، من إيده" : "")
                + ((cell?.declared ?? 0) > 0 ? "، " + HandRules.declaredName(cell?.declared ?? 0) : "")
        }.joined(separator: "، ")
        return HStack(spacing: layout.gap) {
            ForEach(store.players) { p in
                let cell = round.cells[p.id]
                let v = pts[p.id] ?? 0
                let down = HandRules.isDown(cell, in: round)
                Group {
                    if cell?.kind == .zat {
                        Text("زات")
                            .font(.system(size: (layout.rowSize * 0.8).rounded(), weight: .bold))
                            .foregroundStyle(c.gold)
                    } else if zat && blank(cell) {
                        Color.clear.frame(width: 1, height: 1)
                    } else {
                        Text(verbatim: Digits.signed(v))
                            .font(.numerals(layout.rowSize, weight: 500))
                            .foregroundStyle(v == low ? c.ink : c.inkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay {
                                if down { Capsule().strokeBorder(c.gold.opacity(0.6), lineWidth: 1) }
                            }
                            // The same corners as the badges on the field: the hand top right, the megaphone top left.
                            .overlay(alignment: .topTrailing) {
                                if cell?.fromHand == true { mark("hand.raised.fill").offset(x: 5, y: -4) }
                            }
                            .overlay(alignment: .topLeading) {
                                if (cell?.declared ?? 0) > 0 { mark("megaphone.fill").offset(x: -5, y: -4) }
                            }
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        // The round's number, very small, in the margin just past the row's start: clear of the first player's
        // ring and marks at any width.
        .overlay(alignment: .topLeading) {
            Text(verbatim: "\(number)")
                .font(.numerals(10, tabular: false))
                .foregroundStyle(c.inkMuted.opacity(0.75))
                .fixedSize()
                .alignmentGuide(.leading) { d in d.width + 4 }
                .alignmentGuide(.top) { _ in -3 }
                .accessibilityHidden(true)
        }
        .background(highlight ? c.surface : Color.clear)
        .animation(.easeInOut(duration: 0.2), value: highlight)
        .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: aria))
    }

    private func mark(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .regular))
            .foregroundStyle(c.inkMuted)
    }

    private var actions: some View {
        HStack(spacing: 16) {
            Button { store.startEdit(round) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil").font(.system(size: 18, weight: .regular))
                    Text("تعديل").label(14, .bold)
                }
                .foregroundStyle(c.ink)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if store.confirmId == round.id {
                Button { store.delete(round) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 13, weight: .semibold))
                        Text("احذف؟").label(14, .bold)
                    }
                    .foregroundStyle(c.danger)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(c.danger, lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button { store.askDelete(round) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 18, weight: .regular))
                        Text("حذف").label(14, .bold)
                    }
                    .foregroundStyle(c.danger)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(c.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: 1) }
    }
}
