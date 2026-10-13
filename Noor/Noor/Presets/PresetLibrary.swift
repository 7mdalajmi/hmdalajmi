import Foundation
import Observation
import os

/// Preset loading / import problems (diagnostics only, never shown to the user).
private let presetLog = Logger(subsystem: "com.hmdalajmi.noor", category: "Presets")

// MARK: - Import report

/// Outcome of `PresetLibrary.importFiles(_:)`, for the import summary.
struct PresetImportReport: Sendable {
    /// Presets added or replaced, with their final ids.
    var imported: [Preset] = []
    /// User-facing notes per imported preset (only presets that have notes).
    var warnings: [UUID: [String]] = [:]
    /// Human-readable "file: reason" lines for everything that could not be imported.
    var failures: [String] = []
}

/// Errors from changing the library.
enum PresetLibraryError: LocalizedError {
    case builtInIsReadOnly

    var errorDescription: String? {
        switch self {
        case .builtInIsReadOnly:
            return String(localized: "Built-in presets can't be changed.")
        }
    }
}

// MARK: - Library

/// All presets: the built-in pack (read-only, from the app bundle) followed by the user's own and
/// imported presets (one `<id>.noorpreset` file each in Application Support/Presets). Favourites and
/// the user order live in `presets-index.json` next to them.
///
/// File IO runs on a private serial queue (writes stay ordered); the initial load of user presets
/// happens there too, right after the built-ins are shown.
@MainActor
@Observable
final class PresetLibrary {
    /// Built-ins (pack order), then user / imported presets (newest last).
    private(set) var presets: [Preset] = []
    private(set) var favorites: Set<UUID> = []

    @ObservationIgnored private var builtIns: [Preset] = []
    @ObservationIgnored private var builtInIDs: Set<UUID> = []
    @ObservationIgnored private var userPresets: [Preset] = []
    @ObservationIgnored private var isLoaded = false
    /// Favourite toggles made before the user index finished loading (applied on top of it).
    @ObservationIgnored private var pendingFavoriteEdits: [UUID: Bool] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    private let disk: PresetDiskStore
    private let ioQueue = DispatchQueue(label: "com.hmdalajmi.noor.presets.io", qos: .userInitiated)

    /// Built-ins from `BuiltInPresets.json` in the main bundle; user presets from Application Support.
    convenience init() {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("Presets", isDirectory: true)
        self.init(directory: directory, bundle: .main)
    }

    /// Designated initializer (tests can point it at a temporary folder / test bundle).
    init(directory: URL, bundle: Bundle) {
        disk = PresetDiskStore(directory: directory)
        let packed = PresetLibrary.loadBuiltIns(from: bundle)
        builtIns = packed
        builtInIDs = Set(packed.map(\.id))
        presets = packed
        startLoadingUserPresets()
    }

    // MARK: Queries

    func preset(id: UUID) -> Preset? {
        presets.first { $0.id == id }
    }

    func isFavorite(_ id: UUID) -> Bool {
        favorites.contains(id)
    }

    /// True for the read-only presets that ship with the app.
    func isBuiltIn(_ id: UUID) -> Bool {
        builtInIDs.contains(id)
    }

    // MARK: Editing

    /// Adds (or replaces, same id) a user preset and writes `<id>.noorpreset`.
    func add(_ preset: Preset) throws {
        guard !builtInIDs.contains(preset.id) else { throw PresetLibraryError.builtInIsReadOnly }
        var stored = preset
        if stored.source == .builtIn { stored.source = .user }
        let disk = self.disk
        let toWrite = stored
        try ioQueue.sync { try disk.write(toWrite) }
        if let index = userPresets.firstIndex(where: { $0.id == stored.id }) {
            userPresets[index] = stored
        } else {
            userPresets.append(stored)
        }
        publish()
        persistIndex()
    }

    /// Deletes a user / imported preset (built-ins are ignored).
    func delete(_ id: UUID) {
        guard let index = userPresets.firstIndex(where: { $0.id == id }) else { return }
        userPresets.remove(at: index)
        favorites.remove(id)
        pendingFavoriteEdits[id] = nil
        publish()
        let disk = self.disk
        ioQueue.async { disk.remove(id) }
        persistIndex()
    }

    /// Renames a user / imported preset. Empty names are ignored.
    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = userPresets.firstIndex(where: { $0.id == id }) else { return }
        let newName = String(trimmed.prefix(Preset.maxNameLength))
        guard userPresets[index].name != newName || userPresets[index].localizedNames != nil else { return }
        userPresets[index].name = newName
        userPresets[index].localizedNames = nil      // other-language names would now be stale
        publish()
        let disk = self.disk
        let renamed = userPresets[index]
        ioQueue.async {
            do {
                try disk.write(renamed)
            } catch {
                presetLog.error("Rename write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func toggleFavorite(_ id: UUID) {
        let makeFavorite = !favorites.contains(id)
        if isLoaded {
            guard presets.contains(where: { $0.id == id }) else { return }
        } else {
            pendingFavoriteEdits[id] = makeFavorite
        }
        if makeFavorite {
            favorites.insert(id)
        } else {
            favorites.remove(id)
        }
        persistIndex()
    }

    // MARK: Import

    /// Imports `.xmp`, `.noorpreset` / `.json`, DNG presets (XMP packet inside a photo) and folders
    /// (two levels deep). Security-scoped URLs are opened here. Same id + same name replaces the
    /// existing preset; same id + different name is imported as a new preset (new id).
    func importFiles(_ urls: [URL]) async -> PresetImportReport {
        if let loadTask { await loadTask.value }
        let outcome = await Task.detached(priority: .userInitiated) {
            PresetFileCollector.collect(urls)
        }.value

        var report = PresetImportReport()
        report.failures = outcome.failures

        // Stage into memory (main actor, no suspension) so concurrent imports see each other.
        var staged: [StagedImport] = []
        var stagedIndex: [UUID: Int] = [:]
        for item in outcome.items {
            var preset = item.preset
            if builtInIDs.contains(preset.id) {
                if builtIns.contains(where: { $0.id == preset.id && $0.name == preset.name }) {
                    report.failures.append(String(localized: "“\(preset.displayName())” is already in your presets."))
                    continue
                }
                preset.id = UUID()
            }
            if preset.source == .builtIn { preset.source = .user }

            if let index = userPresets.firstIndex(where: { $0.id == preset.id }) {
                if userPresets[index].name == preset.name {
                    let previous = userPresets[index]
                    userPresets[index] = preset
                    if let s = stagedIndex[preset.id] {
                        staged[s].preset = preset          // same file twice in one import: last wins
                        staged[s].warnings = item.warnings
                    } else {
                        stagedIndex[preset.id] = staged.count
                        staged.append(StagedImport(preset: preset, previous: previous, warnings: item.warnings))
                    }
                    continue
                }
                preset.id = UUID()
            }
            userPresets.append(preset)
            stagedIndex[preset.id] = staged.count
            staged.append(StagedImport(preset: preset, previous: nil, warnings: item.warnings))
        }
        guard !staged.isEmpty else { return report }
        publish()

        let disk = self.disk
        let toWrite = staged.map(\.preset)
        let writeFailures = await PresetLibrary.runIO(on: ioQueue) { disk.write(toWrite) }

        for entry in staged.reversed() where writeFailures[entry.preset.id] != nil {
            rollBack(entry)
        }
        for entry in staged {
            if let reason = writeFailures[entry.preset.id] {
                report.failures.append(String(localized: "\(entry.preset.name): \(reason)"))
            } else {
                report.imported.append(entry.preset)
                if !entry.warnings.isEmpty { report.warnings[entry.preset.id] = entry.warnings }
            }
        }
        publish()
        persistIndex()
        presetLog.info("Imported \(report.imported.count) preset(s), \(report.failures.count) failure(s)")
        return report
    }

    // MARK: Sharing

    /// Writes the preset to a fresh temporary `.noorpreset` file (named after the preset) for the
    /// share sheet / file exporter.
    func shareURL(for preset: Preset) throws -> URL {
        let folder = PresetDiskStore.shareRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(Preset.fileSafeName(preset.displayName()))
            .appendingPathExtension(PresetCodec.fileExtension)
        try PresetCodec.encode(preset).write(to: url, options: .atomic)
        return url
    }

    // MARK: Private

    /// One preset staged by an import, with what it replaced (for rollback if the write fails).
    private struct StagedImport {
        var preset: Preset
        var previous: Preset?
        var warnings: [String]
    }

    private func rollBack(_ entry: StagedImport) {
        guard let index = userPresets.firstIndex(where: { $0.id == entry.preset.id }) else { return }
        if let previous = entry.previous {
            userPresets[index] = previous
        } else {
            userPresets.remove(at: index)
        }
    }

    private func publish() {
        presets = builtIns + userPresets
    }

    /// Writes order + favourites (only once the on-disk index has been read, so nothing is lost).
    private func persistIndex() {
        guard isLoaded else { return }
        let index = PresetIndexFile(order: userPresets.map(\.id),
                                    favorites: favorites.sorted { $0.uuidString < $1.uuidString })
        let disk = self.disk
        ioQueue.async { disk.writeIndex(index) }
    }

    private func startLoadingUserPresets() {
        let disk = self.disk
        let queue = ioQueue
        let launch = Date()
        loadTask = Task { [weak self] in
            let loaded = await PresetLibrary.runIO(on: queue) { () -> LoadedUserPresets in
                disk.removeSharedFiles(createdBefore: launch)
                return disk.loadAll()
            }
            self?.finishLoading(loaded)
        }
    }

    private func finishLoading(_ loaded: LoadedUserPresets) {
        var merged = loaded.presets.filter { !builtInIDs.contains($0.id) }
        let loadedIDs = Set(merged.map(\.id))
        merged.append(contentsOf: userPresets.filter { !loadedIDs.contains($0.id) })   // added meanwhile
        userPresets = merged

        let known = builtInIDs.union(merged.map(\.id))
        var favs = loaded.favorites.intersection(known)
        for (id, isFavorite) in pendingFavoriteEdits {
            if isFavorite { favs.insert(id) } else { favs.remove(id) }
        }
        pendingFavoriteEdits = [:]
        favorites = favs
        isLoaded = true
        publish()
        if favs != loaded.favorites || merged.map(\.id) != loaded.order {
            persistIndex()
        }
    }

    /// Runs `work` on the IO queue and resumes with its result.
    private static func runIO<T: Sendable>(on queue: DispatchQueue,
                                           _ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// Decodes the bundled pack. A broken entry is skipped; a missing / unreadable file yields no
    /// built-ins. Never crashes.
    private static func loadBuiltIns(from bundle: Bundle) -> [Preset] {
        guard let url = bundle.url(forResource: "BuiltInPresets", withExtension: "json") else {
            presetLog.error("BuiltInPresets.json is missing from the bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let entries = try decoder.decode([LossyPreset].self, from: data)
            var seenIDs = Set<UUID>()
            var result: [Preset] = []
            for case let decoded? in entries.map(\.preset)
            where decoded.formatVersion <= Preset.currentFormatVersion && !seenIDs.contains(decoded.id) {
                var preset = decoded
                preset.source = .builtIn
                seenIDs.insert(preset.id)
                result.append(preset)
            }
            if result.count != entries.count {
                presetLog.error("Skipped \(entries.count - result.count) invalid built-in preset(s)")
            }
            return result
        } catch {
            presetLog.error("BuiltInPresets.json could not be read: \(String(describing: error), privacy: .public)")
            return []
        }
    }
}

// MARK: - Disk store

/// Snapshot of the user presets on disk.
private struct LoadedUserPresets: Sendable {
    var presets: [Preset] = []
    var order: [UUID] = []
    var favorites: Set<UUID> = []
}

/// `presets-index.json`: user order and favourites (built-in ids may be favourites too).
private struct PresetIndexFile: Codable, Sendable {
    var version = 1
    var order: [UUID] = []
    var favorites: [UUID] = []
}

/// Decodes one pack entry without failing the whole pack.
private struct LossyPreset: Decodable {
    let preset: Preset?

    init(from decoder: Decoder) {
        var decoded: Preset?
        do {
            decoded = try Preset(from: decoder)
        } catch {
            presetLog.error("Invalid built-in preset: \(String(describing: error), privacy: .public)")
        }
        preset = decoded
    }
}

/// File access for the user presets folder. A value type with no state, so it can be used from the
/// IO queue; callers keep writes ordered by running them on that one serial queue.
private struct PresetDiskStore: Sendable {
    let directory: URL

    /// Temporary folder for `shareURL(for:)` files (earlier sessions' files are cleared at launch).
    static var shareRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SharedPresets", isDirectory: true)
    }

    private var indexURL: URL {
        directory.appendingPathComponent("presets-index.json")
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension(PresetCodec.fileExtension)
    }

    func write(_ preset: Preset) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PresetCodec.encode(preset).write(to: fileURL(for: preset.id), options: .atomic)
    }

    /// Writes each preset; returns a user-facing reason for every id that failed.
    func write(_ presets: [Preset]) -> [UUID: String] {
        var failures: [UUID: String] = [:]
        for preset in presets {
            do {
                try write(preset)
            } catch {
                presetLog.error("Preset write failed: \(error.localizedDescription, privacy: .public)")
                failures[preset.id] = error.localizedDescription
            }
        }
        return failures
    }

    func remove(_ id: UUID) {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            presetLog.error("Preset delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func writeIndex(_ index: PresetIndexFile) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(index).write(to: indexURL, options: .atomic)
        } catch {
            presetLog.error("Preset index write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Every readable `.noorpreset` in the folder, in index order (unknown files after, oldest first).
    func loadAll() -> LoadedUserPresets {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return LoadedUserPresets() }
        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                               options: [.skipsHiddenFiles])
        } catch {
            presetLog.error("Presets folder unreadable: \(error.localizedDescription, privacy: .public)")
            return LoadedUserPresets()
        }
        var byID: [UUID: Preset] = [:]
        for file in files where file.pathExtension.lowercased() == PresetCodec.fileExtension {
            do {
                for preset in try PresetCodec.decode(Data(contentsOf: file)) where byID[preset.id] == nil {
                    byID[preset.id] = preset
                }
            } catch {
                presetLog.error("Skipped preset file \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        var index = PresetIndexFile()
        if let data = try? Data(contentsOf: indexURL) {
            do {
                index = try JSONDecoder().decode(PresetIndexFile.self, from: data)
            } catch {
                presetLog.error("Preset index unreadable: \(String(describing: error), privacy: .public)")
            }
        }

        var ordered: [Preset] = []
        var placed = Set<UUID>()
        for id in index.order {
            if let preset = byID[id], !placed.contains(id) {
                ordered.append(preset)
                placed.insert(id)
            }
        }
        let rest = byID.values.filter { !placed.contains($0.id) }.sorted {
            ($0.createdAt, $0.name) < ($1.createdAt, $1.name)
        }
        ordered.append(contentsOf: rest)
        return LoadedUserPresets(presets: ordered, order: index.order, favorites: Set(index.favorites))
    }

    /// Removes share files left from earlier sessions (folders created before `cutoff`).
    func removeSharedFiles(createdBefore cutoff: Date) {
        let fm = FileManager.default
        let root = PresetDiskStore.shareRoot
        guard let folders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey],
                                                        options: [.skipsHiddenFiles]) else { return }
        for folder in folders {
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if created < cutoff { try? fm.removeItem(at: folder) }
        }
    }
}

// MARK: - Import collection (off the main actor)

/// Reads and parses the files picked for import. Pure file work, safe on any thread.
private enum PresetFileCollector {
    struct Item: Sendable {
        var preset: Preset
        var warnings: [String]
    }

    struct Outcome: Sendable {
        var items: [Item] = []
        var failures: [String] = []
    }

    static let maxPresetFileBytes = 8 << 20
    /// Extensions picked up inside folders (others are ignored silently).
    private static let folderExtensions: Set<String> = ["xmp", "noorpreset", "dng", "lrtemplate", "zip"]

    static func collect(_ urls: [URL]) -> Outcome {
        var outcome = Outcome()
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                collectFolder(url, into: &outcome)
            } else {
                importFile(url, into: &outcome)
            }
        }
        return outcome
    }

    /// Files in the folder and in its sub-folders (two levels deep).
    private static func collectFolder(_ folder: URL, into outcome: inout Outcome) {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            outcome.failures.append(String(localized: "\(folder.lastPathComponent): The folder can't be read."))
            return
        }
        var found = 0
        while let item = enumerator.nextObject() as? URL {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if enumerator.level >= 2 { enumerator.skipDescendants() }
                continue
            }
            guard folderExtensions.contains(item.pathExtension.lowercased()) else { continue }
            found += 1
            importFile(item, into: &outcome)
        }
        if found == 0 {
            outcome.failures.append(String(localized: "\(folder.lastPathComponent): No presets found."))
        }
    }

    private static func importFile(_ url: URL, into outcome: inout Outcome) {
        do {
            switch url.pathExtension.lowercased() {
            case PresetCodec.fileExtension, "json":
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= maxPresetFileBytes else { throw XMPImportError.tooLarge }
                for preset in try PresetCodec.decode(Data(contentsOf: url)) {
                    outcome.items.append(Item(preset: preset, warnings: preset.notes ?? []))
                }
            default:
                let result = try XMPPresetImporter.importPreset(from: url)
                outcome.items.append(Item(preset: result.preset, warnings: result.warnings))
            }
        } catch {
            outcome.failures.append(String(localized: "\(url.lastPathComponent): \(reason(for: error))"))
            presetLog.error("Import of \(url.lastPathComponent, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func reason(for error: Error) -> String {
        if error is DecodingError {
            return String(localized: "This isn't a valid Noor preset.")
        }
        return error.localizedDescription
    }
}
