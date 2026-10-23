//
//  SaveSheet.swift
//  Laqta — Shared
//
//  "Save to Laqta" — the same sheet in the Share Extension and in the app.
//

import Foundation
import SwiftData
import SwiftUI

struct SaveSheet: View {
    let session: SaveSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette
    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }) private var folders: [Folder]

    @State private var stats: [UUID: FolderStats] = [:]
    /// The folder whose folders the list is showing. `nil` is the top level, as on Home.
    @State private var openFolderID: UUID?
    /// A folder being made from this sheet, and where it goes. The request carries its
    /// parent itself: a separate state read only inside the sheet's closure can be stale.
    @State private var newFolderRequest: NewFolderRequest?

    /// The open folder, as long as it is still there (iCloud can take it away mid-share).
    private var liveOpenFolderID: UUID? {
        guard let openFolderID, folders.contains(where: { $0.id == openFolderID }) else { return nil }
        return openFolderID
    }

    private static let foldersAnchor = "save-sheet-folders"

    var body: some View {
        ZStack {
            palette.sheet.ignoresSafeArea()

            VStack(spacing: 0) {
                SheetBar("Save to Laqta") {
                    Button {
                        session.cancel()
                    } label: {
                        LaqtaButtonLabel("Cancel", kind: .line, small: false)
                    }
                    .buttonStyle(.pressable)
                    .disabled(session.isBusy)
                } trailing: {
                    Button {
                        newFolder(inside: liveOpenFolderID)
                    } label: {
                        CircleIcon(systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.pressable)
                    .disabled(session.isBusy || session.fixedFolderID != nil)
                    .opacity(session.fixedFolderID == nil ? 1 : 0)
                    .accessibilityLabel(Text(liveOpenFolderID == nil ? "New Folder" : "New Folder Inside"))
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            SavePreviewCard(session: session)
                            optionCard
                            if let folderID = session.fixedFolderID, let folder = folders.first(where: { $0.id == folderID }) {
                                fixedTarget(folder)
                            } else {
                                suggestionSection
                                SaveFolderBrowser(
                                    session: session,
                                    folders: folders,
                                    stats: stats,
                                    openFolderID: $openFolderID,
                                    onStep: { cameFrom in
                                        // Into a folder: its list at the top. Back out: the
                                        // folder you came from, where you left it.
                                        if let cameFrom {
                                            proxy.scrollTo(cameFrom, anchor: .center)
                                        } else {
                                            proxy.scrollTo(Self.foldersAnchor, anchor: .top)
                                        }
                                    },
                                    onNewFolder: { parentID in newFolder(inside: parentID) }
                                )
                                .id(Self.foldersAnchor)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                    .scrollIndicators(.hidden)
                }
            }

            SaveStatusOverlay(session: session)
        }
        .task {
            // What the share is actually for goes first.
            await session.start(context: modelContext)
        }
        .onDisappear {
            if !session.isBusy { session.cancel() }
        }
        .task {
            // Counts and covers are decoration: they arrive once the sheet has
            // settled (it rises in 0.3 s), never in front of it or during it. The
            // count is one fetch on the main thread, so it waits for the motion.
            try? await Task.sleep(for: .milliseconds(320))
            stats = FolderStatsLoader.stats(for: folders, context: modelContext)
            ShareTiming.mark("folders")
        }
        .onChange(of: folders.count) {
            stats = FolderStatsLoader.stats(for: folders, context: modelContext)
        }
        .sheet(item: $newFolderRequest) { request in
            FolderEditorSheet(folder: nil, parentID: request.parentID) { created in
                Task { await session.choose(created, context: modelContext) }
            }
            .laqtaThemed()
        }
        .sensoryFeedback(.success, trigger: session.phase) { _, newValue in
            if case .done = newValue { return true }
            return false
        }
    }

    // MARK: Option

    @ViewBuilder
    private var optionCard: some View {
        @Bindable var session = session
        VStack(spacing: 10) {
            if session.duplicateCount > 0 {
                DuplicateNotice(session: session)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if session.link?.isYouTube == true {
                YouTubeSourceRow(isUnavailable: session.link?.isUnavailable == true)
            } else if session.isLinkSession {
                optionRow(
                    systemImage: "sparkles",
                    title: "Extract everything inside",
                    subtitle: session.extractEverything ? "Summary, chapters, places and prices" : "Title and preview only · you can extract later",
                    isOn: $session.extractEverything
                )
            } else if session.canDeleteOriginals {
                optionRow(
                    systemImage: "trash",
                    title: "Delete original from Photos",
                    subtitle: session.deleteOriginals ? "After saving, iOS asks you to confirm" : "The original stays in Photos",
                    isOn: $session.deleteOriginals
                )
            }
        }
        .animation(.snappy, value: session.duplicateCount)
    }

    private func optionRow(systemImage: String, title: LocalizedStringKey, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn.animation(.snappy)) {
            HStack(spacing: 12) {
                RowIcon(systemImage: systemImage)
                RowText(title: Text(title), subtitle: Text(verbatim: subtitle))
            }
        }
        .disabled(session.isBusy)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
    }

    // MARK: Fixed folder

    private func fixedTarget(_ folder: Folder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Saving to")
            SaveFolderRow(folder: folder, stats: stats[folder.id], isQueued: session.queuedFolderID == folder.id, showsChevron: false)
            Button {
                Task { await session.save(to: folder, context: modelContext) }
            } label: {
                LaqtaButtonLabel(verbatim: saveTitle, systemImage: "arrow.down.to.line", fullWidth: true)
            }
            .buttonStyle(.pressable)
            .disabled(session.isBusy)
        }
        .padding(.top, 6)
    }

    private var saveTitle: String {
        let count = session.newItemCount
        if count == 0 { return "Done" }
        return count > 1 ? "Save \(count) items" : "Save"
    }

    // MARK: Suggestion

    @ViewBuilder
    private var suggestionSection: some View {
        if session.isWorking || session.suggestion != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .laqtaIconFont(11, weight: .semibold)
                        .foregroundStyle(palette.goldHi)
                    SectionLabel("Suggested")
                }
                .padding(.top, 6)

                if let suggestion = session.suggestion {
                    SuggestionCard(
                        suggestion: suggestion,
                        folder: suggestion.existingID.flatMap { id in folders.first { $0.id == id } },
                        stats: suggestion.existingID.flatMap { stats[$0] },
                        isBusy: session.isBusy,
                        isQueued: suggestion.existingID != nil && session.queuedFolderID == suggestion.existingID
                    ) {
                        if let id = suggestion.existingID, let folder = folders.first(where: { $0.id == id }) {
                            Task { await session.choose(folder, context: modelContext) }
                        } else {
                            Task { await session.createSuggestedFolder(context: modelContext) }
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    HStack(spacing: 14) {
                        ShimmerLine(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: 8) {
                            ShimmerLine(width: 120, height: 14)
                            ShimmerLine(width: 180, height: 10)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(minHeight: 76)
                    .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .animation(.snappy, value: session.suggestion)
        }
    }

    // MARK: New folder

    private func newFolder(inside parentID: UUID?) {
        newFolderRequest = NewFolderRequest(parentID: parentID)
    }
}

/// "New Folder" from the sheet: on Home (`nil`), or inside the open folder.
private struct NewFolderRequest: Identifiable {
    let id = UUID()
    let parentID: UUID?
}

// MARK: - All folders

/// The folders on Home, and one tap away the folders inside each of them. A folder
/// that holds folders opens instead of saving; the folder you opened is a place to
/// save too ("Save Here"), and the line at the top goes back up.
private struct SaveFolderBrowser: View {
    let session: SaveSession
    let folders: [Folder]
    let stats: [UUID: FolderStats]
    @Binding var openFolderID: UUID?
    /// After a step: `nil` going in (the list's top comes into view), the folder you
    /// came from going back (so it is in view again).
    var onStep: (_ cameFrom: UUID?) -> Void
    var onNewFolder: (_ parentID: UUID?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which way the last step went: a level coming in slides from the side it lies on.
    @State private var wentDeeper = true

    /// With "Lock private folders" off, Home shows what a private folder holds, and so does this list.
    private var locksPrivateFolders: Bool { AppGroup.bool(SettingsKey.lockPrivateFolders) }

    var body: some View {
        let tree = SaveFolderTree(folders)
        let open = openFolderID.flatMap { tree.folder($0) }
        Group {
            if let open {
                inside(open, tree: tree)
            } else {
                topLevel(tree)
            }
        }
        // The new level replaces the old one at once — nothing overlaps, so the list
        // never jumps — and arrives with a short slide and fade.
        .keyframeAnimator(initialValue: LevelArrival(), trigger: open?.id) { content, arrival in
            content
                .offset(x: arrival.x)
                .opacity(arrival.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.x) {
                MoveKeyframe(reduceMotion ? 0 : (wentDeeper ? 28 : -28))
                SpringKeyframe(0, duration: 0.26, spring: .snappy)
            }
            KeyframeTrack(\.opacity) {
                MoveKeyframe(0.2)
                LinearKeyframe(1, duration: reduceMotion ? 0.16 : 0.18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Levels

    private func topLevel(_ tree: SaveFolderTree) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("All Folders")
                .padding(.top, 8)
                .padding(.bottom, 4)
            rows(tree.roots, tree: tree)
            newFolderButton(inside: nil)
        }
    }

    private func inside(_ folder: Folder, tree: SaveFolderTree) -> some View {
        let parent = tree.parent(of: folder.id)
        let children = tree.children(of: folder.id)
        return VStack(alignment: .leading, spacing: 0) {
            backButton(to: parent, from: folder)
                .padding(.top, 2)
            SaveHereCard(
                folder: folder,
                stats: stats[folder.id],
                subfolders: children.count,
                isLocked: tree.isPrivate(folder.id) && locksPrivateFolders,
                isPrivate: tree.isPrivate(folder.id),
                isBusy: session.isBusy,
                isQueued: session.queuedFolderID == folder.id
            ) {
                save(into: folder)
            }
            .padding(.top, 4)
            if !children.isEmpty {
                SectionLabel("Folders Inside")
                    .padding(.top, 18)
                    .padding(.bottom, 4)
                rows(children, tree: tree)
            }
            newFolderButton(inside: folder.id)
        }
    }

    private func rows(_ list: [Folder], tree: SaveFolderTree) -> some View {
        ForEach(list) { folder in
            let insideCount = tree.children(of: folder.id).count
            Button {
                if insideCount > 0 {
                    step(to: folder.id, deeper: true, cameFrom: nil)
                } else {
                    save(into: folder)
                }
            } label: {
                SaveFolderRow(
                    folder: folder,
                    stats: stats[folder.id],
                    isQueued: session.queuedFolderID == folder.id,
                    showsChevron: insideCount > 0,
                    subfolders: insideCount,
                    isPrivate: tree.isPrivate(folder.id),
                    hidesPrivateContents: locksPrivateFolders
                )
            }
            .buttonStyle(.pressable)
            .disabled(session.isBusy)
            .accessibilityHint(insideCount > 0 ? Text("Shows the folders inside") : Text("Saves here"))
            .id(folder.id)
        }
    }

    private func backButton(to parent: Folder?, from folder: Folder) -> some View {
        Button {
            step(to: parent?.id, deeper: false, cameFrom: folder.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.backward")
                    .laqtaIconFont(14, weight: .semibold)
                if let parent {
                    FolderNameText(name: parent.name, size: 19, color: palette.goldHi, maxScale: 1.3)
                } else {
                    Text("All Folders")
                        .laqtaFont(15, weight: .semibold)
                }
            }
            .foregroundStyle(palette.goldHi)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(session.isBusy)
        .accessibilityLabel(Text("Back to \(parent?.name ?? String(localized: "All Folders"))"))
    }

    private func newFolderButton(inside parentID: UUID?) -> some View {
        Button {
            onNewFolder(parentID)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                Text(parentID == nil ? "New Folder" : "New Folder Inside")
            }
            .laqtaFont(15, weight: .semibold)
            .foregroundStyle(palette.goldHi)
            .frame(maxWidth: .infinity, minHeight: 56)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(palette.buttonBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(session.isBusy)
        .padding(.top, 10)
    }

    // MARK: Actions

    private func save(into folder: Folder) {
        Task { await session.choose(folder, context: modelContext) }
    }

    private func step(to folderID: UUID?, deeper: Bool, cameFrom: UUID?) {
        wentDeeper = deeper
        openFolderID = folderID
        // One real suspension, so the new level is on screen before the list scrolls
        // to it — the row to come back to doesn't exist until then.
        Task {
            try? await Task.sleep(for: .milliseconds(1))
            withAnimation(.snappy(duration: 0.3)) {
                onStep(cameFrom)
            }
        }
    }
}

/// Where a level of the folder list is while it arrives.
private struct LevelArrival {
    var x: CGFloat = 0
    var opacity: Double = 1
}

/// The live folders the way Home arranges them: the ones on Home, each with the
/// folders directly inside it, the latest change first. Built from the folders
/// already in memory, so "is this one private?" costs no fetch per row.
struct SaveFolderTree {
    private(set) var roots: [Folder] = []
    private var rootIDs: Set<UUID> = []
    private var byID: [UUID: Folder] = [:]
    private var childrenByParent: [UUID: [Folder]] = [:]
    private var privateIDs: Set<UUID> = []

    init(_ folders: [Folder]) {
        let live = folders.filter { $0.deletedAt == nil }
        for folder in live {
            byID[folder.id] = folder
        }
        for folder in live {
            if let parent = folder.parentID, parent != folder.id, byID[parent] != nil {
                childrenByParent[parent, default: []].append(folder)
            } else {
                // On Home, or its parent is gone: either way it has to be reachable.
                roots.append(folder)
            }
        }
        // Folders pointing at each other in a circle (only damaged data does that)
        // are reachable from nowhere; they go on the top level too.
        var reached: Set<UUID> = []
        var queue = roots
        while let next = queue.popLast() {
            guard reached.insert(next.id).inserted else { continue }
            queue.append(contentsOf: childrenByParent[next.id] ?? [])
        }
        for folder in live where !reached.contains(folder.id) {
            roots.append(folder)
            reached.insert(folder.id)
        }
        rootIDs = Set(roots.map(\.id))
        roots.sort(by: Self.latestFirst)
        childrenByParent = childrenByParent.mapValues { $0.sorted(by: Self.latestFirst) }
        for folder in live where Self.isLockedOnTheWay(folder, among: byID) {
            privateIDs.insert(folder.id)
        }
    }

    func folder(_ id: UUID) -> Folder? { byID[id] }

    func children(of id: UUID) -> [Folder] { childrenByParent[id] ?? [] }

    /// The folder "back" goes to. `nil` for anything listed on the top level, even if
    /// its `parentID` names a folder: one in a circle would otherwise send you round it.
    func parent(of id: UUID) -> Folder? {
        guard !rootIDs.contains(id) else { return nil }
        return byID[id]?.parentID.flatMap { byID[$0] }
    }

    func isPrivate(_ id: UUID) -> Bool { privateIDs.contains(id) }

    /// Latest change first; the ID settles a tie, so rows never swap places between drawings.
    private static func latestFirst(_ a: Folder, _ b: Folder) -> Bool {
        if a.lastUpdate != b.lastUpdate { return a.lastUpdate > b.lastUpdate }
        return a.id.uuidString < b.id.uuidString
    }

    /// Locked itself, or inside a locked folder at any depth.
    private static func isLockedOnTheWay(_ folder: Folder, among byID: [UUID: Folder]) -> Bool {
        var current = folder
        var seen: Set<UUID> = [folder.id]
        while true {
            if current.isLocked { return true }
            guard let parentID = current.parentID else { return false }
            guard let parent = byID[parentID] else {
                // The folder above is in Recently Deleted: the store still knows if it was locked.
                return current.isPrivate
            }
            guard seen.insert(parent.id).inserted else { return false }
            current = parent
        }
    }
}

/// The open folder, as a place to save: the whole card is the button.
private struct SaveHereCard: View {
    let folder: Folder
    let stats: FolderStats?
    let subfolders: Int
    /// Reads "Locked" instead of what it holds.
    let isLocked: Bool
    let isPrivate: Bool
    let isBusy: Bool
    let isQueued: Bool
    let action: () -> Void

    @Environment(\.laqta) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                FolderThumb(folder: folder, cover: stats?.cover, size: 50, isPrivate: isPrivate)
                VStack(alignment: .leading, spacing: 1) {
                    FolderNameText(name: folder.name, size: 24)
                    Text(verbatim: meta)
                        .laqtaFont(12)
                        .foregroundStyle(palette.ink2)
                        .adaptiveLineLimit(1, accessibility: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isQueued {
                    ProgressView()
                        .tint(palette.goldInk)
                        .frame(width: 60, height: 36)
                        .background(palette.accentFill, in: Capsule())
                } else {
                    LaqtaButtonLabel("Save Here", small: true)
                }
            }
            .padding(12)
            .frame(minHeight: 76)
            .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.buttonBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(isBusy)
        .accessibilityLabel(Text("Save here, in \(folder.name). \(meta)"))
    }

    private var meta: String {
        SaveFolderRow.meta(for: folder, stats: stats, subfolders: subfolders, locked: isLocked)
    }
}

// MARK: - Preview

private struct SavePreviewCard: View {
    let session: SaveSession
    @Environment(\.laqta) private var palette
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if session.isLinkSession {
                linkThumb
            } else {
                photoStack
            }
            VStack(alignment: .leading, spacing: 6) {
                if session.isLinkSession {
                    Text(verbatim: session.link?.title ?? session.incomingLinkURL.map(LinkDraft.displayHost) ?? "Link")
                        .laqtaFont(15, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .lineLimit(2)
                    Text(verbatim: linkLine)
                        .laqtaFont(12)
                        .foregroundStyle(palette.ink2)
                        .adaptiveLineLimit(1, accessibility: 2)
                } else {
                    Text(verbatim: mediaTitle)
                        .laqtaFont(15, weight: .semibold)
                        .foregroundStyle(palette.ink)
                    Text(verbatim: mediaLine)
                        .laqtaFont(12)
                        .foregroundStyle(palette.ink2)
                        .adaptiveLineLimit(1, accessibility: 2)
                }

                if session.isWorking {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(palette.goldHi)
                        Text(verbatim: session.statusText)
                            .laqtaFont(12, weight: .medium)
                            .foregroundStyle(palette.goldHi)
                    }
                    .padding(.top, 2)
                    .transition(.opacity)
                } else if !session.found.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(session.found) { chip in
                            TagChip(text: chip.text, systemImage: chip.systemImage)
                        }
                    }
                    .padding(.top, 2)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
        .animation(.snappy, value: session.found)
        .animation(.snappy, value: session.isWorking)
    }

    private var mediaTitle: String {
        let counts = session.stagedCounts
        guard session.stagedCount > 0 else {
            if session.incomingKinds == [.video] { return "Video" }
            if session.incomingKinds == [.document] { return "PDF" }
            return session.incomingKinds == [.photo] ? "Photo" : "Items"
        }
        var parts: [String] = []
        if let photos = counts[.photo], photos > 0 { parts.append(LaqtaFormat.count(photos, "photo", "photos")) }
        if let videos = counts[.video], videos > 0 { parts.append(LaqtaFormat.count(videos, "video", "videos")) }
        if let documents = counts[.document], documents > 0 { parts.append(LaqtaFormat.count(documents, "PDF", "PDFs")) }
        return parts.joined(separator: " · ")
    }

    private var mediaLine: String {
        var parts: [String] = []
        if session.incomingKinds == [.document] {
            parts.append("From Files")
        } else if !session.incomingKinds.contains(.document) {
            parts.append("From Photos")
        }
        if let duration = session.firstDuration, session.stagedCount == 1 {
            parts.append(LaqtaFormat.duration(duration))
        }
        if session.mediaByteCount > 0 {
            parts.append(LaqtaFormat.bytes(Int64(session.mediaByteCount)))
        }
        if session.failedCount > 0 {
            parts.append("\(session.failedCount) couldn't be read")
        }
        return parts.joined(separator: " · ")
    }

    private var linkLine: String {
        guard let link = session.link else {
            return session.incomingLinkURL.map(LinkDraft.displayHost) ?? ""
        }
        return [link.site, link.author].compactMap { $0 }.joined(separator: " · ")
    }

    private var photoStack: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.field)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
                .frame(width: 62, height: 86)
                .rotationEffect(.degrees(-12 * layoutDirection.sign))
                .offset(x: 6 * layoutDirection.sign, y: 8)
                .opacity(session.stagedCount > 1 ? 1 : 0)
            Group {
                if let image = session.firstPreview {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .accessibilityIgnoresInvertColors()
                } else {
                    palette.field
                        .overlay { ProgressView().controlSize(.small) }
                }
            }
            .frame(width: 62, height: 86)
            .overlay {
                if session.firstKind == .video {
                    Image(systemName: "play.fill")
                        .laqtaIconFont(11, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.black.opacity(0.45), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                }
            }
            .overlay(alignment: .bottomLeading) {
                if session.firstKind == .document {
                    Text(verbatim: "PDF")
                        .laqtaFont(9, weight: .heavy, maxScale: 1.25)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minHeight: 15)
                        .background(Color(hex: 0xB0412F), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.goldHi, lineWidth: 2))
            .rotationEffect(.degrees(-5 * layoutDirection.sign))
            .shadow(color: .black.opacity(0.3), radius: 9, y: 8)
            .offset(x: 12 * layoutDirection.sign, y: 4)
        }
        .frame(width: 82, height: 96, alignment: .topLeading)
    }

    private var linkThumb: some View {
        ZStack {
            palette.field
            if let image = session.linkPreview {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityIgnoresInvertColors()
            } else if session.isWorking {
                ShimmerLine(width: 112, height: 78)
            } else {
                Image(systemName: session.link?.form.systemImage ?? "link")
                    .laqtaIconFont(22, weight: .medium)
                    .foregroundStyle(palette.goldHi)
            }
            if session.link?.form == .video {
                Image(systemName: "play.fill")
                    .laqtaIconFont(12, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.42), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
            }
        }
        .frame(width: 112, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            if let duration = session.link?.duration, session.link?.form == .video {
                Text(verbatim: LaqtaFormat.duration(duration))
                    .laqtaFont(10.5, weight: .semibold, monospacedDigit: true, maxScale: 1.25)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 18)
                    .background(Color.black.opacity(0.62), in: Capsule())
                    .padding(5)
            }
        }
    }
}

// MARK: - YouTube

/// YouTube links keep YouTube's own details; there is nothing to extract.
private struct YouTubeSourceRow: View {
    let isUnavailable: Bool
    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .laqtaIconFont(15, weight: .semibold)
                .foregroundStyle(palette.goldHi)
                .frame(width: 34, height: 34)
                .background(palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(isUnavailable ? "Unavailable on YouTube" : "Details from YouTube")
                    .laqtaFont(15, weight: .semibold)
                    .foregroundStyle(palette.ink)
                Text(isUnavailable ? "The video was removed or made private" : "Title, channel, description and chapters, kept up to date")
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Duplicates

private struct DuplicateNotice: View {
    let session: SaveSession
    @Environment(\.laqta) private var palette

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(systemImage: "square.on.square")
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title)
                        .laqtaFont(15, weight: .semibold)
                        .foregroundStyle(palette.ink)
                    HStack(spacing: 4) {
                        Text("In")
                        FolderNameText(name: folderName, size: 15, color: palette.goldHi)
                        Text(verbatim: detail)
                            .lineLimit(1)
                    }
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
                }
                Spacer(minLength: 0)
            }
            Toggle(isOn: Binding(
                get: { !session.skipDuplicates },
                set: { session.skipDuplicates = !$0 }
            ).animation(.snappy)) {
                Text(session.isLinkSession ? "Save it again anyway" : "Save duplicates too")
                    .laqtaFont(14, weight: .medium)
                    .foregroundStyle(palette.ink)
            }
            .disabled(session.isBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.buttonBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var matches: [SaveSession.DuplicateMatch] {
        if let link = session.linkDuplicate { return [link] }
        return Array(session.duplicates.values).sorted { $0.addedAt > $1.addedAt }
    }

    private var title: String {
        if session.isLinkSession { return "You saved this link before" }
        let count = session.duplicateCount
        if session.allAreDuplicates {
            return count == 1 ? "Already in Laqta" : "All \(count) are already in Laqta"
        }
        return count == 1 ? "1 is already in Laqta" : "\(count) are already in Laqta"
    }

    private var folderName: String {
        matches.first?.folderName ?? "Laqta"
    }

    private var detail: String {
        let folders = Set(matches.map(\.folderName))
        if folders.count > 1 {
            return String(localized: "and \(LaqtaFormat.count(folders.count - 1, "more folder", "more folders"))")
        }
        guard let first = matches.first else { return "" }
        return "· saved \(LaqtaFormat.relative(first.addedAt))"
    }
}

// MARK: - Rows

struct SaveFolderRow: View {
    let folder: Folder
    let stats: FolderStats?
    var isQueued: Bool = false
    var showsChevron: Bool = true
    /// Folders directly inside this one, named in the line under it ("2 folders · …").
    var subfolders: Int = 0
    /// Passed in by a caller that already walked the folders; asked of the folder otherwise.
    var isPrivate: Bool?
    /// A private folder reads "Locked" instead of what it holds, as on Home.
    var hidesPrivateContents: Bool = false

    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(spacing: 14) {
            FolderThumb(folder: folder, cover: stats?.cover, size: 50, isPrivate: isPrivate)
            VStack(alignment: .leading, spacing: 1) {
                FolderNameText(name: folder.name, size: 22)
                Text(verbatim: meta)
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
                    .adaptiveLineLimit(1, accessibility: 2)
            }
            Spacer(minLength: 8)
            if isQueued {
                ProgressView()
                    .tint(palette.goldHi)
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .laqtaIconFont(13, weight: .semibold)
                    .foregroundStyle(palette.ink3)
            }
        }
        .frame(minHeight: 70)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.line).frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(folder.name), \(meta)"))
    }

    private var meta: String {
        let locked = hidesPrivateContents && (isPrivate ?? folder.isPrivate)
        return Self.meta(for: folder, stats: stats, subfolders: subfolders, locked: locked)
    }

    /// "4 shots · 1 link · 2h ago", "2 folders · 3 shots · 2h ago", or "Locked · 2h ago".
    static func meta(for folder: Folder, stats: FolderStats?, subfolders: Int, locked: Bool) -> String {
        let updated = LaqtaFormat.relative(folder.lastUpdate)
        if locked { return "Locked · \(updated)" }
        let inside = LaqtaFormat.count(subfolders, "folder", "folders")
        guard let stats else {
            // The counts come a moment after the sheet. Until then the date stands
            // alone, instead of every folder calling itself empty for a moment.
            if subfolders > 0 { return "\(inside) · \(updated)" }
            return updated.prefix(1).uppercased() + String(updated.dropFirst())
        }
        guard subfolders > 0 else { return "\(LaqtaFormat.contents(stats)) · \(updated)" }
        // An empty parent reads better as "2 folders" than "2 folders · Empty".
        guard stats.total > 0 else { return "\(inside) · \(updated)" }
        return "\(inside) · \(LaqtaFormat.contents(stats)) · \(updated)"
    }
}

/// 50 pt rounded cover thumbnail (blurred), with a lock for private folders.
struct FolderThumb: View {
    let folder: Folder
    let cover: CoverSource?
    var size: CGFloat = 50
    /// Passed in by a caller that already walked the folders; asked of the folder otherwise.
    var isPrivate: Bool?

    @Environment(\.laqta) private var palette

    var body: some View {
        let locked = isPrivate ?? folder.isPrivate
        FolderCoverView(source: locked ? nil : cover, tone: folder.tone, heavy: true)
            .frame(width: size, height: size)
            .overlay {
                if locked {
                    ZStack {
                        Color.black.opacity(0.35)
                        Image(systemName: "lock")
                            .laqtaIconFont(size * 0.26, weight: .semibold)
                            .foregroundStyle(Color(hex: 0xF2E4C4))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 1))
    }
}

private struct SuggestionCard: View {
    let suggestion: FolderSuggestion
    let folder: Folder?
    let stats: FolderStats?
    let isBusy: Bool
    let isQueued: Bool
    let action: () -> Void

    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(spacing: 14) {
            thumb
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    FolderNameText(name: name, size: 24)
                    if folder == nil {
                        Text("New folder")
                            .laqtaFont(10.5, weight: .semibold, maxScale: 1.25)
                            .foregroundStyle(palette.goldHi)
                            .padding(.horizontal, 7)
                            .frame(minHeight: 20)
                            .background(palette.hit, in: Capsule())
                    }
                }
                Text(verbatim: suggestion.reason)
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: action) {
                if isQueued {
                    ProgressView()
                        .tint(palette.goldInk)
                        .frame(width: 60, height: 36)
                        .background(palette.accentFill, in: Capsule())
                } else {
                    LaqtaButtonLabel(folder == nil ? "Create & Save" : "Save", small: true)
                }
            }
            .buttonStyle(.pressable)
            .disabled(isBusy)
        }
        .padding(12)
        .frame(minHeight: 76)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.buttonBorder, lineWidth: 1))
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.shimmer)
                .padding(-4)
        )
        .padding(4)
        .accessibilityElement(children: .combine)
    }

    private var name: String {
        if let folder { return folder.name }
        if case let .new(name, _, _) = suggestion.target { return name }
        return ""
    }

    @ViewBuilder
    private var thumb: some View {
        if let folder {
            FolderThumb(folder: folder, cover: stats?.cover, size: 50)
        } else if case let .new(_, symbol, tone) = suggestion.target {
            ToneMesh(tone: tone)
                .frame(width: 50, height: 50)
                .overlay {
                    Image(systemName: symbol)
                        .laqtaIconFont(18, weight: .medium)
                        .foregroundStyle(Color(hex: 0xF2E4C4))
                }
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }
}

// MARK: - Status

private struct SaveStatusOverlay: View {
    let session: SaveSession
    @Environment(\.laqta) private var palette

    var body: some View {
        Group {
            switch session.phase {
            case .preparing, .analyzing, .ready:
                EmptyView()
            case .saving:
                card {
                    ProgressView()
                        .controlSize(.large)
                        .tint(palette.goldHi)
                    Text("Saving…")
                        .laqtaFont(17, weight: .semibold)
                        .foregroundStyle(palette.ink)
                }
            case .removingOriginals:
                card {
                    ProgressView()
                        .controlSize(.large)
                        .tint(palette.goldHi)
                    Text("Saved in Laqta")
                        .laqtaFont(17, weight: .semibold)
                        .foregroundStyle(palette.ink)
                    Text("Confirm to delete the original from Photos")
                        .laqtaFont(13)
                        .foregroundStyle(palette.ink2)
                        .multilineTextAlignment(.center)
                }
            case let .done(info):
                doneCard(info)
            case let .failed(message):
                card {
                    Image(systemName: "exclamationmark.triangle")
                        .laqtaIconFont(36, weight: .medium)
                        .foregroundStyle(palette.goldHi)
                    Text(verbatim: message)
                        .laqtaFont(16, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .multilineTextAlignment(.center)
                    Button {
                        session.cancel()
                    } label: {
                        LaqtaButtonLabel("Close")
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .animation(.smooth(duration: 0.28), value: session.phase)
    }

    private func doneCard(_ info: SaveSession.DoneInfo) -> some View {
        ZStack {
            palette.sheet.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: info.alreadySaved ? "square.on.square" : "checkmark")
                    .laqtaIconFont(32, weight: .bold)
                    .foregroundStyle(palette.goldInk)
                    .frame(width: 78, height: 78)
                    .background(palette.accentFill, in: Circle())
                    .background(Circle().fill(palette.shimmer).padding(-10))
                    .symbolEffect(.bounce, value: info.count)
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text(verbatim: doneTitle(info))
                            .laqtaFont(20, weight: .semibold)
                            .foregroundStyle(palette.ink)
                        FolderNameText(name: info.folderName, size: 26, color: palette.goldHi)
                    }
                    if let note = info.note {
                        Text(verbatim: note)
                            .laqtaFont(14)
                            .foregroundStyle(palette.ink2)
                            .multilineTextAlignment(.center)
                    }
                }
                if let intelligence = info.intelligenceNote {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text(verbatim: intelligence)
                    }
                    .laqtaFont(12, weight: .medium)
                    .foregroundStyle(palette.goldHi)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 28)
                    .background(palette.hit, in: Capsule())
                }
            }
            .padding(24)
        }
        // It closes by itself in a moment; a tap closes it now.
        .contentShape(Rectangle())
        .onTapGesture { session.close() }
        .transition(.opacity)
    }

    private func doneTitle(_ info: SaveSession.DoneInfo) -> String {
        if info.alreadySaved { return "Already in" }
        return info.count > 1
            ? String(localized: "\(info.count) saved to")
            : String(localized: "Saved to")
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            palette.scrim.ignoresSafeArea()
            VStack(spacing: 12) {
                content()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 300)
            .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
