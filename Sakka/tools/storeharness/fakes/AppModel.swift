// Replaces Sakka/App/SakkaApp.swift for the Linux harness. The real file holds `AppModel` (plain Observation)
// and `SakkaApp: App` (a SwiftUI scene with RootView, which needs the whole UI). This keeps `AppModel` exactly as
// it is there (the settings, one Speaker whose isOn reads settings.voice, and the two stores built on the same
// UserDefaults), and drops the App struct.
import SwiftUI
import Observation

@Observable
final class AppModel {
    let settings: AppSettings
    let speaker: Speaker
    let hand: HandStore
    let baloot: BalootStore

    init(defaults: UserDefaults = .standard) {
        let settings = AppSettings(defaults: defaults)
        let speaker = Speaker(isOn: { settings.voice })
        self.settings = settings
        self.speaker = speaker
        Schedule.nextOwner = "hand"
        hand = HandStore(speaker: speaker, defaults: defaults)
        Schedule.nextOwner = "baloot"
        baloot = BalootStore(speaker: speaker, defaults: defaults)
        Schedule.nextOwner = "store"
    }
}
