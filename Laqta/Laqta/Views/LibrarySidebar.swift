//
//  LibrarySidebar.swift
//  Laqta
//
//  iPad: folders in a sidebar, the open folder beside them. Photos and PDFs take the
//  whole window. Items can be dragged onto a folder, and files dropped onto it are saved.
//

import SwiftData
import SwiftUI

enum SidebarItem: Hashable {
    case home
    case search
    case trash
    case folder(UUID)
}

struct LibrarySplitView: View {
    @Binding var path: [Route]
    @Binding var selection: SidebarItem?

    @AppObject(LockManager.self) private var lock
    @Environment(\.modelContext) private var modelContext

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebar(selection: $selection, path: $path)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } detail: {
            NavigationStack(path: $path) {
                detailRoot
                    .navigationDestination(for: Route.self) { route in
                        RouteDestination(route: route, path: $path)
                    }
            }
            .environment(\.libraryNavigator, navigator)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selection) { _, _ in
            path.removeAll()
        }
        .onChange(of: path) { _, newPath in
            let immersive = newPath.last?.isImmersive ?? false
            withAnimation(.snappy) {
                columnVisibility = immersive ? .detailOnly : .all
            }
        }
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch selection {
        case let .folder(folderID):
            FolderScreen(folderID: folderID, path: $path)
                .id(folderID)
        case .search:
            SearchScreen(path: $path)
        case .trash:
            RecentlyDeletedScreen(path: $path)
        case .home, nil:
            HomeScreen(path: $path)
        }
    }

    private var navigator: LibraryNavigator {
        LibraryNavigator(
            openFolder: { folderID in
                selection = .folder(folderID)
            },
            openSearch: {
                selection = .search
            },
            openTrash: {
                selection = .trash
            }
        )
    }
}

struct LibrarySidebar: View {
    @Binding var selection: SidebarItem?
    @Binding var path: [Route]

    @AppObject(LibraryModel.self) private var library
    @AppObject(LockManager.self) private var lock
    @AppObject(ToastCenter.self) private var toasts
    @AppObject(DropImportModel.self, otherwise: { DropImportModel() }) private var dropImport
    @AppObject(PurchaseCenter.self) private var purchases
    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette

    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }) private var folders: [Folder]
    @Query(SidebarCounts.descriptor) private var items: [Shot]

    @State private var trashCount = 0
    @State private var showingSettings = false
    @State private var showingInsights = false
    @State private var showingImport = false
    @State private var showingNewFolder = false
    @State private var editingFolder: Folder?
    @State private var folderPendingDeletion: Folder?
    @State private var openTrashAfterSettings = false

    /// The sidebar lists the top level; folders inside a folder open from the folder itself.
    private var sortedFolders: [Folder] {
        folders.filter { $0.parentID == nil }.sorted { $0.lastUpdate > $1.lastUpdate }
    }

    private var counts: [UUID: FolderStats] {
        var result: [UUID: FolderStats] = [:]
        for item in items {
            guard let folderID = item.folderID else { continue }
            result[folderID, default: FolderStats()].count(item.kind)
        }
        return result
    }

    var body: some View {
        let counts = counts
        List(selection: $selection) {
            Section {
                Label("All Folders", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.home)
                Label("Search", systemImage: "magnifyingglass")
                    .tag(SidebarItem.search)
                Button {
                    showingInsights = true
                } label: {
                    Label("Insights", systemImage: "sparkles")
                }
                .foregroundStyle(palette.ink)
                Label("Recently Deleted", systemImage: "trash")
                    .badge(trashCount)
                    .tag(SidebarItem.trash)
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Laqta")
                        .laqtaDisplayFont(38, maxScale: 1.25)
                        .foregroundStyle(palette.goldHi)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: summary(counts))
                        .laqtaFont(13)
                        .foregroundStyle(palette.ink2)
                        .textCase(nil)
                }
                .padding(.bottom, 10)
            }

            Section {
                ForEach(sortedFolders) { folder in
                    SidebarFolderRow(
                        folder: folder,
                        stats: counts[folder.id] ?? FolderStats(),
                        isUnlocked: lock.canShow(folder),
                        highlighted: library.highlightedFolderID == folder.id,
                        isSelected: selection == .folder(folder.id)
                    )
                    .tag(SidebarItem.folder(folder.id))
                    .contextMenu {
                        folderMenu(folder)
                    }
                }
            } header: {
                Text("Folders")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(LaqtaBackground())
        // A deep bronze selection keeps white text readable in both themes.
        .tint(palette.isNoir ? Color(hex: 0x8A6A32) : palette.goldHi)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    if purchases.allowAdding(.saving) { showingImport = true }
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                Spacer()
                Button {
                    if purchases.allowAdding(.folder) { showingNewFolder = true }
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .background {
            Button("Search") { selection = .search }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .task(id: library.trashVersion) {
            trashCount = library.trashCount(context: modelContext)
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            if openTrashAfterSettings {
                openTrashAfterSettings = false
                selection = .trash
            }
        }) {
            SettingsScreen {
                openTrashAfterSettings = true
            }
            .laqtaThemed()
        }
        .sheet(isPresented: $showingInsights) {
            // Items opened from Insights appear in the detail column.
            InsightsSheet(path: $path)
                .laqtaThemed()
        }
        .sheet(isPresented: $showingImport) {
            ImportSheet(targetFolderID: selectedFolderID)
                .laqtaThemed()
        }
        .sheet(isPresented: $showingNewFolder) {
            FolderEditorSheet(folder: nil) { created in
                library.highlight(created.id)
                selection = .folder(created.id)
            }
            .laqtaThemed()
        }
        .sheet(item: $editingFolder) { folder in
            FolderEditorSheet(folder: folder)
                .laqtaThemed()
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(get: { folderPendingDeletion != nil }, set: { if !$0 { folderPendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                if let folder = folderPendingDeletion { trash(folder) }
                folderPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                folderPendingDeletion = nil
            }
        } message: {
            Text("It moves to Recently Deleted for 30 days. Your Photos library isn't touched.")
        }
    }

    private var selectedFolderID: UUID? {
        if case let .folder(folderID)? = selection { return folderID }
        return nil
    }

    private func summary(_ counts: [UUID: FolderStats]) -> String {
        var total = FolderStats()
        for value in counts.values {
            total.photos += value.photos
            total.videos += value.videos
            total.documents += value.documents
            total.links += value.links
        }
        let contents = total.total == 0 ? LaqtaFormat.count(0, "shot", "shots") : LaqtaFormat.contents(total)
        return "\(contents) · \(LaqtaFormat.count(folders.count, "folder", "folders"))"
    }

    @ViewBuilder
    private func folderMenu(_ folder: Folder) -> some View {
        Button {
            withUnlock(folder) { editingFolder = folder }
        } label: {
            Label("Edit Folder", systemImage: "pencil")
        }
        if folder.isLocked, lock.locksEnabled, lock.unlockedFolderIDs.contains(folder.id) {
            Button {
                lock.lock(folder.id)
                if selection == .folder(folder.id) { selection = .home }
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

    private func trash(_ folder: Folder) {
        if selection == .folder(folder.id) { selection = .home }
        withAnimation {
            library.trash(folder: folder, context: modelContext)
        }
        toasts.show(String(localized: "“\(folder.name)” moved to Recently Deleted"), systemImage: "trash", actionTitle: String(localized: "Undo")) {
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

enum SidebarCounts {
    static var descriptor: FetchDescriptor<Shot> {
        var descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.deletedAt == nil })
        descriptor.propertiesToFetch = [\.folderID, \.kindRaw]
        return descriptor
    }
}

private struct SidebarFolderRow: View {
    let folder: Folder
    let stats: FolderStats
    let isUnlocked: Bool
    let highlighted: Bool
    let isSelected: Bool

    @AppObject(DropImportModel.self, otherwise: { DropImportModel() }) private var dropImport
    @Environment(\.laqta) private var palette
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                ToneMesh(tone: folder.tone)
                Image(systemName: folder.isPrivate && !isUnlocked ? "lock" : folder.badgeSymbol)
                    .laqtaIconFont(13, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 1))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                FolderNameText(name: folder.name, size: 19, color: isSelected ? .white : palette.ink)
                Text(verbatim: folder.isPrivate && !isUnlocked ? String(localized: "Locked") : stats.summary)
                    .laqtaFont(12)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.78) : palette.ink2)
                    .adaptiveLineLimit(1, accessibility: 2)
            }
            Spacer(minLength: 0)
            if highlighted {
                Circle()
                    .fill(isSelected ? Color.white : palette.goldHi)
                    .frame(width: 7, height: 7)
                    .transition(.scale)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .background {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.goldHi.opacity(0.18))
                    .padding(-6)
            }
        }
        .acceptsDrops(into: folder.id, model: dropImport, isTargeted: $isDropTarget)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Drop photos, videos, PDFs or links here to save them to this folder"))
    }
}
