import SwiftUI

/// «مين يلعب؟»: the names (2 to 6 players), the scoring table, and «ابدأ». It slides up over the game,
/// and «إلغاء» leaves the game as it was.
struct HandSetupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var c
    @FocusState private var focused: Int?

    private var store: HandStore { app.hand }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { store.closeSetup() } label: {
                    Text("إلغاء")
                        .label(15, .semibold)
                        .foregroundStyle(c.inkMuted)
                        .padding(.horizontal, 4)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .frame(height: 44)
            Text("مين يلعب؟")
                .font(.amiri(30))
                .foregroundStyle(c.gold)
                .lineBox(38)
                .padding(.top, 2)
                .accessibilityAddTraits(.isHeader)
            // The names, the table and the notes scroll together; only «ابدأ» stays put. On a small phone with
            // the keyboard up there is room for the name being typed, and it is scrolled into view.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(store.setup.players.enumerated()), id: \.element.id) { i, _ in
                            nameRow(i)
                        }
                        if store.setup.players.count < HandRules.maxPlayers {
                            Button { store.addPlayer(); focused = store.setup.players.count - 1 } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus").font(.system(size: 16, weight: .regular))
                                    Text("إضافة لاعب").label(15, .bold)
                                }
                                .foregroundStyle(c.ink)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(c.line, lineWidth: 1))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        table
                        notes.padding(.top, 2)
                    }
                    .padding(.vertical, 2)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
                .onChange(of: focused) { _, i in
                    guard let i, store.setup.players.indices.contains(i) else { return }
                    let id = store.setup.players[i].id
                    // Near the top: still in view once the keyboard has shrunk the list, whichever comes first.
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.1)) }
                }
            }
            .padding(.top, 20)
            Button {
                focused = nil
                store.startGame()
            } label: {
                Text("ابدأ")
                    .label(17, .bold)
                    .foregroundStyle(c.ground)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.ink))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(c.ground.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
    }

    private func nameRow(_ i: Int) -> some View {
        let count = store.setup.players.count
        let name = Binding<String>(
            get: { store.setup.players.indices.contains(i) ? store.setup.players[i].name : "" },
            set: { store.setName(at: i, $0) })
        return HStack(spacing: 6) {
            // Amiri, as the names are everywhere else (the board's 22).
            TextField("", text: name, prompt: Text(verbatim: "لاعب \(i + 1)").font(.amiri(22)).foregroundStyle(c.inkMuted))
                .font(.amiri(22))
                .foregroundStyle(c.ink)
                .tint(c.ink)
                .focused($focused, equals: i)
                .submitLabel(i + 1 < count ? .next : .done)
                .onSubmit { focused = i + 1 < count ? i + 1 : nil }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.surface))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(c.lineStrong, lineWidth: 1))
                .accessibilityLabel(Text(verbatim: "اسم اللاعب \(i + 1)"))
            if count > HandRules.minPlayers {
                Button {
                    focused = nil
                    store.removePlayer(at: i)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(c.inkMuted)
                        .frame(width: 44, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "شيل " + HandRules.name(of: store.setup.players[i].id, in: store.setup.players)))
            }
        }
    }

    /// The scoring: what the finisher scores, what ما نزل scores, and what «من إيده» adds. A number is typed as it
    /// is, so the cards' multiplier left the table in build 6.
    private var table: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: 76, height: 1)
                ForEach(HandKind.finishes, id: \.self) { k in
                    Text(verbatim: k.name).label(13, .bold).foregroundStyle(c.ink).frame(maxWidth: .infinity)
                }
            }
            GridRow {
                rowLabel("اللي خلّص")
                ForEach(HandKind.finishes, id: \.self) { k in
                    Text(verbatim: Digits.signed(-30 * k.multiplier))
                        .font(.numerals(20, tabular: false))
                        .foregroundStyle(c.ink)
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity)
                }
            }
            GridRow {
                rowLabel("ما نزل")
                ForEach(HandKind.finishes, id: \.self) { k in
                    Text(verbatim: "\(100 * k.multiplier)")
                        .font(.numerals(20, tabular: false))
                        .foregroundStyle(c.inkMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            // «من إيده» on top of the player's score; nothing with خلّص.
            GridRow {
                rowLabel("من إيده")
                ForEach(HandKind.finishes, id: \.self) { k in
                    Text(verbatim: HandRules.fromHandPoints(multiplier: k.multiplier).map { "+\($0)" } ?? "")
                        .label(15, .semibold)
                        .foregroundStyle(c.inkMuted)
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(c.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("الحسبة")
    }

    private func rowLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .label(12, .semibold)
            .foregroundStyle(c.inkMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 76, alignment: .leading)
    }

    private var notes: some View {
        VStack(spacing: 0) {
            Text("الرقم ينكتب مثل ما هو، واللي رقمه أقل من «ما نزل» نزل، وتطلع له دائرة فوق اسمه")
            Text("كل لاعب له نزول واحد، ونزولين إذا صار جيكر")
            Text("معلن جيكر يزيد 100 على «ما نزل»، ومعلن جيكرين 200")
            Text("زات: اللعبة تخلص والفوز للي جابه")
            Text("7 جولات، وتصير 9 إذا نزل جيكر، والأقل يفوز")
        }
        .label(13, .medium)
        .foregroundStyle(c.inkMuted)
        .multilineTextAlignment(.center)
        .lineSpacing(2)
        .frame(maxWidth: .infinity)
    }
}
