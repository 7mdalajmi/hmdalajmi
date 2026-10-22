import Foundation
import SwiftUI

/// A clean UserDefaults domain for one scenario (the stores and the settings all save there).
private var suiteCounter = 0
func freshDefaults(_ name: String) -> UserDefaults {
    suiteCounter += 1
    let suite = "sakka.harness.\(suiteCounter).\(name)"
    let d = UserDefaults(suiteName: suite)!
    d.removePersistentDomain(forName: suite)
    return d
}

/// A fresh app on a fresh clock: what launching the app does (AppModel builds the settings, the voice and both stores,
/// and each store restores itself from `defaults`).
func launch(_ defaults: UserDefaults) -> AppModel {
    VirtualClock.reset()
    AnimationLog.calls = []
    Motion.reduceMotionSwitch = false
    return AppModel(defaults: defaults)
}

/// The JSON the stores write, read back with the same keys (`Saved` is private in both stores).
struct SavedBaloot: Codable, Equatable {
    var hands: [BalootHand]
    var said: [Team]
}

struct SavedHand: Codable {
    var players: [HandPlayer]
    var rounds: [HandRound]
    var entry: [String: EntryCell]
    var uid: Int
    var started: Bool
}

func savedBaloot(_ d: UserDefaults) -> SavedBaloot? {
    guard let data = d.data(forKey: "baloot.v1") else { return nil }
    return try? JSONDecoder().decode(SavedBaloot.self, from: data)
}

func savedHand(_ d: UserDefaults) -> SavedHand? {
    guard let data = d.data(forKey: "hand.v1") else { return nil }
    return try? JSONDecoder().decode(SavedHand.self, from: data)
}

/// The win sequence's timers after the count ends at `end` (the boards' finale: 180, 220, 800, 1000; then the intro
/// 30 ms after the poster, and the voice 480 ms after the intro).
func winTimeline(owner: String, countEnd end: Int) -> [VirtualClock.Fired] {
    [
        .init(time: end, owner: owner, key: "countEnd"),
        .init(time: end + 180, owner: owner, key: "growBox"),
        .init(time: end + 220, owner: owner, key: "growFull"),
        .init(time: end + 800, owner: owner, key: "poster"),
        .init(time: end + 830, owner: owner, key: "intro"),
        .init(time: end + 1000, owner: owner, key: "growOff"),
        .init(time: end + 1310, owner: owner, key: "voice")
    ]
}

/// The timers a recorded hand or round sets, from the boards: fresh 30, ghost 40 and 600, press 140 (صكة only),
/// count 360 (+700), pulse 380 and 640.
func recordTimeline(owner: String, at t0: Int, press: Bool) -> [VirtualClock.Fired] {
    var list: [VirtualClock.Fired] = [
        .init(time: t0 + 30, owner: owner, key: "fresh"),
        .init(time: t0 + 40, owner: owner, key: "ghostOn"),
        .init(time: t0 + 360, owner: owner, key: "count"),
        .init(time: t0 + 380, owner: owner, key: "pulseOn"),
        .init(time: t0 + 600, owner: owner, key: "ghostOff"),
        .init(time: t0 + 640, owner: owner, key: "pulseOff"),
        .init(time: t0 + 1060, owner: owner, key: "countEnd")
    ]
    if press { list.insert(.init(time: t0 + 140, owner: owner, key: "press"), at: 2) }
    return list
}

/// The fired timers of `owner` with one of `keys`, between two times.
func fired(_ owner: String, from: Int, to: Int, keys: Set<String>) -> [VirtualClock.Fired] {
    VirtualClock.fired.filter { $0.owner == owner && $0.time >= from && $0.time <= to && keys.contains($0.key) }
}

/// «بعد لعبة وحدة» … «بعد 11 لعبة», as the Baloot board writes it (handsText).
func boardHandsText(_ n: Int) -> String {
    if n == 1 { return "بعد لعبة وحدة" }
    if n == 2 { return "بعد لعبتين" }
    if n >= 3 && n <= 10 { return "بعد \(n) لعبات" }
    return "بعد \(n) لعبة"
}

/// «بعد جولة وحدة» … as the Hand board writes it (roundsText).
func boardRoundsText(_ n: Int) -> String {
    if n == 1 { return "بعد جولة وحدة" }
    if n == 2 { return "بعد جولتين" }
    if n >= 3 && n <= 10 { return "بعد \(n) جولات" }
    return "بعد \(n) جولة"
}

/// The board's count: cubic ease-out from `a` to `b`, `elapsed` ms into a 700 ms count, rounded as JavaScript's
/// Math.round does (halves go up).
func boardCount(_ a: Int, _ b: Int, elapsed: Double, duration: Double = 700) -> Int {
    let k = min(1, max(0, elapsed / duration))
    let e = 1 - pow(1 - k, 3)
    return Int((Double(a) + Double(b - a) * e + 0.5).rounded(.down))
}

/// The home page's voice chip (HomeView.swift, SettingsRow, build 4): it toggles the setting, and turning it off
/// silences the line being said at once.
func tapVoiceChip(_ app: AppModel) {
    app.settings.toggleVoice()
    if !app.settings.voice { app.speaker.stop() }
}

/// What a store kept of a damaged save (build 4: "hand.v1.damaged", "baloot.v1.damaged").
func damagedCopy(_ d: UserDefaults, _ key: String) -> String? {
    d.data(forKey: key + ".damaged").map { String(decoding: $0, as: UTF8.self) }
}
