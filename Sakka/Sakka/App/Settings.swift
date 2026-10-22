import Foundation
import Observation

/// The app's shared settings, on the home page: the theme, the voice and haptics. They apply to both games.
@Observable
final class AppSettings {
    private(set) var theme: ThemeChoice
    private(set) var voice: Bool
    private(set) var haptics: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = ThemeChoice(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .auto
        voice = defaults.object(forKey: Keys.voice) as? Bool ?? true
        haptics = defaults.object(forKey: Keys.haptics) as? Bool ?? true
    }

    func cycleTheme() {
        theme = theme.next
        defaults.set(theme.rawValue, forKey: Keys.theme)
    }

    func toggleVoice() {
        voice.toggle()
        defaults.set(voice, forKey: Keys.voice)
    }

    func toggleHaptics() {
        haptics.toggle()
        defaults.set(haptics, forKey: Keys.haptics)
    }

    private enum Keys {
        static let theme = "settings.theme"
        static let voice = "settings.voice"
        static let haptics = "settings.haptics"
    }
}
