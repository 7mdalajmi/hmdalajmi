import SwiftUI
import Observation
import os

/// Settings problems (diagnostics only, never shown to the user).
private let settingsLog = Logger(subsystem: "com.hmdalajmi.noor", category: "Settings")

// MARK: - Settings

/// The background around the photo in the editor (Settings → Canvas Surround).
enum CanvasSurround: String, Codable, CaseIterable, Identifiable, Sendable {
    case dark       // #121212, the default
    case black      // #000000, OLED
    case grey       // #777777, assessment mid-grey (about L* 50)

    var id: String { rawValue }
}

/// App-wide preferences, stored as JSON in `UserDefaults` under `"noor.settings"`.
struct AppSettings: Codable, Equatable, Sendable {
    var surround: CanvasSurround = .dark
    var haptics = true
    /// Starting point of the export sheet.
    var defaultExport = ExportOptions()

    enum CodingKeys: String, CodingKey {
        case surround, haptics, defaultExport
    }
}

extension AppSettings {
    /// Tolerant: a missing or unknown value falls back to its default, so a settings blob written by
    /// another version of Noor never resets everything. Declared in an extension so the memberwise
    /// and `init()` initializers stay available.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        surround = (try? c.decodeIfPresent(CanvasSurround.self, forKey: .surround)) ?? surround
        haptics = (try? c.decodeIfPresent(Bool.self, forKey: .haptics)) ?? haptics
        defaultExport = (try? c.decodeIfPresent(ExportOptions.self, forKey: .defaultExport)) ?? defaultExport
    }
}

// MARK: - App model

/// The app-wide objects every screen reads from the environment
/// (`@Environment(AppModel.self) private var app`): the photo library, the presets and the settings.
@MainActor
@Observable
final class AppModel {
    let library: LibraryStore
    let presets: PresetLibrary

    /// Saved to `UserDefaults` whenever it changes.
    var settings: AppSettings {
        didSet {
            if settings != oldValue { saveSettings() }
        }
    }

    /// `UserDefaults` key of the settings JSON. Not user-facing.
    static let settingsKey = "noor.settings"

    init() {
        library = LibraryStore()
        presets = PresetLibrary()
        settings = AppModel.loadSettings()
    }

    // MARK: Persistence

    private static func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey) else { return AppSettings() }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            settingsLog.error("Unreadable settings, using defaults: \(error.localizedDescription, privacy: .public)")
            return AppSettings()
        }
    }

    private func saveSettings() {
        do {
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: AppModel.settingsKey)
        } catch {
            settingsLog.error("Could not save settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
