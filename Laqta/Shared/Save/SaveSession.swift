//
//  SaveSession.swift
//  Laqta — Shared
//
//  "Save to Laqta": prepares shared photos, videos, PDFs or a link, reads them on device,
//  spots items that are already in Laqta, suggests a folder, saves, and removes
//  originals from Photos when asked.
//

import Foundation
import Observation
import Photos
import SwiftData
import UIKit

nonisolated enum SaveInput: Sendable {
    /// Share Extension attachments.
    case provider(ProviderBox)
    /// A file picked in the app (with its Photos identifier).
    case file(url: URL, name: String?, assetID: String?)
    case link(URL)
}

@Observable
final class SaveSession {
    static let itemLimit = 30

    nonisolated enum RemovalOutcome: Equatable, Sendable {
        case notRequested
        case removed(Int)
        case waitingForApp
        case declined
    }

    enum Phase: Equatable {
        case preparing
        case analyzing
        case ready
        case saving
        case removingOriginals
        case done(DoneInfo)
        case failed(String)
    }

    struct DoneInfo: Equatable {
        let folderName: String
        let count: Int
        let isLink: Bool
        /// Nothing new was saved: everything was already in Laqta.
        let alreadySaved: Bool
        let note: String?
        let intelligenceNote: String?
    }

    struct FoundChip: Identifiable, Equatable {
        let text: String
        let systemImage: String
        var id: String { systemImage + text }
    }

    /// An item that is already in the library.
    struct DuplicateMatch: Equatable {
        let itemID: UUID
        let folderID: UUID?
        let folderName: String
        let addedAt: Date
    }

    private(set) var phase: Phase = .preparing
    private(set) var statusText = "Getting ready…"
    private(set) var media: [StagedMedia] = []
    private(set) var link: LinkDraft?
    private(set) var linkPreview: UIImage?
    private(set) var found: [FoundChip] = []
    private(set) var suggestion: FolderSuggestion?
    private(set) var failedCount = 0
    private(set) var failureMessage: String?
    private(set) var queuedFolderID: UUID?
    private(set) var incomingLinkURL: URL?
    private(set) var hasIncomingMedia = false
    /// Kinds of the incoming media, known before staging finishes.
    private(set) var incomingKinds: Set<MediaKind> = []
    /// Stays the same after saving, for the preview card.
    private(set) var stagedCounts: [MediaKind: Int] = [:]
    private(set) var stagedBytes = 0
    private(set) var firstPreview: UIImage?
    private(set) var firstKind: MediaKind?
    private(set) var firstDuration: Double?
    private(set) var duplicates: [UUID: DuplicateMatch] = [:]
    private(set) var linkDuplicate: DuplicateMatch?

    var deleteOriginals: Bool
    var extractEverything: Bool
    var skipDuplicates: Bool
    let fixedFolderID: UUID?

    @ObservationIgnored private var preliminary: [UUID: ShotAnalysis] = [:]
    @ObservationIgnored private var labelIdentifiers: [String] = []
    @ObservationIgnored private var sharedPageURL: String?
    private let inputs: [SaveInput]
    private let onFinish: () -> Void
    private let onCancel: () -> Void
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var didSave = false
    @ObservationIgnored private var didCancel = false
    @ObservationIgnored private var didFinish = false
    /// The quick reading on this device got to the end before the save.
    @ObservationIgnored private var didFinishAnalysis = false

    init(inputs: [SaveInput], fixedFolderID: UUID? = nil, onFinish: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.inputs = inputs
        self.fixedFolderID = fixedFolderID
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.deleteOriginals = AppGroup.bool(SettingsKey.autoDeleteFromPhotos)
        self.extractEverything = AppGroup.bool(SettingsKey.extractLinks)
        self.skipDuplicates = AppGroup.bool(SettingsKey.skipDuplicates)
    }

    // MARK: State

    var isLinkSession: Bool { incomingLinkURL != nil && !hasIncomingMedia }

    var stagedCount: Int { stagedCounts.values.reduce(0, +) }

    var itemCount: Int { max(stagedCount, isLinkSession ? 1 : 0) }

    /// How many items a save would add.
    var newItemCount: Int {
        if isLinkSession { return skipDuplicates && linkDuplicate != nil ? 0 : 1 }
        return skipDuplicates ? media.filter { duplicates[$0.id] == nil }.count : media.count
    }

    var duplicateCount: Int {
        isLinkSession ? (linkDuplicate == nil ? 0 : 1) : duplicates.count
    }

    var allAreDuplicates: Bool {
        duplicateCount > 0 && duplicateCount == max(itemCount, media.count)
    }

    /// Photos and videos can have originals in Photos; PDFs can't.
    var canDeleteOriginals: Bool {
        incomingKinds.contains(.photo) || incomingKinds.contains(.video)
    }

    var isBusy: Bool {
        switch phase {
        case .saving, .removingOriginals, .done: true
        default: false
        }
    }

    var isWorking: Bool {
        phase == .preparing || phase == .analyzing
    }

    var mediaByteCount: Int { stagedBytes }

    // MARK: Preparing

    func start(context: ModelContext) async {
        guard !didStart, !didCancel, !Task.isCancelled else { return }
        didStart = true

        var providerMedia: [(box: ProviderBox, kind: MediaKind)] = []
        var files: [(url: URL, name: String?, assetID: String?)] = []
        var linkURL: URL?
        for input in inputs {
            guard !didCancel, !Task.isCancelled else { return }
            switch input {
            case let .provider(box):
                switch ItemProviderLoader.kind(of: box.provider) {
                case let .media(kind)?:
                    providerMedia.append((box, kind))
                case .url?, .text?:
                    if linkURL == nil { linkURL = await ItemProviderLoader.loadURL(box) }
                case nil:
                    break
                }
            case let .file(url, name, assetID):
                files.append((url, name, assetID))
            case let .link(url):
                linkURL = url
            }
        }

        guard !didCancel, !Task.isCancelled else { return }

        let total = providerMedia.count + files.count
        hasIncomingMedia = total > 0
        incomingLinkURL = linkURL
        incomingKinds = Set(providerMedia.map(\.kind))
        for file in files {
            if let kind = MediaInspector.kind(forFileAt: file.url) { incomingKinds.insert(kind) }
        }

        if hasIncomingMedia {
            if total > Self.itemLimit {
                failureMessage = MediaError.tooManyItems(limit: Self.itemLimit).errorDescription
                failedCount += total - Self.itemLimit
            }
            // A page link shared together with a screenshot becomes its source.
            sharedPageURL = linkURL?.absoluteString
            statusText = "Preparing…"
            await stageMedia(
                providers: Array(providerMedia.prefix(Self.itemLimit)),
                files: Array(files.prefix(max(0, Self.itemLimit - providerMedia.count)))
            )
            guard !didCancel, !Task.isCancelled else { return }
            guard !media.isEmpty else {
                phase = .failed(failureMessage ?? noMediaMessage)
                return
            }
            findDuplicates(context: context)
            phase = .analyzing
            // A folder picked while the items were still arriving: save now. Laqta reads
            // what's inside anything saved unread, so nothing is lost by not waiting.
            if await saveQueuedFolder(context: context) { return }
            statusText = "Analyzing on this \(LaqtaDevice.name)…"
            await analyzeMedia(context: context)
        } else if let linkURL {
            statusText = "Opening the link…"
            let draft = await LinkReader.read(linkURL, deep: false)
            guard !didCancel, !Task.isCancelled else {
                if let image = draft.image { MediaStore.discard(image) }
                return
            }
            link = draft
            findLinkDuplicate(draft, originalURL: linkURL, context: context)
            found = chips(for: draft)
            phase = .analyzing
            // The link is read; its picture is decoration and never holds a save back.
            if await saveQueuedFolder(context: context) { return }
            statusText = "Finding what's inside…"
            suggest(context: context)
            // Once a folder is tapped the picture is moot: the save has moved its file,
            // and fetching it again from the web would be work for nothing.
            if !didSave, let image = draft.image, let thumbnailURL = image.thumbnailURL,
               let preview = await ImageLoader.image(at: thumbnailURL, maxPixelSize: 480) {
                if !didSave { linkPreview = preview.image }
            } else if !didSave, let remote = draft.imageURL.flatMap(URL.init(string:)),
                      let preview = await RemoteImageLoader.image(at: remote, maxPixelSize: 480) {
                if !didSave { linkPreview = preview.image }
            }
        } else {
            phase = .failed("There's nothing Laqta can save here. Share a photo, a video, a PDF or a link.")
            return
        }

        // Still reading, and nothing else happened meanwhile: a failure shown in the
        // meantime (a tap after the thirty days ran out) stays on screen.
        guard !didSave, !didCancel, !Task.isCancelled, phase == .analyzing else { return }
        phase = .ready
        if let queuedFolderID, let folder = LaqtaStore.folder(with: queuedFolderID, context: context) {
            await save(to: folder, context: context)
        }
    }

    /// Saves into the folder picked while the items were still on their way, if there
    /// is one. True when that was the end of it — saved, or failed for a reason shown.
    private func saveQueuedFolder(context: ModelContext) async -> Bool {
        guard let queued = queuedFolderID else { return false }
        if let folder = LaqtaStore.folder(with: queued, context: context) {
            await save(to: folder, context: context)
            if didSave || phase != .analyzing { return true }
        }
        // The folder went to Recently Deleted meanwhile: the sheet stays, pick another.
        queuedFolderID = nil
        return false
    }

    private var noMediaMessage: String {
        if incomingKinds == [.video] { return "Laqta couldn't read the shared video." }
        if incomingKinds == [.document] { return "Laqta couldn't open the shared PDF." }
        return "Laqta couldn't read the shared item."
    }

    private func stageMedia(providers: [(box: ProviderBox, kind: MediaKind)], files: [(url: URL, name: String?, assetID: String?)]) async {
        let total = providers.count + files.count
        var index = 0
        for entry in providers {
            guard !didCancel, !Task.isCancelled else { return }
            index += 1
            if total > 3 { statusText = "Preparing \(index) of \(total)…" }
            do {
                let item = try await ItemProviderLoader.stage(entry.box, kind: entry.kind)
                await addStaged(item)
            } catch {
                record(error)
            }
        }
        for file in files {
            guard !didCancel, !Task.isCancelled else { return }
            index += 1
            if total > 3 { statusText = "Preparing \(index) of \(total)…" }
            do {
                let item = try await MediaStore.stageFile(at: file.url, originalName: file.name, sourceAssetID: file.assetID)
                await addStaged(item)
            } catch {
                record(error)
            }
        }
    }

    private func record(_ error: any Error) {
        failedCount += 1
        if let mediaError = error as? MediaError, case .notEnoughSpace = mediaError {
            failureMessage = mediaError.errorDescription
        }
        DebugLog.write("save: staging failed \(error)")
    }

    private func addStaged(_ item: StagedMedia) async {
        guard !didCancel, !Task.isCancelled else {
            MediaStore.discard(item)
            return
        }
        media.append(item)
        stagedCounts[item.kind, default: 0] += 1
        stagedBytes += item.byteCount
        if firstPreview == nil, let thumbnailURL = item.thumbnailURL,
           let preview = await ImageLoader.image(at: thumbnailURL, maxPixelSize: 360) {
            firstPreview = preview.image
            firstKind = item.kind
            firstDuration = item.info.duration
        }
    }

    // MARK: Duplicates

    private func findDuplicates(context: ModelContext) {
        let hashes = media.compactMap(\.contentHash)
        let captureKeys = media.compactMap(\.captureKey)
        let assetIDs = media.compactMap(\.sourceAssetID)
        guard !hashes.isEmpty || !captureKeys.isEmpty || !assetIDs.isEmpty else { return }
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { shot in
            shot.deletedAt == nil && (
                (shot.contentHash.flatMap { hashes.contains($0) } ?? false)
                || (shot.captureKey.flatMap { captureKeys.contains($0) } ?? false)
                || (shot.sourceAssetID.flatMap { assetIDs.contains($0) } ?? false)
            )
        })
        guard let fetched = try? context.fetch(descriptor) else { return }
        // A stale record is not a retained copy. Import it again instead of skipping
        // it and potentially deleting the only remaining original from Photos.
        let existing = fetched.filter { $0.hasMediaFile && CloudFiles.exists($0.fileURL) }
        guard !existing.isEmpty else { return }
        let names = folderNames(context: context)
        for item in media {
            let match = existing.first { shot in
                (item.contentHash != nil && shot.contentHash == item.contentHash)
                    || (item.captureKey != nil && shot.captureKey == item.captureKey)
                    || (item.sourceAssetID != nil && shot.sourceAssetID == item.sourceAssetID)
            }
            if let match {
                duplicates[item.id] = DuplicateMatch(
                    itemID: match.id,
                    folderID: match.folderID,
                    folderName: match.folderID.flatMap { names[$0] } ?? "Laqta",
                    addedAt: match.addedAt
                )
            }
        }
    }

    private func findLinkDuplicate(_ draft: LinkDraft, originalURL: URL, context: ModelContext) {
        let keys = Array(Set([DuplicateKey.link(for: draft.url), DuplicateKey.link(for: originalURL)]))
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { shot in
            shot.deletedAt == nil && (shot.linkKey.flatMap { keys.contains($0) } ?? false)
        })
        guard let match = (try? context.fetch(descriptor))?.max(by: { $0.addedAt < $1.addedAt }) else { return }
        let names = folderNames(context: context)
        linkDuplicate = DuplicateMatch(
            itemID: match.id,
            folderID: match.folderID,
            folderName: match.folderID.flatMap { names[$0] } ?? "Laqta",
            addedAt: match.addedAt
        )
    }

    private func folderNames(context: ModelContext) -> [UUID: String] {
        let folders = LaqtaStore.foldersByUpdate(context)
        return Dictionary(folders.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Analysis

    private func analyzeMedia(context: ModelContext) async {
        guard AppGroup.bool(SettingsKey.analyzeShots) else {
            found = basicChips()
            suggest(context: context)
            return
        }
        var chips: [FoundChip] = []
        var textForSuggestion = ""
        let candidates = media.filter { duplicates[$0.id] == nil }
        for item in (candidates.isEmpty ? media : candidates).prefix(3) {
            // A folder was picked: the save went ahead, and what's left is Laqta's to read.
            guard !didSave, !didCancel, !Task.isCancelled else { return }
            var options = PhotoAnalysisOptions.quick
            options.readText = AppGroup.bool(SettingsKey.readText)
            options.findSource = AppGroup.bool(SettingsKey.findSource)

            var result: PhotoAnalysisResult
            switch item.kind {
            case .photo:
                let input = PhotoAnalysisInput(
                    imageURL: item.thumbnailURL ?? item.fileURL,
                    fileURL: item.fileURL,
                    isScreenshot: item.info.isScreenCapture,
                    capturedAt: item.info.capturedAt,
                    addedAt: .now,
                    pixelWidth: item.info.pixelWidth,
                    pixelHeight: item.info.pixelHeight,
                    sharedURL: sharedPageURL
                )
                result = await QuickAnalyzer.analyzePhoto(input, options: options)
            case .video:
                let input = VideoAnalysisInput(
                    fileURL: item.fileURL,
                    duration: item.info.duration ?? 0,
                    isScreenRecording: item.info.isScreenCapture,
                    capturedAt: item.info.capturedAt,
                    addedAt: .now,
                    latitude: item.info.latitude,
                    longitude: item.info.longitude,
                    cameraModel: item.info.cameraModel
                )
                result = await VideoAnalyzer.analyze(input, frameCount: 2, options: options)
            case .document:
                let input = DocumentAnalysisInput(
                    fileURL: item.fileURL,
                    title: item.info.title,
                    fileName: item.originalName,
                    pageCount: item.info.pageCount ?? 0,
                    createdAt: item.info.capturedAt,
                    addedAt: .now
                )
                result = await DocumentAnalyzer.analyze(input, maxPages: 3, ocrPages: 0, options: options).result
            }

            guard !didSave, !didCancel, !Task.isCancelled else { return }
            var analysis = result.analysis
            if let coordinate = result.coordinate, AppGroup.bool(SettingsKey.recognizePlaces) {
                analysis.place = await withTimeout(seconds: 4) {
                    await PlaceResolver.place(near: coordinate.latitude, coordinate.longitude)
                }
                guard !didSave, !didCancel, !Task.isCancelled else { return }
            }
            preliminary[item.id] = analysis
            labelIdentifiers.append(contentsOf: result.labelIdentifiers)
            labelIdentifiers.append(contentsOf: suggestionLabels(for: result.labelIdentifiers))
            if let place = analysis.place, Self.isAbroad(place) {
                // Taken in another country: most likely a trip.
                labelIdentifiers.append(contentsOf: ["airplane", "resort", "beach"])
                textForSuggestion += "\ntravel trip"
            }
            textForSuggestion += "\n" + [analysis.title, analysis.category, analysis.place?.name, analysis.place?.detail, analysis.text.map { String($0.prefix(3_000)) }]
                .compactMap { $0 }
                .joined(separator: "\n")
            if chips.isEmpty {
                chips = self.chips(for: analysis, item: item)
            }
        }
        guard !didSave, !didCancel, !Task.isCancelled else { return }
        found = Array(chips.prefix(4))
        suggest(context: context, text: textForSuggestion)
        didFinishAnalysis = true
    }

    /// Document types lean toward the matching folders.
    private func suggestionLabels(for identifiers: [String]) -> [String] {
        var labels: [String] = []
        for identifier in identifiers {
            switch DocumentHeuristics.Kind(rawValue: identifier) {
            case .boardingPass?, .booking?: labels.append(contentsOf: ["airplane", "suitcase"])
            case .ticket?: labels.append("ticket")
            case .invoice?, .receipt?, .contract?, .statement?, .certificate?, .form?: labels.append("document")
            case .menu?: labels.append("food")
            default: break
            }
        }
        return labels
    }

    static func isAbroad(_ place: PlaceRef) -> Bool {
        guard let detail = place.detail, place.origin == "GPS" || place.origin == "Landmark",
              let region = Locale.current.region?.identifier,
              let home = Locale(identifier: "en_US").localizedString(forRegionCode: region) else { return false }
        let country = detail.split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !country.isEmpty else { return false }
        return country.localizedCaseInsensitiveCompare(home) != .orderedSame && !detail.localizedCaseInsensitiveContains(home)
    }

    private func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: Found

    private func basicChips() -> [FoundChip] {
        guard let item = media.first else { return [] }
        return [kindChip(for: item)]
    }

    private func kindChip(for item: StagedMedia) -> FoundChip {
        switch item.kind {
        case .photo:
            return FoundChip(text: item.info.isScreenCapture ? "Screenshot" : "Photo", systemImage: item.info.isScreenCapture ? "camera.viewfinder" : "photo")
        case .video:
            let label = item.info.isScreenCapture ? "Screen recording" : "Video"
            let length = item.info.duration.map { " · \(LaqtaFormat.duration($0))" } ?? ""
            return FoundChip(text: label + length, systemImage: item.info.isScreenCapture ? "record.circle" : "video")
        case .document:
            let pages = item.info.pageCount.map { " · \(LaqtaFormat.count($0, "page", "pages"))" } ?? ""
            return FoundChip(text: "PDF" + pages, systemImage: "doc.richtext")
        }
    }

    private func chips(for analysis: ShotAnalysis, item: StagedMedia) -> [FoundChip] {
        var chips: [FoundChip] = []
        if item.kind != .photo {
            chips.append(kindChip(for: item))
        }
        if let place = analysis.place {
            chips.append(FoundChip(text: place.name, systemImage: place.category == "Location" ? "mappin.and.ellipse" : "building.columns"))
        }
        let generic: Set<String> = ["Place", "Text", "Video", "Screen recording", "Document"]
        if let category = analysis.category, !generic.contains(category) {
            chips.append(FoundChip(text: category, systemImage: item.kind == .document ? "doc.text.magnifyingglass" : "text.viewfinder"))
        }
        let interesting: Set<DetectedEntity.Kind> = [.date, .price, .flight]
        for entity in analysis.entities.filter({ interesting.contains($0.kind) }).prefix(3) {
            chips.append(FoundChip(text: entity.display, systemImage: entity.systemImage))
        }
        if chips.count < 2, let label = analysis.labels.first, !chips.contains(where: { $0.text == label }) {
            chips.append(FoundChip(text: label, systemImage: "photo"))
        }
        if chips.isEmpty, let text = analysis.text, !text.isEmpty {
            chips.append(FoundChip(text: "Text found", systemImage: "text.viewfinder"))
        }
        return chips
    }

    private func chips(for draft: LinkDraft) -> [FoundChip] {
        var chips: [FoundChip] = []
        if let duration = draft.duration, draft.form == .video {
            chips.append(FoundChip(text: "\(draft.form.label) · \(LaqtaFormat.duration(duration))", systemImage: draft.form.systemImage))
        } else {
            chips.append(FoundChip(text: draft.form.label, systemImage: draft.form.systemImage))
        }
        if draft.chapters.count >= 2 {
            chips.append(FoundChip(text: LaqtaFormat.count(draft.chapters.count, "chapter", "chapters"), systemImage: "list.bullet"))
        }
        if !draft.placeNames.isEmpty {
            chips.append(FoundChip(text: LaqtaFormat.count(draft.placeNames.count, "place", "places"), systemImage: "mappin.and.ellipse"))
        }
        if !draft.prices.isEmpty {
            chips.append(FoundChip(text: draft.prices.count == 1 ? draft.prices[0].value : "Prices", systemImage: "tag"))
        }
        return chips
    }

    // MARK: Suggestion

    private func suggest(context: ModelContext, text: String = "") {
        guard fixedFolderID == nil else { return }
        let folders = LibraryWriter.snapshots(context)
        let lastUsed = AppGroup.defaults.string(forKey: SettingsKey.lastUsedFolderID).flatMap(UUID.init(uuidString:))
        if let link, link.isYouTube {
            // YouTube details aren't used to make suggestions; where you keep videos is.
            suggestion = youTubeSuggestion(folders: folders, lastUsed: lastUsed, context: context)
        } else if let link {
            let content = [link.title, link.site, link.author ?? "", link.details ?? "", link.placeNames.joined(separator: " ")]
                .joined(separator: "\n")
            let lead = link.placeNames.isEmpty ? link.form.label : "\(link.form.label) · \(LaqtaFormat.count(link.placeNames.count, "place", "places"))"
            suggestion = FolderSuggester.suggest(
                text: content,
                title: link.title,
                labels: [],
                host: link.site,
                isLink: true,
                kindLabel: lead,
                folders: folders,
                lastUsedFolderID: lastUsed
            )
        } else {
            let firstItem = media.first { duplicates[$0.id] == nil } ?? media.first
            let first = firstItem.flatMap { preliminary[$0.id] }
            let kind: String
            if first?.place != nil, first?.place?.category != "Location", firstItem?.kind == .photo {
                kind = "Landmark photo"
            } else if let category = first?.category {
                kind = category
            } else {
                kind = firstItem.map { kindChip(for: $0).text } ?? "Photo"
            }
            let noun: String
            switch firstItem?.kind {
            case .video?: noun = "videos"
            case .document?: noun = "documents"
            default: noun = "shots"
            }
            suggestion = FolderSuggester.suggest(
                text: text,
                title: first?.title ?? "",
                labels: labelIdentifiers,
                host: nil,
                isLink: false,
                kindLabel: kind,
                folders: folders,
                lastUsedFolderID: lastUsed,
                itemNoun: noun
            )
        }
    }

    private func youTubeSuggestion(folders: [FolderSnapshot], lastUsed: UUID?, context: ModelContext) -> FolderSuggestion {
        let open = Set(folders.filter { !$0.isLocked }.map(\.id))
        let linkKind: Int? = ItemKind.link.rawValue
        var descriptor = FetchDescriptor<Shot>(
            predicate: #Predicate<Shot> { item in
                item.kindRaw == linkKind && item.deletedAt == nil
            },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 300
        let recent = ((try? context.fetch(descriptor)) ?? []).first { item in
            item.isYouTube && (item.folderID.map(open.contains) ?? false)
        }
        if let folderID = recent?.folderID {
            return FolderSuggestion(target: .existing(folderID), reason: "Video · where you keep YouTube videos")
        }
        if let lastUsed, open.contains(lastUsed) {
            return FolderSuggestion(target: .existing(lastUsed), reason: "Video · your last folder")
        }
        return FolderSuggestion(target: .new(name: "Videos", symbol: "play.rectangle", tone: .dusk), reason: "Video · a folder for the videos you save")
    }

    // MARK: Saving

    func choose(_ folder: Folder, context: ModelContext) async {
        switch phase {
        case .preparing:
            // Still on their way in: they go into this folder the moment they arrive.
            queuedFolderID = folder.id
        case .analyzing, .ready:
            // Reading what's inside never holds a save back — Laqta finishes that later.
            await save(to: folder, context: context)
        default:
            break
        }
    }

    /// Creates the suggested new folder, then saves into it.
    func createSuggestedFolder(context: ModelContext) async {
        // The category's own tone is passed over: the palette picks from what
        // is still free, leaning toward the same meaning anyway.
        guard case let .new(name, symbol, _)? = suggestion?.target else { return }
        let folder = LibraryWriter.createFolder(name: name, symbol: symbol, locked: false, context: context)
        try? context.save()
        await choose(folder, context: context)
    }

    func save(to folder: Folder, context: ModelContext) async {
        guard !didSave, !didCancel, !Task.isCancelled, !folder.isInTrash else { return }
        // The last word on the thirty days. Every screen checks before it gets here,
        // so this only catches a way in that nobody thought of.
        guard Entitlement.canAddThings else {
            phase = .failed(String(localized: "Your thirty days are over. Open Laqta to buy it, and saving starts again."))
            return
        }
        if phase == .preparing {
            queuedFolderID = folder.id
            return
        }
        didSave = true
        phase = .saving
        let deleting = deleteOriginals && canDeleteOriginals
        var saved: [Shot] = []
        var skipped: [StagedMedia] = []
        var skippedLink = false

        if let link, media.isEmpty {
            if skipDuplicates, linkDuplicate != nil {
                skippedLink = true
                if let image = link.image { MediaStore.discard(image) }
            } else {
                saved.append(LibraryWriter.addLink(link, to: folder, deep: extractEverything, context: context))
            }
        } else {
            for item in media {
                if skipDuplicates, duplicates[item.id] != nil {
                    skipped.append(item)
                    continue
                }
                do {
                    let analysis = preliminary[item.id]
                    let shot = try LibraryWriter.addMedia(
                        item,
                        to: folder,
                        deleteOriginal: deleting,
                        preliminary: analysis,
                        sourceName: analysis?.source?.app,
                        context: context
                    )
                    saved.append(shot)
                } catch {
                    MediaStore.discard(item)
                    failedCount += 1
                }
            }
            media.removeAll()
        }

        do {
            try context.save()
        } catch {
            // The file moves happen before the database save. Roll them back as well
            // so a failed save cannot leave orphaned files or pending Photos deletion.
            let committed = saved.map { StoredFiles(fileName: $0.fileName, thumbnailName: $0.thumbnailName) }
            context.rollback()
            for files in committed {
                MediaStore.deleteStoredFiles(fileName: files.fileName, thumbnailName: files.thumbnailName)
            }
            for item in skipped { MediaStore.discard(item) }
            phase = .failed("Laqta couldn't save: \(error.localizedDescription)")
            return
        }
        guard !saved.isEmpty || !skipped.isEmpty || skippedLink else {
            phase = .failed(failureMessage ?? "Laqta couldn't save any of the selected items. Try importing them again.")
            return
        }
        if !saved.isEmpty {
            AppGroup.defaults.set(folder.id.uuidString, forKey: SettingsKey.lastUsedFolderID)
            AppGroup.markExternalChange()
        }

        // Originals of skipped duplicates can go too: Laqta already has a copy.
        var removal: RemovalOutcome = .notRequested
        let removable = saved.filter { !$0.isDocument && !$0.isLink }
        if deleting, !removable.isEmpty || !skipped.isEmpty {
            removal = await removeOriginals(of: removable, skipped: skipped.filter { $0.kind != .document }, context: context)
        }
        for item in skipped {
            MediaStore.discard(item)
        }

        let isLink = link != nil && stagedCount == 0
        let alreadySaved = saved.isEmpty && (!skipped.isEmpty || skippedLink)
        let existingFolder = linkDuplicate?.folderName ?? skipped.first.flatMap { duplicates[$0.id]?.folderName }
        phase = .done(DoneInfo(
            folderName: alreadySaved ? (existingFolder ?? folder.name) : folder.name,
            count: saved.count,
            isLink: isLink,
            alreadySaved: alreadySaved,
            note: note(for: removal, isLink: isLink, skipped: skippedLink ? 1 : skipped.count, alreadySaved: alreadySaved),
            intelligenceNote: alreadySaved ? nil : intelligenceNote(isLink: isLink)
        ))
        // Long enough to see where it went, and no longer; a tap on the card closes it
        // sooner. A line worth reading — originals removed, already saved, skipped or
        // unreadable items — gets a little more.
        let hasNews = removal != .notRequested || alreadySaved || !skipped.isEmpty || failedCount > 0
        try? await Task.sleep(for: .seconds(hasNews ? 1.2 : 0.6))
        finishOnce()
    }

    /// Leaves once, whether the moment ran out or the card was tapped first.
    private func finishOnce() {
        guard !didFinish else { return }
        didFinish = true
        onFinish()
    }

    private func note(for removal: RemovalOutcome, isLink: Bool, skipped: Int, alreadySaved: Bool) -> String? {
        var parts: [String] = []
        if skipped > 0, !alreadySaved {
            parts.append(skipped == 1 ? "1 item was already in Laqta" : "\(skipped) items were already in Laqta")
        }
        switch removal {
        case .notRequested:
            if !isLink, !alreadySaved, canDeleteOriginals { parts.append("The original stays in Photos") }
        case .removed:
            parts.append("The original was moved to Recently Deleted")
        case .waitingForApp:
            parts.append("Laqta will finish removing the original when you open it")
        case .declined:
            parts.append("The original stays in Photos")
        }
        if failedCount > 0 {
            parts.append(failedCount == 1 ? "1 item couldn't be read" : "\(failedCount) items couldn't be read")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func intelligenceNote(isLink: Bool) -> String? {
        if isLink {
            guard let link else { return nil }
            if link.isYouTube {
                return link.isUnavailable ? "Saved the link only" : "Details from YouTube"
            }
            if extractEverything {
                return found.count > 1 ? "Reading everything inside" : "Summary coming up in Laqta"
            }
            return link.title.isEmpty ? nil : "Title and preview saved"
        }
        guard AppGroup.bool(SettingsKey.analyzeShots) else { return nil }
        // Saved before the quick reading here was done: Laqta reads it instead.
        guard didFinishAnalysis else { return stagedCount > 1 ? "Laqta reads them next" : "Laqta reads it next" }
        if let chip = found.first(where: { !$0.text.hasPrefix("PDF") && !$0.text.hasPrefix("Video") && !$0.text.hasPrefix("Screen recording") }) {
            return "Found \(chip.text)"
        }
        return incomingKinds.contains(.video) ? "Laqta reads the video next" : "Analyzed on this \(LaqtaDevice.name)"
    }

    private func removeOriginals(of shots: [Shot], skipped: [StagedMedia], context: ModelContext) async -> RemovalOutcome {
        guard PhotoLibraryService.canModifyLibrary else {
            if AppGroup.isRunningInExtension {
                DebugLog.write("save: Photos status \(PhotoLibraryService.authorizationStatus.rawValue), deferring to app")
                return shots.isEmpty ? .notRequested : .waitingForApp
            }
            _ = await PhotoLibraryService.requestAccess()
            guard PhotoLibraryService.canModifyLibrary else { return shots.isEmpty ? .notRequested : .waitingForApp }
            return await removeOriginals(of: shots, skipped: skipped, context: context)
        }
        phase = .removingOriginals

        var fingerprints = shots.map(\.fingerprint)
        var skippedOwners: [UUID: UUID] = [:]
        for item in skipped {
            guard let match = duplicates[item.id] else { continue }
            fingerprints.append(Self.fingerprint(for: item))
            skippedOwners[item.id] = match.itemID
        }
        let matches = await PhotoLibraryService.resolve(fingerprints)
        let identifiers = Array(Set(matches.values))
        guard !identifiers.isEmpty else { return shots.isEmpty ? .notRequested : .waitingForApp }

        let outcome: RemovalOutcome
        let existing = LaqtaStore.items(withIDs: Array(skippedOwners.values), context: context)
        do {
            try await PhotoLibraryService.deleteAssets(withIdentifiers: identifiers)
            for shot in shots where matches[shot.id] != nil {
                shot.libraryStatus = .deleted
            }
            for (stagedID, ownerID) in skippedOwners where matches[stagedID] != nil {
                existing.first { $0.id == ownerID }?.libraryStatus = .deleted
            }
            outcome = .removed(identifiers.count)
        } catch {
            DebugLog.write("save: delete failed \(error)")
            guard PhotoLibraryService.isUserCancellation(error) else { return .waitingForApp }
            for shot in shots where matches[shot.id] != nil {
                shot.libraryStatus = .declined
            }
            outcome = .declined
        }
        try? context.save()
        AppGroup.markExternalChange()
        return outcome
    }

    static func fingerprint(for item: StagedMedia) -> AssetFingerprint {
        AssetFingerprint(
            shotID: item.id,
            knownAssetID: item.sourceAssetID,
            originalName: item.originalName,
            pixelWidth: item.info.pixelWidth,
            pixelHeight: item.info.pixelHeight,
            capturedAt: item.info.capturedAt,
            captureOffsetKnown: item.info.captureOffsetKnown,
            isScreenshot: item.info.isScreenCapture,
            addedAt: .now,
            isVideo: item.kind == .video,
            duration: item.info.duration
        )
    }

    // MARK: Leaving

    func cancel() {
        guard !isBusy, !didCancel else { return }
        didCancel = true
        for item in media {
            MediaStore.discard(item)
        }
        media.removeAll()
        if !didSave, let image = link?.image {
            MediaStore.discard(image)
        }
        onCancel()
    }

    /// The done card was tapped. A save still being written finishes first and then
    /// closes by itself; leaving the extension in the middle of it could cut it short.
    func close() {
        switch phase {
        case .done:
            finishOnce()
        case .removingOriginals, .saving:
            break
        default:
            cancel()
        }
    }
}
