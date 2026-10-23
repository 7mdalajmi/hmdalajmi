//
//  IntelligenceSheet.swift
//  Laqta
//
//  What Laqta understood about a photo or video: place, text, speech, summary,
//  source, and questions.
//

import Foundation
import MapKit
import SwiftData
import SwiftUI
import Translation

struct IntelligenceSheet: View {
    let itemID: UUID
    /// Jumps a video to a moment (key moments, transcript lines, places).
    var onSeek: ((Double) -> Void)?
    /// Closes the panel when it's shown as an inspector on iPad.
    var onClose: (() -> Void)?

    @Environment(\.laqta) private var palette
    @Query private var matches: [Shot]

    init(itemID: UUID, onSeek: ((Double) -> Void)? = nil, onClose: (() -> Void)? = nil) {
        self.itemID = itemID
        self.onSeek = onSeek
        self.onClose = onClose
        let target = itemID
        _matches = Query(filter: #Predicate<Shot> { $0.id == target })
    }

    var body: some View {
        Group {
            if let item = matches.first {
                IntelligenceContent(item: item, onSeek: onSeek, onClose: onClose)
            } else {
                palette.sheet
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.sheet)
        .presentationCornerRadius(32)
        .presentationDragIndicator(.visible)
    }
}

private struct IntelligenceContent: View {
    let item: Shot
    let onSeek: ((Double) -> Void)?
    let onClose: (() -> Void)?

    @AppObject(IntelligenceCenter.self) private var intelligence
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.laqta) private var palette
    @AppStorage(SettingsKey.analyzeShots, store: AppGroup.defaults) private var analyzeOn = true

    @State private var toasts = ToastCenter()
    @State private var noteItem: Shot?
    @State private var translating = false

    private var analysis: ShotAnalysis { item.analysis ?? ShotAnalysis() }
    private var kindWord: String { item.kindLabel.lowercased() }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    if !analyzeOn {
                        offCard
                    } else {
                        DetectedCard(item: item, analysis: analysis, isRunning: intelligence.isRunning(item.id) || item.analysisState == .pending)
                        if !item.note.isEmpty {
                            NoteCard(note: item.note) { noteItem = item }
                        }
                        if item.isVideoFile, !analysis.summary.isEmpty {
                            summaryCard
                        }
                        if item.isVideoFile {
                            TranscriptCard(item: item, analysis: analysis, toasts: toasts, onSeek: onSeek)
                        }
                        if item.isVideoFile, analysis.sections.contains(where: \.isTimed) {
                            MomentsCard(sections: analysis.sections.filter(\.isTimed), title: analysis.sectionsTitle ?? "Key moments", onSeek: onSeek)
                        }
                        if let place = analysis.place, place.origin != "From text" {
                            PlaceCard(place: place, toasts: toasts)
                        }
                        if !analysis.places.isEmpty {
                            MentionedPlacesCard(places: analysis.places, onSeek: onSeek)
                        }
                        if let text = analysis.text, !text.isEmpty {
                            textCard(text)
                        }
                        if !item.isVideoFile, !analysis.summary.isEmpty || (analysis.text?.count ?? 0) >= 40 {
                            summaryCard
                        }
                        if let place = analysis.place, place.origin == "From text" {
                            PlaceCard(place: place, toasts: toasts)
                        }
                        if let source = analysis.source {
                            SourceCard(source: source, toasts: toasts)
                        }
                        AskCard(item: item, title: "Ask about this \(kindWord)", suggestions: analysis.questions)
                        Text("Intelligence can make mistakes. Check important info.")
                            .laqtaFont(12)
                            .foregroundStyle(palette.ink3)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(palette.sheet.ignoresSafeArea())
        .toastHost(toasts)
        .sheet(item: $noteItem) { item in
            NoteEditorSheet(item: item)
                .laqtaThemed()
        }
        .onDisappear {
            intelligence.markSeen(item.id)
        }
        .task(id: item.id) {
            if analyzeOn, item.analysisState == .pending {
                await intelligence.analyze(item, context: modelContext)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AIBadge(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Intelligence")
                    .laqtaFont(20, weight: .semibold)
                    .foregroundStyle(palette.ink)
                Label("Analyzed privately on this device", systemImage: "lock")
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
            }
            Spacer(minLength: 0)
            Button {
                if let onClose {
                    onClose()
                } else {
                    dismiss()
                }
            } label: {
                CircleIcon(systemImage: "xmark")
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    private var offCard: some View {
        LaqtaCard {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .laqtaIconFont(28, weight: .light)
                    .foregroundStyle(palette.goldHi)
                Text("Intelligence is off")
                    .laqtaFont(17, weight: .semibold)
                    .foregroundStyle(palette.ink)
                Text("Turn it on to find places, text, speech and where an item came from. Everything is analyzed on this device.")
                    .laqtaFont(14)
                    .foregroundStyle(palette.ink2)
                    .multilineTextAlignment(.center)
                Button {
                    analyzeOn = true
                    intelligence.processPending(context: modelContext)
                } label: {
                    LaqtaButtonLabel("Turn On", systemImage: "sparkles")
                }
                .buttonStyle(.pressable)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: Text

    private func textCard(_ text: String) -> some View {
        LaqtaCard {
            CardHeader("Text found", systemImage: "text.viewfinder") {
                HStack(spacing: 14) {
                    Button {
                        translating = true
                    } label: {
                        Label("Translate", systemImage: "translate")
                            .laqtaFont(13, weight: .semibold)
                            .foregroundStyle(palette.goldHi)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(Text("Translate the text in this shot"))
                    Button {
                        Clipboard.copy(text)
                        toasts.show(String(localized: "Text copied"), systemImage: "doc.on.doc")
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .laqtaFont(13, weight: .semibold)
                            .foregroundStyle(palette.goldHi)
                    }
                    .buttonStyle(.pressable)
                }
            }
            ExpandableText(text: text)
            if !analysis.entities.isEmpty {
                EntityActions(
                    entities: analysis.entities,
                    eventTitle: analysis.title ?? analysis.category ?? "Event",
                    eventNotes: analysis.text,
                    toasts: toasts
                )
                .padding(.top, 12)
            }
        }
        // Apple's own translation, in its own sheet. The language pack downloads
        // once and then works offline; the text never leaves the phone.
        .translationPresentation(isPresented: $translating, text: text)
    }

    // MARK: Summary

    private var summaryCard: some View {
        LaqtaCard {
            CardHeader("Summary", systemImage: "sparkles")
            if !analysis.summary.isEmpty {
                BulletList(items: analysis.summary, reveal: intelligence.isFresh(item.id))
            } else if intelligence.isSummarizing(item.id) {
                VStack(alignment: .leading, spacing: 10) {
                    ThinkingDots()
                    ShimmerLine(height: 11)
                    ShimmerLine(width: 220, height: 11)
                }
            } else {
                HStack(spacing: 14) {
                    Text("Get the key points of this \(kindWord) in a few lines.")
                        .laqtaFont(14)
                        .foregroundStyle(palette.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        Task { await intelligence.summarize(item, context: modelContext) }
                    } label: {
                        LaqtaButtonLabel("Summarize", systemImage: "sparkles")
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .animation(.snappy, value: analysis.summary)
        .animation(.snappy, value: intelligence.isSummarizing(item.id))
    }
}

// MARK: - Detected

private struct DetectedCard: View {
    let item: Shot
    let analysis: ShotAnalysis
    let isRunning: Bool

    @Environment(\.laqta) private var palette

    var body: some View {
        LaqtaCard {
            HStack(alignment: .top, spacing: 14) {
                ShotThumbnail(shot: item, cornerRadius: 8)
                    .frame(width: 48, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: headline)
                        .laqtaFont(17, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .lineLimit(2)
                    Text(verbatim: meta)
                        .laqtaFont(13)
                        .foregroundStyle(palette.ink2)
                    if isRunning, analysis.title == nil {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(palette.goldHi)
                            Text("Analyzing on this \(LaqtaDevice.name)…")
                                .laqtaFont(12, weight: .medium)
                                .foregroundStyle(palette.goldHi)
                        }
                    } else if !chips.isEmpty {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(chips) { chip in
                                TagChip(text: chip.text, systemImage: chip.symbol)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var headline: String {
        let kind = item.kindLabel
        // "Photo · Camera", "Video · Safari"; never "Video · Video".
        if let app = analysis.source?.app, !["Photos", "Screenshot"].contains(app), app.caseInsensitiveCompare(kind) != .orderedSame {
            return "\(kind) · \(app)"
        }
        return kind
    }

    private var meta: String {
        let date = item.capturedAt ?? item.addedAt
        var parts = [LaqtaFormat.dateTime(date)]
        if let duration = item.mediaDuration, item.isVideoFile { parts.append(LaqtaFormat.duration(duration)) }
        parts.append(LaqtaFormat.bytes(Int64(item.byteCount)))
        return parts.joined(separator: " · ")
    }

    private struct Chip: Identifiable {
        let text: String
        let symbol: String
        var id: String { text }
    }

    private var chips: [Chip] {
        var result: [Chip] = []
        func add(_ text: String, _ symbol: String) {
            guard !text.isEmpty, !result.contains(where: { $0.text == text }) else { return }
            result.append(Chip(text: text, symbol: symbol))
        }
        if let category = analysis.category, category != "Place" {
            add(category, "text.viewfinder")
        }
        if let place = analysis.place {
            add(place.name, "building.columns")
        }
        for entity in analysis.entities.prefix(4) where entity.kind == .date || entity.kind == .price || entity.kind == .flight || entity.kind == .link {
            add(entity.display, entity.systemImage)
        }
        for label in analysis.labels.prefix(2) {
            add(label, "photo")
        }
        return Array(result.prefix(5))
    }
}

// MARK: - Place

struct PlaceCard: View {
    let place: PlaceRef
    let toasts: ToastCenter

    @Environment(\.laqta) private var palette
    @State private var route: RouteSummary?
    @State private var location = LocationAccess.shared

    var body: some View {
        LaqtaCard {
            CardHeader("Place", systemImage: "mappin.and.ellipse") {
                if let origin = place.origin {
                    Text(verbatim: origin == "GPS" ? String(localized: "From photo location") : origin)
                        .laqtaFont(12)
                        .foregroundStyle(palette.ink2)
                        .multilineTextAlignment(.trailing)
                        .layoutPriority(1)
                }
            }
            if place.hasCoordinate {
                PlaceMap(place: place, route: route)
                    .frame(height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
                    .padding(.bottom, 12)
            }
            Text(verbatim: place.name)
                .laqtaFont(18, weight: .semibold)
                .foregroundStyle(palette.ink)
            if let detail = place.distinctDetail {
                Text(verbatim: detail)
                    .laqtaFont(13)
                    .foregroundStyle(palette.ink2)
                    .padding(.top, 2)
            }
            if let line = categoryLine {
                Text(verbatim: line)
                    .laqtaFont(12, weight: .medium)
                    .foregroundStyle(palette.goldHi)
                    .padding(.top, 4)
            }
            if let route {
                HStack(spacing: 12) {
                    Image(systemName: "car")
                        .laqtaIconFont(16, weight: .medium)
                        .foregroundStyle(palette.goldHi)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(LaqtaFormat.travelTime(route.travelTime)) · \(LaqtaFormat.distance(route.distance))")
                            .laqtaFont(15, weight: .semibold)
                            .foregroundStyle(palette.ink)
                        if !route.name.isEmpty {
                            Text("Fastest route via \(route.name)")
                                .laqtaFont(12)
                                .foregroundStyle(palette.ink2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 12)
                .transition(.opacity)
            } else if place.hasCoordinate, location.canAsk {
                Button {
                    location.requestIfNeeded()
                } label: {
                    Label("Show travel time", systemImage: "location")
                        .laqtaFont(13, weight: .semibold)
                        .foregroundStyle(palette.goldHi)
                }
                .buttonStyle(.pressable)
                .padding(.top, 10)
            }
            AdaptiveButtonRow {
                Button {
                    Directions.openDirections(to: place)
                } label: {
                    LaqtaButtonLabel(route == nil ? "Directions" : "Start", systemImage: "location")
                }
                Button {
                    Directions.showInMaps(place)
                } label: {
                    LaqtaButtonLabel("Maps", systemImage: "map", kind: .line)
                }
                Button {
                    Clipboard.copy([place.name, place.detail].compactMap { $0 }.joined(separator: ", "))
                    toasts.show(String(localized: "Place copied"), systemImage: "doc.on.doc")
                } label: {
                    OutlineIconButtonLabel(systemImage: "doc.on.doc")
                }
                .accessibilityLabel(Text("Copy"))
            }
            .buttonStyle(.pressable)
            .padding(.top, 14)
        }
        .animation(.snappy, value: route?.travelTime)
        .task(id: "\(place.id)-\(location.isAuthorized)") {
            route = await Directions.route(to: place)
        }
    }

    private var categoryLine: String? {
        let parts = [place.category, place.note].compactMap { $0 }.filter { !$0.isEmpty && $0 != "Location" }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct PlaceMap: View {
    let place: PlaceRef
    var route: RouteSummary?

    @Environment(\.laqta) private var palette

    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude ?? 0, longitude: place.longitude ?? 0)
        Map(initialPosition: position(for: coordinate), interactionModes: []) {
            if let route {
                MapPolyline(route.polyline)
                    .stroke(palette.goldHi, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            Annotation(place.name, coordinate: coordinate, anchor: .center) {
                Image(systemName: "mappin")
                    .laqtaIconFont(11, weight: .bold)
                    .foregroundStyle(palette.goldInk)
                    .frame(width: 26, height: 26)
                    .background(palette.accentFill, in: Circle())
                    .overlay(Circle().strokeBorder(palette.sheet2, lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 3)
            }
            .annotationTitles(.hidden)
            if route != nil {
                UserAnnotation()
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .id(route == nil ? "plain" : "route")
        .allowsHitTesting(false)
    }

    private func position(for coordinate: CLLocationCoordinate2D) -> MapCameraPosition {
        if let route {
            let rect = route.polyline.boundingMapRect
            let padded = rect.insetBy(dx: -rect.size.width * 0.25, dy: -rect.size.height * 0.35)
            return .rect(padded)
        }
        return .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1_400, longitudinalMeters: 1_400))
    }
}

// MARK: - Source

struct SourceCard: View {
    let source: SourceRef
    let toasts: ToastCenter

    @Environment(\.openURL) private var openURL
    @Environment(\.laqta) private var palette

    var body: some View {
        LaqtaCard {
            CardHeader("Source", systemImage: "globe")
            HStack(spacing: 12) {
                Image(systemName: source.systemImage)
                    .laqtaIconFont(18, weight: .medium)
                    .foregroundStyle(palette.goldHi)
                    .frame(width: 44, height: 44)
                    .background(palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: source.headline)
                        .laqtaFont(16, weight: .semibold)
                        .foregroundStyle(palette.ink)
                    if let detail = source.detail {
                        Text(verbatim: detail)
                            .laqtaFont(13)
                            .foregroundStyle(source.url == nil ? palette.ink2 : palette.goldHi)
                            .adaptiveLineLimit(1, accessibility: 3)
                    }
                }
                Spacer(minLength: 0)
            }
            if let reason = source.reason, !reason.isEmpty {
                Text(verbatim: reason)
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
                    .padding(.top, 10)
            }
            if let urlString = source.url, let url = URL(string: urlString) {
                AdaptiveButtonRow {
                    Button {
                        openURL(url)
                    } label: {
                        LaqtaButtonLabel("Open Link", systemImage: "arrow.up.right")
                    }
                    Button {
                        Clipboard.copy(urlString)
                        toasts.show(String(localized: "Link copied"), systemImage: "doc.on.doc")
                    } label: {
                        LaqtaButtonLabel("Copy Link", systemImage: "doc.on.doc", kind: .line)
                    }
                }
                .buttonStyle(.pressable)
                .padding(.top, 14)
            }
        }
    }
}

// MARK: - Ask

struct AskCard: View {
    let item: Shot
    let title: String
    let suggestions: [String]

    @AppObject(IntelligenceCenter.self) private var intelligence
    @Environment(\.laqta) private var palette
    @State private var question = ""
    @FocusState private var focused: Bool

    var body: some View {
        LaqtaCard {
            CardHeader(verbatim: title, systemImage: "bubble.left")
            if !intelligence.modelAvailable {
                Text(verbatim: intelligence.modelMessage)
                    .laqtaFont(13)
                    .foregroundStyle(palette.ink2)
            } else {
                let thread = intelligence.conversation(for: item.id)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(thread) { message in
                        bubble(message)
                    }
                    if intelligence.isAsking(item.id) {
                        ThinkingDots()
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(palette.field, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
                    }
                }
                .animation(.snappy, value: thread)

                let remaining = suggestions.filter { suggestion in !thread.contains { $0.text == suggestion } }
                if !remaining.isEmpty {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(remaining, id: \.self) { suggestion in
                            Button {
                                send(suggestion)
                            } label: {
                                Text(verbatim: suggestion)
                                    .laqtaFont(13)
                                    .foregroundStyle(palette.ink)
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
                            }
                            .buttonStyle(.pressable)
                            .disabled(intelligence.isAsking(item.id))
                        }
                    }
                    .padding(.top, thread.isEmpty ? 0 : 12)
                }

                HStack(spacing: 8) {
                    TextField(text: $question, prompt: Text("Ask anything…").foregroundStyle(palette.ink3)) {
                        Text("Question")
                    }
                    .laqtaFont(15)
                    .foregroundStyle(palette.ink)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { send(question) }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(palette.field, in: Capsule())
                    .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))

                    Button {
                        send(question)
                    } label: {
                        Image(systemName: "arrow.up")
                            .laqtaIconFont(16, weight: .bold)
                            .foregroundStyle(palette.goldInk)
                            .frame(width: 44, height: 44)
                            .background(palette.accentFill, in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || intelligence.isAsking(item.id))
                    .accessibilityLabel(Text("Send"))
                }
                .padding(.top, 12)
            }
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        question = ""
        Task { await intelligence.ask(trimmed, about: item) }
    }

    @ViewBuilder
    private func bubble(_ message: IntelligenceCenter.ChatMessage) -> some View {
        if message.fromUser {
            HStack {
                Spacer(minLength: 40)
                Text(verbatim: message.text)
                    .laqtaFont(14)
                    .foregroundStyle(palette.bubbleMeInk)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(palette.bubbleMe, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous))
            }
        } else {
            HStack {
                TypingText(text: message.text, animate: message.animate)
                    .laqtaFont(14)
                    .lineSpacing(3)
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(palette.field, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
                    .onDisappear {
                        intelligence.stopAnimating(message.id, in: item.id)
                    }
                Spacer(minLength: 24)
            }
        }
    }
}

// MARK: - Text block

struct ExpandableText: View {
    let text: String
    @State private var expanded = false
    @Environment(\.laqta) private var palette

    private var lines: [String] {
        text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: (expanded ? lines : Array(lines.prefix(8))).joined(separator: "\n"))
                .laqtaFont(14)
                .lineSpacing(4)
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if lines.count > 8 {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Show less" : "Show all \(lines.count) lines")
                        .laqtaFont(13, weight: .semibold)
                        .foregroundStyle(palette.goldHi)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Actions on detected details

/// Dates, links, phones, addresses, flights, prices and codes as tappable chips.
struct EntityActions: View {
    let entities: [DetectedEntity]
    let eventTitle: String
    let eventNotes: String?
    let toasts: ToastCenter

    @Environment(\.openURL) private var openURL
    @State private var eventDraft: EventDraft?
    @State private var doneKeys: Set<String> = []

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(entities) { entity in
                Button {
                    handle(entity)
                } label: {
                    EntityChipLabel(
                        text: chipText(entity),
                        systemImage: entity.systemImage,
                        done: doneKeys.contains(entity.id)
                    )
                }
                .buttonStyle(.pressable)
                .accessibilityHint(Text(hint(for: entity)))
            }
        }
        .sheet(item: $eventDraft) { draft in
            EventEditView(draft: draft) { saved in
                if saved {
                    doneKeys.insert(draft.actionKey)
                    toasts.show(String(localized: "Added to Calendar · \(draft.title) · \(LaqtaFormat.eventDate(draft.start, allDay: draft.allDay))"))
                }
            }
            .ignoresSafeArea()
        }
    }

    private func chipText(_ entity: DetectedEntity) -> String {
        switch entity.kind {
        case .flight: "Track \(entity.display)"
        default: entity.display
        }
    }

    private func hint(for entity: DetectedEntity) -> LocalizedStringKey {
        switch entity.kind {
        case .date: "Adds it to Calendar"
        case .link: "Opens the link"
        case .phone: "Calls the number"
        case .email: "Writes an email"
        case .address: "Shows it in Maps"
        case .flight: "Looks up the flight"
        case .price, .code: "Copies it"
        }
    }

    private func handle(_ entity: DetectedEntity) {
        switch entity.kind {
        case .date:
            guard let date = entity.date else { return }
            eventDraft = EventDraft(
                title: eventTitle,
                start: date,
                allDay: entity.allDay,
                notes: eventNotes,
                actionKey: entity.id
            )
        case .link:
            if let url = URL(string: entity.value) { openURL(url) }
        case .phone:
            let digits = entity.value.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:\(digits)") { openURL(url) }
        case .email:
            if let url = URL(string: "mailto:\(entity.value)") { openURL(url) }
        case .address:
            Directions.searchInMaps(entity.value)
        case .flight:
            var components = URLComponents(string: "https://www.google.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: "flight \(entity.value)")]
            if let url = components?.url { openURL(url) }
        case .price, .code:
            Clipboard.copy(entity.value)
            doneKeys.insert(entity.id)
            toasts.show(String(localized: "Copied \(entity.display)"), systemImage: "doc.on.doc")
        }
    }
}

// MARK: - Note

struct NoteCard: View {
    let note: String
    let onEdit: () -> Void

    @Environment(\.laqta) private var palette

    var body: some View {
        LaqtaCard {
            CardHeader("Your note", systemImage: "note.text") {
                Button(action: onEdit) {
                    Text("Edit")
                        .laqtaFont(13, weight: .semibold)
                        .foregroundStyle(palette.goldHi)
                }
                .buttonStyle(.pressable)
            }
            Text(verbatim: note)
                .laqtaFont(15)
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Speech

private struct TranscriptCard: View {
    let item: Shot
    let analysis: ShotAnalysis
    let toasts: ToastCenter
    let onSeek: ((Double) -> Void)?

    @AppObject(IntelligenceCenter.self) private var intelligence
    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette
    @AppStorage(SettingsKey.transcribeVideos, store: AppGroup.defaults) private var transcribeOn = true
    @State private var expanded = false

    private var lines: [TranscriptLine] { analysis.transcript ?? [] }
    private var isWorking: Bool { intelligence.isTranscribing(item.id) }
    private var languages: [String] { VideoTranscriber.candidateLanguages(textHint: analysis.text) }

    var body: some View {
        LaqtaCard {
            CardHeader("What's said", systemImage: "text.bubble") {
                if !lines.isEmpty {
                    languageMenu
                }
            }
            if isWorking {
                HStack(spacing: 10) {
                    ThinkingDots()
                    Text("Listening to the video…")
                        .laqtaFont(14, weight: .medium)
                        .foregroundStyle(palette.goldHi)
                }
            } else if !lines.isEmpty {
                transcript
            } else if !VideoTranscriber.isSupported {
                Text("Reading speech isn't available on this device.")
                    .laqtaFont(14)
                    .foregroundStyle(palette.ink2)
            } else {
                emptyState
            }
        }
        .animation(.snappy, value: isWorking)
        .animation(.snappy, value: lines)
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array((expanded ? lines : Array(lines.prefix(6))).enumerated()), id: \.offset) { index, line in
                Button {
                    onSeek?(line.seconds)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: LaqtaFormat.duration(line.seconds))
                            .laqtaFont(12, weight: .semibold, monospacedDigit: true)
                            .foregroundStyle(palette.goldHi)
                            .frame(minWidth: 40, alignment: .leading)
                        Text(verbatim: line.text)
                            .laqtaFont(14)
                            .foregroundStyle(palette.ink)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .disabled(onSeek == nil)
                .accessibilityHint(onSeek == nil ? Text("") : Text("Plays from here"))
                if index < (expanded ? lines.count : min(lines.count, 6)) - 1 {
                    RowSeparator(inset: 50)
                }
            }
            HStack {
                if lines.count > 6 {
                    Button {
                        withAnimation(.snappy) { expanded.toggle() }
                    } label: {
                        Text(expanded ? "Show less" : "Show all \(lines.count) lines")
                            .laqtaFont(13, weight: .semibold)
                            .foregroundStyle(palette.goldHi)
                    }
                }
                Spacer()
                Button {
                    Clipboard.copy(lines.map(\.text).joined(separator: "\n"))
                    toasts.show(String(localized: "Transcript copied"), systemImage: "doc.on.doc")
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .laqtaFont(13, weight: .semibold)
                        .foregroundStyle(palette.goldHi)
                }
            }
            .buttonStyle(.pressable)
            .padding(.top, 10)
            if let note = analysis.transcriptNote {
                Text(verbatim: note)
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
                    .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let note = analysis.transcriptNote
        let downloadLanguage = note?.hasPrefix("download:") == true ? String(note!.dropFirst("download:".count)) : nil
        VStack(alignment: .leading, spacing: 12) {
            if let downloadLanguage {
                Text("To read what's said, Laqta needs Apple's \(VideoTranscriber.displayName(for: downloadLanguage)) speech model. It downloads once and works offline.")
                    .laqtaFont(14)
                    .foregroundStyle(palette.ink2)
            } else if let note, !note.isEmpty {
                Text(verbatim: note)
                    .laqtaFont(14)
                    .foregroundStyle(palette.ink2)
            } else if !transcribeOn {
                Text("Turn on Read speech in Settings to transcribe videos automatically.")
                    .laqtaFont(14)
                    .foregroundStyle(palette.ink2)
            } else if item.analysisState == .pending {
                Text("Laqta reads the speech after the first look at the video.")
                    .laqtaFont(14)
                    .foregroundStyle(palette.ink2)
            } else {
                Text("Read what's said in this video, on this device.")
                    .laqtaFont(14)
                    .foregroundStyle(palette.ink2)
            }
            AdaptiveButtonRow {
                Button {
                    run(downloadLanguage ?? languages.first ?? "en")
                } label: {
                    LaqtaButtonLabel(downloadLanguage == nil ? "Transcribe" : "Download & Transcribe", systemImage: "waveform", small: true)
                }
                .buttonStyle(.pressable)
                if languages.count > 1 {
                    languageMenu
                }
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(allLanguages, id: \.self) { language in
                Button {
                    run(language)
                } label: {
                    if analysis.transcriptLanguage.map({ Locale(identifier: $0).language.languageCode?.identifier == language }) == true {
                        Label(VideoTranscriber.displayName(for: language), systemImage: "checkmark")
                    } else {
                        Text(verbatim: VideoTranscriber.displayName(for: language))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                Text(verbatim: currentLanguageName)
            }
            .laqtaFont(12, weight: .semibold)
            .foregroundStyle(palette.goldHi)
            .lineLimit(1)
        }
        .layoutPriority(1)
        .accessibilityLabel(Text("Speech language"))
    }

    private var allLanguages: [String] {
        var result = languages
        for code in ["ar", "en", "fr", "es", "de", "hi", "ur", "tr"] where !result.contains(code) {
            result.append(code)
        }
        return result
    }

    private var currentLanguageName: String {
        guard let language = analysis.transcriptLanguage else { return "Language" }
        let code = Locale(identifier: language).language.languageCode?.identifier ?? language
        return VideoTranscriber.displayName(for: code)
    }

    private func run(_ language: String) {
        Task { await intelligence.transcribe(item, language: language, context: modelContext) }
    }
}

private struct MomentsCard: View {
    let sections: [Chapter]
    let title: String
    let onSeek: ((Double) -> Void)?

    @Environment(\.laqta) private var palette

    var body: some View {
        LaqtaCard {
            CardHeader(verbatim: title, systemImage: "list.bullet")
            VStack(spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, chapter in
                    Button {
                        onSeek?(chapter.seconds)
                    } label: {
                        HStack(spacing: 12) {
                            Text(verbatim: LaqtaFormat.duration(chapter.seconds))
                                .laqtaFont(12.5, weight: .semibold, monospacedDigit: true)
                                .foregroundStyle(palette.goldHi)
                                .padding(.horizontal, 9)
                                .frame(minWidth: 30, minHeight: 26)
                                .background(palette.hit, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(verbatim: chapter.title)
                                .laqtaFont(14)
                                .foregroundStyle(palette.ink)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "play.circle")
                                .foregroundStyle(palette.ink3)
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .disabled(onSeek == nil)
                    if index < sections.count - 1 {
                        RowSeparator(inset: 0)
                    }
                }
            }
        }
    }
}

private struct MentionedPlacesCard: View {
    let places: [PlaceRef]
    let onSeek: ((Double) -> Void)?

    @Environment(\.laqta) private var palette

    var body: some View {
        LaqtaCard {
            CardHeader("Places mentioned", systemImage: "mappin.and.ellipse")
            VStack(spacing: 0) {
                ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: place.name)
                                .laqtaFont(15, weight: .medium)
                                .foregroundStyle(palette.ink)
                            if let detail = [place.category, place.distinctDetail].compactMap({ $0 }).first {
                                Text(verbatim: detail)
                                    .laqtaFont(12)
                                    .foregroundStyle(palette.ink2)
                                    .adaptiveLineLimit(1, accessibility: 3)
                            }
                        }
                        Spacer(minLength: 8)
                        if let seconds = place.mentionedAt, let onSeek {
                            Button {
                                onSeek(seconds)
                            } label: {
                                Text(verbatim: LaqtaFormat.duration(seconds))
                                    .laqtaFont(12, weight: .semibold, monospacedDigit: true)
                                    .foregroundStyle(palette.goldHi)
                                    .padding(.horizontal, 9)
                                    .frame(minHeight: 28)
                                    .background(palette.hit, in: Capsule())
                            }
                            .buttonStyle(.pressable)
                            .accessibilityLabel(Text("Play from \(LaqtaFormat.spokenDuration(seconds))"))
                        }
                        Button {
                            Directions.openDirections(to: place)
                        } label: {
                            Image(systemName: place.hasCoordinate ? "car" : "magnifyingglass")
                                .laqtaIconFont(13, weight: .semibold)
                                .foregroundStyle(palette.goldInk)
                                .frame(width: 34, height: 34)
                                .background(palette.accentFill, in: Circle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(Text(place.hasCoordinate ? "Directions" : "Find in Maps"))
                    }
                    .frame(minHeight: 56)
                    if index < places.count - 1 {
                        RowSeparator(inset: 0)
                    }
                }
            }
        }
    }
}
