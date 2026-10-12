import SwiftUI
import UIKit
import CoreGraphics
import Observation

/// Renders and caches the preset strip's thumbnails: the current photo with each preset applied at
/// 100 % over the editor's preset baseline, which is exactly what a tap on the preset produces.
///
/// * Thumbnails are small, display-only 8-bit renders of the ORIGINAL through the same recipe
///   pipeline as the canvas and export (`ThumbnailRenderer`). Nothing is ever exported from them.
/// * Every picture is keyed by (preset id + the preset's look, baseline recipe, project). When the
///   baseline changes (a preset is committed, undo, reset …) queued work is dropped and the visible
///   presets are re-rendered after a short pause. The previous pictures stay on screen until their
///   replacements arrive, so the strip never flashes back to placeholders.
/// * One render at a time (a single serial worker task), off the main actor (`Task.detached`), and
///   only for cells that are on screen: a cell that scrolls off is removed from the queue.
/// * One shared instance, because the Presets panel is rebuilt on every tool switch and the pictures
///   should survive that. Opening another photo clears it, and a memory warning purges it. The photo
///   document is held weakly, so a closed editor's caches are never kept alive by this object.
///
/// Main-actor confined; the only work that leaves the main actor is the render itself, which gets a
/// value-type job (`Sendable`) and returns a `CGImage`.
@MainActor
@Observable
final class PresetThumbnailCache {
    /// The cache shared by every Presets panel.
    static let shared = PresetThumbnailCache()

    /// One rendered thumbnail.
    struct Thumbnail {
        let image: Image
        /// Changes every time the picture is replaced (drives the cell's fade-in).
        let revision: Int
        /// The photo it shows. Cells compare it with their own photo, so a newly opened photo never
        /// flashes the previous photo's pictures before `prepare(for:displayScale:)` clears them.
        let projectID: UUID
    }

    // MARK: Configuration

    /// Side of a strip cell in points.
    static let cellSide: CGFloat = 72
    /// Pause after a baseline change before re-rendering (the user may still be tapping undo).
    private static let refreshDelay: Duration = .milliseconds(350)
    /// Pause after a memory warning before re-rendering what is still on screen.
    private static let purgeDelay: Duration = .seconds(1)
    /// Thumbnail long-edge bounds in pixels (the cell is filled, so the short edge must cover it).
    private static let minimumLongEdge: CGFloat = 200
    private static let maximumLongEdge: CGFloat = 480

    // MARK: Observable state

    /// Latest picture per preset id. May belong to the previous baseline while a refresh is pending.
    private(set) var thumbnails: [UUID: Thumbnail] = [:]

    // MARK: Private state (not observed)

    @ObservationIgnored private weak var document: PhotoDocument?
    @ObservationIgnored private var context: RenderContext?
    /// The key each stored thumbnail was rendered for.
    @ObservationIgnored private var renderedKeys: [UUID: ThumbnailKey] = [:]
    /// Keys whose render failed (not retried until the context changes).
    @ObservationIgnored private var failedKeys: Set<ThumbnailKey> = []
    /// Presets whose cells are on screen, with the order they appeared in.
    @ObservationIgnored private var visible: [UUID: VisiblePreset] = [:]
    /// Preset ids waiting for a render, in order.
    @ObservationIgnored private var queue: [UUID] = []
    @ObservationIgnored private var inFlight: ThumbnailKey?
    @ObservationIgnored private var worker: Task<Void, Never>?
    /// Bumped whenever queued / in-flight work becomes stale.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var revisionCounter = 0
    @ObservationIgnored private var appearanceCounter = 0
    @ObservationIgnored private var pendingDelay: Duration = .zero
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol?

    private init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.purge() }
        }
    }

    // MARK: Public API

    /// Points the cache at the editor's photo and preset baseline. Call when the Presets panel
    /// appears and whenever `model.presetBaseline` changes. Cheap when nothing changed.
    func prepare(for model: EditorModel, displayScale: CGFloat) {
        let document = model.document
        let baseline = model.presetBaseline
        let scale = displayScale.isFinite && displayScale > 0 ? displayScale : 2
        let next = RenderContext(projectID: model.project.id,
                                 baseline: baseline,
                                 baselineHash: baseline.hashValue,
                                 asShotKelvin: document.info.asShotKelvin,
                                 asShotTint: document.info.asShotTint,
                                 longEdge: Self.longEdge(for: baseline, document: document, scale: scale),
                                 scale: scale)
        let previous = context
        if let previous, previous == next, self.document === document { return }

        let isNewPhoto = previous == nil || previous?.projectID != next.projectID || self.document !== document
        self.document = document
        context = next
        restart(clearingPictures: isNewPhoto, delay: isNewPhoto ? .zero : Self.refreshDelay)
    }

    /// The latest picture for `preset` (possibly from the previous baseline while it refreshes).
    func thumbnail(for preset: Preset) -> Thumbnail? {
        thumbnails[preset.id]
    }

    /// A cell for `preset` is on screen (or its preset changed): render it if its picture is missing
    /// or stale. `cell` names the on-screen cell (the strip's group), because the same preset can be
    /// shown by two cells at once while the strip switches groups (Favorites ↔ its own group); the
    /// preset stays "visible" until every cell showing it has left. Repeated calls are idempotent.
    func request(_ preset: Preset, cell: String = "") {
        if var existing = visible[preset.id] {
            existing.preset = preset
            existing.cells.insert(cell)
            visible[preset.id] = existing
        } else {
            appearanceCounter &+= 1
            visible[preset.id] = VisiblePreset(preset: preset, order: appearanceCounter, cells: [cell])
        }
        enqueue(preset)
        startWorkerIfNeeded()
    }

    /// The cell `cell` showing `presetID` left the screen. When no cell shows the preset any more, its
    /// queued render is dropped (an in-flight one finishes).
    func cancel(_ presetID: UUID, cell: String = "") {
        guard var entry = visible[presetID] else { return }
        entry.cells.remove(cell)
        if entry.cells.isEmpty {
            visible[presetID] = nil
            queue.removeAll { $0 == presetID }
        } else {
            visible[presetID] = entry
        }
    }

    /// Frees every picture (memory warning). Cells still on screen re-render after a pause.
    func purge() {
        restart(clearingPictures: true, delay: Self.purgeDelay)
    }

    // MARK: Scheduling

    /// Drops queued and in-flight work and queues the visible presets for the current context.
    private func restart(clearingPictures: Bool, delay: Duration) {
        generation &+= 1
        worker?.cancel()
        worker = nil
        inFlight = nil
        queue.removeAll()
        failedKeys.removeAll()
        if clearingPictures {
            thumbnails.removeAll()
            renderedKeys.removeAll()
        }
        pendingDelay = delay
        for entry in visible.values.sorted(by: { $0.order < $1.order }) {
            enqueue(entry.preset)
        }
        startWorkerIfNeeded()
    }

    private func enqueue(_ preset: Preset) {
        guard let context, let key = Self.key(for: preset, in: context) else { return }
        guard renderedKeys[preset.id] != key,
              !failedKeys.contains(key),
              inFlight != key,
              !queue.contains(preset.id) else { return }
        queue.append(preset.id)
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, !queue.isEmpty, context != nil else { return }
        let generation = self.generation
        let delay = pendingDelay
        pendingDelay = .zero
        worker = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            await self?.drain(generation: generation)
        }
    }

    /// The serial worker: renders queued presets one by one until the queue is empty or the work
    /// became stale.
    private func drain(generation: Int) async {
        while !Task.isCancelled, generation == self.generation, let job = nextJob() {
            inFlight = job.key
            let rendered = await Task.detached(priority: .utility) {
                PresetThumbnailCache.render(job)
            }.value
            guard generation == self.generation else { return }
            inFlight = nil
            if let rendered {
                revisionCounter &+= 1
                renderedKeys[job.presetID] = job.key
                thumbnails[job.presetID] = Thumbnail(image: Image(decorative: rendered, scale: job.scale),
                                                     revision: revisionCounter,
                                                     projectID: job.key.projectID)
            } else {
                failedKeys.insert(job.key)
            }
        }
        if generation == self.generation {
            worker = nil
        }
    }

    /// Next queued preset that is still on screen and still needs a picture.
    private func nextJob() -> ThumbnailJob? {
        guard let context, let document else {
            queue.removeAll()
            return nil
        }
        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard let entry = visible[id], let key = Self.key(for: entry.preset, in: context) else { continue }
            if renderedKeys[id] == key || failedKeys.contains(key) { continue }
            return ThumbnailJob(presetID: id,
                                key: key,
                                preset: entry.preset,
                                baseline: context.baseline,
                                asShotKelvin: context.asShotKelvin,
                                asShotTint: context.asShotTint,
                                document: document,
                                longEdge: context.longEdge,
                                scale: context.scale)
        }
        return nil
    }

    // MARK: Rendering (any thread)

    /// The preset at 100 % over the baseline, exactly as `EditorModel.previewPreset` builds it.
    nonisolated private static func render(_ job: ThumbnailJob) -> CGImage? {
        let applyContext = PresetApplyContext(asShotKelvin: job.asShotKelvin, asShotTint: job.asShotTint)
        var recipe = job.preset.applied(to: job.baseline, amount: 1, context: applyContext)
        recipe.geometry = job.baseline.geometry     // presets never move the crop
        recipe.keepsHDR = job.baseline.keepsHDR
        return ThumbnailRenderer.render(job.document, recipe: recipe, longEdge: job.longEdge)
    }

    // MARK: Keys and sizes

    private static func key(for preset: Preset, in context: RenderContext) -> ThumbnailKey? {
        ThumbnailKey(presetID: preset.id,
                     look: lookFingerprint(preset),
                     baselineHash: context.baselineHash,
                     projectID: context.projectID,
                     longEdge: Int(context.longEdge))
    }

    /// Everything about a preset that changes its picture (a rename does not).
    private static func lookFingerprint(_ preset: Preset) -> Int {
        var hasher = Hasher()
        hasher.combine(preset.values)
        hasher.combine(preset.includes)
        hasher.combine(preset.supportsAmount)
        return hasher.finalize()
    }

    /// Long edge (pixels) so that the picture's short edge fills a cell at the screen's scale.
    private static func longEdge(for baseline: EditRecipe, document: PhotoDocument, scale: CGFloat) -> CGFloat {
        let cellPixels = (cellSide * scale).rounded(.up)
        let size = baseline.geometry.clamped().outputSize(for: document.uprightSize)
        let long = max(size.width, size.height)
        let short = min(size.width, size.height)
        guard long.isFinite, short.isFinite, short >= 1 else {
            return min(max(cellPixels, minimumLongEdge), maximumLongEdge)
        }
        let needed = (cellPixels * long / short).rounded(.up)
        return min(max(needed, minimumLongEdge), maximumLongEdge)
    }
}

// MARK: - Supporting types

/// The photo state thumbnails are rendered for.
private struct RenderContext: Equatable {
    var projectID: UUID
    var baseline: EditRecipe
    var baselineHash: Int
    var asShotKelvin: Double
    var asShotTint: Double
    var longEdge: CGFloat
    var scale: CGFloat
}

/// Identity of one rendered picture: (preset, its look, baseline recipe, project, size).
private struct ThumbnailKey: Hashable {
    var presetID: UUID
    var look: Int
    var baselineHash: Int
    var projectID: UUID
    var longEdge: Int
}

/// A preset whose strip cell is on screen.
private struct VisiblePreset {
    var preset: Preset
    var order: Int
    /// The on-screen cells showing it (see `request(_:cell:)`).
    var cells: Set<String>
}

/// Everything one render needs, as values (safe to hand to a detached task).
private struct ThumbnailJob: Sendable {
    var presetID: UUID
    var key: ThumbnailKey
    var preset: Preset
    var baseline: EditRecipe
    var asShotKelvin: Double
    var asShotTint: Double
    var document: PhotoDocument
    var longEdge: CGFloat
    var scale: CGFloat
}
