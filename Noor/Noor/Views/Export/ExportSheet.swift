import SwiftUI
import Accessibility
import UIKit
import UniformTypeIdentifiers

/// The export sheet (UX spec §1.3 and §6). The "zero quality loss" promise is visible here:
///
/// * **Destination:** Photos (exact bytes, add-only access), Files (`fileExporter`) or Share
///   (`ShareLink`, offered once the file is ready).
/// * **Format:** Same as Original (shows what it resolves to), HEIF 10-bit, TIFF 16-bit, PNG 16-bit,
///   JPEG, HEIF 8-bit, each with a one-line explanation. **Size:** original (the cropped size) or a
///   smaller long edge; exports are never upscaled. **Quality** only for lossy formats (default 100).
///   **Color space**, **Keep HDR** (only for HDR originals), **metadata / location**, **file name**.
/// * A live **summary** from `Exporter.plan`, e.g. "6048 × 4024 · HEIF 10-bit · Display P3 · ≈ 14 MB",
///   and a "Lossless — identical to the original" badge when the original's own bytes will be used.
/// * **Export** runs `Exporter.export` in a detached task with stage feedback; the sheet can't be
///   swiped away meanwhile, the screen stays awake and a background task lets the export finish if the
///   user leaves the app. Success plays a haptic and shows a toast; failures show an alert.
///
/// The last choices are remembered in `AppSettings.defaultExport` (except the per-photo file name);
/// the destination is remembered on this device.
@MainActor
struct ExportSheet: View {
    let model: EditorModel

    @Environment(AppModel.self) private var app

    init(model: EditorModel) {
        self.model = model
    }

    var body: some View {
        ExportSheetContent(model: model,
                           initialOptions: ExportSheetContent.startingOptions(app.settings.defaultExport, model: model))
    }
}

// MARK: - Content

/// The sheet itself. Its option state is seeded once from the saved defaults.
@MainActor
private struct ExportSheetContent: View {
    let model: EditorModel

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the last export went (a per-device convenience).
    @AppStorage("noor.export.destination") private var destination: ExportSheetDestination = .photos
    @State private var options: ExportOptions
    @State private var fileNameText = ""
    @State private var plan: ExportPlan?
    /// The plan for "Same as Original" (names what that choice resolves to in the menu).
    @State private var originalPlan: ExportPlan?
    @State private var session = ExportSheetSession()

    /// Long-edge sizes offered besides the original size (only those smaller than the photo).
    private static let standardLongEdges = [4096, 2048, 1080]

    init(model: EditorModel, initialOptions: ExportOptions) {
        self.model = model
        _options = State(initialValue: initialOptions)
    }

    /// The saved defaults adapted to this photo: no stale file name, no size the photo can't reach.
    static func startingOptions(_ saved: ExportOptions, model: EditorModel) -> ExportOptions {
        var options = saved
        options.fileName = nil
        if case .longEdge(let edge) = options.size {
            let full = fullSize(of: model)
            if edge <= 0 || CGFloat(edge) >= max(full.width, full.height) {
                options.size = .original
            }
        }
        options.quality = options.quality.isFinite ? min(max(options.quality, 0.5), 1) : 1
        // ProPhoto is only offered for 16-bit files ("Same as Original" is checked once it resolves).
        if options.colorSpace == .proPhoto, options.format != .original, !isSixteenBit(options.format) {
            options.colorSpace = .displayP3
        }
        return options
    }

    var body: some View {
        NavigationStack {
            Form {
                destinationSection
                fileSection
                if model.document.info.isHDR {
                    hdrSection
                }
                metadataSection
                fileNameSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface1)
            .disabled(session.isBusy)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .disabled(session.isBusy)
                }
            }
        }
        .overlay(alignment: .top) {
            toastView
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: session.toast)
        .task(id: planInput) {
            await updatePlan()
        }
        .onChange(of: options) {
            session.invalidateShare()
        }
        .onChange(of: destination) {
            session.invalidateShare()
        }
        .onChange(of: fileNameText) {
            session.invalidateShare()
        }
        .onChange(of: offersProPhoto) {
            // The format moved away from 16 bits: ProPhoto would posterize (the exporter would fall
            // back to Display P3 anyway), so show that choice instead of an unlisted selection.
            if !offersProPhoto && options.colorSpace == .proPhoto {
                options.colorSpace = .displayP3
            }
        }
        .onDisappear {
            session.tearDown()
        }
        .fileExporter(isPresented: $session.isFileExporterPresented,
                      item: session.fileForExporter,
                      contentTypes: session.fileExporterTypes,
                      defaultFilename: session.fileExporterName,
                      onCompletion: { result in
                          switch result {
                          case .success:
                              session.didSaveToFiles()
                          case .failure(let error):
                              session.fail(error)
                          }
                      })
        .alert("Export Failed", isPresented: $session.isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: session.errorMessage)
        }
        .sensoryFeedback(.success, trigger: session.successCount) { _, _ in app.settings.haptics }
        .sensoryFeedback(.error, trigger: session.errorCount) { _, _ in app.settings.haptics }
        .interactiveDismissDisabled(session.isBusy)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface1)
    }

    // MARK: Sections

    private var destinationSection: some View {
        Section {
            Picker("Destination", selection: $destination) {
                Text("Photos").tag(ExportSheetDestination.photos)
                Text("Files").tag(ExportSheetDestination.files)
                Text("Share").tag(ExportSheetDestination.share)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Theme.surface1)
            .listRowInsets(EdgeInsets(top: Theme.Space.xs, leading: 0, bottom: Theme.Space.xs, trailing: 0))
        }
    }

    private var fileSection: some View {
        Section {
            Picker("Format", selection: $options.format) {
                ForEach(ExportFormat.allCases) { format in
                    Text(verbatim: formatMenuTitle(format)).tag(format)
                }
            }
            .pickerStyle(.menu)

            Picker("Size", selection: $options.size) {
                let full = Self.fullSize(of: model)
                Text("Original (\(Int(full.width)) × \(Int(full.height)))").tag(ExportSize.original)
                ForEach(longEdgeChoices, id: \.self) { edge in
                    Text("Long Edge \(edge) px").tag(ExportSize.longEdge(edge))
                }
            }
            .pickerStyle(.menu)

            if showsQuality {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    AdjustmentSlider("Quality",
                                     value: qualityBinding,
                                     range: 50...100,
                                     defaultValue: 100,
                                     isEnabled: !session.isBusy)
                    Text("100 is the highest quality. JPEG and HEIF are still lossy formats.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Picker("Color Space", selection: $options.colorSpace) {
                ForEach(offeredColorSpaces) { space in
                    Text(verbatim: Self.colorSpaceTitle(space)).tag(space)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("File")
        } footer: {
            Text(verbatim: Self.formatExplanation(options.format))
        }
        .listRowBackground(Theme.surface2)
    }

    private var hdrSection: some View {
        Section {
            Toggle("Keep HDR", isOn: $options.keepHDR)
                .tint(Theme.accent)
        } footer: {
            if !options.keepHDR {
                Text("The photo is exported in standard dynamic range.")
            } else if plan?.writesHDR == true {
                Text("HDR screens show the photo's full brightness; other screens show a standard version.")
            } else if hdrNeedsNewerSystem {
                Text("Keeping HDR in an edited photo needs iOS 18, so it is exported in standard dynamic range.")
            } else {
                Text("This format can't keep HDR here, so the photo is exported in standard dynamic range.")
            }
        }
        .listRowBackground(Theme.surface2)
    }

    private var metadataSection: some View {
        Section {
            Toggle("Keep Metadata", isOn: $options.keepMetadata)
                .tint(Theme.accent)
            Toggle("Keep Location", isOn: locationBinding)
                .tint(Theme.accent)
                .disabled(!options.keepMetadata)
        } header: {
            Text("Metadata")
        } footer: {
            Text("Camera, lens, date and copyright details.")
        }
        .listRowBackground(Theme.surface2)
    }

    private var fileNameSection: some View {
        Section {
            HStack(spacing: Theme.Space.xxs) {
                TextField("File Name", text: $fileNameText, prompt: Text(verbatim: defaultBaseName))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                if let plan {
                    Text(verbatim: ".\(plan.fileExtension)")
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        } header: {
            Text("File Name")
        }
        .listRowBackground(Theme.surface2)
    }

    // MARK: Footer (summary + action)

    private var footer: some View {
        VStack(spacing: Theme.Space.s) {
            if let plan {
                Text(verbatim: summary(plan))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if plan.isPassthrough {
                    losslessBadge
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.textTertiary)
            }
            actionArea
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.m)
        .padding(.bottom, Theme.Space.s)
        .frame(maxWidth: .infinity)
        .background {
            Theme.surface1
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 1)
                }
        }
    }

    private var losslessBadge: some View {
        Label("Lossless — identical to the original", systemImage: "checkmark.seal.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.xs)
            .background {
                Capsule().fill(Theme.surface2)
            }
            .overlay {
                Capsule().strokeBorder(Theme.accent, lineWidth: 1)
            }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch session.phase {
        case .idle:
            if destination == .share, let shared = session.shareableResult {
                ShareLink(item: shared.url) {
                    primaryLabel(Label("Share", systemImage: "square.and.arrow.up"))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    startExport()
                } label: {
                    primaryLabel(Text("Export"))
                }
                .buttonStyle(.plain)
                .disabled(plan == nil)
                .opacity(plan == nil ? 0.5 : 1)
            }
        case .exporting(let stage):
            progressRow(stageText(stage), cancellable: true)
        case .savingToPhotos:
            progressRow(Text("Saving to Photos…"), cancellable: false)
        }
    }

    private func primaryLabel(_ content: some View) -> some View {
        content
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .fill(Theme.accent)
            }
            .contentShape(Rectangle())
    }

    private func progressRow(_ title: Text, cancellable: Bool) -> some View {
        HStack(spacing: Theme.Space.m) {
            ProgressView()
                .tint(Theme.textSecondary)
            title
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if cancellable {
                Button("Cancel") {
                    session.cancel()
                }
                .foregroundStyle(Theme.textPrimary)
            }
        }
        .frame(minHeight: 50)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = session.toast {
            VStack(spacing: Theme.Space.xxs) {
                Label {
                    switch toast.kind {
                    case .savedToPhotos: Text("Saved to Photos")
                    case .savedToFiles: Text("Saved to Files")
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                if !toast.detail.isEmpty {
                    Text(verbatim: toast.detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .fill(Theme.surface3)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
            }
            .padding(.top, Theme.Space.s)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { return }
                session.clearToast(toast.id)
            }
        }
    }

    // MARK: Derived values

    private var planInput: ExportSheetPlanInput {
        ExportSheetPlanInput(recipe: model.recipe, options: options)
    }

    /// What "Same as Original" resolves to for this photo (nil until the first plan arrives).
    private var resolvedOriginalFormat: ExportFormat? {
        originalPlan?.format
    }

    /// The resolved output format (the plan's, else the user's choice).
    private var effectiveFormat: ExportFormat? {
        if let plan { return plan.format }
        return outputFormat
    }

    /// The format of the current choice, straight from the options (no wait for a new plan).
    private var outputFormat: ExportFormat? {
        options.format == .original ? resolvedOriginalFormat : options.format
    }

    /// ProPhoto RGB is only offered for 16-bit files: in 8 or 10 bits it posterizes.
    /// While "Same as Original" is still resolving, a saved ProPhoto choice stays listed.
    private var offersProPhoto: Bool {
        guard let format = outputFormat else { return options.colorSpace == .proPhoto }
        return Self.isSixteenBit(format)
    }

    private var offeredColorSpaces: [ExportColorSpace] {
        ExportColorSpace.allCases.filter { $0 != .proPhoto || offersProPhoto }
    }

    /// HDR is lost only because this system is older than iOS 18: before it, only an unedited
    /// original is copied with its HDR; an edit can't get a new gain map.
    private var hdrNeedsNewerSystem: Bool {
        guard !Self.canWriteGainMaps, let format = outputFormat else { return false }
        return Self.supportsGainMap(format)
    }

    /// Quality matters only for lossy formats, and not when the original is simply copied.
    private var showsQuality: Bool {
        guard let format = effectiveFormat, Self.isLossy(format) else { return false }
        return !(options.format == .original && plan?.isPassthrough == true)
    }

    /// Standard long edges below the photo's long edge (plus a saved custom one, if valid).
    private var longEdgeChoices: [Int] {
        let full = Self.fullSize(of: model)
        let long = max(full.width, full.height)
        var edges = Self.standardLongEdges
        if case .longEdge(let edge) = options.size, !edges.contains(edge) {
            edges.append(edge)
        }
        return edges.filter { $0 > 0 && CGFloat($0) < long }.sorted(by: >)
    }

    private var qualityBinding: Binding<Double> {
        Binding(
            get: { @MainActor in (options.quality * 100).rounded() },
            set: { @MainActor percent in options.quality = min(max(percent / 100, 0.5), 1) }
        )
    }

    /// Location can only be kept together with the rest of the metadata.
    private var locationBinding: Binding<Bool> {
        Binding(
            get: { @MainActor in options.keepMetadata && options.keepLocation },
            set: { @MainActor keep in options.keepLocation = keep }
        )
    }

    /// The exporter's default name: "<original>-noor" (exactly what `Exporter.export` will use).
    private var defaultBaseName: String {
        Exporter.exportFileBaseName(requested: nil, fallback: model.project.displayName)
    }

    private func formatMenuTitle(_ format: ExportFormat) -> String {
        guard format == .original, let resolved = originalPlan else {
            return Self.formatTitle(format)
        }
        // The depth actually written: an unedited 8-bit HEIC is copied as it is, not as 10-bit.
        let resolvedTitle = Self.familyAndDepth(resolved.format, bits: resolved.bitsPerComponent)
        return String(localized: "Same as Original (\(resolvedTitle))")
    }

    /// "6048 × 4024 · HEIF 10-bit · Display P3 · ≈ 14 MB" (exact size for a passthrough copy).
    private func summary(_ plan: ExportPlan) -> String {
        let width = Int(plan.pixelSize.width.rounded())
        let height = Int(plan.pixelSize.height.rounded())
        let style = ByteCountFormatStyle(style: .file, allowedUnits: .all, spellsOutZero: true,
                                         includesActualByteCount: false, locale: locale)
        let bytes = max(plan.estimatedBytes, 0).formatted(style)
        let size = plan.isPassthrough ? bytes : "≈ \(bytes)"
        let hdr = plan.writesHDR ? " · HDR" : ""
        return "\(width) × \(height) · \(Self.familyAndDepth(plan.format, bits: plan.bitsPerComponent)) · \(plan.colorSpaceName)\(hdr) · \(size)"
    }

    private func stageText(_ stage: ExportStage) -> Text {
        switch stage {
        case .preparing:
            return Text("Preparing…")
        case .rendering:
            let size = model.document.uprightSize
            let megapixels = max(1, Int((size.width * size.height / 1_000_000).rounded()))
            return Text("Rendering \(megapixels) MP…")
        case .encoding:
            let name = plan.map { Self.familyAndDepth($0.format, bits: $0.bitsPerComponent) } ?? ""
            return Text("Encoding \(name)…")
        case .finishing:
            return Text("Checking the file…")
        }
    }

    // MARK: Actions

    private func updatePlan() async {
        let document = model.document
        let recipe = model.recipe
        let current = options
        let original: ExportOptions = {
            var copy = current
            copy.format = .original
            return copy
        }()
        let plans = await Task.detached(priority: .userInitiated) {
            (Exporter.plan(document: document, recipe: recipe, options: current),
             Exporter.plan(document: document, recipe: recipe, options: original))
        }.value
        guard !Task.isCancelled else { return }
        plan = plans.0
        originalPlan = plans.1
    }

    private func startExport() {
        guard plan != nil, !session.isBusy else { return }
        let trimmedName = fileNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        var exportOptions = options
        exportOptions.fileName = trimmedName.isEmpty ? nil : trimmedName

        // Remember the choices for the next export (the file name belongs to this photo only).
        var remembered = options
        remembered.fileName = nil
        if app.settings.defaultExport != remembered {
            app.settings.defaultExport = remembered
        }

        session.start(document: model.document,
                      recipe: model.recipe,
                      options: exportOptions,
                      baseName: model.project.displayName,
                      destination: destination)
    }

    // MARK: Labels and rules

    /// The cropped, rotated output size of the edit at full resolution.
    static func fullSize(of model: EditorModel) -> CGSize {
        let size = model.recipe.geometry.clamped().outputSize(for: model.document.uprightSize)
        return CGSize(width: max(1, size.width.rounded()), height: max(1, size.height.rounded()))
    }

    private static func isLossy(_ format: ExportFormat) -> Bool {
        switch format {
        case .jpeg, .heif8, .heif10: return true
        case .tiff16, .png16, .original: return false
        }
    }

    private static func isSixteenBit(_ format: ExportFormat) -> Bool {
        format == .tiff16 || format == .png16
    }

    /// Formats that can carry an HDR gain map (JPEG and HEIF).
    private static func supportsGainMap(_ format: ExportFormat) -> Bool {
        switch format {
        case .jpeg, .heif8, .heif10: return true
        case .tiff16, .png16, .original: return false
        }
    }

    /// Core Image writes an edited photo's HDR gain map (Adaptive HDR) only on iOS 18 and later.
    private static var canWriteGainMaps: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    private static func formatTitle(_ format: ExportFormat) -> String {
        switch format {
        case .original: return String(localized: "Same as Original")
        case .heif10: return String(localized: "HEIF 10-bit")
        case .tiff16: return String(localized: "TIFF 16-bit")
        case .png16: return String(localized: "PNG 16-bit")
        case .jpeg: return String(localized: "JPEG")
        case .heif8: return String(localized: "HEIF 8-bit")
        }
    }

    private static func formatExplanation(_ format: ExportFormat) -> String {
        switch format {
        case .original:
            return String(localized: "The original's format at its best quality. An unedited photo is copied byte for byte.")
        case .heif10:
            // Gain-map (HDR) export of an edit needs iOS 18; don't promise it on iOS 17.
            if canWriteGainMaps {
                return String(localized: "10-bit and efficient: the best lossy format. Keeps HDR.")
            }
            return String(localized: "10-bit and efficient: the best lossy format.")
        case .tiff16:
            return String(localized: "16-bit, uncompressed: a lossless master for further editing.")
        case .png16:
            return String(localized: "16-bit and lossless. Large files.")
        case .jpeg:
            return String(localized: "8-bit and lossy. Opens everywhere.")
        case .heif8:
            return String(localized: "8-bit and lossy, like a classic iPhone photo.")
        }
    }

    /// "HEIF 10-bit", from the format family and the bit depth actually written.
    static func familyAndDepth(_ format: ExportFormat, bits: Int) -> String {
        let family: String
        switch format {
        case .jpeg: family = "JPEG"
        case .heif8, .heif10, .original: family = "HEIF"
        case .png16: family = "PNG"
        case .tiff16: family = "TIFF"
        }
        return String(localized: "\(family) \(bits)-bit")
    }

    private static func colorSpaceTitle(_ space: ExportColorSpace) -> String {
        switch space {
        case .matchSource: return String(localized: "Same as Original")
        case .displayP3: return "Display P3"
        case .sRGB: return "sRGB"
        case .adobeRGB: return "Adobe RGB (1998)"
        case .proPhoto: return "ProPhoto RGB"
        }
    }
}

// MARK: - Destination

/// Where the export sheet sends the file. Raw values are stored in UserDefaults; never rename them.
enum ExportSheetDestination: String, CaseIterable, Identifiable {
    case photos, files, share
    var id: String { rawValue }
}

/// What the plan depends on.
private struct ExportSheetPlanInput: Equatable {
    var recipe: EditRecipe
    var options: ExportOptions
}

/// What an export file depends on (an identical request reuses the file already written).
private struct ExportSheetRequest: Equatable {
    var documentURL: URL
    var recipe: EditRecipe
    var options: ExportOptions
    var baseName: String
}

// MARK: - Session

/// One export sheet's work: the running export, delivery to Photos / Files / Share, the toast and
/// errors, plus the "keep awake" and background-task bookkeeping. Main-actor confined; the export
/// itself runs in a detached task and reports its stages back to the main actor.
///
/// The exported file lives in its own temporary folder and is reused while the options are
/// unchanged (so "Photos" then "Share" doesn't render twice). It is deleted when a different export
/// replaces it and when the sheet closes.
@MainActor
@Observable
final class ExportSheetSession {
    enum Phase: Equatable {
        case idle
        case exporting(ExportStage)
        case savingToPhotos
    }

    enum ToastKind: Equatable {
        case savedToPhotos
        case savedToFiles
    }

    struct Toast: Equatable {
        let id = UUID()
        let kind: ToastKind
        let detail: String
    }

    // MARK: Observable state

    private(set) var phase: Phase = .idle
    private(set) var toast: Toast?
    private(set) var successCount = 0
    private(set) var errorCount = 0
    var isErrorPresented = false
    private(set) var errorMessage = ""
    var isFileExporterPresented = false
    private(set) var fileForExporter: ExportedFile?
    private(set) var fileExporterTypes: [UTType] = []
    private(set) var fileExporterName: String?
    /// The finished file, offered through `ShareLink` (Share destination).
    private(set) var shareableResult: ExportResult?

    var isBusy: Bool { phase != .idle }

    // MARK: Private state

    @ObservationIgnored private var lastRequest: ExportSheetRequest?
    @ObservationIgnored private var lastResult: ExportResult?
    @ObservationIgnored private var work: Task<ExportResult, Error>?
    @ObservationIgnored private var flow: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var keepsScreenAwake = false

    /// Types with a dedicated `ExportedFile` representation; others are offered as a generic image.
    private static let specificFileTypes: [UTType] = [.heic, .heif, .jpeg, .png, .tiff]

    // MARK: Export

    func start(document: PhotoDocument, recipe: EditRecipe, options: ExportOptions, baseName: String,
               destination: ExportSheetDestination) {
        guard !isBusy else { return }
        shareableResult = nil
        let request = ExportSheetRequest(documentURL: document.url, recipe: recipe, options: options, baseName: baseName)

        // Same request as the file already written: deliver it again instead of re-rendering.
        if let lastRequest, lastRequest == request, let lastResult,
           FileManager.default.fileExists(atPath: lastResult.url.path(percentEncoded: false)) {
            // Busy right away, so a second tap before the delivery task runs can't save twice.
            if destination == .photos {
                phase = .savingToPhotos
            }
            beginBackgroundWork()
            flow = Task { [weak self] in
                await self?.deliver(lastResult, to: destination)
                self?.endBackgroundWork()
            }
            return
        }

        discardLastExport()
        phase = .exporting(.preparing)
        beginBackgroundWork()

        let progress: @Sendable (ExportStage) -> Void = { [weak self] stage in
            Task { @MainActor [weak self] in
                self?.advance(to: stage)
            }
        }
        let work = Task.detached(priority: .userInitiated) { () throws -> ExportResult in
            try Exporter.export(document: document, recipe: recipe, options: options, baseName: baseName,
                                progress: progress)
        }
        self.work = work
        flow = Task { [weak self] in
            let outcome: Result<ExportResult, Error>
            do {
                let result = try await work.value
                if work.isCancelled {
                    // Cancelled after the exporter's last checkpoint: don't deliver what the user stopped.
                    ExportSheetSession.removeExportFolder(of: result)
                    outcome = .failure(ExportError.cancelled)
                } else {
                    outcome = .success(result)
                }
            } catch {
                outcome = .failure(error)
            }
            guard let self else {
                if case .success(let result) = outcome {
                    ExportSheetSession.removeExportFolder(of: result)
                }
                return
            }
            self.work = nil
            switch outcome {
            case .success(let result):
                self.lastRequest = request
                self.lastResult = result
                await self.deliver(result, to: destination)
            case .failure(let error):
                self.fail(error)
            }
            self.endBackgroundWork()
        }
    }

    /// Cancels a running export (the exporter stops between stages and leaves nothing on disk).
    func cancel() {
        work?.cancel()
    }

    /// The sheet is closing: stop work and delete the temporary export (after a save to Photos that
    /// is still reading the file has finished).
    func tearDown() {
        work?.cancel()
        if isBusy, let flow {
            Task {
                await flow.value
                self.discardLastExport()
                self.endBackgroundWork()
            }
        } else {
            discardLastExport()
            endBackgroundWork()
        }
    }

    /// Options changed: a prepared Share file no longer matches them.
    func invalidateShare() {
        shareableResult = nil
    }

    func didSaveToFiles() {
        succeed(.savedToFiles)
    }

    func fail(_ error: Error) {
        phase = .idle
        if error is CancellationError { return }
        if let exportError = error as? ExportError, case .cancelled = exportError { return }
        errorMessage = error.localizedDescription
        errorCount += 1
        isErrorPresented = true
    }

    func clearToast(_ id: UUID) {
        if toast?.id == id { toast = nil }
    }

    // MARK: Delivery

    private func deliver(_ result: ExportResult, to destination: ExportSheetDestination) async {
        switch destination {
        case .photos:
            phase = .savingToPhotos
            do {
                try await PhotoLibrarySaver.save(result)
                phase = .idle
                succeed(.savedToPhotos, result: result)
            } catch {
                fail(error)
            }
        case .files:
            phase = .idle
            fileForExporter = ExportedFile(url: result.url, contentType: result.contentType)
            fileExporterTypes = Self.specificFileTypes.contains(result.contentType) ? [result.contentType] : [.image]
            fileExporterName = result.url.deletingPathExtension().lastPathComponent
            pendingDetail = Self.detail(for: result)
            isFileExporterPresented = true
        case .share:
            phase = .idle
            shareableResult = result
            AccessibilityNotification.Announcement(String(localized: "Ready to share")).post()
        }
    }

    /// Detail line for the Files toast (the file exporter reports back later).
    @ObservationIgnored private var pendingDetail = ""

    private func succeed(_ kind: ToastKind, result: ExportResult? = nil) {
        var detail = pendingDetail
        if let result {
            detail = Self.detail(for: result)
        }
        successCount += 1
        toast = Toast(kind: kind, detail: detail)
        let announcement: String
        switch kind {
        case .savedToPhotos: announcement = String(localized: "Saved to Photos")
        case .savedToFiles: announcement = String(localized: "Saved to Files")
        }
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func advance(to stage: ExportStage) {
        if case .exporting = phase {
            phase = .exporting(stage)
        }
    }

    // MARK: Housekeeping

    private func beginBackgroundWork() {
        if !keepsScreenAwake {
            UIApplication.shared.isIdleTimerDisabled = true
            keepsScreenAwake = true
        }
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Noor export") { [weak self] in
            // Out of background time: stop cleanly instead of being killed in the middle of a write.
            self?.work?.cancel()
            self?.endBackgroundWork()
        }
    }

    private func endBackgroundWork() {
        if keepsScreenAwake {
            UIApplication.shared.isIdleTimerDisabled = false
            keepsScreenAwake = false
        }
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    private func discardLastExport() {
        if let lastResult {
            ExportSheetSession.removeExportFolder(of: lastResult)
        }
        lastRequest = nil
        lastResult = nil
        shareableResult = nil
        fileForExporter = nil
    }

    /// Deletes the export's own temporary folder (`tmp/Exports/<uuid>/`) off the main actor.
    /// `Exporter.discard` only ever touches folders that `Exporter.export` created.
    nonisolated private static func removeExportFolder(of result: ExportResult) {
        Task.detached(priority: .utility) {
            Exporter.discard(result)
        }
    }

    /// "HEIF 10-bit · 6048 × 4024 · Display P3" for the success toast.
    nonisolated private static func detail(for result: ExportResult) -> String {
        let width = Int(result.pixelSize.width.rounded())
        let height = Int(result.pixelSize.height.rounded())
        return "\(family(of: result.contentType, bits: result.bitsPerComponent)) · \(width) × \(height) · \(result.colorSpaceName)"
    }

    nonisolated private static func family(of type: UTType, bits: Int) -> String {
        let name: String
        if type.conforms(to: .jpeg) {
            name = "JPEG"
        } else if type.conforms(to: .heic) || type.conforms(to: .heif) {
            name = "HEIF"
        } else if type.conforms(to: .png) {
            name = "PNG"
        } else if type.conforms(to: .tiff) {
            name = "TIFF"
        } else {
            name = (type.preferredFilenameExtension ?? "").uppercased()
        }
        return String(localized: "\(name) \(bits)-bit")
    }
}
