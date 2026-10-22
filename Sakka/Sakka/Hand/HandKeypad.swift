import SwiftUI

/// The keypad of الهند. Top row: how the round was finished, خلّص هند جيكر جيكرين with the finisher's score, then
/// زات, which ends the game. Below: the digits on the left in the usual order with ± and ⌫, and on the right
/// «ما نزل», «من إيده», «معلن» and «سجّل» at the bottom, under the thumb. A number stays in its field as typed:
/// the next field is a tap away.
/// It slides up for a tapped field and down after «سجّل» or a tap anywhere else.
struct HandKeypad: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var c
    @Environment(\.screenInsets) private var insets
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: HandStore { app.hand }

    var body: some View {
        let up = store.padUp
        VStack(spacing: 8) {
            ladder
            pad
        }
        .padding(.top, 10)
        .padding(.horizontal, 20)
        // The last row sits just above the home indicator, not a gap's height over it.
        .padding(.bottom, HandView.padBottom(insets))
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .background(c.ground)
        .overlay(alignment: .top) { Rectangle().fill(c.line).frame(height: 1) }
        .offset(y: up ? 0 : HandView.padContent + HandView.padBottom(insets) + 2)
        .animation(reduceMotion ? nil : (up ? .settle(0.34) : .sinking(0.26)), value: up)
        .allowsHitTesting(up)
        .accessibilityHidden(!up)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("لوحة الأرقام")
    }

    private var focused: EntryCell? { store.entry[store.focus] }
    private var focusKind: HandKind? { focused?.kind }
    private var onFinisher: Bool { focusKind?.isFinish == true }

    private var ladder: some View {
        HStack(spacing: 8) {
            ForEach(HandKind.ladder, id: \.self) { kind in
                let active = focusKind == kind
                let off = store.locked || (kind == .zat && !store.zatOpen)
                Button { store.press(.finish(kind)) } label: {
                    VStack(spacing: 4) {
                        Text(verbatim: kind.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(c.ink)
                        if kind == .zat {
                            Text("فوز")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(c.gold)
                        } else {
                            Text(verbatim: Digits.signed(-30 * kind.multiplier))
                                .font(.numerals(15, tabular: false))
                                .foregroundStyle(c.inkMuted)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c.surface))
                    .overlay(keyBorder(active: active))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScale(scale: 0.96, duration: 0.12))
                .disabled(off)
                .opacity(off ? 0.35 : 1)
                .accessibilityLabel(Text(verbatim: kind == .zat ? "زات، اللعبة تخلص والفوز له" : kind.name + "، سالب \(30 * kind.multiplier)"))
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .frame(height: 48)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("مين خلّص وكيف")
    }

    private var pad: some View {
        let columns: [[PadKey]] = [
            [.digit("1"), .digit("4"), .digit("7"), .sign],
            [.digit("2"), .digit("5"), .digit("8"), .digit("0")],
            [.digit("3"), .digit("6"), .digit("9"), .erase]
        ]
        return HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { col in
                VStack(spacing: 8) {
                    ForEach(columns[col], id: \.self) { key in
                        keyButton(key).frame(height: HandView.keyHeight)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: 8) {
                ForEach([PadKey.notDown, .fromHand, .declared, .record], id: \.self) { key in
                    keyButton(key).frame(height: HandView.keyHeight)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    /// «من إيده» goes on once the finisher is هند, جيكر or جيكرين, never on the finisher's field or an old «حر»,
    /// and a field that has it can always take it off.
    private var fromHandOpen: Bool {
        (store.status.multiplier >= 2 || focusFromHand) && !onFinisher && focusKind != .free
    }

    /// A round of زات, and the focus on another field: it takes nothing but a finish key, which moves the finish.
    private var zatElsewhere: Bool { HandRules.zatElsewhere(store.entry, focus: store.focus) }

    private var focusFromHand: Bool { focused?.fromHand == true }
    private var focusDeclared: Int { focused?.declared ?? 0 }
    private var focusNegative: Bool { (focusKind == .exact || focusKind == .free) && focused?.negative == true }

    private func keyButton(_ key: PadKey) -> some View {
        let isRecord = key == .record
        let active = (key == .notDown && focusKind == .notDown) || (key == .fromHand && focusFromHand)
            || (key == .declared && focusDeclared > 0) || (key == .sign && focusNegative)
        let off = store.locked || (isRecord && !store.status.ready) || (key == .fromHand && !fromHandOpen)
            || ((key == .declared || key == .sign) && onFinisher) || (zatElsewhere && !isRecord)
        return Button { store.press(key) } label: {
            keyFace(key)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isRecord ? c.ink : c.surface))
                .overlay {
                    if !isRecord { keyBorder(active: active) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.96, duration: 0.12))
        .disabled(off)
        .opacity(off ? 0.35 : 1)
        .animation(.easeInOut(duration: 0.2), value: off)
        .accessibilityLabel(Text(verbatim: accessibilityName(key)))
        .accessibilityValue(Text(verbatim: accessibilityState(key)))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// The sign of the focused number for ±, and which «معلن» the field has.
    private func accessibilityState(_ key: PadKey) -> String {
        switch key {
        case .sign:
            guard focusKind == .exact || focusKind == .free else { return "" }
            return focusNegative ? "سالب" : "موجب"
        case .declared:
            return focusDeclared > 0 ? HandRules.declaredName(focusDeclared) : ""
        default:
            return ""
        }
    }

    @ViewBuilder
    private func keyFace(_ key: PadKey) -> some View {
        switch key {
        case .digit(let d):
            Text(verbatim: String(d))
                .font(.numerals(28, tabular: false))
                .foregroundStyle(c.ink)
        case .erase:
            Image(systemName: "delete.left")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(c.ink)
        case .sign:
            Text(verbatim: "±")
                .font(.numerals(26, tabular: false))
                .foregroundStyle(c.ink)
        case .notDown:
            VStack(spacing: 3) {
                Text("ما نزل")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.ink)
                Text(verbatim: "\(100 * store.status.multiplier)")
                    .font(.numerals(15, tabular: false))
                    .foregroundStyle(c.inkMuted)
            }
        case .fromHand:
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 10, weight: .regular))
                    Text("من إيده")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(c.ink)
                .environment(\.layoutDirection, .rightToLeft)
                Text(verbatim: HandRules.fromHandPoints(multiplier: store.status.multiplier).map { "\($0)" } ?? " ")
                    .font(.numerals(15, tabular: false))
                    .foregroundStyle(c.inkMuted)
            }
        case .declared:
            // «معلن», then «معلن جيكر» 100 and «معلن جيكرين» 200 as the key is pressed again.
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 10, weight: .regular))
                    Text(verbatim: focusDeclared > 0 ? HandRules.declaredName(focusDeclared) : "معلن")
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(c.ink)
                .environment(\.layoutDirection, .rightToLeft)
                Text(verbatim: "\(HandRules.declaredPoints(max(1, focusDeclared)))")
                    .font(.numerals(15, tabular: false))
                    .foregroundStyle(c.inkMuted)
            }
            .padding(.horizontal, 4)
        case .record:
            Text(store.editId != nil ? "حفظ" : "سجّل")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(c.ground)
        case .finish(let kind):
            Text(verbatim: kind.name)
        }
    }

    private func keyBorder(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(active ? c.ink : c.line, lineWidth: active ? 2 : 1)
            .animation(.easeInOut(duration: 0.2), value: active)
    }

    private func accessibilityName(_ key: PadKey) -> String {
        switch key {
        case .digit(let d): return String(d)
        case .erase: return "مسح"
        case .sign: return "سالب أو موجب"
        case .notDown: return "ما نزل"
        case .fromHand:
            return "من إيده" + (HandRules.fromHandPoints(multiplier: store.status.multiplier).map { "، \($0)" } ?? "")
        case .declared: return "معلن، جيكر 100 ثم جيكرين 200"
        case .record: return store.editId != nil ? "حفظ التعديل" : "سجّل الجولة"
        case .finish(let kind): return kind.name
        }
    }
}
