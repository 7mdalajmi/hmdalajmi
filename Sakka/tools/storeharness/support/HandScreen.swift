import Foundation

/// One cell of a round as the boards write it: ["out", 35, "nd", "nd"]. A number there is the cards left, as the
/// boards had them; from build 6 the player types what they come to (× the round), so `enter` types that.
/// `.typed` is a number typed as it is, and `.zat` the finish that ends the game.
enum Cell: Equatable, CustomStringConvertible {
    case out, hand, joker, joker2, zat, nd
    case n(Int)
    case typed(Int)

    var kind: HandKind? {
        switch self {
        case .out: return .out
        case .hand: return .hand
        case .joker: return .joker
        case .joker2: return .joker2
        case .zat: return .zat
        default: return nil
        }
    }

    var description: String {
        switch self {
        case .out: return "out"
        case .hand: return "hand"
        case .joker: return "joker"
        case .joker2: return "joker2"
        case .zat: return "zat"
        case .nd: return "nd"
        case .n(let v): return "\(v)"
        case .typed(let v): return "=\(v)"
        }
    }
}

/// Drives `HandStore` the way Sakka/Hand/HandView.swift, HandKeypad.swift, HandSetupView.swift, HandPoster.swift and
/// the first visit in Home/RootView.swift do: the same store calls, only when the control is on screen and enabled.
/// Every tap returns whether it reached the store (false: hidden, covered or disabled).
final class HandScreen {
    let app: AppModel
    var store: HandStore { app.hand }

    init(app: AppModel) {
        self.app = app
    }

    private func turn() {
        VirtualClock.advance(by: 0)
    }

    /// «مين يلعب؟» is a full-screen cover (HandView.swift:77), and the win screen a layer over the page (line 68).
    var covered: Bool { store.setupOpen || store.posterVisible }

    /// The page has finished opening from the home card: the first visit opens «مين يلعب؟» (RootView.swift:151-153).
    func open() {
        if !store.started { store.openSetup() }
        turn()
    }

    func id(_ index: Int) -> String { store.players[index].id }

    // MARK: Lane (HandView.swift:347-427)

    @discardableResult
    func tapField(_ index: Int) -> Bool {
        guard !covered else { return false }
        store.focusField(id(index))
        turn()
        return true
    }

    /// A tap on the background, the header, the status line or a row that cannot be touched (lines 57-59 and others).
    func tapBackground() {
        guard !covered else { return }
        store.hidePad()
        turn()
    }

    // MARK: Keypad (HandKeypad.swift)

    /// Whether a key can be pressed: the pad is up (hit-testing follows padUp) and the key is enabled
    /// (finish keys: not locked, زات only in a new round or the newest one edited; others: not locked, «سجّل» only
    /// when the round is ready, «من إيده» once the finisher is هند, جيكر or جيكرين and not on the finisher's field,
    /// «معلن» and ± not on the finisher's field; HandKeypad.ladder and keyButton).
    func canPress(_ key: PadKey) -> Bool {
        guard !covered, store.padUp else { return false }
        if store.locked { return false }
        if key == .finish(.zat) && !store.zatOpen { return false }
        if key == .record && !store.status.ready { return false }
        let focused = store.entry[store.focus]
        let onFinisher = focused?.kind?.isFinish == true
        // «من إيده» (HandKeypad.fromHandOpen): on with هند, جيكر or جيكرين, or to take a mark off; never on the
        // finisher or an old «حر» field.
        let marked = focused?.fromHand == true
        if key == .fromHand && ((store.status.multiplier < 2 && !marked) || onFinisher || focused?.kind == .free) { return false }
        if (key == .declared || key == .sign) && onFinisher { return false }
        // A round of زات: the other fields take nothing but a finish key (HandKeypad.zatElsewhere).
        if HandRules.zatElsewhere(store.entry, focus: store.focus) {
            if case .finish = key { return true }
            if key != .record { return false }
        }
        return true
    }

    @discardableResult
    func press(_ key: PadKey) -> Bool {
        guard canPress(key) else { return false }
        store.press(key)
        turn()
        return true
    }

    func digits(_ text: String) {
        for ch in text { press(.digit(ch)) }
    }

    /// The label on the tall key: «حفظ» while editing, else «سجّل» (HandKeypad.swift:137).
    var recordLabel: String { store.editId != nil ? "حفظ" : "سجّل" }

    /// Types a round as a player does: the finisher's field and its key (the rest go on ما نزل by themselves),
    /// then each number in its own field, a tap on it and its digits (they stay there, from build 6), then ما نزل
    /// on any field that should be on it and is not. Cards (`.n`) are typed as what they come to, × the round.
    func enter(_ cells: [Cell]) {
        let m = cells.compactMap { $0.kind?.multiplier }.max() ?? 1
        if let f = cells.firstIndex(where: { $0.kind != nil }), let kind = cells[f].kind {
            tapField(f)
            press(.finish(kind))
        }
        for (i, c) in cells.enumerated() {
            let value: Int
            switch c {
            case .n(let v): value = v * m
            case .typed(let v): value = v
            default: continue
            }
            tapField(i)
            // Clear what is there first, as a player would with the erase key.
            var guardCount = 0
            while let x = store.entry[id(i)], x.kind == .cards || x.kind == .exact || x.kind == .free,
                  !x.digits.isEmpty || x.negative, guardCount < 6 {
                press(.erase)
                guardCount += 1
            }
            if value < 0 { press(.sign) }
            digits("\(abs(value))")
        }
        for (i, c) in cells.enumerated() where c == .nd {
            if store.entry[id(i)]?.kind != .notDown {
                tapField(i)
                press(.notDown)
            }
        }
    }

    /// Types and records a round. Returns true when the round went in.
    @discardableResult
    func record(_ cells: [Cell]) -> Bool {
        let before = store.rounds.count
        enter(cells)
        press(.record)
        return store.rounds.count == before + 1
    }

    // MARK: Top bar (HandView.swift:107-122)

    @discardableResult
    func tapNewGame() -> Bool {
        guard store.topVisible, !covered else { return false }
        store.openSetup()
        turn()
        return true
    }

    @discardableResult
    func tapHome() -> Bool {
        guard (store.topVisible && !covered) || (store.posterVisible && !store.setupOpen) else { return false }
        store.leave()
        turn()
        return true
    }

    /// VoiceOver's escape (two-finger Z), RootView.swift:114 and leaveGame() at 201-212 in commit 131e012: the open game's
    /// store.leave(), the keyboard down, then the page shrinks home. The keypad is the store's own (leave puts it away).
    @discardableResult
    func escape() -> Bool {
        store.leave()
        turn()
        return true
    }

    // MARK: Status (HandView.swift:263-328)

    /// The الفرق line under the round line (gapLine): one number per player, in seat order, as the view writes
    /// them from the totals on screen; nil when the line is not drawn at all — it is only there in آخر جولة and
    /// the جولة فاصلة, and the «تعديل الجولة N» row takes the status line's place while a round is edited.
    /// A banner on top of the status line hides it for its 3.2 s (`bannerOn`) without taking it away.
    var gapTexts: [String]? {
        guard store.showsGap, store.editId == nil else { return nil }
        let g = store.gaps(store.shown(at: Date()))
        return store.players.map { Digits.gap(g[$0.id] ?? 0) }
    }

    // MARK: Log (HandView.swift:447-561)

    /// The rows on screen, newest first.
    var rows: [HandRound] { store.rounds.reversed() }

    func isSelected(_ r: HandRound) -> Bool { store.selected == r.id && store.editId == nil }

    /// A tap on a row: the two newest open (tapRow), any other row is background (hidePad).
    @discardableResult
    func tapRow(_ r: HandRound) -> Bool {
        guard !covered else { return false }
        if store.canTouch(r) {
            store.tapRow(r)
            turn()
            return true
        }
        store.hidePad()
        turn()
        return false
    }

    @discardableResult
    func tapEdit(_ r: HandRound) -> Bool {
        guard !covered, isSelected(r) else { return false }
        store.startEdit(r)
        turn()
        return true
    }

    @discardableResult
    func tapDelete(_ r: HandRound) -> Bool {
        guard !covered, isSelected(r), store.confirmId != r.id else { return false }
        store.askDelete(r)
        turn()
        return true
    }

    @discardableResult
    func tapConfirmDelete(_ r: HandRound) -> Bool {
        guard !covered, isSelected(r), store.confirmId == r.id else { return false }
        store.delete(r)
        turn()
        return true
    }

    /// «إلغاء» next to «تعديل الجولة N» (HandView.swift:249-263).
    @discardableResult
    func tapCancelEdit() -> Bool {
        guard !covered, store.editId != nil else { return false }
        store.cancelEdit()
        turn()
        return true
    }

    // MARK: Win screen (HandPoster.swift:44-77)

    @discardableResult
    func tapPosterNewGame() -> Bool {
        guard store.posterVisible, !store.setupOpen else { return false }
        store.openSetup()
        turn()
        return true
    }

    @discardableResult
    func tapPosterEdit() -> Bool {
        guard store.posterVisible, !store.setupOpen else { return false }
        store.reviewLast()
        turn()
        return true
    }

    // MARK: «مين يلعب؟» (HandSetupView.swift)

    @discardableResult
    func setupCancel() -> Bool {
        guard store.setupOpen else { return false }
        store.closeSetup()
        turn()
        return true
    }

    @discardableResult
    func setupName(_ index: Int, _ text: String) -> Bool {
        guard store.setupOpen, store.setup.players.indices.contains(index) else { return false }
        store.setName(at: index, text)
        return true
    }

    /// «إضافة لاعب» shows below six players (line 38).
    @discardableResult
    func setupAdd() -> Bool {
        guard store.setupOpen, store.setup.players.count < HandRules.maxPlayers else { return false }
        store.addPlayer()
        return true
    }

    /// The ✕ shows above two players (line 99).
    @discardableResult
    func setupRemove(_ index: Int) -> Bool {
        guard store.setupOpen, store.setup.players.count > HandRules.minPlayers else { return false }
        store.removePlayer(at: index)
        return true
    }

    @discardableResult
    func setupStart() -> Bool {
        guard store.setupOpen else { return false }
        store.startGame()
        turn()
        return true
    }

    /// Opens «مين يلعب؟» from the top bar, sets the names and starts.
    func newGame(_ names: [String]) {
        if !store.setupOpen { tapNewGame() }
        for _ in 0..<6 where store.setup.players.count < names.count { setupAdd() }
        for _ in 0..<6 where store.setup.players.count > names.count { setupRemove(store.setup.players.count - 1) }
        for (i, n) in names.enumerated() { setupName(i, n) }
        setupStart()
    }

    func wait(_ milliseconds: Int) {
        VirtualClock.advance(by: milliseconds)
        turn()
    }

    /// The totals in seat order.
    var totals: [Int] { store.players.map { store.totals[$0.id] ?? 0 } }
    var downs: [Int] { store.players.map { store.downs[$0.id] ?? 0 } }
    var names: [String] { store.players.map { store.name($0.id) } }
}

/// The board's rounds (Hand.dc.html, seedConfig): everyone goes down once before the جيكر in round 5 and once after.
let boardRounds: [[Cell]] = [
    [.out, .n(35), .nd, .nd],
    [.nd, .nd, .out, .n(22)],
    [.n(15), .hand, .nd, .nd],
    [.nd, .nd, .n(31), .out],
    [.joker, .nd, .n(12), .nd],
    [.nd, .out, .nd, .n(30)],
    [.n(27), .nd, .out, .nd],
    [.out, .n(33), .nd, .nd],
    [.nd, .out, .nd, .nd]
]
let boardNames = ["حمد", "أنور", "فهد", "سالم"]
