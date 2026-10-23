//
//  IntelligenceCenter.swift
//  Laqta
//
//  Runs analysis in the app: new photos, videos, PDFs and links, transcripts,
//  summaries, questions and Insights. Works in the foreground and in background tasks.
//

import Foundation
import Observation
import SwiftData

@Observable
final class IntelligenceCenter {
    struct ChatMessage: Identifiable, Equatable {
        let id = UUID()
        let fromUser: Bool
        let text: String
        var animate: Bool
    }

    /// Background work avoids the Neural Engine and the language model.
    nonisolated enum Mode: Sendable {
        case foreground
        case background
    }

    private(set) var running: Set<UUID> = []
    private(set) var summarizing: Set<UUID> = []
    private(set) var transcribing: Set<UUID> = []
    /// Results that should type in the first time they appear.
    private(set) var fresh: Set<UUID> = []
    private(set) var asking: Set<UUID> = []
    private(set) var conversations: [UUID: [ChatMessage]] = [:]
    private(set) var hasInsights = false

    @ObservationIgnored private var queueTask: Task<Void, Never>?
    @ObservationIgnored private var requeue = false

    var modelAvailable: Bool { AIWriter.isAvailable }
    var modelMessage: String { AIWriter.unavailableMessage }

    func isRunning(_ id: UUID) -> Bool { running.contains(id) }
    func isTranscribing(_ id: UUID) -> Bool { transcribing.contains(id) }
    func isSummarizing(_ id: UUID) -> Bool { summarizing.contains(id) }
    func isFresh(_ id: UUID) -> Bool { fresh.contains(id) }
    func isAsking(_ id: UUID) -> Bool { asking.contains(id) }
    func conversation(for id: UUID) -> [ChatMessage] { conversations[id] ?? [] }

    func markSeen(_ id: UUID) {
        fresh.remove(id)
    }

    // MARK: Queue

    func processPending(context: ModelContext) {
        guard !AppEnvironment.isRunningTests else { return }
        guard queueTask == nil else {
            requeue = true
            return
        }
        queueTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.requeue = false
                await self.drainQueue(context: context, mode: .foreground)
            } while self.requeue && !Task.isCancelled
            self.refreshInsights(context: context)
            self.queueTask = nil
        }
    }

    /// Items still waiting to be analyzed.
    func pendingCount(context: ModelContext) -> Int {
        let pendingRaw: Int? = AnalysisState.pending.rawValue
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> {
            ($0.analysisStateRaw == nil || $0.analysisStateRaw == pendingRaw) && $0.deletedAt == nil
        })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Analysis inside a background task. Returns when the queue is empty or the task is cancelled.
    func runInBackground(context: ModelContext, progress: (@MainActor (Int, Int) -> Void)? = nil) async {
        queueTask?.cancel()
        queueTask = nil
        await drainQueue(context: context, mode: .background, progress: progress)
        refreshInsights(context: context)
    }

    private func drainQueue(context: ModelContext, mode: Mode, progress: (@MainActor (Int, Int) -> Void)? = nil) async {
        var attempted = Set<UUID>()
        let total = pendingCount(context: context)
        while !Task.isCancelled {
            let pendingRaw: Int? = AnalysisState.pending.rawValue
            var descriptor = FetchDescriptor<Shot>(
                predicate: #Predicate<Shot> {
                    ($0.analysisStateRaw == nil || $0.analysisStateRaw == pendingRaw) && $0.deletedAt == nil
                },
                sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 40
            let batch = ((try? context.fetch(descriptor)) ?? []).filter { !attempted.contains($0.id) }
            guard !batch.isEmpty else { break }
            for item in batch {
                guard !Task.isCancelled else { break }
                attempted.insert(item.id)
                await analyze(item, context: context, mode: mode)
                progress?(attempted.count, max(total, attempted.count))
            }
        }
    }

    /// Runs the right analysis for the item's kind.
    func analyze(_ item: Shot, context: ModelContext, mode: Mode = .foreground) async {
        switch item.kind {
        case .link:
            if item.deepAnalysis == true {
                await analyzeLink(item, context: context, mode: mode)
            } else {
                item.analysisState = .shallow
                context.commit(.analysis)
            }
        case .photo:
            guard AppGroup.bool(SettingsKey.analyzeShots) else { return }
            await analyzePhoto(item, context: context, mode: mode)
        case .video:
            guard AppGroup.bool(SettingsKey.analyzeShots) else { return }
            await analyzeVideo(item, context: context, mode: mode)
        case .document:
            guard AppGroup.bool(SettingsKey.analyzeShots) else { return }
            await analyzeDocument(item, context: context, mode: mode)
        }
    }

    /// The media file is on this device (not still in iCloud).
    private func mediaIsReady(_ item: Shot) -> Bool {
        if MediaWaiter.isAvailable(fileName: item.fileName) { return true }
        CloudMediaStore.requestDownload(of: item.fileName)
        return false
    }

    // MARK: Photos

    func analyzePhoto(_ item: Shot, context: ModelContext, mode: Mode = .foreground) async {
        guard !running.contains(item.id), item.hasMediaFile, mediaIsReady(item) else { return }
        running.insert(item.id)
        defer { running.remove(item.id) }

        let previous = item.analysis
        let sharedURL = previous?.source?.headline == "Shared from Safari" ? previous?.source?.url : nil
        let input = PhotoAnalysisInput(
            imageURL: item.fileURL,
            fileURL: item.fileURL,
            isScreenshot: item.isScreenshot,
            capturedAt: item.capturedAt,
            addedAt: item.addedAt,
            pixelWidth: item.pixelWidth,
            pixelHeight: item.pixelHeight,
            sharedURL: sharedURL
        )
        var options = PhotoAnalysisOptions.full
        options.readText = AppGroup.bool(SettingsKey.readText)
        options.findSource = AppGroup.bool(SettingsKey.findSource)
        options.cpuOnly = mode == .background
        let result = await QuickAnalyzer.analyzePhoto(input, options: options)
        var analysis = result.analysis
        analysis.summary = previous?.summary ?? []

        let placesOn = AppGroup.bool(SettingsKey.recognizePlaces)
        if placesOn {
            if let coordinate = result.coordinate {
                analysis.place = await PlaceResolver.place(near: coordinate.latitude, coordinate.longitude)
            }
            if analysis.place == nil, let address = analysis.entities.first(where: { $0.kind == .address }) {
                analysis.place = await PlaceResolver.geocode(address: address.value)
            }
        }

        if AIWriter.isAvailable, mode == .foreground, PromptContext.hasPhotoDetails(analysis) {
            let context = PromptContext.photo(analysis, kindLabel: item.kindLabel)
            if let insight = try? await AIWriter.photoInsight(context: context) {
                let title = insight.title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.")))
                if !title.isEmpty, title.count <= 48, analysis.title == nil || analysis.category == "Text" || analysis.category == "Document" {
                    analysis.title = title
                }
                analysis.questions = Array(insight.questions.filter { !$0.isEmpty }.prefix(3))
                let placeName = insight.placeName.trimmingCharacters(in: .whitespacesAndNewlines)
                if placesOn, analysis.place == nil, placeName.count >= 3, placeName.count <= 60,
                   PlaceGrounding.isMentioned(placeName, in: analysis.text) {
                    let hint = result.coordinate
                    if var place = await PlaceResolver.search(placeName, near: hint) {
                        place.origin = "From text"
                        analysis.place = place
                    }
                }
                analysis.usedLanguageModel = true
            }
        }

        if let place = analysis.place {
            if analysis.title == nil { analysis.title = place.name }
            let parts = [place.category, place.distinctDetail].compactMap { $0 }
            analysis.subtitle = parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        if analysis.questions.isEmpty {
            analysis.questions = defaultQuestions(for: analysis, isScreenshot: item.isScreenshot)
        }
        analysis.analyzedAt = .now
        item.store(analysis, state: .done)
        context.commit(.analysis)
    }

    private func defaultQuestions(for analysis: ShotAnalysis, isScreenshot: Bool) -> [String] {
        var questions: [String] = []
        if analysis.place != nil { questions.append("What is this place?") }
        if analysis.entities.contains(where: { $0.kind == .date }) { questions.append("When is it?") }
        if analysis.entities.contains(where: { $0.kind == .price }) { questions.append("How much does it cost?") }
        if analysis.text != nil { questions.append("What does it say?") }
        questions.append(isScreenshot ? "Where is this screenshot from?" : "What's in this photo?")
        return Array(questions.prefix(3))
    }

    // MARK: Videos

    func analyzeVideo(_ item: Shot, context: ModelContext, mode: Mode = .foreground) async {
        guard !running.contains(item.id), item.hasMediaFile, mediaIsReady(item) else { return }
        running.insert(item.id)
        defer { running.remove(item.id) }

        let duration = item.mediaDuration ?? 0
        let input = VideoAnalysisInput(
            fileURL: item.fileURL,
            duration: duration,
            isScreenRecording: item.isScreenshot,
            capturedAt: item.capturedAt,
            addedAt: item.addedAt,
            latitude: item.latitude,
            longitude: item.longitude,
            cameraModel: item.cameraModel
        )
        var options = PhotoAnalysisOptions.full
        options.maxPixelSize = 1_280
        options.readText = AppGroup.bool(SettingsKey.readText)
        options.cpuOnly = mode == .background
        let frameCount = min(12, max(4, Int(duration / 8)))
        let result = await VideoAnalyzer.analyze(input, frameCount: frameCount, options: options)

        let previous = item.analysis
        var analysis = result.analysis
        analysis.transcript = previous?.transcript
        analysis.transcriptLanguage = previous?.transcriptLanguage
        analysis.transcriptNote = previous?.transcriptNote
        analysis.summary = previous?.summary ?? []
        if !AppGroup.bool(SettingsKey.findSource) {
            analysis.source = nil
        }

        if AppGroup.bool(SettingsKey.recognizePlaces) {
            if let coordinate = result.coordinate {
                analysis.place = await PlaceResolver.place(near: coordinate.latitude, coordinate.longitude)
            }
            if analysis.place == nil, let address = analysis.entities.first(where: { $0.kind == .address }) {
                analysis.place = await PlaceResolver.geocode(address: address.value)
            }
        }

        // Speech needs the foreground (and the language model even more).
        if mode == .foreground, analysis.transcript == nil, analysis.transcriptNote == nil,
           AppGroup.bool(SettingsKey.transcribeVideos), item.hasAudio != false, duration >= 2 {
            let language = VideoTranscriber.candidateLanguages(textHint: analysis.text).first ?? "en"
            apply(await VideoTranscriber.transcribe(fileURL: item.fileURL, duration: duration, language: language, allowDownload: false), to: &analysis)
        }
        if mode == .foreground {
            await writeVideoInsight(for: item, analysis: &analysis)
        }
        finishVideo(&analysis, item: item)
        item.store(analysis, state: .done)
        fresh.insert(item.id)
        context.commit(.analysis)
    }

    /// Transcribes (again) in a chosen language. Downloads the speech model when needed.
    func transcribe(_ item: Shot, language: String, context: ModelContext) async {
        guard item.isVideoFile, !transcribing.contains(item.id), mediaIsReady(item) else { return }
        transcribing.insert(item.id)
        defer { transcribing.remove(item.id) }
        var analysis = item.analysis ?? ShotAnalysis()
        let outcome = await VideoTranscriber.transcribe(
            fileURL: item.fileURL,
            duration: item.mediaDuration ?? 0,
            language: language,
            allowDownload: true
        )
        apply(outcome, to: &analysis)
        if case .transcript = outcome {
            analysis.summary = []
            await writeVideoInsight(for: item, analysis: &analysis)
        }
        finishVideo(&analysis, item: item)
        item.store(analysis, state: item.analysisState == .pending ? .pending : .done)
        fresh.insert(item.id)
        // Reading the speech again is minutes of work: this one offers to try the save.
        context.commit(.transcript, retry: { [weak self] in
            Task { await self?.transcribe(item, language: language, context: context) }
        })
    }

    private func apply(_ outcome: TranscriptionOutcome, to analysis: inout ShotAnalysis) {
        switch outcome {
        case let .transcript(lines, language, truncated):
            analysis.transcript = lines
            analysis.transcriptLanguage = language
            analysis.transcriptNote = truncated ? "Transcribed the first \(Int(VideoTranscriber.maximumDuration / 60)) minutes" : nil
        case .noSpeech:
            analysis.transcript = []
            analysis.transcriptNote = "No speech in this video"
        case let .needsDownload(language):
            analysis.transcript = nil
            analysis.transcriptNote = "download:\(language)"
        case let .unavailable(message):
            analysis.transcript = nil
            analysis.transcriptNote = message
        }
    }

    private func writeVideoInsight(for item: Shot, analysis: inout ShotAnalysis) async {
        let spoken = (analysis.transcript ?? []).map(\.text).joined(separator: "\n")
        let screen = analysis.text ?? ""
        let body = [spoken.isEmpty ? nil : "Speech:\n\(spoken)", screen.isEmpty ? nil : "Text on screen:\n\(screen)"]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        guard body.count >= 60 else { return }
        if AIWriter.isAvailable {
            let header = "A \(item.kindLabel.lowercased()) saved on \(LaqtaDevice.name)" + (item.mediaDuration.map { ", \(LaqtaFormat.duration($0)) long" } ?? "") + "."
            if let insight = try? await AIWriter.contentInsight(kind: item.kindLabel.lowercased(), header: header, body: body) {
                let title = insight.title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.")))
                if !title.isEmpty, title.count <= 60, analysis.title == nil || analysis.category == "Text" {
                    analysis.title = title
                }
                analysis.summary = Array(insight.summary.filter { !$0.isEmpty }.prefix(5))
                analysis.questions = Array(insight.questions.filter { !$0.isEmpty }.prefix(3))
                if AppGroup.bool(SettingsKey.recognizePlaces), analysis.places.isEmpty {
                    var places: [PlaceRef] = []
                    var hint: (latitude: Double, longitude: Double)?
                    if let latitude = analysis.place?.latitude, let longitude = analysis.place?.longitude {
                        hint = (latitude, longitude)
                    }
                    let transcript = analysis.transcript ?? []
                    for name in insight.places.prefix(4) where name.count >= 3 && PlaceGrounding.isMentioned(name, in: body) {
                        if var place = await PlaceResolver.search(name, near: hint) {
                            place.name = name
                            place.origin = "Mentioned"
                            place.mentionedAt = transcript.first { $0.text.localizedCaseInsensitiveContains(name) }?.seconds
                            places.append(place)
                        }
                    }
                    analysis.places = places
                }
                analysis.usedLanguageModel = true
            }
        }
        if analysis.summary.isEmpty, spoken.count >= 200 {
            analysis.summary = ExtractiveSummary.points(from: spoken)
        }
    }

    private func finishVideo(_ analysis: inout ShotAnalysis, item: Shot) {
        let hasSpeech = !(analysis.transcript ?? []).isEmpty
        let hasText = (analysis.text?.count ?? 0) >= 12
        switch (hasSpeech, hasText) {
        case (true, true): analysis.basis = "From what is said and shown in the video"
        case (true, false): analysis.basis = "From what is said in the video"
        case (false, true): analysis.basis = "From the text shown in the video"
        case (false, false): analysis.basis = "From the video's frames"
        }
        if let place = analysis.place {
            if analysis.title == nil { analysis.title = place.name }
            let parts = [place.category, place.distinctDetail].compactMap { $0 }
            analysis.subtitle = parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        if analysis.questions.isEmpty {
            analysis.questions = hasSpeech
                ? ["What is this video about?", "What are the main points?", "Which places are mentioned?"]
                : ["What's in this video?", "Where was it recorded?"]
        }
        analysis.analyzedAt = .now
    }

    // MARK: PDFs

    func analyzeDocument(_ item: Shot, context: ModelContext, mode: Mode = .foreground) async {
        guard !running.contains(item.id), item.hasMediaFile, mediaIsReady(item) else { return }
        running.insert(item.id)
        defer { running.remove(item.id) }

        let input = DocumentAnalysisInput(
            fileURL: item.fileURL,
            title: item.documentTitle,
            fileName: item.originalName,
            pageCount: item.documentPages ?? 0,
            createdAt: item.capturedAt,
            addedAt: item.addedAt
        )
        var options = PhotoAnalysisOptions.full
        options.cpuOnly = mode == .background
        let output = await DocumentAnalyzer.analyze(
            input,
            maxPages: 80,
            ocrPages: AppGroup.bool(SettingsKey.readText) ? (mode == .background ? 3 : 12) : 0,
            options: options
        )
        let previous = item.analysis
        var analysis = output.result.analysis
        analysis.summary = previous?.summary ?? []
        analysis.questions = previous?.questions ?? []

        if AppGroup.bool(SettingsKey.recognizePlaces),
           let address = analysis.entities.first(where: { $0.kind == .address }) {
            analysis.place = await PlaceResolver.geocode(address: address.value)
        }

        let body = output.body
        if mode == .foreground, body.count >= 80, AIWriter.isAvailable {
            let header = """
            A PDF saved on \(LaqtaDevice.name)\(analysis.category.map { ", probably a \($0.lowercased())" } ?? "").
            Title: \(item.displayTitle)
            Pages: \(item.documentPages ?? 0)
            """
            if let insight = try? await AIWriter.contentInsight(kind: (analysis.category ?? "document").lowercased(), header: header, body: body) {
                let title = insight.title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.")))
                if item.documentTitle == nil, !title.isEmpty, title.count <= 70 {
                    analysis.title = title
                }
                analysis.summary = Array(insight.summary.filter { !$0.isEmpty }.prefix(5))
                analysis.questions = Array(insight.questions.filter { !$0.isEmpty }.prefix(3))
                analysis.places = insight.places
                    .filter { PlaceGrounding.isMentioned($0, in: body) }
                    .prefix(6)
                    .map { PlaceRef(name: $0, origin: "Mentioned") }
                analysis.usedLanguageModel = true
            }
        }
        if analysis.summary.isEmpty, body.count >= 200 {
            analysis.summary = ExtractiveSummary.points(from: body)
        }
        if analysis.questions.isEmpty {
            analysis.questions = ["What is this document about?", "What are the key dates?", "Are there any amounts to pay?"]
        }
        analysis.basis = body.isEmpty ? "This PDF has no readable text" : (output.scanned ? "From the scanned pages" : "From the PDF's text")
        analysis.analyzedAt = .now
        item.store(analysis, state: .done)
        fresh.insert(item.id)
        context.commit(.analysis)
    }

    // MARK: Links

    func extractEverything(_ item: Shot, context: ModelContext) async {
        item.deepAnalysis = true
        item.analysisState = .pending
        guard context.commit(.linkDetails, retry: { [weak self] in
            Task { await self?.extractEverything(item, context: context) }
        }) else { return }
        await analyzeLink(item, context: context)
    }

    func analyzeLink(_ item: Shot, context: ModelContext, mode: Mode = .foreground) async {
        guard !running.contains(item.id), let url = item.url else {
            if item.url == nil {
                item.analysisState = .failed
                context.commit(.analysis)
            }
            return
        }
        running.insert(item.id)
        defer { running.remove(item.id) }

        // YouTube links get their title, channel and thumbnail from YouTube's oEmbed.
        if item.isYouTube {
            await YouTubeRefresher.refresh([item], context: context)
            return
        }

        let draft = await LinkReader.read(url, deep: true, downloadImage: !item.hasThumbnail)

        // Better metadata than what the extension had time for.
        if draft.title != draft.site, !draft.title.isEmpty { item.linkTitle = draft.title }
        item.linkSite = draft.site
        item.linkAuthor = draft.author ?? item.linkAuthor
        item.linkDuration = draft.duration ?? item.linkDuration
        item.linkDetails = draft.details ?? item.linkDetails
        item.linkViews = draft.views ?? item.linkViews
        item.linkPublishedAt = draft.publishedAt ?? item.linkPublishedAt
        item.linkFormRaw = draft.form.rawValue
        if let image = draft.image {
            if !item.hasThumbnail, let files = try? MediaStore.commit(image) {
                item.fileName = files.fileName
                item.thumbnailName = files.thumbnailName
            } else {
                MediaStore.discard(image)
            }
        }

        var analysis = item.analysis ?? ShotAnalysis()
        analysis.category = draft.form.label
        if !draft.chapters.isEmpty { analysis.sections = draft.chapters }
        analysis.sectionsTitle = draft.form.sectionsTitle
        var placeNames = draft.placeNames
        var prices = draft.prices
        let notPlaces = Set([draft.author, draft.site, item.linkAuthor, draft.sourceName].compactMap { $0 }.map { SearchIndex.normalize($0) })

        let hasText = (draft.details?.count ?? 0) + (draft.bodyText?.count ?? 0) > 60
        if AIWriter.isAvailable, hasText, mode == .foreground {
            if let insight = try? await AIWriter.linkInsight(
                title: draft.title,
                site: draft.site,
                kind: draft.form.label.lowercased(),
                description: draft.details,
                body: draft.bodyText
            ) {
                analysis.summary = Array(insight.summary.filter { !$0.isEmpty }.prefix(5))
                analysis.tips = Array(insight.tips.filter { !$0.isEmpty && !$0.contains("http") }.prefix(4))
                analysis.questions = Array(insight.questions.filter { !$0.isEmpty }.prefix(3))
                // The model's list is more precise than name tagging; keep tagged names it agrees with.
                let linkText = [draft.title, draft.details, draft.bodyText].compactMap { $0 }.joined(separator: "\n")
                let modelPlaces = insight.places
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && PlaceGrounding.isMentioned($0, in: linkText) }
                let agreed = placeNames.filter { name in
                    modelPlaces.contains { SearchIndex.normalize($0).contains(SearchIndex.normalize(name)) || SearchIndex.normalize(name).contains(SearchIndex.normalize($0)) }
                }
                placeNames = agreed
                for name in modelPlaces where !placeNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    placeNames.append(name)
                }
                if prices.isEmpty {
                    prices = insight.prices.compactMap { line in
                        let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        guard parts.count == 2, !parts[1].isEmpty else { return nil }
                        return PriceRef(label: parts[0], value: parts[1])
                    }
                }
                analysis.usedLanguageModel = true
            }
        }
        if analysis.summary.isEmpty {
            analysis.summary = ExtractiveSummary.points(from: [draft.details, draft.bodyText].compactMap { $0 }.joined(separator: "\n"))
        }
        if analysis.questions.isEmpty {
            analysis.questions = draft.form == .video
                ? ["What is this video about?", "Which places are mentioned?", "What are the main tips?"]
                : ["What is this about?", "What are the key details?", "Is there a price?"]
        }

        placeNames = placeNames.filter { !notPlaces.contains(SearchIndex.normalize($0)) }

        // Find the places on the map.
        if AppGroup.bool(SettingsKey.recognizePlaces) {
            let cityHint = placeNames.first { name in
                name.localizedCaseInsensitiveContains("city") || name.split(separator: " ").count == 1
            }
            var places: [PlaceRef] = []
            // A page about a landmark: the subject itself comes first.
            if draft.form == .article || draft.form == .page || draft.form == .place,
               var subject = await PlaceResolver.search(draft.title),
               subject.category != nil, subject.category != "Address" {
                subject.origin = "Subject"
                places.append(subject)
                let subjectKey = SearchIndex.normalize(subject.name)
                placeNames.removeAll { SearchIndex.normalize($0) == subjectKey }
            }
            for name in placeNames.prefix(6) where !places.contains(where: { SearchIndex.normalize($0.name) == SearchIndex.normalize(name) }) {
                if var place = await PlaceResolver.search(name, context: name == cityHint ? nil : cityHint) {
                    place.name = name
                    place.origin = "Mentioned"
                    place.mentionedAt = analysis.sections.first { $0.seconds >= 0 && $0.title.localizedCaseInsensitiveContains(name) }?.seconds
                    places.append(place)
                } else {
                    places.append(PlaceRef(name: name, origin: "Mentioned"))
                }
            }
            analysis.places = places
        } else {
            analysis.places = placeNames.prefix(8).map { PlaceRef(name: $0, origin: "Mentioned") }
        }
        analysis.prices = Array(prices.prefix(6))
        analysis.basis = LibraryWriter.basis(for: draft, deep: true)
        analysis.analyzedAt = .now

        item.deepAnalysis = true
        item.store(analysis, state: .done)
        fresh.insert(item.id)
        context.commit(.linkDetails)
    }

    // MARK: Summaries

    func summarize(_ item: Shot, context: ModelContext) async {
        guard !summarizing.contains(item.id) else { return }
        summarizing.insert(item.id)
        defer { summarizing.remove(item.id) }

        var analysis = item.analysis ?? ShotAnalysis()
        let text = [analysis.text, analysis.transcript.map { $0.map(\.text).joined(separator: " ") }]
            .compactMap { $0 }
            .joined(separator: "\n")
        var points: [String] = []
        if AIWriter.isAvailable, text.count > 20 || analysis.place != nil {
            let context = PromptContext.item(item)
            points = (try? await AIWriter.keyPoints(for: context, kind: item.kindLabel.lowercased())) ?? []
        }
        if points.isEmpty {
            points = ExtractiveSummary.points(from: text)
        }
        if points.isEmpty {
            points = ["There isn't enough text in this \(item.kindLabel.lowercased()) to summarize."]
        }
        analysis.summary = Array(points.prefix(5))
        fresh.insert(item.id)
        item.store(analysis, state: item.analysisState == .pending ? .pending : .done)
        context.commit(.analysis)
    }

    // MARK: Questions

    func ask(_ question: String, about item: Shot) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !asking.contains(item.id) else { return }
        let history = conversation(for: item.id).map { (fromUser: $0.fromUser, text: $0.text) }
        conversations[item.id, default: []].append(ChatMessage(fromUser: true, text: trimmed, animate: false))
        asking.insert(item.id)
        defer { asking.remove(item.id) }

        let answer: String
        if AIWriter.isAvailable {
            do {
                answer = try await AIWriter.answer(question: trimmed, context: PromptContext.item(item, question: trimmed), history: history)
            } catch {
                answer = "I couldn't answer that right now. Try asking in a different way."
            }
        } else {
            answer = AIWriter.unavailableMessage
        }
        conversations[item.id, default: []].append(ChatMessage(fromUser: false, text: answer, animate: true))
    }

    func stopAnimating(_ messageID: UUID, in itemID: UUID) {
        guard var thread = conversations[itemID], let index = thread.firstIndex(where: { $0.id == messageID }) else { return }
        thread[index].animate = false
        conversations[itemID] = thread
    }

    // MARK: Insights

    func refreshInsights(context: ModelContext) {
        hasInsights = !upcoming(context: context, limit: 1).isEmpty
    }

    struct Upcoming: Identifiable {
        let item: Shot
        let entity: DetectedEntity
        let date: Date
        let title: String
        var id: String { item.id.uuidString + entity.id }
    }

    func upcoming(context: ModelContext, limit: Int = 20) -> [Upcoming] {
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.tagsRaw != nil && $0.deletedAt == nil })
        let items = ((try? context.fetch(descriptor)) ?? []).filter { $0.tags.contains(.date) }
        let now = Date.now
        let horizon = now.addingTimeInterval(120 * 86_400)
        var result: [Upcoming] = []
        for item in items {
            guard let analysis = item.analysis else { continue }
            for entity in analysis.entities where entity.kind == .date {
                guard let date = entity.date, date > now, date < horizon else { continue }
                result.append(Upcoming(item: item, entity: entity, date: date, title: analysis.title ?? analysis.category ?? item.kindLabel))
                break
            }
        }
        return Array(result.sorted { $0.date < $1.date }.prefix(limit))
    }
}
