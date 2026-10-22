//
//  LinkScreen.swift
//  Laqta
//
//  A saved link: blurred hero, actions, and "What's inside" — summary, chapters,
//  places, prices, tips and questions.
//

import Foundation
import SwiftData
import SwiftUI

struct LinkScreen: View {
    let itemID: UUID
    @Binding var path: [Route]

    @Environment(\.laqta) private var palette
    @Query private var matches: [Shot]

    init(itemID: UUID, path: Binding<[Route]>) {
        self.itemID = itemID
        self._path = path
        let target = itemID
        _matches = Query(filter: #Predicate<Shot> { $0.id == target })
    }

    var body: some View {
        if let item = matches.first, item.deletedAt == nil {
            LinkContent(item: item, path: $path)
        } else {
            ZStack {
                LaqtaBackground()
                Text("This link was deleted.")
                    .foregroundStyle(palette.ink2)
            }
        }
    }
}

private struct LinkContent: View {
    let item: Shot
    @Binding var path: [Route]

    @AppObject(LibraryModel.self) private var library
    @AppObject(IntelligenceCenter.self) private var intelligence
    @AppObject(ToastCenter.self) private var rootToasts
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.laqta) private var palette

    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }) private var folders: [Folder]
    @State private var toasts = ToastCenter()
    @State private var showingMove = false
    @State private var noteItem: Shot?
    @State private var backdrop: UIImage?
    @State private var travelTimes: [String: Double] = [:]
    @State private var savedPlaceNames: Set<String> = []

    private var analysis: ShotAnalysis { item.analysis ?? ShotAnalysis() }
    private var folder: Folder? { folders.first { $0.id == item.folderID } }
    private var isReading: Bool {
        intelligence.isRunning(item.id) || (item.analysisState == .pending && item.deepAnalysis == true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock
                    actions
                        .padding(.top, 16)
                    if !item.note.isEmpty {
                        NoteCard(note: item.note) { noteItem = item }
                            .padding(.top, 16)
                    }
                    if item.isYouTube {
                        youTubeSection
                            .padding(.top, 28)
                    } else {
                        insideHeader
                            .padding(.top, 28)
                        insideContent
                            .padding(.top, 14)
                    }
                    footer
                        .padding(.top, 24)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = item.url {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .toastHost(toasts)
        .sheet(isPresented: $showingMove) {
            MoveToFolderSheet(itemIDs: [item.id], currentFolderID: item.folderID)
                .laqtaThemed()
        }
        .sheet(item: $noteItem) { item in
            NoteEditorSheet(item: item)
                .laqtaThemed()
        }
        .task(id: item.thumbnailName) {
            // YouTube thumbnails are shown as they are, never blurred.
            guard item.hasThumbnail, !item.isYouTube else {
                backdrop = nil
                return
            }
            backdrop = await CoverRenderer.backdrop(from: item.thumbnailURL)?.image
        }
        .task(id: item.id) {
            library.markViewed(item, context: modelContext)
            if item.isYouTube {
                if YouTubeRefresher.needsDetails(item) {
                    await intelligence.analyzeLink(item, context: modelContext)
                }
            } else if item.analysisState == .pending, item.deepAnalysis == true {
                await intelligence.analyzeLink(item, context: modelContext)
            }
        }
        .onDisappear {
            intelligence.markSeen(item.id)
        }
    }

    // MARK: Hero

    private var hero: some View {
        Button {
            openPrimary()
        } label: {
            ZStack {
                if item.isYouTube, item.hasPreviewImage {
                    // Shown whole and uncovered, as YouTube provides it.
                    ShotThumbnail(shot: item, cornerRadius: 14, fits: true)
                        .aspectRatio(16 / 9, contentMode: .fit)
                } else if item.hasPreviewImage {
                    ShotThumbnail(shot: item, cornerRadius: 14)
                        .aspectRatio(16 / 9, contentMode: .fit)
                } else {
                    GenericLinkArt(site: item.linkSite ?? "")
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                if item.isLinkVideo, !item.isYouTube || !item.hasPreviewImage {
                    Image(systemName: "play.fill")
                        .laqtaIconFont(24, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 66, height: 66)
                        .glassEffect(.regular.tint(.black.opacity(0.3)), in: Circle())
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let duration = item.linkDuration, item.isLinkVideo, !item.isYouTube {
                    Text(verbatim: LaqtaFormat.duration(duration))
                        .laqtaFont(13, weight: .semibold, monospacedDigit: true)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(minHeight: 26)
                        .background(Color.black.opacity(0.62), in: Capsule())
                        .padding(10)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 10)
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, 12)
        .padding(.top, 104)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Color(hex: 0x0E0C0B)
                Color.clear
                    .overlay {
                        if let backdrop {
                            Image(uiImage: backdrop)
                                .resizable()
                                .scaledToFill()
                                .accessibilityIgnoresInvertColors()
                                .scaleEffect(1.25)
                                .opacity(0.9)
                        }
                    }
                    .clipped()
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35))
                LinearGradient(colors: [palette.bg.opacity(0), palette.bg], startPoint: UnitPoint(x: 0.5, y: 0.82), endPoint: .bottom)
            }
        }
        .clipped()
        .accessibilityLabel(Text(verbatim: "\(primaryActionTitle) \(item.displayTitle)"))
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: item.linkForm.systemImage)
                    .laqtaIconFont(12, weight: .semibold)
                Text(verbatim: [item.linkSite, item.linkAuthor].compactMap { $0 }.joined(separator: " · "))
                    .adaptiveLineLimit(1, accessibility: 2)
            }
            .laqtaFont(14)
            .foregroundStyle(palette.ink2)

            Text(verbatim: item.displayTitle)
                .laqtaFont(23, weight: .bold)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if !metaLine.isEmpty {
                Text(verbatim: metaLine)
                    .laqtaFont(13)
                    .foregroundStyle(palette.ink2)
            }
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let duration = item.linkDuration, item.isLinkVideo { parts.append(LaqtaFormat.duration(duration)) }
        if let views = item.linkViews, views > 0 { parts.append("\(LaqtaFormat.compact(views)) views") }
        if let published = item.linkPublishedAt { parts.append(LaqtaFormat.shortDate(published)) }
        if parts.isEmpty { parts.append(item.linkForm.label) }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private var actions: some View {
        // One row when it fits (iPad, short labels); otherwise the main action gets its own row.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                primaryButton(fullWidth: false)
                copyButton(fullWidth: false)
                iconButtons
            }
            VStack(spacing: 10) {
                primaryButton(fullWidth: true)
                HStack(spacing: 8) {
                    copyButton(fullWidth: true)
                    iconButtons
                }
            }
        }
        .buttonStyle(.pressable)
    }

    private func primaryButton(fullWidth: Bool) -> some View {
        Button(action: openPrimary) {
            LaqtaButtonLabel(verbatim: primaryActionTitle, systemImage: item.linkForm.primarySymbol, fullWidth: fullWidth)
        }
    }

    private func copyButton(fullWidth: Bool) -> some View {
        Button {
            if let url = item.linkURL {
                Clipboard.copy(url)
                toasts.show(String(localized: "Link copied"), systemImage: "doc.on.doc")
            }
        } label: {
            LaqtaButtonLabel("Copy Link", systemImage: "doc.on.doc", kind: .line, fullWidth: fullWidth)
        }
    }

    @ViewBuilder
    private var iconButtons: some View {
        Button {
            noteItem = item
        } label: {
            OutlineIconButtonLabel(systemImage: item.note.isEmpty ? "note.text.badge.plus" : "note.text")
        }
        .accessibilityLabel(Text(item.note.isEmpty ? "Add Note" : "Edit Note"))
        Button {
            showingMove = true
        } label: {
            OutlineIconButtonLabel(systemImage: "folder.badge.plus")
        }
        .accessibilityLabel(Text("Move"))
        Button {
            trash()
        } label: {
            OutlineIconButtonLabel(systemImage: "trash")
        }
        .accessibilityLabel(Text("Delete"))
    }

    private var primaryActionTitle: String {
        guard item.isYouTube else { return item.linkForm.primaryAction }
        return item.isLinkVideo ? "Watch on YouTube" : "Open in YouTube"
    }

    private func trash() {
        let target = item
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            library.trash([target], context: modelContext)
            rootToasts.show(String(localized: "Moved to Recently Deleted"), systemImage: "trash", actionTitle: String(localized: "Undo")) {
                library.restore([target], context: modelContext)
            }
        }
    }

    private func openPrimary() {
        guard let url = item.url else { return }
        openURL(url)
    }

    // MARK: YouTube

    /// The video's details as YouTube returns them.
    private var youTubeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Image(systemName: "play.rectangle.fill")
                        .laqtaIconFont(15, weight: .semibold)
                        .foregroundStyle(palette.goldHi)
                        .frame(width: 32, height: 32)
                        .background(palette.field, in: Circle())
                        .accessibilityHidden(true)
                    Text("From YouTube")
                        .laqtaFont(20, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .layoutPriority(1)
                        .accessibilityAddTraits(.isHeader)
                    Rectangle()
                        .fill(palette.hair)
                        .frame(height: 1)
                }
                Text(verbatim: youTubeStatusLine)
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
                    .padding(.leading, 44)
            }

            if intelligence.isRunning(item.id), YouTubeRefresher.needsDetails(item) {
                ReadingCard(form: .video, message: "Getting the details from YouTube…")
            } else if item.linkUnavailable == true {
                LaqtaCard {
                    Text("This video was removed or made private on YouTube. The link and your note are still here.")
                        .laqtaFont(14)
                        .foregroundStyle(palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if YouTubeRefresher.needsDetails(item) {
                LaqtaCard {
                    Text("Laqta couldn't reach YouTube. The video's details appear when you're online.")
                        .laqtaFont(14)
                        .foregroundStyle(palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { await intelligence.analyzeLink(item, context: modelContext) }
                    } label: {
                        LaqtaButtonLabel("Try Again", systemImage: "arrow.clockwise", kind: .line, small: true)
                    }
                    .buttonStyle(.pressable)
                    .disabled(intelligence.isRunning(item.id))
                    .padding(.top, 12)
                }
            }

            if let details = item.linkDetails?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty {
                LaqtaCard {
                    CardHeader("Description", systemImage: "text.alignleft")
                    ExpandableText(text: details)
                }
            }
            if !analysis.sections.isEmpty {
                sectionsCard
            }

            Text("The title, channel and thumbnail come from YouTube. Playing a video opens it in YouTube.")
                .laqtaFont(12)
                .foregroundStyle(palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 4)
        }
        .animation(.snappy, value: item.linkRefreshedAt)
    }

    private var youTubeStatusLine: String {
        if item.linkUnavailable == true { return "No longer available on YouTube" }
        guard !YouTubeRefresher.needsDetails(item), let refreshed = item.linkRefreshedAt else { return "Waiting for YouTube" }
        return "Updated \(LaqtaFormat.relative(refreshed))"
    }

    // MARK: What's inside

    private var insideHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                AIBadge(size: 32)
                Text("What's inside")
                    .laqtaFont(20, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .layoutPriority(1)
                Rectangle()
                    .fill(palette.hair)
                    .frame(height: 1)
            }
            Text(verbatim: basisLine)
                .laqtaFont(12)
                .foregroundStyle(palette.ink2)
                .padding(.leading, 44)
        }
    }

    private var basisLine: String {
        if item.deepAnalysis != true {
            return "Only the title and preview were saved"
        }
        return analysis.basis ?? "Reading the \(item.linkForm.label.lowercased())…"
    }

    @ViewBuilder
    private var insideContent: some View {
        VStack(spacing: 12) {
            if item.deepAnalysis != true {
                shallowCard
            } else if isReading, analysis.summary.isEmpty {
                ReadingCard(form: item.linkForm)
            } else {
                if !analysis.summary.isEmpty {
                    LaqtaCard {
                        CardHeader("Summary", systemImage: "sparkles")
                        BulletList(items: analysis.summary, reveal: intelligence.isFresh(item.id))
                    }
                }
                if !analysis.sections.isEmpty {
                    sectionsCard
                }
                if !analysis.places.isEmpty {
                    placesCard
                }
                if !analysis.prices.isEmpty {
                    pricesCard
                }
                if !analysis.tips.isEmpty {
                    LaqtaCard {
                        CardHeader("Tips", systemImage: "lightbulb")
                        BulletList(items: analysis.tips)
                    }
                }
                if item.analysisState == .failed {
                    LaqtaCard {
                        Text("Laqta couldn't open this link. It may need a sign-in, or the site may be unavailable.")
                            .laqtaFont(14)
                            .foregroundStyle(palette.ink2)
                        Button {
                            Task { await intelligence.extractEverything(item, context: modelContext) }
                        } label: {
                            LaqtaButtonLabel("Try Again", systemImage: "arrow.clockwise", kind: .line, small: true)
                        }
                        .buttonStyle(.pressable)
                        .padding(.top, 12)
                    }
                }
            }
            if item.deepAnalysis == true {
                AskCard(item: item, title: askTitle, suggestions: analysis.questions)
            }
        }
        .animation(.snappy, value: analysis)
        .animation(.snappy, value: isReading)
    }

    private var askTitle: String {
        switch item.linkForm {
        case .video: "Ask about this video"
        case .article: "Ask about this article"
        case .post: "Ask about this post"
        case .product: "Ask about this product"
        case .place, .page: "Ask about this page"
        }
    }

    private var shallowCard: some View {
        LaqtaCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Extract everything")
                        .laqtaFont(16, weight: .semibold)
                        .foregroundStyle(palette.ink)
                    Text("Laqta reads the \(item.linkForm.label.lowercased()) on this \(LaqtaDevice.name): summary, chapters, places and prices.")
                        .laqtaFont(13)
                        .foregroundStyle(palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    Task { await intelligence.extractEverything(item, context: modelContext) }
                } label: {
                    LaqtaButtonLabel("Extract", systemImage: "sparkles")
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private var sectionsCard: some View {
        LaqtaCard {
            CardHeader(verbatim: analysis.sectionsTitle ?? item.linkForm.sectionsTitle, systemImage: "list.bullet")
            VStack(spacing: 0) {
                ForEach(Array(analysis.sections.enumerated()), id: \.offset) { index, chapter in
                    Button {
                        open(at: chapter)
                    } label: {
                        HStack(spacing: 12) {
                            Text(verbatim: chapter.seconds >= 0 ? LaqtaFormat.duration(chapter.seconds) : "\(index + 1)")
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
                            if chapter.seconds >= 0, item.isLinkVideo {
                                Image(systemName: "play.circle")
                                    .foregroundStyle(palette.ink3)
                            }
                        }
                        .frame(minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .disabled(chapter.seconds < 0)
                    if index < analysis.sections.count - 1 {
                        RowSeparator(inset: 0)
                    }
                }
            }
        }
    }

    private func open(at chapter: Chapter) {
        guard let url = item.url, chapter.seconds >= 0 else { return }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = components?.queryItems?.filter { $0.name != "t" } ?? []
        items.append(URLQueryItem(name: "t", value: "\(Int(chapter.seconds))s"))
        components?.queryItems = items
        openURL(components?.url ?? url)
        toasts.show(String(localized: "Opening at \(LaqtaFormat.duration(chapter.seconds))"), systemImage: "play")
    }

    private var placesCard: some View {
        LaqtaCard {
            CardHeader("Places mentioned", systemImage: "mappin.and.ellipse")
            VStack(spacing: 0) {
                ForEach(Array(analysis.places.enumerated()), id: \.element.id) { index, place in
                    HStack(spacing: 12) {
                        Image(systemName: "mappin")
                            .laqtaIconFont(13, weight: .semibold)
                            .foregroundStyle(palette.goldHi)
                            .frame(width: 32, height: 32)
                            .background(palette.field, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(verbatim: place.name)
                                    .laqtaFont(15, weight: .medium)
                                    .foregroundStyle(palette.ink)
                                    .adaptiveLineLimit(1, accessibility: 2)
                                if savedPlaceNames.contains(SearchIndex.normalize(place.name)) {
                                    Text("In your shots")
                                        .laqtaFont(10.5, weight: .semibold, maxScale: 1.25)
                                        .foregroundStyle(palette.goldHi)
                                        .padding(.horizontal, 7)
                                        .frame(minHeight: 20)
                                        .background(palette.hit, in: Capsule())
                                }
                            }
                            if let detail = [place.category, place.distinctDetail].compactMap({ $0 }).first {
                                Text(verbatim: detail)
                                    .laqtaFont(12)
                                    .foregroundStyle(palette.ink2)
                                    .adaptiveLineLimit(1, accessibility: 3)
                            }
                        }
                        Spacer(minLength: 8)
                        Button {
                            Directions.openDirections(to: place)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: place.hasCoordinate ? "car" : "magnifyingglass")
                                    .laqtaIconFont(12, weight: .semibold)
                                Text(verbatim: travelTimes[place.id].map(LaqtaFormat.travelTime) ?? (place.hasCoordinate ? "Go" : "Find"))
                                    .laqtaFont(13, weight: .semibold)
                            }
                            .foregroundStyle(palette.goldInk)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(palette.accentFill, in: Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                    .frame(minHeight: 62)
                    if index < analysis.places.count - 1 {
                        RowSeparator(inset: 44)
                    }
                }
            }
        }
        .task(id: analysis.places.map(\.id)) {
            savedPlaceNames = loadSavedPlaceNames()
            for place in analysis.places where place.hasCoordinate && travelTimes[place.id] == nil {
                if let time = await Directions.travelTime(to: place) {
                    travelTimes[place.id] = time
                }
            }
        }
    }

    /// Place names the user already has in their photos.
    private func loadSavedPlaceNames() -> Set<String> {
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { item in
            item.tagsRaw != nil && item.deletedAt == nil
        })
        let items = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.kind == .photo }
        let names: [String] = items.compactMap { $0.analysis?.place?.name }
        return Set(names.map { SearchIndex.normalize($0) })
    }

    private var pricesCard: some View {
        LaqtaCard {
            CardHeader(item.linkForm == .product ? "Price" : "Prices", systemImage: "tag")
            VStack(spacing: 0) {
                ForEach(Array(analysis.prices.enumerated()), id: \.element.id) { index, price in
                    HStack(spacing: 12) {
                        Text(verbatim: price.label)
                            .laqtaFont(14)
                            .foregroundStyle(palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: price.value)
                            .laqtaFont(14, weight: .semibold, monospacedDigit: true)
                            .foregroundStyle(palette.goldHi)
                    }
                    .padding(.vertical, 8)
                    .frame(minHeight: 50)
                    .contextMenu {
                        Button {
                            Clipboard.copy(price.value)
                        } label: {
                            Label("Copy Price", systemImage: "doc.on.doc")
                        }
                    }
                    if index < analysis.prices.count - 1 {
                        RowSeparator(inset: 0)
                    }
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .laqtaIconFont(12)
            Text("Saved to")
            if let folder {
                FolderNameText(name: folder.name, size: 15, color: palette.goldHi)
            }
            Text(verbatim: "·")
            Text("Shared from \(item.sourceName ?? "Safari") · \(LaqtaFormat.shortDate(item.addedAt))")
                .lineLimit(1)
        }
        .laqtaFont(12)
        .foregroundStyle(palette.ink2)
        .frame(maxWidth: .infinity)
    }
}

private struct ReadingCard: View {
    let form: LinkForm
    var message: String?
    @Environment(\.laqta) private var palette

    var body: some View {
        LaqtaCard {
            HStack(spacing: 10) {
                ThinkingDots()
                Text(verbatim: message ?? defaultMessage)
                    .laqtaFont(14, weight: .medium)
                    .foregroundStyle(palette.goldHi)
            }
            VStack(alignment: .leading, spacing: 10) {
                ShimmerLine(height: 12)
                ShimmerLine(width: 260, height: 12)
                ShimmerLine(width: 200, height: 12)
            }
            .padding(.top, 14)
        }
    }

    private var defaultMessage: String {
        switch form {
        case .video: "Reading the video's chapters and description…"
        case .article: "Reading the article…"
        case .product: "Reading the product page…"
        default: "Reading everything inside…"
        }
    }
}

