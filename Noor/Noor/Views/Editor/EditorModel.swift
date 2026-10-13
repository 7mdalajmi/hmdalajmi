import SwiftUI
import CoreImage
import Observation

/// The tools on the editor's tool rail, in editing order (Lightroom-style).
enum EditorTool: String, CaseIterable, Identifiable {
    case presets, crop, light, color, effects, detail
    var id: String { rawValue }
}

/// State of one open photo in the editor.
///
/// The model owns the live `EditRecipe`, the undo history and the preset-browsing session, and it
/// drives the preview renderer. It never touches pixels itself: every change is a new recipe
/// value, rendered from the original file by the engine (so the original is never modified).
@MainActor @Observable
final class EditorModel {

    // MARK: Collaborators

    // `let`s are never tracked by `@Observable`.
    let document: PhotoDocument
    private let library: LibraryStore
    private let presetLibrary: PresetLibrary
    private let renderer: PreviewRenderer
    @ObservationIgnored private weak var canvas: CanvasView?

    // MARK: Observable state

    private(set) var project: PhotoProject

    /// The live recipe (includes a previewed preset). Every change re-renders the preview.
    private(set) var recipe: EditRecipe {
        didSet { recipeDidChange(from: oldValue) }
    }

    var selectedTool: EditorTool = .light {
        didSet { toolDidChange(from: oldValue) }
    }
    var isPanelVisible = true
    /// Sticky before/after toggle from the top bar.
    var showOriginal = false {
        didSet { if showOriginal != oldValue { requestRender(settled: true) } }
    }
    var isHistogramVisible = true {
        didSet { if isHistogramVisible && !oldValue { requestRender(settled: true) } }
    }
    private(set) var histogram: Histogram?
    private(set) var isInteracting = false
    /// True while the user presses and holds the photo (temporary "before" view).
    private(set) var isPressingOriginal = false
    var isExportPresented = false
    var isSavePresetPresented = false

    // History (each entry stores the recipe *before* a change).
    private var undoStack: [HistoryEntry] = []
    private var redoStack: [HistoryEntry] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    /// Label of the step `undo()` would revert, for menus / VoiceOver.
    var undoLabel: String? { undoStack.last?.label }

    // Presets (Lightroom flow: the baseline is captured when browsing starts; taps preview).
    private(set) var activePresetID: UUID?
    private(set) var presetAmount: Double = 100
    private var presetSessionBaseline: EditRecipe?

    /// Recipe that preset thumbnails are rendered over (the photo before any previewed preset).
    var presetBaseline: EditRecipe { presetSessionBaseline ?? recipe }

    // Crop tool
    private(set) var cropFrameImage: CGImage?
    var frameSize: CGSize { recipe.geometry.frameSize(for: document.uprightSize) }

    private(set) var canPaste = false

    // MARK: Private bookkeeping

    private struct HistoryEntry {
        let label: String
        let recipe: EditRecipe
    }

    @ObservationIgnored private var interactionStart: EditRecipe?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var cropFrameTask: Task<Void, Never>?
    @ObservationIgnored private var cropFrameKey: EditRecipe?
    @ObservationIgnored private var lastHistogramRequest = Date.distantPast
    /// Recipe of the last histogram request: a moving viewport alone never asks for a new one.
    @ObservationIgnored private var lastHistogramRecipe: EditRecipe?
    @ObservationIgnored private var lastSavedRecipe: EditRecipe
    @ObservationIgnored private var backgroundObserver: NSObjectProtocol?
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol?
    @ObservationIgnored private var isClosed = false

    private static let historyLimit = 200
    /// Copy / Paste Settings clipboard, shared by every editor session while the app runs.
    private static var settingsClipboard: EditRecipe?

    // MARK: Init

    init(project: PhotoProject, document: PhotoDocument, library: LibraryStore, presets: PresetLibrary) {
        self.project = project
        self.document = document
        self.library = library
        self.presetLibrary = presets
        self.renderer = PreviewRenderer(document: document)
        let initial = project.recipe.clamped()
        self.recipe = initial
        self.lastSavedRecipe = initial
        self.canPaste = EditorModel.settingsClipboard != nil

        renderer.onHistogram = { [weak self] histogram in
            Task { @MainActor [weak self] in
                // An unchanged histogram (a settled pan or zoom) does not redraw its views.
                guard let self, !self.isClosed, self.needsHistogram, self.histogram != histogram else { return }
                self.histogram = histogram
            }
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.save()
                // A full-resolution decode can be hundreds of MB: drop it so the suspended app is
                // less likely to be terminated (it is decoded again when next needed).
                self.renderer.purgeCaches()
            }
        }
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.renderer.purgeCaches() }
        }
    }

    // MARK: Editing

    /// A binding for a slider. Changes made between `beginInteraction()` and `endInteraction(_:)`
    /// become one undo step; a change made outside a gesture (e.g. VoiceOver) is its own step.
    /// Weak: a binding (or a gesture callback holding one) may outlive the closed editor; it then
    /// reads the default value and ignores writes instead of crashing.
    func binding(_ keyPath: WritableKeyPath<EditRecipe, Double>) -> Binding<Double> {
        Binding(
            get: { @MainActor [weak self] in self?.recipe[keyPath: keyPath] ?? EditRecipe()[keyPath: keyPath] },
            set: { @MainActor [weak self] newValue in self?.setValue(newValue, at: keyPath) }
        )
    }

    /// A binding for any recipe value (Bool, Geometry, ToneCurves, ColorGrading, …).
    func binding<Value>(_ keyPath: WritableKeyPath<EditRecipe, Value>) -> Binding<Value> {
        Binding(
            get: { @MainActor [weak self] in self?.recipe[keyPath: keyPath] ?? EditRecipe()[keyPath: keyPath] },
            set: { @MainActor [weak self] newValue in self?.setValue(newValue, at: keyPath) }
        )
    }

    private func setValue<Value>(_ value: Value, at keyPath: WritableKeyPath<EditRecipe, Value>) {
        let before = recipe
        var next = recipe
        next[keyPath: keyPath] = value
        guard next != before else { return }
        endPresetSessionIfEditing()
        if interactionStart == nil {
            pushUndo(String(localized: "Edit"), before: before)
        }
        recipe = next
    }

    /// Call when a drag on a slider / curve / wheel / crop handle starts.
    func beginInteraction() {
        if interactionStart == nil { interactionStart = recipe }
        isInteracting = true
    }

    /// Call when the drag ends. Creates one undo step named `label` if anything changed.
    func endInteraction(_ label: String) {
        isInteracting = false
        if let start = interactionStart {
            interactionStart = nil
            if start != recipe { pushUndo(label, before: start) }
        }
        requestRender(settled: true)
        scheduleSave()
    }

    /// One-shot undoable change (buttons, toggles, menu actions).
    func apply(_ label: String, _ change: (inout EditRecipe) -> Void) {
        var next = recipe
        change(&next)
        guard next != recipe else { return }
        endPresetSessionIfEditing()
        pushUndo(label, before: recipe)
        recipe = next
    }

    func reset(_ group: SettingGroup) {
        apply(String(localized: "Reset")) { $0.reset(group) }
    }

    /// Back to the original look (geometry included). Undoable.
    func resetAll() {
        cancelPresetSession()
        apply(String(localized: "Reset All")) { r in
            let keepsHDR = r.keepsHDR
            r = EditRecipe()
            r.keepsHDR = keepsHDR
        }
    }

    // MARK: Undo / redo

    func undo() {
        commitPreset()
        guard let entry = undoStack.popLast() else { return }
        redoStack.append(HistoryEntry(label: entry.label, recipe: recipe))
        recipe = entry.recipe
        scheduleSave()
    }

    func redo() {
        commitPreset()
        guard let entry = redoStack.popLast() else { return }
        undoStack.append(HistoryEntry(label: entry.label, recipe: recipe))
        recipe = entry.recipe
        scheduleSave()
    }

    private func pushUndo(_ label: String, before: EditRecipe) {
        undoStack.append(HistoryEntry(label: label, recipe: before))
        if undoStack.count > Self.historyLimit { undoStack.removeFirst(undoStack.count - Self.historyLimit) }
        redoStack.removeAll()
    }

    // MARK: Copy / paste settings

    /// Copies every tonal / colour / effect setting (not crop or rotation).
    func copySettings() {
        EditorModel.settingsClipboard = recipe
        canPaste = true
    }

    func pasteSettings() {
        guard let clip = EditorModel.settingsClipboard else { return }
        apply(String(localized: "Paste Settings")) { $0.copy(Set(SettingGroup.allCases), from: clip) }
    }

    // MARK: Presets

    private var presetContext: PresetApplyContext {
        PresetApplyContext(asShotKelvin: document.info.asShotKelvin, asShotTint: document.info.asShotTint)
    }

    /// Shows `preset` over the baseline at 100 %. Tapping another preset replaces the preview.
    func previewPreset(_ preset: Preset) {
        if presetSessionBaseline == nil { presetSessionBaseline = recipe }
        activePresetID = preset.id
        presetAmount = 100
        applyPresetPreview()
    }

    /// Preset intensity, 0…200 %.
    func setPresetAmount(_ percent: Double) {
        guard presetSessionBaseline != nil else { return }
        presetAmount = EditRecipe.Limits.amount.clamp(percent)
        applyPresetPreview()
    }

    private func applyPresetPreview() {
        guard let baseline = presetSessionBaseline,
              let id = activePresetID,
              let preset = presetLibrary.preset(id: id) else { return }
        var next = preset.applied(to: baseline, amount: presetAmount / 100, context: presetContext)
        next.geometry = baseline.geometry       // presets never move the crop
        next.keepsHDR = baseline.keepsHDR
        recipe = next
    }

    /// Keeps the previewed preset as one undo step ("Preset: <name>").
    func commitPreset() {
        guard let baseline = presetSessionBaseline else { return }
        let name = activePresetID.flatMap { presetLibrary.preset(id: $0)?.displayName() } ?? ""
        presetSessionBaseline = nil
        activePresetID = nil
        presetAmount = 100
        if recipe != baseline {
            pushUndo(String(localized: "Preset: \(name)"), before: baseline)
            scheduleSave()
        }
    }

    /// Discards the previewed preset and restores the baseline.
    func cancelPreset() {
        guard let baseline = presetSessionBaseline else { return }
        presetSessionBaseline = nil
        activePresetID = nil
        presetAmount = 100
        recipe = baseline
    }

    private func cancelPresetSession() {
        if presetSessionBaseline != nil { cancelPreset() }
    }

    /// A manual edit while a preset is previewed keeps the preset (as Lightroom does).
    private func endPresetSessionIfEditing() {
        if presetSessionBaseline != nil { commitPreset() }
    }

    // MARK: Tools

    private func toolDidChange(from old: EditorTool) {
        guard old != selectedTool else { return }
        if old == .presets { commitPreset() }
        if selectedTool == .crop {
            // The canvas is going away: a pending full-resolution frame would be wasted on it.
            detailTask?.cancel()
            detailTask = nil
            refreshCropFrameIfNeeded(force: cropFrameImage == nil)
        } else if old == .crop {
            // The canvas comes back as a new view; `attach(canvas:)` renders it once it exists.
            cropFrameTask?.cancel()
            cropFrameImage = nil
            cropFrameKey = nil
            requestRender(settled: true)
        } else if selectedTool == .light {
            // The tone curve draws the histogram even when the overlay is hidden: refresh it.
            requestRender(settled: true)
        }
    }

    /// Histograms are computed while the overlay is shown or the Light tool (tone curve) is open.
    private var needsHistogram: Bool {
        isHistogramVisible || selectedTool == .light
    }

    /// Re-renders the crop tool's picture when something other than crop/straighten changed.
    private func refreshCropFrameIfNeeded(force: Bool = false) {
        guard selectedTool == .crop, !isClosed else { return }
        var key = recipe
        key.geometry.straighten = 0
        key.geometry.crop = .full
        key.geometry.aspect = .original
        guard force || key != cropFrameKey else { return }
        cropFrameKey = key
        cropFrameTask?.cancel()
        let document = self.document
        cropFrameTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))   // coalesce rapid changes
            guard !Task.isCancelled else { return }
            let image = await Task.detached(priority: .userInitiated) {
                ThumbnailRenderer.render(document, recipe: key, longEdge: 1600, stage: .frameOnly)
            }.value
            guard !Task.isCancelled, let self, self.selectedTool == .crop else { return }
            self.cropFrameImage = image
        }
    }

    // MARK: Recipe changes

    private func recipeDidChange(from old: EditRecipe) {
        guard recipe != old, !isClosed else { return }
        if recipe.geometry != old.geometry, selectedTool != .crop {
            canvas?.setImageSize(recipe.geometry.outputSize(for: document.uprightSize), refit: true)
        }
        refreshCropFrameIfNeeded()
        requestRender(settled: !isInteracting)
        if !isInteracting { scheduleSave() }
    }

    // MARK: Canvas & rendering

    /// Called by `PhotoCanvas` whenever a canvas view is created (also after leaving the crop tool).
    func attach(canvas: CanvasView) {
        guard !isClosed else { return }
        self.canvas = canvas
        // Before the first frame: the renderer draws the size the canvas expects.
        canvas.setImageSize(recipe.geometry.outputSize(for: document.uprightSize), refit: true)
        canvas.onViewportChange = { [weak self] _, settled in
            self?.requestRender(settled: settled)
        }
        canvas.onPressChanged = { [weak self] pressed in
            guard let self else { return }
            self.isPressingOriginal = pressed
            self.requestRender(settled: true)
        }
        canvas.onTwoFingerTap = { [weak self] in
            self?.isHistogramVisible.toggle()
        }
        renderer.attach(canvas: canvas)
        requestRender(settled: true)
    }

    /// Asks for a new preview frame. While dragging (`settled == false`) only the fast proxy is
    /// rendered; once settled, a full-resolution "detail" frame follows when zoomed in past the proxy.
    func requestRender(settled: Bool) {
        // The crop tool shows its own picture; a canvas still alive during its removal transition
        // must not be drawn (least of all at full resolution) for every crop drag step.
        guard let canvas, !isClosed, selectedTool != .crop else { return }
        generation &+= 1
        let gen = generation

        let screen = canvas.window?.windowScene?.screen
        let potential = Float(screen?.potentialEDRHeadroom ?? 1)
        let current = Float(screen?.currentEDRHeadroom ?? 1)
        let edr = recipe.keepsHDR && document.info.isHDR && potential > 1

        // Every settled frame refreshes the histogram; while something moves, only a changed recipe
        // does (at most 10 per second). A pan or pinch alone never recomputes it.
        let now = Date()
        let wantsHistogram = needsHistogram
            && (settled || (recipe != lastHistogramRecipe && now.timeIntervalSince(lastHistogramRequest) > 0.1))
        if wantsHistogram {
            lastHistogramRequest = now
            lastHistogramRecipe = recipe
        }

        let request = PreviewRequest(
            recipe: recipe,
            showOriginal: showOriginal || isPressingOriginal,
            tier: .proxy,
            edr: edr,
            targetHeadroom: max(current, 1),
            wantsHistogram: wantsHistogram
        )
        renderer.submit(request)

        detailTask?.cancel()
        detailTask = nil
        guard canvas.viewport.needsDetail(proxyScale: renderer.proxyScale) else { return }
        detailTask = Task { [weak self] in
            if !settled { try? await Task.sleep(for: .milliseconds(150)) }
            guard let self, !Task.isCancelled, gen == self.generation else { return }
            var detail = request
            detail.tier = .detail
            detail.wantsHistogram = false
            self.renderer.submit(detail)
        }
    }

    // MARK: Persistence & lifecycle

    private func scheduleSave() {
        guard !isClosed else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Persists the committed recipe (a previewed preset is saved only once committed).
    func save() {
        let committed = presetSessionBaseline ?? recipe
        guard committed != lastSavedRecipe else { return }
        lastSavedRecipe = committed
        project.recipe = committed
        project.modifiedAt = Date()
        library.update(project)
    }

    /// Leaving the editor: keep a previewed preset, save, stop rendering and free memory.
    func close() {
        guard !isClosed else { return }
        commitPreset()
        saveTask?.cancel()
        save()
        isClosed = true
        detailTask?.cancel()
        detailTask = nil
        cropFrameTask?.cancel()
        cropFrameTask = nil
        canvas = nil
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        backgroundObserver = nil
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
        memoryWarningObserver = nil
        // No further frames; the full-resolution purge and cache clearing run on the render queue
        // after a frame that may still be in flight (so it cannot re-decode afterwards, and the main
        // thread never waits on the document's decode lock).
        renderer.stop()
    }
}
