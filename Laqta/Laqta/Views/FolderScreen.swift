//
//  FolderScreen.swift
//  Laqta
//
//  A folder: blurred cover band, Amiri title, smart filters, sorting,
//  and the grid of photos, videos, PDFs and links.
//

import Foundation
import SwiftData
import SwiftUI

nonisolated enum SmartFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case places
    case text
    case videos
    case documents
    case links
    case notes
    case favorites

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .places: "Places"
        case .text: "Text"
        case .videos: "Videos"
        case .documents: "PDFs"
        case .links: "Links"
        case .notes: "Notes"
        case .favorites: "Favorites"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "photo.on.rectangle"
        case .places: "mappin.and.ellipse"
        case .text: "text.viewfinder"
        case .videos: "play.rectangle"
        case .documents: "doc.richtext"
        case .links: "link"
        case .notes: "note.text"
        case .favorites: "heart"
        }
    }
}

struct FolderScreen: View {
    let folderID: UUID
    @Binding var path: [Route]

    @AppObject(LockManager.self) private var lock
    @Environment(\.laqta) private var palette
    @Query private var matches: [Folder]

    init(folderID: UUID, path: Binding<[Route]>) {
        self.folderID = folderID
        self._path = path
        let target = folderID
        _matches = Query(filter: #Predicate<Folder> { $0.id == target })
    }

    var body: some View {
        if let folder = matches.first, folder.deletedAt == nil {
            if lock.canShow(folder) {
                FolderContent(folder: folder, path: $path)
            } else {
                LockedFolderView(folder: folder)
            }
        } else {
            ZStack {
                LaqtaBackground()
                Text(matches.first == nil ? "This folder no longer exists." : "This folder is in Recently Deleted.")
                    .foregroundStyle(palette.ink2)
            }
        }
    }
}

private struct LockedFolderView: View {
    let folder: Folder
    @AppObject(LockManager.self) private var lock
    @Environment(\.laqta) private var palette

    var body: some View {
        ZStack {
            LaqtaBackground()
            VStack(spacing: 16) {
                FolderBadge(symbol: "lock", halo: true)
                FolderNameText(name: folder.name, size: 34, color: palette.goldHi)
                Button {
                    Task { _ = await lock.unlock(folder.id) }
                } label: {
                    LaqtaButtonLabel("Unlock", systemImage: "faceid")
                }
                .buttonStyle(.pressable)
            }
        }
        .task {
            _ = await lock.unlock(folder.id)
        }
    }
}

private struct FolderContent: View {
    let folder: Folder
    @Binding var path: [Route]

    @AppObject(LibraryModel.self) private var library
    @AppObject(LockManager.self) private var lock
    @AppObject(ToastCenter.self) private var toasts
    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var filter: SmartFilter = .all
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var importTab: ImportSheet.Tab?
    @State private var showingEditor = false
    @State private var showingMove = false
    @State private var confirmingDelete = false
    @State private var isDropTarget = false
    @State private var showingNewChild = false
    @AppObject(DropImportModel.self, otherwise: { DropImportModel() }) private var dropImport
    @AppObject(PurchaseCenter.self) private var purchases

    var body: some View {
        FolderItemsView(
            folder: folder,
            filter: $filter,
            isSelecting: isSelecting,
            selection: $selection,
            path: $path
        )
        .id(library.refreshToken)
        .background(LaqtaBackground())
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(palette.goldHi, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .acceptsDrops(into: folder.id, model: dropImport, isTargeted: $isDropTarget)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onChange(of: isSelecting) { _, selecting in
            if !selecting { selection.removeAll() }
        }
        .sheet(item: $importTab) { tab in
            ImportSheet(targetFolderID: folder.id, initialTab: tab)
                .laqtaThemed()
        }
        .sheet(isPresented: $showingEditor) {
            FolderEditorSheet(folder: folder)
                .laqtaThemed()
        }
        .sheet(isPresented: $showingMove) {
            MoveToFolderSheet(itemIDs: Array(selection), currentFolderID: folder.id) {
                isSelecting = false
            }
            .laqtaThemed()
        }
        .sheet(isPresented: $showingNewChild) {
            FolderEditorSheet(folder: nil, parentID: folder.id) { created in
                library.highlight(created.id)
            }
            .laqtaThemed()
        }
    }

    private var deleteTitle: String {
        let count = LaqtaStore.itemCount(in: folder.id, context: modelContext)
        return count == 0
            ? "Delete “\(folder.name)”?"
            : "Delete “\(folder.name)” and \(LaqtaFormat.count(count, "item", "items"))?"
    }

    private func deleteFolder() {
        let target = folder
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            library.trash(folder: target, context: modelContext)
            toasts.show(String(localized: "“\(target.name)” moved to Recently Deleted"), systemImage: "trash", actionTitle: String(localized: "Undo")) {
                library.restore(folder: target, context: modelContext)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { isSelecting = false }
                    .fontWeight(.semibold)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                ShareLink(items: selectedShareItems) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(selection.isEmpty)
                Spacer()
                Text(selection.isEmpty ? "Select items" : "\(selection.count) selected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.ink2)
                Spacer()
                Button {
                    showingMove = true
                } label: {
                    Label("Move", systemImage: "folder")
                }
                .disabled(selection.isEmpty)
                Button(role: .destructive) {
                    trashSelection()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection.isEmpty)
            }
        } else {
            if folder.isLocked, lock.locksEnabled {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        lock.lock(folder.id)
                        dismiss()
                    } label: {
                        Label("Lock", systemImage: "lock")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        if purchases.allowAdding(.saving) { importTab = .photos }
                    } label: {
                        Label("Photos & Videos", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        if purchases.allowAdding(.saving) { importTab = .files }
                    } label: {
                        Label("Files", systemImage: "folder")
                    }
                    Button {
                        if purchases.allowAdding(.saving) { importTab = .link }
                    } label: {
                        Label("Link", systemImage: "link")
                    }
                    Divider()
                    Button {
                        if purchases.allowAdding(.folder) { showingNewChild = true }
                    } label: {
                        Label("Folder Inside", systemImage: "folder.badge.plus")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("Add")
                    }
                    .laqtaFont(15, weight: .semibold)
                    .foregroundStyle(palette.goldHi)
                }
                .accessibilityLabel(Text("Add to folder"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isSelecting = true
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    Picker(selection: Binding(
                        get: { folder.sort },
                        set: { newValue in
                            withAnimation(.snappy) {
                                library.setSort(newValue, for: folder, context: modelContext)
                            }
                        }
                    )) {
                        ForEach(FolderSort.allCases) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option)
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                        Text(verbatim: folder.sort.title)
                    }
                    .pickerStyle(.menu)
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Edit Folder", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete Folder", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                // Shown next to the button that asked for it.
                .confirmationDialog(deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete Folder", role: .destructive) {
                        deleteFolder()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("It moves to Recently Deleted for 30 days. Your Photos library isn't touched.")
                }
            }
        }
    }

    private var selectedItems: [Shot] {
        LaqtaStore.items(withIDs: Array(selection), context: modelContext)
    }

    private var selectedShareItems: [URL] {
        selectedItems.compactMap { item in
            item.isLink ? item.url : item.fileURL
        }
    }

    private func trashSelection() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        withAnimation {
            library.trash(items, context: modelContext)
        }
        isSelecting = false
        toasts.show(
            items.count == 1
                ? String(localized: "Moved to Recently Deleted")
                : String(localized: "\(items.count) items moved to Recently Deleted"),
            systemImage: "trash",
            actionTitle: String(localized: "Undo")
        ) {
            withAnimation {
                library.restore(items, context: modelContext)
            }
        }
    }
}

/// A folder inside a folder: small, so it never competes with the photos below it.
struct SubfolderChip: View {
    let folder: Folder
    let count: Int

    @Environment(\.laqta) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            FolderNameText(name: folder.name, size: 19, maxScale: 1.3)
            Text(verbatim: count == 0 ? "Empty" : LaqtaFormat.count(count, "item", "items"))
                .laqtaFont(11.5)
                .foregroundStyle(palette.meta)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 158, height: 84, alignment: .leading)
        .background {
            ZStack {
                FolderCoverView(source: nil, tone: folder.tone)
                LinearGradient(
                    colors: [palette.veil1, palette.veil2],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .background(palette.sheet2)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Image(systemName: folder.isLocked ? "lock" : folder.badgeSymbol)
                .laqtaIconFont(11, weight: .semibold)
                .foregroundStyle(palette.goldHi)
                .padding(9)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(folder.name), \(LaqtaFormat.count(count, "item", "items"))"))
        .accessibilityAddTraits(.isButton)
    }
}

/// The date beside a day's photos: the number, the month, and a line down the side.
struct DayRail: View {
    let date: Date

    @Environment(\.laqta) private var palette

    var body: some View {
        VStack(spacing: 1) {
            Text(verbatim: date.formatted(.dateTime.day().locale(LaqtaFormat.locale)))
                .laqtaDisplayFont(24, bold: true, maxScale: 1.3)
                .foregroundStyle(palette.goldHi)
            Text(verbatim: date.formatted(.dateTime.month(.abbreviated).locale(LaqtaFormat.locale)).uppercased())
                .laqtaFont(9.5, weight: .semibold, maxScale: 1.2)
                .tracking(0.9)
                .foregroundStyle(palette.gold)
            if isThisYear {
                Rectangle()
                    .fill(palette.hair)
                    .frame(width: 1)
                    .padding(.top, 6)
            } else {
                Text(verbatim: date.formatted(.dateTime.year().locale(LaqtaFormat.locale)))
                    .laqtaFont(9.5, maxScale: 1.2)
                    .foregroundStyle(palette.ink3)
                Rectangle()
                    .fill(palette.hair)
                    .frame(width: 1)
                    .padding(.top, 6)
            }
        }
        .frame(width: 40)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: LaqtaFormat.shortDate(date)))
    }

    private var isThisYear: Bool {
        Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
    }
}

// MARK: - Items

private struct FolderItemsView: View {
    let folder: Folder
    @Binding var filter: SmartFilter
    let isSelecting: Bool
    @Binding var selection: Set<UUID>
    @Binding var path: [Route]

    @AppObject(LibraryModel.self) private var library
    @AppObject(ToastCenter.self) private var toasts
    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var items: [Shot]
    @Query private var childFolders: [Folder]

    @State private var movingItemID: UUID?
    @State private var noteItem: Shot?
    @State private var childCounts: [UUID: Int] = [:]
    @State private var showingNewChild = false
    @AppObject(PurchaseCenter.self) private var purchases

    init(folder: Folder, filter: Binding<SmartFilter>, isSelecting: Bool, selection: Binding<Set<UUID>>, path: Binding<[Route]>) {
        self.folder = folder
        self._filter = filter
        self.isSelecting = isSelecting
        self._selection = selection
        self._path = path
        let target: UUID? = folder.id
        _items = Query(
            filter: #Predicate<Shot> { $0.folderID == target && $0.deletedAt == nil },
            sort: \Shot.addedAt,
            order: .reverse
        )
        _childFolders = Query(filter: #Predicate<Folder> { $0.parentID == target && $0.deletedAt == nil })
    }

    private var sortedChildren: [Folder] {
        childFolders.sorted { $0.lastUpdate > $1.lastUpdate }
    }

    /// Larger text sizes get fewer, bigger tiles so titles stay readable.
    private var columns: [GridItem] {
        let large = dynamicTypeSize.isAccessibilitySize
        let minimum: CGFloat = sizeClass == .regular ? (large ? 240 : 170) : (large ? 160 : 108)
        return [GridItem(.adaptive(minimum: minimum), spacing: 4)]
    }

    private var cellHeight: CGFloat {
        let large = dynamicTypeSize.isAccessibilitySize
        return sizeClass == .regular ? (large ? 290 : 210) : (large ? 215 : 150)
    }

    private func count(_ filter: SmartFilter) -> Int {
        items.filter { matches($0, filter) }.count
    }

    private func matches(_ item: Shot, _ filter: SmartFilter) -> Bool {
        switch filter {
        case .all: true
        case .places: item.tags.contains(.place)
        case .text: item.tags.contains(.text)
        case .videos: item.isVideo
        case .documents: item.isDocument
        case .links: item.isLink
        case .notes: !item.note.isEmpty
        case .favorites: item.isFavorite
        }
    }

    private var sorted: [Shot] {
        let sort = folder.sort
        guard sort != .newest else { return items }
        return items.sorted { sort.areInIncreasingOrder($0.sortKey, $1.sortKey) }
    }

    var body: some View {
        let visible = sorted.filter { matches($0, filter) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    FolderNameText(name: folder.name, size: 46, color: palette.goldHi)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: meta)
                        .laqtaFont(14)
                        .foregroundStyle(palette.meta)
                }
                .padding(.top, 150)
                .padding(.horizontal, 16)

                if !sortedChildren.isEmpty {
                    subfolders
                        .padding(.top, 20)
                }

                chips
                    .padding(.top, 18)

                if visible.isEmpty, sortedChildren.isEmpty {
                    EmptyFolderView(isFiltered: filter != .all)
                        .padding(.top, 40)
                } else if folder.sort == .kind {
                    groupedGrid(visible)
                } else if folder.sort == .title {
                    grid(visible)
                        .padding(.top, 16)
                } else {
                    dayGrid(visible)
                        .padding(.top, 16)
                }
            }
            .padding(.bottom, 40)
            .background(alignment: .top) {
                CoverBand(cover: Shot.bestCover(in: items), tone: folder.tone)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .sheet(item: Binding(
            get: { movingItemID.map(MoveRequest.init(id:)) },
            set: { movingItemID = $0?.id }
        )) { request in
            MoveToFolderSheet(itemIDs: [request.id], currentFolderID: folder.id)
                .laqtaThemed()
        }
        .sheet(item: $noteItem) { item in
            NoteEditorSheet(item: item)
                .laqtaThemed()
        }
        .sheet(isPresented: $showingNewChild) {
            FolderEditorSheet(folder: nil, parentID: folder.id) { created in
                library.highlight(created.id)
            }
            .laqtaThemed()
        }
        .task(id: sortedChildren.map(\.id)) {
            var counts: [UUID: Int] = [:]
            for child in sortedChildren {
                counts[child.id] = LaqtaStore.itemCount(in: child.id, context: modelContext)
            }
            childCounts = counts
        }
    }

    /// Folders inside this one, as a row you scroll sideways.
    private var subfolders: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Folders") {
                Button {
                    if purchases.allowAdding(.folder) { showingNewChild = true }
                } label: {
                    Label("New", systemImage: "folder.badge.plus")
                        .labelStyle(SmallLabelStyle())
                        .foregroundStyle(palette.goldHi)
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(sortedChildren) { child in
                        Button {
                            path.append(.folder(child.id))
                        } label: {
                            SubfolderChip(folder: child, count: childCounts[child.id] ?? 0)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func grid(_ visible: [Shot]) -> some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(visible) { item in
                cell(for: item)
            }
        }
        .padding(.horizontal, 16)
        .animation(.snappy, value: filter)
        .animation(.snappy, value: folder.sort)
    }

    /// The day a shot belongs to: when it was taken, or when it was saved if that's all we know.
    private func day(of item: Shot) -> Date {
        let date = folder.sort == .newest || folder.sort == .oldest ? item.addedAt : (item.capturedAt ?? item.addedAt)
        return Calendar.current.startOfDay(for: date)
    }

    /// Photos under a rail of dates, so a screenshot's day is visible without opening it.
    private func dayGrid(_ visible: [Shot]) -> some View {
        let groups = Dictionary(grouping: visible, by: day(of:))
        let days = groups.keys.sorted(by: folder.sort == .oldest ? (<) : (>))
        return LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(days, id: \.self) { date in
                let dayItems = groups[date] ?? []
                HStack(alignment: .top, spacing: 10) {
                    DayRail(date: date)
                    VStack(alignment: .leading, spacing: 6) {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(dayItems) { item in
                                cell(for: item)
                            }
                        }
                        Text(verbatim: LaqtaFormat.contents(counts(of: dayItems)))
                            .laqtaFont(11.5)
                            .foregroundStyle(palette.ink3)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .animation(.snappy, value: filter)
        .animation(.snappy, value: folder.sort)
    }

    private func counts(of items: [Shot]) -> FolderStats {
        var stats = FolderStats()
        for item in items { stats.count(item.kind) }
        return stats
    }

    private func groupedGrid(_ visible: [Shot]) -> some View {
        let groups = Dictionary(grouping: visible, by: \.kind)
        let kinds = groups.keys.sorted { $0.groupOrder < $1.groupOrder }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(kinds, id: \.self) { kind in
                SectionLabel(verbatim: kind.groupTitle) {
                    Text(verbatim: LaqtaFormat.number(groups[kind]?.count ?? 0))
                        .laqtaFont(12, weight: .medium)
                        .foregroundStyle(palette.ink2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 10)
                grid(groups[kind] ?? [])
            }
        }
    }

    private var meta: String {
        var stats = FolderStats()
        for item in items { stats.count(item.kind) }
        let updated = Date.now.timeIntervalSince(folder.lastUpdate) < 120 ? "Updated just now" : LaqtaFormat.updated(folder.lastUpdate)
        guard !sortedChildren.isEmpty else { return "\(stats.summary) · \(updated)" }
        let inside = LaqtaFormat.count(sortedChildren.count, "folder", "folders")
        guard stats.total > 0 else { return "\(inside) · \(updated)" }
        return "\(inside) · \(stats.summary) · \(updated)"
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(SmartFilter.allCases) { option in
                    let total = count(option)
                    if option == .all || total > 0 {
                        Button {
                            withAnimation(.snappy) { filter = option }
                        } label: {
                            FilterChip(title: option.title, systemImage: option.systemImage, count: total, isOn: filter == option)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityAddTraits(filter == option ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func open(_ item: Shot) {
        switch item.kind {
        case .link:
            path.append(.link(item.id))
        case .document:
            path.append(.document(item.id))
        case .photo, .video:
            path.append(.viewer(folderID: folder.id, startID: item.id))
        }
    }

    @ViewBuilder
    private func cell(for item: Shot) -> some View {
        let isSelected = selection.contains(item.id)
        Button {
            if isSelecting {
                if isSelected {
                    selection.remove(item.id)
                } else {
                    selection.insert(item.id)
                }
            } else {
                open(item)
            }
        } label: {
            FolderItemCell(item: item, isSelecting: isSelecting, isSelected: isSelected, height: cellHeight)
                .zoomSource(id: item.id)
        }
        .buttonStyle(.pressable)
        .hoverEffect(.lift)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("Add Note")) { noteItem = item }
        .accessibilityAction(named: Text("Move to Folder")) { movingItemID = item.id }
        .accessibilityAction(named: Text("Delete")) { trash(item) }
        .contextMenu {
            ItemContextMenu(item: item) {
                noteItem = item
            } onMove: {
                movingItemID = item.id
            } onDelete: {
                trash(item)
            }
        }
        .draggable(ItemTransfer(item: item)) {
            FolderItemCell(item: item, height: 120, showsBadges: false)
                .frame(width: 90)
        }
    }

    private func trash(_ item: Shot) {
        withAnimation {
            library.trash([item], context: modelContext)
        }
        toasts.show(String(localized: "Moved to Recently Deleted"), systemImage: "trash", actionTitle: String(localized: "Undo")) {
            withAnimation {
                library.restore([item], context: modelContext)
            }
        }
    }
}

/// The long-press menu of a saved item.
struct ItemContextMenu: View {
    let item: Shot
    let onNote: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    @AppObject(LibraryModel.self) private var library
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if item.isLink, let url = item.url {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                Clipboard.copy(url.absoluteString)
            } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
            }
        } else if item.hasMediaFile {
            ShareLink(item: ShareableFile(item: item), preview: SharePreview(Text(verbatim: item.shareFileName))) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        Button {
            library.toggleFavorite(item, context: modelContext)
        } label: {
            Label(item.isFavorite ? "Remove from Favorites" : "Favorite", systemImage: item.isFavorite ? "heart.slash" : "heart")
        }
        Button(action: onNote) {
            Label(item.note.isEmpty ? "Add Note" : "Edit Note", systemImage: "note.text")
        }
        Button(action: onMove) {
            Label("Move to Folder", systemImage: "folder")
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
    }
}

private nonisolated struct MoveRequest: Identifiable, Sendable {
    let id: UUID
}

/// The soft cover behind the folder title.
private struct CoverBand: View {
    let cover: CoverSource?
    let tone: FolderTone
    @Environment(\.laqta) private var palette

    var body: some View {
        FolderCoverView(source: cover, tone: tone)
            .overlay {
                LinearGradient(colors: [palette.bandTop, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.6))
            }
            // Keeps the folder name readable on bright covers, like the folder cards.
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: palette.veil2, location: 0),
                        .init(color: palette.veil2.opacity(0.55), location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .overlay { GrainOverlay(opacity: 0.4) }
            .frame(height: 330)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.42),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct EmptyFolderView: View {
    let isFiltered: Bool
    @Environment(\.laqta) private var palette

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle" : "photo.on.rectangle.angled")
                .laqtaIconFont(30, weight: .light)
                .foregroundStyle(palette.gold)
                .accessibilityHidden(true)
            Text(isFiltered ? "Nothing here yet" : "Nothing saved yet")
                .laqtaFont(17, weight: .semibold)
                .foregroundStyle(palette.ink)
            Text(isFiltered ? "Try another filter." : "Share a photo, a video, a PDF or a link to Laqta, or tap Add.")
                .laqtaFont(14)
                .foregroundStyle(palette.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}

// MARK: - Cell

struct FolderItemCell: View {
    let item: Shot
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var height: CGFloat = 150
    var showsBadges: Bool = true

    @Environment(\.laqta) private var palette

    var body: some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                switch item.kind {
                case .link:
                    LinkCellContent(item: item)
                case .document:
                    DocumentCellContent(item: item)
                case .photo, .video:
                    ShotThumbnail(shot: item)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if item.isVideoFile {
                    PlayBadge(size: 34)
                }
            }
            .overlay(alignment: .topLeading) {
                if showsBadges, item.isNew, !isSelecting {
                    Text("New")
                        .laqtaFont(11, weight: .semibold, maxScale: 1.25)
                        .foregroundStyle(palette.goldInk)
                        .padding(.horizontal, 7)
                        .frame(minHeight: 20)
                        .background(palette.accentFill, in: Capsule())
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.isVideoFile, !isSelecting, let duration = item.mediaDuration {
                    DurationBadge(seconds: duration)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if showsBadges, item.isViewerMedia, !tagSymbols.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tagSymbols, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .laqtaIconFont(10, weight: .semibold)
                        }
                    }
                    .foregroundStyle(Color(hex: 0xF2E4C4))
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(Color(hex: 0x121010, alpha: 0.55), in: Capsule())
                    .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsBadges, item.isFavorite, item.isViewerMedia {
                    Image(systemName: "heart.fill")
                        .laqtaIconFont(12)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                        .padding(7)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .laqtaIconFont(22)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isSelected ? palette.goldInk : .white, isSelected ? palette.accentFill : Color.black.opacity(0.25))
                        .padding(6)
                }
            }
            .overlay {
                if isSelecting, isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(palette.accentFill, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: accessibilityText))
            .accessibilityAddTraits(item.isPhoto ? .isImage : [])
    }

    private var tagSymbols: [String] {
        var symbols: [String] = []
        let tags = item.tags
        if tags.contains(.place) { symbols.append("mappin.and.ellipse") }
        if tags.contains(.text) { symbols.append("text.viewfinder") }
        if tags.contains(.note) { symbols.append("note.text") }
        return symbols
    }

    private var accessibilityText: String {
        var parts: [String] = [item.kindLabel]
        switch item.kind {
        case .link:
            parts.append(item.displayTitle)
            if let site = item.linkSite { parts.append(site) }
        case .document:
            parts.append(item.displayTitle)
            if let pages = item.documentPages { parts.append(LaqtaFormat.count(pages, "page", "pages")) }
        case .photo, .video:
            if item.displayTitle != item.kindLabel { parts.append(item.displayTitle) }
            if let duration = item.mediaDuration, item.isVideoFile { parts.append(LaqtaFormat.spokenDuration(duration)) }
            if let place = item.analysis?.place?.name { parts.append(place) }
        }
        if item.isFavorite { parts.append("Favorite") }
        if !item.note.isEmpty { parts.append("Note: \(item.note)") }
        parts.append("Added \(LaqtaFormat.shortDate(item.addedAt))")
        return parts.joined(separator: ", ")
    }
}

/// Round play glyph over video thumbnails.
struct PlayBadge: View {
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: "play.fill")
            .laqtaIconFont(size * 0.34, weight: .bold)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.ultraThinMaterial.opacity(0.6), in: Circle())
            .background(Color(hex: 0x121010, alpha: 0.42), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

struct DurationBadge: View {
    let seconds: Double

    var body: some View {
        Text(verbatim: LaqtaFormat.duration(seconds))
            .laqtaFont(10.5, weight: .semibold, monospacedDigit: true, maxScale: 1.25)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(minHeight: 20)
            .background(Color(hex: 0x0A0908, alpha: 0.62), in: Capsule())
            .accessibilityHidden(true)
    }
}

private struct LinkCellContent: View {
    let item: Shot

    var body: some View {
        if item.isYouTube {
            youTubeCell
        } else {
            webCell
        }
    }

    /// YouTube thumbnails stay whole and uncovered, with the details below.
    private var youTubeCell: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color(hex: 0x0A0908)
                if item.hasPreviewImage {
                    ShotThumbnail(shot: item, fits: true)
                } else {
                    GenericLinkArt(site: "youtube.com")
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.displayTitle)
                    .laqtaFont(11.5, weight: .semibold, maxScale: 1.5)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: "play.rectangle")
                        .laqtaIconFont(8, weight: .semibold)
                    Text(verbatim: item.linkAuthor ?? "YouTube")
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if let duration = item.linkDuration, item.isLinkVideo {
                        Text(verbatim: LaqtaFormat.duration(duration))
                            .laqtaFont(10, weight: .semibold, monospacedDigit: true, maxScale: 1.5)
                    }
                }
                .laqtaFont(10, maxScale: 1.5)
                .foregroundStyle(.white.opacity(0.74))
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(hex: 0x17140F))
        }
    }

    private var webCell: some View {
        ZStack(alignment: .bottomLeading) {
            if item.hasPreviewImage {
                ShotThumbnail(shot: item)
            } else {
                GenericLinkArt(site: item.linkSite ?? "")
            }
            LinearGradient(
                colors: [Color(hex: 0x0A0908, alpha: 0.9), Color(hex: 0x0A0908, alpha: 0)],
                startPoint: .bottom,
                endPoint: UnitPoint(x: 0.5, y: 0.28)
            )
            if item.isLinkVideo {
                PlayBadge()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: -12)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.displayTitle)
                    .laqtaFont(11.5, weight: .semibold, maxScale: 1.5)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: item.linkForm.systemImage)
                        .laqtaIconFont(8, weight: .semibold)
                    Text(verbatim: item.linkSite ?? "")
                        .lineLimit(1)
                }
                .laqtaFont(10, maxScale: 1.5)
                .foregroundStyle(.white.opacity(0.74))
            }
            .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            if let duration = item.linkDuration, item.isLinkVideo {
                DurationBadge(seconds: duration)
                    .padding(6)
            }
        }
    }
}

/// A PDF's first page on a soft backdrop, with its title.
private struct DocumentCellContent: View {
    let item: Shot

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hex: 0x3A3129), Color(hex: 0x1E1A16)], startPoint: .topLeading, endPoint: .bottomTrailing)
            ShotThumbnail(shot: item, cornerRadius: 3)
                .aspectRatio(0.74, contentMode: .fit)
                .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                .padding(.top, 12)
                .padding(.horizontal, 16)
                .padding(.bottom, 34)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            LinearGradient(
                colors: [Color(hex: 0x0A0908, alpha: 0.92), Color(hex: 0x0A0908, alpha: 0)],
                startPoint: .bottom,
                endPoint: UnitPoint(x: 0.5, y: 0.55)
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.displayTitle)
                    .laqtaFont(11.5, weight: .semibold, maxScale: 1.5)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(verbatim: "PDF")
                        .laqtaFont(8.5, weight: .heavy, maxScale: 1.25)
                        .padding(.horizontal, 4)
                        .frame(minHeight: 13)
                        .background(Color(hex: 0xB0412F), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    if let pages = item.documentPages {
                        Text(verbatim: LaqtaFormat.count(pages, "page", "pages"))
                            .lineLimit(1)
                    }
                }
                .laqtaFont(10, maxScale: 1.5)
                .foregroundStyle(.white.opacity(0.78))
            }
            .padding(8)
        }
    }
}

/// Stand-in art for links without a preview image.
struct GenericLinkArt: View {
    let site: String

    var body: some View {
        ZStack {
            RadialGradient(
                stops: [
                    .init(color: Color(hex: 0x6B5A43), location: 0),
                    .init(color: Color(hex: 0x2A241D), location: 0.6),
                    .init(color: Color(hex: 0x1A1714), location: 1)
                ],
                center: UnitPoint(x: 0.8, y: 0.2),
                startRadius: 0,
                endRadius: 180
            )
            VStack(spacing: 6) {
                Image(systemName: "globe")
                    .laqtaIconFont(24, weight: .light)
                Text(verbatim: site)
                    .laqtaFont(10, weight: .medium)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            }
            .foregroundStyle(Color(hex: 0xE9D3A4))
            .offset(y: -14)
        }
        .accessibilityHidden(true)
    }
}
