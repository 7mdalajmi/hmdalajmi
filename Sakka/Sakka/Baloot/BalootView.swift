import SwiftUI
import UIKit

/// صكة, as in its design spec: «صكة جديدة» on top, the two boxes, the fields and «سجل النتيجة», the status line,
/// and the log, newest first. The back chevron goes to the home page; the version lives there now.
struct BalootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var c
    @Environment(\.screenInsets) private var insets
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onHome: () -> Void

    enum Field: Hashable { case us, them, editUs, editThem }

    @FocusState private var focus: Field?
    @State private var boxFrames: [Team: CGRect] = [:]
    @State private var size: CGSize = .zero
    /// The status line opens and folds in its own animation, so the log below moves with it.
    @State private var statusShown = false
    /// How far the keyboard reaches up from the bottom of the screen; the page is drawn full screen and
    /// does not shrink for it, so the log makes room itself and a row being edited stays above it.
    @State private var keyboard: CGFloat = 0
    /// The log's top edge in the window (it moves with the status line, not with scrolling).
    @State private var logTop: CGFloat = 0

    static let space = "baloot"
    private var store: BalootStore { app.baloot }

    var body: some View {
        ZStack(alignment: .top) {
            c.ground
                .contentShape(Rectangle())
                .onTapGesture { focus = nil }
            column
            if store.grow != .off, let frame = boxFrames[store.growTeam] {
                GrowingBox(stage: store.grow, from: frame, to: CGRect(origin: .zero, size: size),
                           total: "\(store.totals[store.growTeam])", totalFont: .numerals(72), totalOffset: Box.totalOffset)
            }
            if store.posterVisible {
                BalootPoster(onHome: leave)
            }
        }
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .sensoryFeedback(trigger: store.feedbackTick) { _, _ in
            app.settings.haptics ? store.feedback.sensory : nil
        }
        .onChange(of: store.editId) { _, id in
            focus = id == nil ? nil : .editUs
        }
        // From the winning hand on, nothing is typed: the keyboard goes before the win screen comes.
        .onChange(of: store.holdPoster) { _, on in if on { focus = nil } }
        .onChange(of: store.posterVisible) { _, on in if on { focus = nil } }
        .onAppear { statusShown = store.statusOpen }
        .onChange(of: store.statusOpen) { _, open in
            withAnimation(.easeInOut(duration: 0.24)) { statusShown = open }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
            keyboard = Self.overlap(ofKeyboard: end)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboard = 0
        }
    }

    private func leave() {
        focus = nil
        store.leave()
        onHome()
    }

    /// How far the keyboard (its frame comes in screen coordinates) reaches up into the window, which this page
    /// fills: right for an iPad window that is not the whole screen too.
    private static func overlap(ofKeyboard end: CGRect) -> CGFloat {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return 0 }
        let inWindow = window.convert(end, from: window.screen.coordinateSpace)
        guard inWindow.intersects(window.bounds) else { return 0 }
        return max(0, window.bounds.maxY - inWindow.minY)
    }

    // MARK: Column

    private var column: some View {
        VStack(spacing: 0) {
            topBar
            names.padding(.top, 14)
            boxes.padding(.top, 6)
            if store.showEntry {
                lane.padding(.top, 14)
                status
            }
            log.padding(.top, 12)
        }
        .padding(.top, insets.top + 8)
        .padding(.horizontal, 20)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
    }

    private var topBar: some View {
        let confirming = store.confirmNew && !store.isWon
        return ZStack {
            CapsuleButton(title: confirming ? "متأكد؟" : "صكة جديدة", danger: confirming, padding: 12) {
                focus = nil
                store.newGame()
            }
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

    private var names: some View {
        HStack(spacing: 12) {
            ForEach(Team.allCases, id: \.self) { team in
                Text(verbatim: team.name)
                    .font(.amiri(30))
                    .foregroundStyle(c.gold)
                    .lineBox(36)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Boxes

    /// The score box, as in the spec: the total (66) over the track (3), 10 apart, with 16 above and 18 below.
    enum Box {
        static let padTop: CGFloat = 16
        static let padBottom: CGFloat = 18
        static let total: CGFloat = 66
        static let gap: CGFloat = 10
        static let track: CGFloat = 3
        /// Where the total sits against the box's middle: the growing copy puts its own total there.
        static var totalOffset: CGFloat { (padTop - padBottom) / 2 - (gap + track) / 2 }
    }

    private var boxes: some View {
        TimelineView(.animation(paused: !store.counting)) { context in
            let shown = store.shown(at: context.date)
            HStack(spacing: 12) {
                ForEach(Team.allCases, id: \.self) { team in
                    scoreBox(team, value: shown[team])
                }
            }
        }
    }

    private func scoreBox(_ team: Team, value: Int) -> some View {
        let tone = store.tone(team, value: value)
        let color: Color = tone == .gold ? c.gold : (tone == .muted ? c.inkMuted : c.ink)
        let fill = BalootRules.trackFill(value)
        return VStack(spacing: Box.gap) {
            Text(verbatim: "\(value)")
                .font(.numerals(72))
                .foregroundStyle(color)
                .animation(.easeInOut(duration: 0.3), value: tone)
                .lineBox(Box.total)
                .frame(maxWidth: .infinity)
                .overlay { rising(team) }
            Track(fill: fill, fillColor: value > BalootRules.hundred ? c.gold : c.inkMuted, base: c.line, tick: c.inkMuted)
        }
        .padding(EdgeInsets(top: Box.padTop, leading: 12, bottom: Box.padBottom, trailing: 12))
        .frame(maxWidth: .infinity, minHeight: 118)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.surface))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(store.lift && store.growTeam == team ? c.ink : c.line, lineWidth: 1)
                .animation(.easeInOut(duration: 0.2), value: store.lift)
        }
        .scaleEffect(store.pulse.contains(team) && !reduceMotion ? 1.035 : 1)
        .animation(.settle(0.24), value: store.pulse.contains(team))
        .contentShape(Rectangle())
        .onTapGesture { focus = nil }
        .reportFrame(in: Self.space) { boxFrames[team] = $0 }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(team.name) \(value)"))
    }

    /// The typed number rises into its box from below the bottom edge (the box clips it) up to the total's line,
    /// and fades there as the total starts counting.
    @ViewBuilder
    private func rising(_ team: Team) -> some View {
        if let g = store.ghost, !reduceMotion {
            let text = team == .us ? g.us : g.them
            if !text.isEmpty {
                let up = store.ghostOn
                Text(verbatim: text)
                    .font(.numerals(34, tabular: false))
                    .foregroundStyle(c.ink)
                    .animation(.settle(0.52)) { $0.offset(y: up ? 0 : 100) }
                    .animation(.easeIn(duration: 0.2).delay(0.32)) { $0.opacity(up ? 0 : 1) }
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Lane

    private var lane: some View {
        HStack(spacing: 10) {
            field(.us)
            recordButton.frame(width: 108)
            field(.them)
        }
    }

    private func field(_ team: Team) -> some View {
        let key: Field = team == .us ? .us : .them
        let focused = focus == key
        // The setter only runs for what the player types: two digits in «لنا» go straight on to «لهم»;
        // a third digit or a deletion stays.
        let text = Binding<String>(
            get: { team == .us ? store.inUs : store.inThem },
            set: { value in
                if team == .us {
                    let before = Digits.field(store.inUs)
                    store.inUs = value
                    if Digits.field(value).count == 2 && before.count < 2 { focus = .them }
                } else {
                    store.inThem = value
                }
            })
        return TextField("", text: text)
            .keyboardType(.asciiCapableNumberPad)
            // Cleaned after the change, not inside the binding, so the field redraws with the cleaned digits.
            .onChange(of: team == .us ? store.inUs : store.inThem) { _, new in
                let cleaned = Digits.field(new)
                guard cleaned != new else { return }
                if team == .us { store.inUs = cleaned } else { store.inThem = cleaned }
            }
            .multilineTextAlignment(.center)
            .font(.numerals(34, tabular: false))
            .foregroundStyle(c.ink)
            .tint(c.ink)
            .focused($focus, equals: key)
            .disabled(store.holdPoster)
            .submitLabel(team == .us ? .next : .done)
            .onSubmit {
                if team == .us { focus = .them } else { record() }
            }
            .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.surface))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(focused ? c.ink : c.lineStrong, lineWidth: focused ? 2 : 1)
            }
            .overlay { ghost(team) }
            .contentShape(Rectangle())
            .onTapGesture { if !store.holdPoster { focus = key } }
            .accessibilityLabel(team == .us ? "نقاط لنا" : "نقاط لهم")
    }

    /// The digits just recorded lift a little out of the field and fade.
    @ViewBuilder
    private func ghost(_ team: Team) -> some View {
        if let g = store.ghost {
            let text = team == .us ? g.us : g.them
            if !text.isEmpty {
                let lifted = store.ghostOn
                Text(verbatim: text)
                    .font(.numerals(34, tabular: false))
                    .foregroundStyle(c.ink)
                    .animation(.easeOut(duration: 0.22)) { $0.offset(y: lifted && !reduceMotion ? -10 : 0) }
                    .animation(.easeOut(duration: reduceMotion ? 0.2 : 0.18)) { $0.opacity(lifted ? 0 : 1) }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var recordButton: some View {
        Button(action: record) {
            Text("سجل النتيجة")
                .label(16, .bold)
                .foregroundStyle(c.ground)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.ink))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.96, duration: 0.14))
        .disabled(!store.canRecord)
        .opacity(store.canRecord ? 1 : 0.35)
        .scaleEffect(store.pressing && !reduceMotion ? 0.96 : 1)
        .animation(.easeOut(duration: 0.14), value: store.pressing)
        .animation(.easeInOut(duration: 0.2), value: store.canRecord)
    }

    private func record() {
        store.record()
        focus = nil
    }

    // MARK: Status

    private var status: some View {
        ZStack {
            BannerPill(text: store.banner)
                .opacity(store.bannerOn ? 1 : 0)
            if let at = store.tieAt {
                Text(verbatim: BalootRules.tieNote(at))
                    .label(15, .medium)
                    .foregroundStyle(c.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(store.bannerOn ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: statusShown ? 34 : 0)
        .clipped()
        .padding(.top, statusShown ? 10 : 0)
        .animation(.easeInOut(duration: 0.24), value: store.bannerOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Log

    private var log: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if store.hands.isEmpty {
                        Text("سجّل أول لعبة من فوق")
                            .label(15, .medium)
                            .foregroundStyle(c.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }
                    ForEach(store.hands.reversed()) { hand in
                        row(hand)
                    }
                }
                .padding(.bottom, max(insets.bottom, keyboard) + 20)
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollIndicators(.hidden)
            .overlay(alignment: .top) { Rectangle().fill(c.line).frame(height: 1) }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { logTop = $0 }
            // A row opened for «تعديل» is scrolled clear of the keyboard, when the keyboard would cover it.
            .onChange(of: store.editId) { _, id in reveal(id, proxy) }
            .onChange(of: keyboard) { _, _ in reveal(store.editId, proxy) }
        }
    }

    /// The rows that can be edited are the two newest, at the top of the log. If the keyboard would cover the row
    /// (rows are counted at 64, a little more than their 56, so a larger text size errs on the side of scrolling),
    /// it goes to the top of the log's view, which is above the keyboard whenever any of the log is; the bottom
    /// padding gives the room to scroll there. A row already clear of the keyboard is left where it is.
    private func reveal(_ id: Int?, _ proxy: ScrollViewProxy) {
        guard let id, keyboard > 0, let index = Array(store.hands.reversed()).firstIndex(where: { $0.id == id }) else { return }
        let bottom = logTop + CGFloat(index + 1) * 64
        guard bottom > size.height - keyboard else { return }
        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .top) }
    }

    private func row(_ hand: BalootHand) -> some View {
        let editing = store.editId == hand.id
        let confirming = !editing && store.confirmId == hand.id
        let fresh = store.freshId == hand.id && !store.freshOn
        let moving = store.freshId == hand.id && store.freshOn
        return HStack(spacing: 10) {
            cell(hand, team: .us, editing: editing)
            // 108 under «سجل النتيجة»; a row being edited may take more for «حفظ» and «إلغاء» at large text sizes.
            middle(hand, editing: editing, confirming: confirming)
                .frame(width: editing ? nil : 108)
                .frame(minWidth: editing ? 108 : nil)
            cell(hand, team: .them, editing: editing)
        }
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: 1) }
        .animation(moving ? .easeOut(duration: reduceMotion ? 0.2 : 0.26).delay(reduceMotion ? 0 : 0.16) : nil) {
            $0.opacity(fresh ? 0 : 1)
        }
        .animation(moving ? .settle(0.32).delay(0.16) : nil) {
            $0.offset(y: fresh && !reduceMotion ? -8 : 0)
        }
    }

    @ViewBuilder
    private func cell(_ hand: BalootHand, team: Team, editing: Bool) -> some View {
        if editing {
            let key: Field = team == .us ? .editUs : .editThem
            let text = Binding<String>(
                get: { team == .us ? store.edUs : store.edThem },
                set: { value in
                    if team == .us {
                        let before = Digits.field(store.edUs)
                        store.edUs = value
                        if Digits.field(value).count == 2 && before.count < 2 { focus = .editThem }
                    } else {
                        store.edThem = value
                    }
                })
            TextField("", text: text)
                .keyboardType(.asciiCapableNumberPad)
                .onChange(of: team == .us ? store.edUs : store.edThem) { _, new in
                    let cleaned = Digits.field(new)
                    guard cleaned != new else { return }
                    if team == .us { store.edUs = cleaned } else { store.edThem = cleaned }
                }
                .multilineTextAlignment(.center)
                .font(.numerals(26, tabular: false))
                .foregroundStyle(c.ink)
                .tint(c.ink)
                .focused($focus, equals: key)
                .onSubmit { store.saveEdit() }
                .frame(maxWidth: 96, minHeight: 42, maxHeight: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c.surface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(c.ink, lineWidth: 1))
                .frame(maxWidth: .infinity)
                .accessibilityLabel(team == .us ? "تعديل نقاط لنا" : "تعديل نقاط لهم")
        } else {
            let mine = hand.points(team), theirs = hand.points(team.other)
            Text(verbatim: "\(mine)")
                .font(.numerals(26, weight: 500))
                .foregroundStyle(mine < theirs ? c.inkMuted : c.ink)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(verbatim: "\(team.name) \(mine)"))
        }
    }

    @ViewBuilder
    private func middle(_ hand: BalootHand, editing: Bool, confirming: Bool) -> some View {
        if editing {
            HStack(spacing: 6) {
                Button { store.saveEdit() } label: {
                    Text("حفظ")
                        .label(14, .bold)
                        .foregroundStyle(c.ground)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c.ink))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!store.canSave)
                .opacity(store.canSave ? 1 : 0.35)
                Button { store.cancelEdit() } label: {
                    Text("إلغاء")
                        .label(14, .semibold)
                        .foregroundStyle(c.inkMuted)
                        .lineLimit(1)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else if confirming {
            Button { store.delete(hand) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash").font(.system(size: 13, weight: .semibold))
                    Text("احذف؟").label(13, .bold).lineLimit(1)
                }
                .foregroundStyle(c.danger)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(c.danger, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if store.canTouch(hand) {
            HStack(spacing: 4) {
                Button { store.startEdit(hand) } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(c.inkMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("تعديل النتيجة")
                Button { focus = nil; store.askDelete(hand) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(c.danger)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("حذف التسجيل")
            }
        } else {
            Color.clear.frame(height: 44)
        }
    }
}

/// The thin line under a total: 3 points high, filling from the right edge toward 152, with a 1 × 9 tick at 100
/// drawn over it (the tick takes no room, so the box keeps the spec's 118 points).
struct Track: View {
    var fill: Double
    var fillColor: Color
    var base: Color
    var tick: Color?
    var widthFraction: CGFloat = 0.62

    var body: some View {
        GeometryReader { g in
            let w = g.size.width * widthFraction
            Capsule().fill(base)
                .frame(width: w, height: 3)
                .overlay(alignment: .trailing) {
                    Capsule().fill(fillColor).frame(width: max(0, w * fill), height: 3)
                }
                .overlay(alignment: .trailing) {
                    if let tick {
                        Rectangle().fill(tick).frame(width: 1, height: 9)
                            .offset(x: -w * CGFloat(BalootRules.hundred) / CGFloat(BalootRules.target))
                    }
                }
                .frame(maxWidth: .infinity)
        }
        .frame(height: 3)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}
