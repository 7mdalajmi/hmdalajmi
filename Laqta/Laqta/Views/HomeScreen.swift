//
//  HomeScreen.swift
//  Laqta
//
//  Home: the wordmark, folders sorted by last update, and the Import / New Folder dock.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct HomeScreen: View {
    @Binding var path: [Route]

    @AppObject(LibraryModel.self) private var library
    @AppObject(LockManager.self) private var lock
    @AppObject(ToastCenter.self) private var toasts
    @Environment(\.modelContext) private var modelContext
    @Environment(\.libraryNavigator) private var navigator

    @State private var showingSettings = false
    @State private var showingInsights = false
    @State private var showingImport = false
    @State private var showingNewFolder = false
    @State private var editingFolder: Folder?
    @State private var folderPendingDeletion: Folder?
    @State private var openTrashAfterSettings = false

    var body: some View {
        HomeFolders(
            path: $path,
            showingSettings: $showingSettings,
            showingInsights: $showingInsights,
            showingImport: $showingImport,
            showingNewFolder: $showingNewFolder,
            editingFolder: $editingFolder,
            folderPendingDeletion: $folderPendingDeletion
        )
        .id(library.refreshToken)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingSettings, onDismiss: {
            if openTrashAfterSettings {
                openTrashAfterSettings = false
                if let navigator {
                    navigator.openTrash()
                } else {
                    path.append(.trash)
                }
            }
        }) {
            SettingsScreen {
                openTrashAfterSettings = true
            }
            .laqtaThemed()
        }
        .sheet(isPresented: $showingInsights) {
            InsightsSheet(path: $path)
                .laqtaThemed()
        }
        .sheet(isPresented: $showingImport) {
            ImportSheet(targetFolderID: nil)
                .laqtaThemed()
        }
        .sheet(isPresented: $showingNewFolder) {
            FolderEditorSheet(folder: nil) { created in
                library.highlight(created.id)
            }
            .laqtaThemed()
        }
        .sheet(item: $editingFolder) { folder in
            FolderEditorSheet(folder: folder)
                .laqtaThemed()
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                if let folder = folderPendingDeletion {
                    trash(folder)
                }
                folderPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                folderPendingDeletion = nil
            }
        } message: {
            Text("It moves to Recently Deleted for 30 days. Your Photos library isn't touched.")
        }
    }

    private func trash(_ folder: Folder) {
        withAnimation {
            library.trash(folder: folder, context: modelContext)
        }
        let name = folder.name
        toasts.show(String(localized: "“\(name)” moved to Recently Deleted"), systemImage: "trash", actionTitle: String(localized: "Undo")) {
            withAnimation {
                library.restore(folder: folder, context: modelContext)
            }
        }
    }

    private var deletionTitle: String {
        guard let folder = folderPendingDeletion else { return "" }
        let count = LaqtaStore.itemCount(in: folder.id, context: modelContext)
        return count == 0
            ? "Delete “\(folder.name)”?"
            : "Delete “\(folder.name)” and \(LaqtaFormat.count(count, "item", "items"))?"
    }
}

/// A link taken off the clipboard, on its way to the import sheet.
private struct PendingLink: Identifiable {
    let text: String
    var id: String { text }
}

private struct HomeFolders: View {
    @Binding var path: [Route]
    @Binding var showingSettings: Bool
    @Binding var showingInsights: Bool
    @Binding var showingImport: Bool
    @Binding var showingNewFolder: Bool
    @Binding var editingFolder: Folder?
    @Binding var folderPendingDeletion: Folder?

    @AppObject(LibraryModel.self) private var library
    @AppObject(LockManager.self) private var lock
    @AppObject(IntelligenceCenter.self) private var intelligence
    @AppObject(DropImportModel.self, otherwise: { DropImportModel() }) private var dropImport
    @AppObject(PurchaseCenter.self) private var purchases
    @Environment(\.laqta) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.libraryNavigator) private var navigator

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }) private var folders: [Folder]
    @Query(HomeFolders.itemsDescriptor) private var items: [Shot]
    @State private var trashCount = 0
    @State private var showingMerge = false
    @State private var clipboard = ClipboardOffer()
    @State private var clipboardLink: PendingLink?
    @State private var remindingAbout: DatedShot?
    @State private var cameraFolder: Folder?

    @AppObject(ReminderCenter.self, otherwise: { ReminderCenter() }) private var reminders
    @AppStorage(SettingsKey.showComingUp, store: AppGroup.defaults) private var showsComingUp = true
    @AppStorage(SettingsKey.offerClipboard, store: AppGroup.defaults) private var offersClipboard = true

    static var itemsDescriptor: FetchDescriptor<Shot> {
        var descriptor = FetchDescriptor<Shot>(
            predicate: #Predicate<Shot> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        descriptor.propertiesToFetch = [\.id, \.folderID, \.kindRaw, \.addedAt, \.thumbnailName, \.fileName, \.linkKey, \.linkURL]
        return descriptor
    }

    /// Home shows the top level only; the rest live inside their parents.
    private var sortedFolders: [Folder] {
        folders.filter { $0.parentID == nil }.sorted { $0.lastUpdate > $1.lastUpdate }
    }

    private var subfolderCounts: [UUID: Int] {
        LaqtaStore.subfolderCounts(folders)
    }

    /// One column on iPhone; two or three on iPad.
    private var columns: [GridItem] {
        guard sizeClass == .regular else { return [GridItem(.flexible())] }
        return [GridItem(.adaptive(minimum: 320, maximum: 520), spacing: 14)]
    }

    private var statsByFolder: [UUID: FolderStats] {
        var result: [UUID: FolderStats] = [:]
        var coverPriority: [UUID: Int] = [:]
        // Items come newest first, so the first cover of each priority is the newest one.
        for item in items {
            guard let folderID = item.folderID else { continue }
            var stats = result[folderID] ?? FolderStats()
            stats.count(item.kind)
            if stats.newestAdded == nil {
                stats.newestAdded = item.addedAt
            }
            let priority = item.coverPriority
            if priority < coverPriority[folderID, default: .max], let cover = item.coverSource {
                stats.cover = cover
                coverPriority[folderID] = priority
            }
            result[folderID] = stats
        }
        return result
    }

    /// Quiet for most of the month: the last week, and every day after it, say so.
    private var showsTrialStrip: Bool {
        purchases.access.isExpired || (purchases.access.daysLeft ?? .max) <= 7
    }

    /// Folders that arrived from another device under a name already in use here.
    private func mergePairs(_ stats: [UUID: FolderStats]) -> [FolderMergePair] {
        FolderMerge.needingAnswer(FolderMerge.pairs(folders: folders, counts: stats.mapValues(\.total)))
    }

    var body: some View {
        let stats = statsByFolder
        let insideCounts = subfolderCounts
        let merges = mergePairs(stats)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(stats: stats)
                    .padding(.top, 12)

                if showsTrialStrip {
                    TrialStrip(access: purchases.access) {
                        purchases.paywallReason = purchases.access.isExpired ? .ended : .settings
                    }
                    .padding(.top, 22)
                }

                if showsComingUp, !comingUp.isEmpty {
                    ComingUpStrip(dated: comingUp) { dated in
                        openDated(dated)
                    } onRemind: { dated in
                        remindingAbout = dated
                    }
                }

                if offersClipboard, clipboard.hasLink {
                    ClipboardOfferCard {
                        clipboardLink = clipboard.take().map(PendingLink.init)
                    } onDismiss: {
                        withAnimation(.snappy) { clipboard.answer() }
                    }
                    .padding(.top, 22)
                }

                if !merges.isEmpty {
                    MergeFoldersCard(pairs: merges) {
                        showingMerge = true
                    } onKeepBoth: {
                        withAnimation {
                            for pair in merges { FolderMerge.decline(pair) }
                            library.refresh()
                        }
                    }
                    .padding(.top, 22)
                }

                SectionLabel("Folders") {
                    Label("Last updated", systemImage: "arrow.down")
                        .labelStyle(SmallLabelStyle())
                        .foregroundStyle(palette.ink2)
                }
                .padding(.top, 28)
                .padding(.bottom, 14)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(sortedFolders) { folder in
                        DroppableFolderCard(
                            folder: folder,
                            stats: stats[folder.id] ?? FolderStats(),
                            isUnlocked: lock.canShow(folder),
                            highlighted: library.highlightedFolderID == folder.id,
                            subfolders: insideCounts[folder.id] ?? 0,
                            dropImport: dropImport
                        ) {
                            open(folder)
                        }
                        .contextMenu {
                            folderMenu(folder, twin: FolderMerge.twin(of: folder.id, folders: folders, counts: stats.mapValues(\.total)))
                        }
                    }
                }
                .animation(.spring(response: 0.64, dampingFraction: 0.86), value: sortedFolders.map(\.id))

                if trashCount > 0 {
                    Button {
                        if let navigator {
                            navigator.openTrash()
                        } else {
                            path.append(.trash)
                        }
                    } label: {
                        TrashRow(count: trashCount)
                    }
                    .buttonStyle(.pressable)
                    .padding(.top, 16)
                }

                if items.isEmpty {
                    OnboardingHint()
                        .padding(.top, 22)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(LaqtaBackground())
        .safeAreaInset(edge: .bottom) {
            // On iPad the sidebar has Import and New Folder.
            if navigator == nil {
                dock
            }
        }
        .task(id: library.trashVersion) {
            trashCount = library.trashCount(context: modelContext)
        }
        .task(id: library.refreshToken) {
            // A folder that arrived with a name already here, and nothing in it, just folds in.
            if FolderMerge.mergeEmptySided(context: modelContext) > 0 {
                library.refresh()
            }
        }
        .sheet(isPresented: $showingMerge) {
            MergeFoldersSheet(pairs: merges)
                .laqtaThemed()
        }
        .sheet(item: $cameraFolder) { folder in
            FolderCameraSheet(folder: folder)
                .laqtaThemed()
        }
        .sheet(item: $remindingAbout) { dated in
            ReminderPickerSheet(
                dated: dated,
                thumbnailURL: AppGroup.thumbnailsURL.appending(path: dated.thumbnailName)
            )
            .laqtaThemed()
        }
        .sheet(item: $clipboardLink) { link in
            ImportSheet(targetFolderID: nil, initialTab: .link, initialLink: link.text)
                .laqtaThemed()
        }
        .task(id: library.refreshToken) {
            // Only ever asks whether something link-shaped is on the clipboard.
            guard offersClipboard else { return }
            await clipboard.check()
        }
        .task(id: comingUpFingerprint) {
            // A reminder stops being ours only when its shot is gone or its day has
            // passed. Never because the strip is full, the toggle is off, or the folder
            // happens to be locked right now — so the prune measures itself against
            // every dated shot, not against the three the strip shows.
            await reminders.prune(keeping: Set(allDated.map(\.itemID)))
        }
    }

    // MARK: Coming up

    /// Every live shot still carrying a day worth showing, soonest first.
    ///
    /// The whole truth: no limit, no toggle, no lock filter. The reminders are pruned
    /// against this, and the strip takes its few from it. Reading `item.analysis`
    /// faults the analysis blob back in for every item, so it is walked once and
    /// shared rather than recomputed for the strip and again for the fingerprint.
    private var allDated: [DatedShot] {
        let now = Date.now
        var dated: [DatedShot] = []
        for item in items where item.deletedAt == nil {
            guard let analysis = item.analysis,
                  let entity = ComingUp.soonest(in: analysis.entities, now: now),
                  let date = entity.date else { continue }
            dated.append(DatedShot(
                itemID: item.id,
                folderID: item.folderID,
                title: analysis.title ?? item.displayTitle,
                detail: detailLine(for: item, analysis: analysis, entity: entity),
                date: date,
                allDay: entity.allDay,
                thumbnailName: item.thumbnailName
            ))
        }
        return ComingUp.order(dated)
    }

    /// What the strip shows: the soonest few, and nothing out of a folder that is
    /// locked at this moment. A locked folder keeps its business to itself on screen,
    /// but its reminders still stand.
    private var comingUp: [DatedShot] {
        guard showsComingUp else { return [] }
        let visible = allDated.filter { dated in
            guard let folderID = dated.folderID,
                  let folder = folders.first(where: { $0.id == folderID }) else { return true }
            return lock.canShow(folder)
        }
        return Array(visible.prefix(ComingUp.stripLimit))
    }

    /// Changes only when the dated shots themselves change, so pruning is not run on
    /// every draw.
    private var comingUpFingerprint: String {
        allDated.map { "\($0.itemID.uuidString)|\($0.date.timeIntervalSince1970)" }.joined(separator: ",")
    }

    private func detailLine(for item: Shot, analysis: ShotAnalysis, entity: DetectedEntity) -> String? {
        let parts = [analysis.category, entity.display].compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private func openDated(_ dated: DatedShot) {
        guard let folderID = dated.folderID,
              let folder = folders.first(where: { $0.id == folderID }) else { return }
        if let navigator {
            navigator.openFolder(folderID)
            return
        }
        let itemID = dated.itemID
        withUnlock(folder) {
            path.append(.viewer(folderID: folderID, startID: itemID))
        }
    }

    // MARK: Header

    private func header(stats: [UUID: FolderStats]) -> some View {
        // At accessibility text sizes the buttons move under the title, so the summary has room.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: navigator == nil ? "Laqta" : "All Folders")
                    .laqtaDisplayFont(50, maxScale: 1.25)
                    .foregroundStyle(palette.goldHi)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: summaryLine(stats))
                    .laqtaFont(14)
                    .foregroundStyle(palette.ink2)
                    .lineLimit(stacked ? 3 : 2)
            }
            if !stacked {
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button {
                    showingInsights = true
                } label: {
                    CircleIcon(systemImage: "sparkles", showsDot: intelligence.hasInsights)
                }
                .accessibilityLabel(Text("Insights"))
                if navigator == nil {
                    Button {
                        path.append(.search)
                    } label: {
                        CircleIcon(systemImage: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("Search"))
                }
                Button {
                    showingSettings = true
                } label: {
                    CircleIcon(systemImage: "slider.horizontal.3")
                }
                .accessibilityLabel(Text("Settings"))
            }
            .buttonStyle(.pressable)
            .padding(.bottom, stacked ? 0 : 4)
        }
    }

    private func summaryLine(_ stats: [UUID: FolderStats]) -> String {
        var total = FolderStats()
        for value in stats.values {
            total.photos += value.photos
            total.videos += value.videos
            total.documents += value.documents
            total.links += value.links
        }
        let contents = total.total == 0 ? LaqtaFormat.count(0, "shot", "shots") : LaqtaFormat.contents(total)
        var line = "\(contents) · \(LaqtaFormat.count(folders.count, "folder", "folders"))"
        // Before the strip appears, the countdown lives here — a word, not a banner.
        if let days = purchases.access.daysLeft, !showsTrialStrip {
            line += " · " + String(localized: "\(LaqtaFormat.count(days, "day", "days")) left")
        }
        return line
    }

    // MARK: Dock

    private var dock: some View {
        HStack(spacing: 0) {
            Button {
                if purchases.allowAdding(.saving) { showingImport = true }
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .labelStyle(DockLabelStyle())
            }
            .largeContentLabel(Text("Import"), systemImage: "square.and.arrow.down")
            Rectangle()
                .fill(palette.hair)
                .frame(width: 1, height: 22)
            Button {
                if purchases.allowAdding(.folder) { showingNewFolder = true }
            } label: {
                Label("New Folder", systemImage: "plus")
                    .labelStyle(DockLabelStyle())
            }
            .largeContentLabel(Text("New Folder"), systemImage: "plus")
        }
        .buttonStyle(.pressable)
        .foregroundStyle(palette.goldHi)
        .padding(.horizontal, 6)
        .frame(minHeight: 56)
        .laqtaGlass(in: Capsule(), interactive: true)
        .padding(.bottom, 10)
    }

    // MARK: Actions

    @ViewBuilder
    private func folderMenu(_ folder: Folder, twin: FolderMergePair?) -> some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button {
                guard purchases.allowAdding() else { return }
                withUnlock(folder) { cameraFolder = folder }
            } label: {
                Label("Camera into “\(folder.name)”", systemImage: "camera")
            }
        }
        Button {
            withUnlock(folder) { editingFolder = folder }
        } label: {
            Label("Edit Folder", systemImage: "pencil")
        }
        // Stays available after "Keep Both", for when the answer changes.
        if let twin {
            Button {
                withUnlock(folder) { merge(twin) }
            } label: {
                Label("Merge the Two “\(folder.name)”", systemImage: "arrow.triangle.merge")
            }
        }
        if folder.isLocked, lock.locksEnabled, lock.unlockedFolderIDs.contains(folder.id) {
            Button {
                lock.lock(folder.id)
            } label: {
                Label("Lock Now", systemImage: "lock")
            }
        }
        Divider()
        Button(role: .destructive) {
            withUnlock(folder) { folderPendingDeletion = folder }
        } label: {
            Label("Delete Folder", systemImage: "trash")
        }
    }

    private func merge(_ pair: FolderMergePair) {
        withAnimation {
            FolderMerge.merge(pair, context: modelContext)
        }
        library.refresh()
        library.highlight(pair.keepID)
    }

    private func withUnlock(_ folder: Folder, _ action: @escaping () -> Void) {
        if folder.isLocked, !lock.isUnlocked(folder.id) {
            let folderID = folder.id
            Task {
                if await lock.unlock(folderID) { action() }
            }
        } else {
            action()
        }
    }

    private func open(_ folder: Folder) {
        let folderID = folder.id
        if let navigator {
            // The sidebar handles private folders.
            navigator.openFolder(folderID)
            return
        }
        withUnlock(folder) {
            path.append(.folder(folderID))
        }
    }
}

// MARK: - Pieces

/// A folder card that also takes dropped items.
private struct DroppableFolderCard: View {
    let folder: Folder
    let stats: FolderStats
    let isUnlocked: Bool
    let highlighted: Bool
    var subfolders: Int = 0
    let dropImport: DropImportModel
    let action: () -> Void

    @Environment(\.laqta) private var palette
    @State private var isDropTarget = false

    var body: some View {
        Button(action: action) {
            FolderCard(folder: folder, stats: stats, isUnlocked: isUnlocked, highlighted: highlighted, subfolders: subfolders)
                .overlay {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(palette.goldHi, lineWidth: 2.5)
                    }
                }
                .scaleEffect(isDropTarget ? 1.02 : 1)
                .animation(.snappy(duration: 0.2), value: isDropTarget)
        }
        .buttonStyle(.pressable)
        .hoverEffect(.lift)
        .acceptsDrops(into: folder.id, model: dropImport, isTargeted: $isDropTarget)
    }
}

/// "Recently Deleted · 3 items" at the end of the folder list.
struct TrashRow: View {
    let count: Int
    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .laqtaIconFont(15, weight: .semibold)
                .foregroundStyle(palette.goldHi)
                .frame(width: 36, height: 36)
                .background(palette.field, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Recently Deleted")
                    .laqtaFont(15, weight: .semibold)
                    .foregroundStyle(palette.ink)
                Text("\(LaqtaFormat.count(count, "item", "items")) · kept for 30 days")
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .laqtaIconFont(13, weight: .semibold)
                .foregroundStyle(palette.ink3)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 62)
        .background(palette.sheet2.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct SmallLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .laqtaIconFont(11, weight: .semibold)
            configuration.title
                .laqtaFont(12, weight: .medium)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct DockLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .laqtaIconFont(16, weight: .semibold)
            configuration.title
                .laqtaFont(15, weight: .semibold, maxScale: 1.35)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .contentShape(Capsule())
    }
}

private struct OnboardingHint: View {
    @Environment(\.laqta) private var palette

    var body: some View {
        LaqtaCard {
            CardHeader("Start from the share sheet", systemImage: "square.and.arrow.up")
            VStack(alignment: .leading, spacing: 10) {
                step(1, "Open a photo, a screenshot or any link.")
                step(2, "Tap Share, then choose Laqta.")
                step(3, "Pick the suggested folder. Laqta keeps its own copy.")
            }
            Text("Don't see Laqta? Scroll to the end of the app row, tap More, and turn it on.")
                .laqtaFont(12)
                .foregroundStyle(palette.ink2)
                .padding(.top, 12)
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number, format: .number)
                .laqtaFont(12, weight: .bold)
                .foregroundStyle(palette.goldInk)
                .frame(width: 22, height: 22)
                .background(palette.accentFill, in: Circle())
            Text(text)
                .laqtaFont(14)
                .foregroundStyle(palette.ink)
        }
    }
}
