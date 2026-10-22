import SwiftUI
import Observation

/// Everything the screens share: the settings, the voice, and the two games.
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
        hand = HandStore(speaker: speaker, defaults: defaults)
        baloot = BalootStore(speaker: speaker, defaults: defaults)
    }
}

/// صكة: الهند and البلوت in one app. It opens on «وش نلعب؟».
@main
struct SakkaApp: App {
    @State private var app = AppModel()

    init() {
        BundledFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(\.locale, Locale(identifier: "ar@numbers=latn"))
        }
    }
}
