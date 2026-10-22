//
//  ShotViewer.swift
//  Laqta
//
//  Full-screen viewer for photos and videos: glass chrome, the Intelligence pill,
//  video controls, notes, a filmstrip and actions.
//  Swipe between items, swipe down to close, swipe up for Intelligence.
//

import Foundation
import SwiftData
import SwiftUI

struct ShotViewer: View {
    let folderID: UUID
    let startID: UUID
    @Binding var path: [Route]

    @AppObject(LibraryModel.self) private var library
    @AppObject(IntelligenceCenter.self) private var intelligence
    @AppObject(ToastCenter.self) private var toasts
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.laqta) private var palette

    @Query private var folderItems: [Shot]
    @Query private var folderMatches: [Folder]

    @State private var currentID: UUID?
    @State private var chromeHidden = false
    @State private var isZoomed = false
    @State private var showingIntelligence = false
    @State private var showingDetails = false
    @State private var showingMove = false
    @State private var showingPlace = false
    /// Read once per shot rather than on every draw of the toolbar.
    @State private var contacts = ShotContacts()
    @State private var noteItem: Shot?
    @State private var eventDraft: EventDraft?
    @State private var completedActions: Set<String> = []
    @State private var playback = VideoPlaybackModel()

    init(folderID: UUID, startID: UUID, path: Binding<[Route]>) {
        self.folderID = folderID
        self.startID = startID
        self._path = path
        let target: UUID? = folderID
        _folderItems = Query(
            filter: #Predicate<Shot> { item in
                item.folderID == target && item.deletedAt == nil
            },
            sort: \Shot.addedAt,
            order: .reverse
        )
        let folderTarget = folderID
        _folderMatches = Query(filter: #Predicate<Folder> { $0.id == folderTarget })
    }

    /// Photos and videos in the folder (PDFs and links open in their own screens).
    private var shots: [Shot] {
        folderItems.filter(\.isViewerMedia)
    }

    /// Same order as the folder grid.
    private var items: [Shot] {
        let sort = folderMatches.first?.sort ?? .newest
        guard sort != .newest else { return shots }
        return shots.sorted { sort.areInIncreasingOrder($0.sortKey, $1.sortKey) }
    }

    private var current: Shot? {
        guard let currentID else { return nil }
        return shots.first { $0.id == currentID }
    }

    var body: some View {
        ZStack {
            (chromeHidden ? Color.black : palette.viewer)
                .ignoresSafeArea()

            pager

            if !chromeHidden {
                chrome
                    .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(chromeHidden)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard !isZoomed else { return }
                    let vertical = value.translation.height
                    let horizontal = abs(value.translation.width)
                    if vertical < -70, horizontal < 70 {
                        showingIntelligence = true
                    }
                }
        )
        .onAppear {
            if currentID == nil { currentID = startID }
        }
        .onChange(of: currentID) { _, newValue in
            isZoomed = false
            showingDetails = false
            if let newValue, let item = shots.first(where: { $0.id == newValue }) {
                library.markViewed(item, context: modelContext)
                if item.isVideoFile {
                    playback.prepare(item)
                } else {
                    playback.stop()
                }
            }
        }
        .onChange(of: shots.map(\.id)) { _, ids in
            if ids.isEmpty {
                dismiss()
            } else if let currentID, !ids.contains(currentID) {
                self.currentID = ids.first
            }
        }
        .onDisappear {
            playback.stop()
        }
        .task(id: currentID) {
            contacts = ContactReader.read(current?.analysis)
        }
        .sheet(isPresented: sheetIntelligence) {
            if let current {
                IntelligenceSheet(itemID: current.id) { seconds in
                    showingIntelligence = false
                    if current.isVideoFile {
                        playback.seek(to: seconds, in: current)
                    }
                }
                .laqtaThemed()
            }
        }
        // iPad: Intelligence stays open beside the photo while you page through.
        .inspector(isPresented: inspectorIntelligence) {
            if let current {
                IntelligenceSheet(itemID: current.id, onSeek: { seconds in
                    if current.isVideoFile {
                        playback.seek(to: seconds, in: current)
                    }
                }, onClose: {
                    showingIntelligence = false
                })
                .id(current.id)
                .laqtaThemed()
                .inspectorColumnWidth(min: 340, ideal: 380, max: 460)
            }
        }
        .sheet(isPresented: $showingPlace) {
            if let current {
                ShotPlaceSheet(item: current)
                    .laqtaThemed()
            }
        }
        .sheet(item: $noteItem) { item in
            NoteEditorSheet(item: item)
                .laqtaThemed()
        }
        .sheet(isPresented: $showingMove) {
            if let current {
                MoveToFolderSheet(itemIDs: [current.id], currentFolderID: folderID)
                    .laqtaThemed()
            }
        }
        .sheet(item: $eventDraft) { draft in
            EventEditView(draft: draft) { saved in
                if saved {
                    completedActions.insert(draft.actionKey)
                    toasts.show("Added to Calendar · \(draft.title)", systemImage: "checkmark")
                }
            }
            .ignoresSafeArea()
        }
        .background {
            // Keyboard: arrows move between items, space plays a video.
            Group {
                Button("Previous") { step(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("Next") { step(1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Play or Pause") {
                    if let current, current.isVideoFile { playback.toggle(current) }
                }
                .keyboardShortcut(.space, modifiers: [])
                Button("Info") { showingIntelligence.toggle() }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private var usesInspector: Bool { sizeClass == .regular }

    private var sheetIntelligence: Binding<Bool> {
        Binding(
            get: { showingIntelligence && !usesInspector },
            set: { showingIntelligence = $0 }
        )
    }

    private var inspectorIntelligence: Binding<Bool> {
        Binding(
            get: { showingIntelligence && usesInspector },
            set: { showingIntelligence = $0 }
        )
    }

    private func step(_ offset: Int) {
        let list = items
        guard let currentID, let index = list.firstIndex(where: { $0.id == currentID }) else { return }
        let next = index + offset
        guard list.indices.contains(next) else { return }
        withAnimation(.snappy) { self.currentID = list[next].id }
    }

    // MARK: Pager

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(items) { shot in
                    Group {
                        if shot.isVideoFile {
                            VideoPage(shot: shot, playback: playback) {
                                toggleChrome()
                            }
                        } else {
                            ShotPage(shot: shot, isZoomed: $isZoomed) {
                                toggleChrome()
                            }
                        }
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(shot.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .scrollDisabled(isZoomed)
        // On iPad the Intelligence inspector takes the trailing space, so photos stay beside it.
        .ignoresSafeArea(edges: usesInspector ? .vertical : .all)
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.22)) {
            chromeHidden.toggle()
        }
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            bottomStack
        }
        .background {
            VStack(spacing: 0) {
                LinearGradient(colors: [palette.viewerTop, palette.viewerTop.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
                Spacer(minLength: 0)
                LinearGradient(colors: [palette.viewerBottom.opacity(0), palette.viewerBottom], startPoint: .top, endPoint: .bottom)
                    .frame(height: 300)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                CircleIcon(systemImage: "chevron.left", glass: true)
            }
            .accessibilityLabel(Text("Back"))
            .largeContentLabel(Text("Back"), systemImage: "chevron.left")
            Spacer(minLength: 0)
            if let current {
                VStack(spacing: 0) {
                    Text(verbatim: LaqtaFormat.viewerDate(current.capturedAt ?? current.addedAt))
                        .laqtaFont(15, weight: .semibold, maxScale: 1.25)
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    if let folder = folderMatches.first {
                        FolderNameText(name: folder.name, size: 14, color: palette.ink2, maxScale: 1.25)
                            .frame(minHeight: 16)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
                .frame(minHeight: 48)
                .laqtaGlass(in: Capsule())
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.snappy) { showingDetails.toggle() }
            } label: {
                CircleIcon(systemImage: showingDetails ? "xmark" : "info.circle", glass: true)
            }
            .accessibilityLabel(Text("Details"))
            .largeContentLabel(Text("Details"), systemImage: "info.circle")
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .overlay(alignment: .topTrailing) {
            if showingDetails, let current {
                ShotDetailsCard(shot: current)
                    .padding(.top, 62)
                    .padding(.trailing, 16)
                    .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .zIndex(1)
    }

    private var bottomStack: some View {
        VStack(spacing: 10) {
            if let current, !current.note.isEmpty {
                NotePill(note: current.note) {
                    noteItem = current
                }
                .id("note-\(current.id)")
                .transition(.opacity)
            }
            if let current, let pill = pillModel(for: current) {
                AIPill(model: pill, isDone: completedActions.contains(pill.actionKey)) {
                    perform(pill.action, for: current, key: pill.actionKey)
                } onOpen: {
                    showingIntelligence = true
                }
                .id(current.id)
                .transition(.opacity)
            }
            if let current, current.isVideoFile {
                VideoControls(shot: current, playback: playback)
                    .id("controls-\(current.id)")
                    .transition(.opacity)
            }
            if shots.count > 1 {
                Filmstrip(shots: items, currentID: $currentID)
            }
            toolbar
        }
        .frame(maxWidth: 620)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.snappy, value: currentID)
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            if let current {
                ShareLink(item: ShareableFile(item: current), preview: SharePreview(Text(verbatim: current.shareFileName))) {
                    toolbarIcon("square.and.arrow.up")
                }
                .accessibilityLabel(Text("Share"))
                .largeContentLabel(Text("Share"), systemImage: "square.and.arrow.up")
                if contacts.isWorthShowing {
                    Button {
                        showingPlace = true
                    } label: {
                        toolbarIcon("mappin.and.ellipse")
                    }
                    .accessibilityLabel(Text("Place and Links"))
                    .largeContentLabel(Text("Place and Links"), systemImage: "mappin.and.ellipse")
                }
                Button {
                    library.toggleFavorite(current, context: modelContext)
                } label: {
                    toolbarIcon(current.isFavorite ? "heart.fill" : "heart")
                        .symbolEffect(.bounce, value: current.isFavorite)
                }
                .accessibilityLabel(Text(current.isFavorite ? "Remove from Favorites" : "Favorite"))
                .largeContentLabel(Text(current.isFavorite ? "Remove from Favorites" : "Favorite"), systemImage: current.isFavorite ? "heart.fill" : "heart")
                Button {
                    showingIntelligence = true
                } label: {
                    toolbarIcon("sparkles")
                }
                .accessibilityLabel(Text("Intelligence"))
                .largeContentLabel(Text("Intelligence"), systemImage: "sparkles")
                Button {
                    noteItem = current
                } label: {
                    toolbarIcon(current.note.isEmpty ? "note.text.badge.plus" : "note.text")
                }
                .accessibilityLabel(Text(current.note.isEmpty ? "Add Note" : "Edit Note"))
                .largeContentLabel(Text(current.note.isEmpty ? "Add Note" : "Edit Note"), systemImage: "note.text")
                Button {
                    showingMove = true
                } label: {
                    toolbarIcon("folder.badge.plus")
                }
                .accessibilityLabel(Text("Move"))
                .largeContentLabel(Text("Move"), systemImage: "folder.badge.plus")
                Button {
                    deleteCurrent()
                } label: {
                    toolbarIcon("trash")
                }
                .accessibilityLabel(Text("Delete"))
                .largeContentLabel(Text("Delete"), systemImage: "trash")
            }
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, 12)
        .frame(height: 58)
        .laqtaGlass(in: Capsule())
    }

    private func toolbarIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .laqtaIconFont(19, weight: .regular)
            .foregroundStyle(palette.goldHi)
            .frame(maxWidth: .infinity, minHeight: 48)
            .frame(minWidth: 40)
            .contentShape(Rectangle())
    }

    // MARK: Intelligence pill

    private func pillModel(for shot: Shot) -> AIPillModel? {
        guard AppGroup.bool(SettingsKey.analyzeShots) else { return nil }
        let analysis = shot.analysis
        if shot.analysisState == .pending || intelligence.isRunning(shot.id) {
            if analysis?.title == nil, analysis?.place == nil {
                let title = shot.isVideoFile ? "Watching the video…" : "Analyzing…"
                return AIPillModel(systemImage: "sparkles", title: title, subtitle: "On this \(LaqtaDevice.name)", action: .nothing, actionKey: "")
            }
        }
        guard let analysis else { return nil }
        let key = shot.id.uuidString

        if shot.isVideoFile, let transcript = analysis.transcript, !transcript.isEmpty, analysis.place == nil {
            let title = analysis.title ?? (analysis.summary.first ?? String(localized: "What's said"))
            let subtitle = "\(LaqtaFormat.count(transcript.count, "line", "lines")) of speech · \(analysis.summary.isEmpty ? "tap to read" : "summary ready")"
            return AIPillModel(systemImage: "text.bubble", title: title, subtitle: subtitle, action: .nothing, actionKey: key)
        }

        if let place = analysis.place, place.hasCoordinate {
            var subtitle = [place.category, place.distinctDetail]
                .compactMap { $0 }
                .filter { $0 != "Location" }
                .joined(separator: " · ")
            if subtitle.isEmpty {
                subtitle = place.origin == "GPS" ? "Where it was taken" : "On the map"
            }
            return AIPillModel(systemImage: "mappin.and.ellipse", title: place.name, subtitle: subtitle, action: .directions(place), actionKey: key + "directions")
        }
        let now = Date.now
        if let date = analysis.entities.first(where: { $0.kind == .date && ($0.date ?? .distantPast) > now }), let when = date.date {
            let title = analysis.title ?? analysis.category ?? "Event"
            if analysis.category == "Warranty" || analysis.category == "Receipt" {
                return AIPillModel(systemImage: "bell", title: title, subtitle: "Due \(date.display)", action: .remind(title: title, date: when), actionKey: key + "remind")
            }
            return AIPillModel(systemImage: "calendar", title: title, subtitle: date.display, action: .addEvent(EventDraft(title: title, start: when, allDay: date.allDay, notes: analysis.text, actionKey: key + "event")), actionKey: key + "event")
        }
        if let source = analysis.source, let urlString = source.url, let url = URL(string: urlString) {
            return AIPillModel(systemImage: source.systemImage, title: analysis.title ?? source.headline, subtitle: source.detail ?? LinkDraft.displayHost(url), action: .open(url), actionKey: key + "open")
        }
        if let text = analysis.text, text.count > 120 {
            return AIPillModel(systemImage: "text.viewfinder", title: analysis.title ?? "Text found", subtitle: analysis.category ?? "Get the key points", action: .summarize, actionKey: key + "summarize")
        }
        if let title = analysis.title {
            return AIPillModel(systemImage: "sparkles", title: title, subtitle: analysis.category ?? analysis.labels.joined(separator: " · "), action: .nothing, actionKey: key)
        }
        if !analysis.labels.isEmpty {
            return AIPillModel(systemImage: "photo", title: analysis.labels[0], subtitle: analysis.labels.dropFirst().joined(separator: " · "), action: .nothing, actionKey: key)
        }
        return nil
    }

    private func perform(_ action: AIPillModel.Action, for shot: Shot, key: String) {
        switch action {
        case .nothing:
            showingIntelligence = true
        case let .directions(place):
            Directions.openDirections(to: place)
        case let .addEvent(draft):
            eventDraft = draft
        case let .remind(title, date):
            Task {
                if await Reminders.schedule(title: title, at: date) {
                    completedActions.insert(key)
                    toasts.show("Reminder set · \(LaqtaFormat.eventDate(date, allDay: true))", systemImage: "bell")
                } else {
                    toasts.show("Allow notifications to get reminders", systemImage: "bell.slash")
                }
            }
        case let .open(url):
            openURL(url)
        case .summarize:
            showingIntelligence = true
            Task { await intelligence.summarize(shot, context: modelContext) }
        }
    }

    private func deleteCurrent() {
        let list = items
        guard let current, let index = list.firstIndex(where: { $0.id == current.id }) else { return }
        var neighbour: Shot?
        if list.indices.contains(index + 1) {
            neighbour = list[index + 1]
        } else if index > 0 {
            neighbour = list[index - 1]
        }
        if current.isVideoFile { playback.stop() }
        currentID = neighbour?.id
        withAnimation {
            library.trash([current], context: modelContext)
        }
        toasts.show("Moved to Recently Deleted", systemImage: "trash", actionTitle: "Undo") {
            withAnimation {
                library.restore([current], context: modelContext)
            }
        }
        if neighbour == nil { dismiss() }
    }
}

// MARK: - Pieces

struct AIPillModel {
    enum Action {
        case nothing
        case directions(PlaceRef)
        case addEvent(EventDraft)
        case remind(title: String, date: Date)
        case open(URL)
        case summarize
    }

    let systemImage: String
    let title: String
    let subtitle: String
    let action: Action
    let actionKey: String

    var actionTitle: String? {
        switch action {
        case .nothing: nil
        case .directions: "Directions"
        case .addEvent: "Add"
        case .remind: "Remind"
        case .open: "Open"
        case .summarize: "Summarize"
        }
    }

    var actionSymbol: String {
        switch action {
        case .nothing: "sparkles"
        case .directions: "location"
        case .addEvent: "calendar.badge.plus"
        case .remind: "bell"
        case .open: "arrow.up.right"
        case .summarize: "sparkles"
        }
    }

    var doneTitle: String {
        switch action {
        case .addEvent: "Added"
        case .remind: "Set"
        default: "Done"
        }
    }
}

private struct AIPill: View {
    let model: AIPillModel
    let isDone: Bool
    let onAction: () -> Void
    let onOpen: () -> Void

    @Environment(\.laqta) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: model.systemImage)
                        .laqtaIconFont(17, weight: .semibold)
                        .foregroundStyle(LaqtaPalette.aiInk)
                        .frame(width: 42, height: 42)
                        .background(LaqtaPalette.aiGradient, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: model.title)
                            .laqtaFont(15, weight: .semibold, maxScale: 1.4)
                            .foregroundStyle(palette.ink)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        if !model.subtitle.isEmpty {
                            Text(verbatim: model.subtitle)
                                .laqtaFont(12, maxScale: 1.4)
                                .foregroundStyle(palette.ink2)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Shows Intelligence for this item"))

            if let title = model.actionTitle {
                Button(action: onAction) {
                    HStack(spacing: 6) {
                        Image(systemName: isDone ? "checkmark" : model.actionSymbol)
                            .laqtaIconFont(13, weight: .semibold)
                        Text(verbatim: isDone ? model.doneTitle : title)
                            .laqtaFont(15, weight: .semibold, maxScale: 1.3)
                            .lineLimit(1)
                    }
                    .foregroundStyle(palette.goldInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .frame(minHeight: 38)
                    .background(palette.accentFill, in: Capsule())
                    .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.pressable)
                .disabled(isDone)
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 64)
        .laqtaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct Filmstrip: View {
    let shots: [Shot]
    @Binding var currentID: UUID?
    @Environment(\.laqta) private var palette

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                // Lazy: a non-lazy stack builds a thumbnail view, and starts its load
                // task, for every photo in the folder the moment the viewer opens.
                LazyHStack(spacing: 2) {
                    ForEach(shots) { shot in
                        Button {
                            withAnimation(.snappy) { currentID = shot.id }
                        } label: {
                            ShotThumbnail(shot: shot, cornerRadius: 8)
                                .frame(width: 36, height: 50)
                                .overlay(alignment: .bottomTrailing) {
                                    if shot.isVideoFile {
                                        Image(systemName: "play.fill")
                                            .laqtaIconFont(7, weight: .bold)
                                            .foregroundStyle(.white)
                                            .padding(3)
                                            .background(Color.black.opacity(0.5), in: Circle())
                                            .padding(2)
                                    }
                                }
                                .padding(2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(shot.id == currentID ? palette.goldHi : .clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .id(shot.id)
                        .accessibilityLabel(Text(verbatim: shot.kindLabel))
                        .accessibilityAddTraits(shot.id == currentID ? .isSelected : [])
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: CGFloat(shots.count) * 42 + 8)
            .laqtaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onChange(of: currentID) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(height: 62)
    }
}

private struct ShotDetailsCard: View {
    let shot: Shot
    @Environment(\.laqta) private var palette
    /// Grows with the text size, up to what fits on a phone.
    @ScaledMetric(relativeTo: .footnote) private var width: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Type", shot.kindLabel)
            if let duration = shot.mediaDuration, shot.isVideoFile {
                row("Length", LaqtaFormat.duration(duration))
            }
            row("Size", "\(LaqtaFormat.number(shot.pixelWidth)) × \(LaqtaFormat.number(shot.pixelHeight)) · \(LaqtaFormat.bytes(Int64(shot.byteCount)))")
            if let captured = shot.capturedAt {
                row(shot.isVideoFile ? "Recorded" : "Taken", LaqtaFormat.dateTime(captured))
            }
            if let camera = shot.cameraModel {
                row("Camera", ImageTools.displayCameraName(camera))
            }
            row("Saved", LaqtaFormat.dateTime(shot.addedAt))
            if let source = shot.sourceName {
                row("From", source)
            }
            row("Original", originalText)
            if let name = shot.originalName, !name.isEmpty {
                row("File", name)
            }
        }
        .laqtaFont(13, maxScale: 1.6)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: min(width, 330))
        .laqtaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func row(_ key: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .foregroundStyle(palette.ink2)
            Spacer(minLength: 0)
            Text(verbatim: value)
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private var originalText: String {
        switch shot.libraryStatus {
        case .untouched: String(localized: "Still in Photos")
        case .pendingDeletion: String(localized: "Waiting to delete")
        case .deleted: String(localized: "Deleted from Photos")
        case .notFound: String(localized: "Not in Photos")
        case .declined: String(localized: "Kept in Photos")
        }
    }
}

private struct ShotPage: View {
    let shot: Shot
    @Binding var isZoomed: Bool
    var onTap: () -> Void

    @State private var image: UIImage?
    @State private var isFullImage = false

    var body: some View {
        ZoomableImageView(image: image, isZoomed: $isZoomed, onSingleTap: onTap)
            .overlay {
                if image == nil {
                    ProgressView()
                }
            }
            .overlay(alignment: .bottom) {
                if image != nil, !isFullImage {
                    CloudDownloadBadge()
                        .padding(.bottom, 120)
                        .transition(.opacity)
                }
            }
            .task(id: shot.id) {
                await load()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: shot.analysis?.title ?? shot.kindLabel))
            .accessibilityAddTraits(.isImage)
    }

    /// The full photo, or its thumbnail while the photo is still in iCloud.
    private func load() async {
        let fileName = shot.fileName
        if MediaWaiter.isAvailable(fileName: fileName) {
            if let box = await ImageLoader.image(at: MediaLocation.fileURL(named: fileName), maxPixelSize: 3_000) {
                image = box.image
                isFullImage = true
            }
            return
        }
        if image == nil, let thumbnail = await ImageLoader.thumbnail(at: shot.thumbnailURL, original: nil) {
            image = thumbnail.image
        }
        guard let url = await MediaWaiter.waitForFile(named: fileName),
              let box = await ImageLoader.image(at: url, maxPixelSize: 3_000) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            image = box.image
            isFullImage = true
        }
    }
}

private struct VideoPage: View {
    let shot: Shot
    let playback: VideoPlaybackModel
    var onTap: () -> Void

    @Environment(\.laqta) private var palette

    private var isActive: Bool { playback.itemID == shot.id && playback.player != nil }
    private var aspectRatio: CGFloat? {
        guard shot.pixelWidth > 0, shot.pixelHeight > 0 else { return nil }
        return CGFloat(shot.pixelWidth) / CGFloat(shot.pixelHeight)
    }
    @State private var mediaArrived = false

    private var isDownloaded: Bool {
        mediaArrived || MediaWaiter.isAvailable(fileName: shot.fileName)
    }

    var body: some View {
        ZStack {
            Color.clear
            ShotThumbnail(shot: shot)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .opacity(isActive && playback.isReady ? 0 : 1)
                .allowsHitTesting(false)
            if isActive, let player = playback.player {
                PlayerLayerView(player: player)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .allowsHitTesting(false)
            }
            if !(isActive && playback.isPlaying) {
                Button {
                    playback.play(shot)
                } label: {
                    if isDownloaded {
                        PlayBadge(size: 72)
                    } else {
                        VStack(spacing: 10) {
                            ProgressView()
                                .tint(.white)
                            Text("Downloading from iCloud…")
                                .laqtaFont(13, weight: .medium)
                                .foregroundStyle(.white)
                        }
                        .padding(18)
                        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("Play video"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .tracksMediaAvailability(of: shot.fileName, isAvailable: $mediaArrived)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "\(shot.kindLabel), \(LaqtaFormat.spokenDuration(shot.mediaDuration ?? 0))"))
    }
}

/// The item's note, above the Intelligence pill.
private struct NotePill: View {
    let note: String
    let onEdit: () -> Void

    @Environment(\.laqta) private var palette

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "note.text")
                    .laqtaIconFont(13, weight: .semibold)
                    .foregroundStyle(palette.goldHi)
                    .padding(.top, 2)
                Text(verbatim: note)
                    .laqtaFont(14)
                    .foregroundStyle(palette.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .laqtaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Note: \(note)"))
        .accessibilityHint(Text("Edit the note"))
    }
}
