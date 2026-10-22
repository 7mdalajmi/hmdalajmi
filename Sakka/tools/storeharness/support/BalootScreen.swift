import Foundation

/// Drives `BalootStore` the way Sakka/Baloot/BalootView.swift and BalootPoster.swift do: the same store calls,
/// in the same order, only when the control is on screen and enabled. The few lines of view logic that are not in
/// the store (the fields' bindings and focus) are copied here from build 4's BalootView.swift, with their line numbers.
/// Every tap returns whether it reached the store (false: the control was hidden, covered or disabled).
final class BalootScreen {
    enum Field: Hashable { case us, them, editUs, editThem }

    let app: AppModel
    var store: BalootStore { app.baloot }
    /// The keyboard focus (@FocusState in the view).
    private(set) var focus: Field?
    private var seenEditId: Int?
    private var seenHold = false
    private var seenPoster = false

    init(app: AppModel) {
        self.app = app
        seenEditId = app.baloot.editId
        seenHold = app.baloot.holdPoster
        seenPoster = app.baloot.posterVisible
    }

    /// The win screen is a full-screen layer over the page (BalootView.swift:37), and from build 4 the growing copy
    /// takes the taps that land on it (Components.swift, GrowingBox): full screen once it has grown.
    var covered: Bool { store.posterVisible || store.grow == .full }

    /// One turn of the run loop: 0 ms timers run, then the view's onChange handlers (BalootView.swift:46-51):
    /// editId moves the focus to «لنا» of the open row; the win sequence and the win screen close the keyboard.
    private func turn() {
        VirtualClock.advance(by: 0)
        if store.editId != seenEditId {
            seenEditId = store.editId
            focus = store.editId == nil ? nil : .editUs
        }
        if store.holdPoster != seenHold {
            seenHold = store.holdPoster
            if seenHold { focus = nil }
        }
        if store.posterVisible != seenPoster {
            seenPoster = store.posterVisible
            if seenPoster { focus = nil }
        }
    }

    // MARK: Top bar (lines 70-86)

    var newGameTitle: String { (store.confirmNew && !store.isWon) ? "متأكد؟" : "صكة جديدة" }

    @discardableResult
    func tapNewGame() -> Bool {
        guard store.topVisible, !covered else { return false }
        focus = nil
        store.newGame()
        turn()
        return true
    }

    @discardableResult
    func tapHome() -> Bool {
        guard (store.topVisible && !covered) || store.posterVisible else { return false }
        focus = nil
        store.leave()
        turn()
        return true
    }

    /// VoiceOver's escape (two-finger Z), RootView.swift:114 and leaveGame() at 201-212 in commit 131e012: the open game's
    /// store.leave(), the keyboard down (resignFirstResponder), then the page shrinks home. It works from anywhere in a
    /// game, also during the win sequence, where the chevron is hidden. (RootView is not compiled; this is its path.)
    @discardableResult
    func escape() -> Bool {
        store.leave()
        focus = nil
        turn()
        return true
    }

    // MARK: Fields (lines 207-252)

    /// The fields are disabled, and their tap does nothing, while the win sequence runs (lines 236 and 249).
    @discardableResult
    func tapField(_ team: Team) -> Bool {
        guard store.showEntry, !covered, !store.holdPoster else { return false }
        focus = team == .us ? .us : .them
        return true
    }

    /// Types one key into the focused field, as the TextField would: the binding's setter, then the onChange that cleans.
    @discardableResult
    func key(_ text: String) -> Bool {
        guard let f = focus else { return false }
        switch f {
        case .us, .them:
            guard store.showEntry, !covered, !store.holdPoster else { return false }
            setEntry(f == .us ? .us : .them, current(f) + text)
        case .editUs, .editThem:
            guard store.editId != nil, !covered else { return false }
            setEdit(f == .editUs ? .us : .them, current(f) + text)
        }
        turn()
        return true
    }

    /// Types a string one character at a time.
    func type(_ text: String) {
        for ch in text { key(String(ch)) }
    }

    /// Pastes a whole string into the focused field at once.
    @discardableResult
    func paste(_ text: String) -> Bool { key(text) }

    @discardableResult
    func deleteBackward() -> Bool {
        guard let f = focus, !covered else { return false }
        if (f == .us || f == .them) && store.holdPoster { return false }
        let now = current(f)
        guard !now.isEmpty else { return true }
        switch f {
        case .us, .them: setEntry(f == .us ? .us : .them, String(now.dropLast()))
        case .editUs, .editThem: setEdit(f == .editUs ? .us : .them, String(now.dropLast()))
        }
        turn()
        return true
    }

    private func current(_ f: Field) -> String {
        switch f {
        case .us: return store.inUs
        case .them: return store.inThem
        case .editUs: return store.edUs
        case .editThem: return store.edThem
        }
    }

    // BalootView.swift:213-222 (setter) and 226-230 (onChange), build 4: Digits.field, so a 0 in front is dropped
    // and only two real digits move on.
    private func setEntry(_ team: Team, _ value: String) {
        if team == .us {
            let before = Digits.field(store.inUs)
            store.inUs = value
            if Digits.field(value).count == 2 && before.count < 2 { focus = .them }
        } else {
            store.inThem = value
        }
        let new = team == .us ? store.inUs : store.inThem
        let cleaned = Digits.field(new)
        if cleaned != new { if team == .us { store.inUs = cleaned } else { store.inThem = cleaned } }
    }

    // BalootView.swift:382-391 (setter) and 394-398 (onChange), build 4.
    private func setEdit(_ team: Team, _ value: String) {
        if team == .us {
            let before = Digits.field(store.edUs)
            store.edUs = value
            if Digits.field(value).count == 2 && before.count < 2 { focus = .editThem }
        } else {
            store.edThem = value
        }
        let new = team == .us ? store.edUs : store.edThem
        let cleaned = Digits.field(new)
        if cleaned != new { if team == .us { store.edUs = cleaned } else { store.edThem = cleaned } }
    }

    /// Return on a hardware keyboard (lines 238-240 and 404). A disabled field has no keyboard.
    @discardableResult
    func pressReturn() -> Bool {
        guard let f = focus, !covered else { return false }
        if (f == .us || f == .them) && store.holdPoster { return false }
        switch f {
        case .us: focus = .them
        case .them:
            store.record()
            focus = nil
        case .editUs, .editThem:
            store.saveEdit()
        }
        turn()
        return true
    }

    /// «سجل النتيجة» (lines 271-295): disabled unless canRecord.
    @discardableResult
    func tapRecord() -> Bool {
        guard store.showEntry, !covered, store.canRecord else { return false }
        store.record()
        focus = nil
        turn()
        return true
    }

    /// Types a hand the way a player does: «لنا» then «لهم» (an empty field for 0), then «سجل النتيجة».
    /// A three-digit number in «لنا» needs a second tap: two digits move the cursor on to «لهم».
    @discardableResult
    func recordHand(_ us: Int, _ them: Int) -> Bool {
        // Whatever is left in a field is deleted first, as a player would.
        for team in [Team.us, .them] where !(team == .us ? store.inUs : store.inThem).isEmpty {
            guard tapField(team) else { break }
            for _ in 0..<8 where !(team == .us ? store.inUs : store.inThem).isEmpty { deleteBackward() }
        }
        if us > 0 {
            tapField(.us)
            let digits = "\(us)"
            type(String(digits.prefix(2)))
            if digits.count > 2 {
                tapField(.us)
                type(String(digits.dropFirst(2)))
            }
        }
        if them > 0 {
            if focus != .them { tapField(.them) }
            type("\(them)")
        }
        return tapRecord()
    }

    /// Taps the background, the boxes or scrolls the log: the keyboard goes away.
    func tapBackground() {
        focus = nil
    }

    // MARK: Log (lines 354-486)

    /// The rows on screen, newest first.
    var rows: [BalootHand] { store.hands.reversed() }

    func isEditing(_ hand: BalootHand) -> Bool { store.editId == hand.id }
    func isConfirming(_ hand: BalootHand) -> Bool { store.editId != hand.id && store.confirmId == hand.id }
    /// The pencil and the trash show on a row that is not being edited or confirmed, and only on the two newest.
    func hasIcons(_ hand: BalootHand) -> Bool { !isEditing(hand) && !isConfirming(hand) && store.canTouch(hand) }

    @discardableResult
    func tapPencil(_ hand: BalootHand) -> Bool {
        guard !covered, hasIcons(hand) else { return false }
        store.startEdit(hand)
        turn()
        return true
    }

    @discardableResult
    func tapTrash(_ hand: BalootHand) -> Bool {
        guard !covered, hasIcons(hand) else { return false }
        focus = nil
        store.askDelete(hand)
        turn()
        return true
    }

    @discardableResult
    func tapConfirmDelete(_ hand: BalootHand) -> Bool {
        guard !covered, isConfirming(hand) else { return false }
        store.delete(hand)
        turn()
        return true
    }

    /// «حفظ» on the row being edited: disabled unless canSave.
    @discardableResult
    func tapSave() -> Bool {
        guard !covered, store.editId != nil, store.canSave else { return false }
        store.saveEdit()
        turn()
        return true
    }

    @discardableResult
    func tapCancel() -> Bool {
        guard !covered, store.editId != nil else { return false }
        store.cancelEdit()
        turn()
        return true
    }

    /// Replaces the two edit fields the way a player does: select all and type, «لنا» then «لهم».
    func retype(us: Int, them: Int) {
        guard store.editId != nil else { return }
        clear(.editUs)
        let digits = "\(us)"
        type(String(digits.prefix(2)))
        if digits.count > 2 {
            focus = .editUs
            type(String(digits.dropFirst(2)))
        }
        clear(.editThem)
        type("\(them)")
    }

    // MARK: Win screen (BalootPoster.swift:49-82)

    @discardableResult
    func tapPosterNewGame() -> Bool {
        guard store.posterVisible else { return false }
        store.newGame()
        turn()
        return true
    }

    @discardableResult
    func tapPosterEdit() -> Bool {
        guard store.posterVisible else { return false }
        store.reviewLast()
        turn()
        return true
    }

    /// Empties a field with the delete key (at most a few presses, so a field that will not empty cannot hang the run).
    func clear(_ field: Field) {
        focus = field
        for _ in 0..<8 where !current(field).isEmpty { deleteBackward() }
    }

    /// Lets time pass.
    func wait(_ milliseconds: Int) {
        VirtualClock.advance(by: milliseconds)
        turn()
    }
}
