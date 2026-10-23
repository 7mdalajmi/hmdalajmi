import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum MacSection: Hashable {
    case all, favorites, trash, folder(UUID)
}

struct MacLibraryView: View {
    @Bindable var library: MacLibrary
    @Environment(\.modelContext) private var context
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query(sort: \Shot.addedAt, order: .reverse) private var items: [Shot]
    @State private var section: MacSection? = .all
    @State private var selected: Set<UUID> = []
    @State private var search = ""
    @State private var kind: ItemKind?
    @State private var sort: FolderSort = .newest
    @State private var showingLink = false
    @State private var showingFolder = false
    @State private var editingFolder: Folder?
    @State private var confirmingDelete = false
    @AppStorage("macAppearance") private var appearance = "system"

    private var currentFolder: Folder? {
        if case let .folder(id) = section { return folders.first { $0.id == id } }
        return nil
    }
    private var isTrash: Bool { section == .trash }
    private var accessAllowed: Bool { currentFolder.map { library.canAccess($0.id, folders: folders) } ?? true }
    private var selectedItems: [Shot] { visibleItems.filter { selected.contains($0.id) } }
    private var title: String {
        switch section {
        case .all, .none: "كل العناصر"
        case .favorites: "المفضلة"
        case .trash: "المحذوفة مؤخرًا"
        case .folder: currentFolder?.name ?? "مجلد"
        }
    }
    private var visibleItems: [Shot] {
        let needle = SearchIndex.normalize(search.trimmingCharacters(in: .whitespacesAndNewlines))
        let accessible = Set(folders.filter { library.canAccess($0.id, folders: folders) }.map(\.id))
        let trashed = Set(folders.filter(\.isInTrash).map(\.id))
        return items.filter { item in
            guard item.folderID.map(accessible.contains) ?? true, item.isInTrash == isTrash else { return false }
            if !isTrash, item.folderID.map(trashed.contains) == true { return false }
            if section == .favorites && !item.isFavorite { return false }
            if let folder = currentFolder, item.folderID != folder.id { return false }
            if let kind, item.kind != kind { return false }
            if !needle.isEmpty {
                let text = (item.searchText ?? "") + "\n" + SearchIndex.normalize(item.displayTitle + " " + (item.originalName ?? "") + " " + item.note)
                if !text.contains(needle) { return false }
            }
            return true
        }.sorted { sort.areInIncreasingOrder($0.sortKey, $1.sortKey) }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 360)
        } content: {
            VStack(spacing: 0) {
                if accessAllowed { contentTable }
                else if let folder = currentFolder {
                    ContentUnavailableView {
                        Label("مجلد خاص", systemImage: "lock.fill")
                    } description: {
                        Text("افتحه باستخدام Touch ID أو كلمة مرور الماك.")
                    } actions: {
                        Button("فتح المجلد") { Task { await library.unlock(folder, folders: folders) } }
                    }
                }
                if library.isBusy {
                    VStack(alignment: .leading) {
                        Text(library.activity).font(.caption)
                        ProgressView(value: library.progress)
                    }.padding()
                } else {
                    HStack {
                        Text("\(visibleItems.count) عنصر").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if !selected.isEmpty { Text("\(selected.count) محدد").font(.caption).foregroundStyle(.secondary) }
                    }.padding(10)
                }
            }
            .navigationTitle(title)
            .navigationSplitViewColumnWidth(min: 350, ideal: 560)
            .searchable(text: $search, prompt: "ابحث في النصوص والملاحظات والروابط")
            .toolbar { toolbar }
            .dropDestination(for: URL.self) { urls, _ in
                guard accessAllowed && !isTrash else { return false }
                Task { await handleDroppedURLs(urls) }
                return true
            }
        } detail: {
            if let item = selectedItems.first, selected.count == 1 {
                MacItemDetail(item: item, library: library)
                    .id(item.id)
            } else {
                ContentUnavailableView(selected.count > 1 ? "\(selected.count) عناصر محددة" : "اختر عنصرًا", systemImage: selected.count > 1 ? "square.stack" : "photo.on.rectangle", description: Text("اعرض الصور والفيديو وملفات PDF والروابط، وأضف ملاحظاتك."))
            }
        }
        .focusedSceneValue(\.macWorkspaceActions, MacWorkspaceActions(
            importFiles: { Task { await pickFiles() } },
            addLink: { if accessAllowed && !isTrash { showingLink = true } },
            newFolder: { if accessAllowed && !isTrash { editingFolder = nil; showingFolder = true } },
            restoreBackup: { Task { await pickBackup() } }
        ))
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .onChange(of: section) { _, _ in selected.removeAll(); search = ""; sort = currentFolder?.sort ?? .newest }
        .onChange(of: library.unlockedFolders) { _, _ in selected = selected.intersection(Set(visibleItems.map(\.id))) }
        .onChange(of: Set(visibleItems.map(\.id))) { _, ids in selected.formIntersection(ids) }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in library.lockAll() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in library.lockAll() }
        .onOpenURL { url in
            if url.pathExtension == "laqtabackup" { Task { await library.restoreBackup(url) } }
            else { Task { await handleDroppedURLs([url]) } }
        }
        .sheet(isPresented: $showingLink) {
            MacLinkSheet(library: library, folderID: currentFolder?.id)
        }
        .sheet(isPresented: $showingFolder) {
            MacFolderSheet(library: library, folder: editingFolder, parentID: currentFolder?.id, folders: folders)
        }
        .alert("لقطة", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button("حسنًا") { library.message = nil }
        } message: { Text(library.message ?? "") }
        .confirmationDialog("حذف \(selectedItems.count) عنصر نهائيًا؟ لا يمكن التراجع عن هذا الإجراء.", isPresented: $confirmingDelete) {
            Button("حذف نهائي", role: .destructive) { library.deletePermanently(selectedItems); selected.removeAll() }
            Button("إلغاء", role: .cancel) {}
        }
    }

    private var sidebar: some View {
        List(selection: $section) {
            Section("المكتبة") {
                Label("كل العناصر", systemImage: "square.grid.2x2").tag(MacSection.all)
                Label("المفضلة", systemImage: "star").tag(MacSection.favorites)
                Label("المحذوفة مؤخرًا", systemImage: "trash").tag(MacSection.trash)
            }
            Section("المجلدات") {
                ForEach(folders.filter { !$0.isInTrash }.sorted { folderPath($0) < folderPath($1) }) { folder in
                    HStack {
                        Label(folder.name, systemImage: folder.symbol)
                            .padding(.leading, CGFloat(max(0, LaqtaStore.path(to: folder.id, in: folders).count - 1)) * 12)
                        Spacer()
                        if !library.canAccess(folder.id, folders: folders) { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                    }
                    .tag(MacSection.folder(folder.id))
                    .help(folderPath(folder))
                    .contextMenu {
                        if library.canAccess(folder.id, folders: folders) {
                            Button("تعديل المجلد…") { editingFolder = folder; showingFolder = true }
                            Button("نقل إلى المحذوفة", role: .destructive) {
                                library.trash(folder, folders: folders, items: items)
                                if currentFolder?.id == folder.id { section = .all }
                            }
                        } else {
                            Button("فتح المجلد") { Task { await library.unlock(folder, folders: folders) } }
                        }
                    }
                    .disabled(library.isBusy)
                }
            }
            if isTrash {
                Section("المجلدات المحذوفة") {
                    ForEach(folders.filter(\.isInTrash)) { folder in
                        HStack {
                            Label(folder.name, systemImage: "folder.badge.minus")
                            Spacer()
                            Button("استعادة") {
                                Task {
                                    if !library.canAccess(folder.id, folders: folders) { await library.unlock(folder, folders: folders) }
                                    if library.canAccess(folder.id, folders: folders) { library.restore(folder, folders: folders, items: items) }
                                }
                            }.buttonStyle(.borderless).disabled(library.isBusy)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button { editingFolder = nil; showingFolder = true } label: { Label("مجلد جديد", systemImage: "folder.badge.plus") }
                .disabled(!accessAllowed || isTrash || library.isBusy)
                .padding()
        }
    }

    private var contentTable: some View {
        Table(visibleItems, selection: $selected) {
            TableColumn("العنصر") { shot in
                HStack(spacing: 10) {
                    MacThumbnail(item: shot).frame(width: 46, height: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(shot.originalName ?? shot.displayTitle).lineLimit(1)
                        if shot.originalName != nil { Text(shot.displayTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    if shot.isFavorite { Image(systemName: "star.fill").foregroundStyle(.orange) }
                }.padding(.vertical, 3)
            }.width(min: 190, ideal: 290)
            TableColumn("النوع") { shot in Text(shot.kindLabel).font(.caption).foregroundStyle(.secondary) }.width(80)
            TableColumn("التاريخ") { shot in Text(shot.addedAt, format: .dateTime.day().month().year()).font(.caption) }.width(100)
        }
        .overlay {
            if visibleItems.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? "المكتبة جاهزة لملفاتك" : "لا توجد نتائج", systemImage: search.isEmpty ? "tray.and.arrow.down" : "magnifyingglass")
                } description: {
                    Text(isTrash ? "العناصر التي تحذفها تبقى هنا حتى تستعيدها أو تحذفها نهائيًا." : "اسحب صورًا أو فيديو أو PDF من Finder، أو استخدم زر الاستيراد.")
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            let chosen = visibleItems.filter { ids.contains($0.id) }
            if !chosen.isEmpty {
                if isTrash {
                    Button("استعادة") { library.restore(chosen, folders: folders) }
                } else {
                    Button("تبديل المفضلة") { _ = library.save { for item in chosen { item.isFavorite.toggle() } } }
                    Menu("نقل إلى") {
                        ForEach(folders.filter { !$0.isInTrash && library.canAccess($0.id, folders: folders) }) { folder in
                            Button(folderPath(folder)) { _ = library.save { LibraryWriter.move(chosen, to: folder) } }
                        }
                    }
                    Button("تصدير الملفات…") { Task { await library.exportItems(chosen) } }
                    Button("نقل إلى المحذوفة", role: .destructive) { library.trash(chosen); selected.removeAll() }
                }
            }
        } primaryAction: { ids in selected = ids }
        .disabled(library.isBusy)
        .onDeleteCommand {
            if isTrash { confirmingDelete = !selectedItems.isEmpty }
            else { library.trash(selectedItems); selected.removeAll() }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { Task { await pickFiles() } } label: { Label("استيراد", systemImage: "square.and.arrow.down") }
                .disabled(library.isBusy || !accessAllowed || isTrash)
            Button { showingLink = true } label: { Label("إضافة رابط", systemImage: "link.badge.plus") }
                .disabled(library.isBusy || !accessAllowed || isTrash)
            Menu {
                Picker("النوع", selection: $kind) {
                    Text("كل الأنواع").tag(ItemKind?.none)
                    ForEach(ItemKind.allCases, id: \.rawValue) { Text($0.groupTitle).tag(Optional($0)) }
                }
                Picker("الترتيب", selection: $sort) { ForEach(FolderSort.allCases) { Text($0.title).tag($0) } }
            } label: { Label("عرض وترتيب", systemImage: "line.3.horizontal.decrease") }
            .onChange(of: sort) { _, value in if let folder = currentFolder { _ = library.save { folder.sort = value } } }
            if !selectedItems.isEmpty {
                Button { Task { await library.exportItems(selectedItems) } } label: { Label("تصدير", systemImage: "square.and.arrow.up") }
                if isTrash {
                    Button { library.restore(selectedItems, folders: folders); selected.removeAll() } label: { Label("استعادة", systemImage: "arrow.uturn.backward") }
                    Button { confirmingDelete = true } label: { Label("حذف نهائي", systemImage: "trash.slash") }
                } else {
                    Button { library.trash(selectedItems); selected.removeAll() } label: { Label("حذف", systemImage: "trash") }
                }
            }
            if !library.unlockedFolders.isEmpty {
                Button { library.lockAll() } label: { Label("قفل", systemImage: "lock") }
            }
        }
    }

    private func folderPath(_ folder: Folder) -> String { LaqtaStore.path(to: folder.id, in: folders).map(\.name).joined(separator: " / ") }

    private func pickFiles() async {
        guard accessAllowed && !isTrash && !library.isBusy else { return }
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.image, .movie, .pdf]
        picker.allowsMultipleSelection = true
        guard await picker.begin() == .OK else { return }
        await library.importFiles(picker.urls, folderID: currentFolder?.id)
    }

    private func pickBackup() async {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.laqtaBackup]
        guard await picker.begin() == .OK, let url = picker.url else { return }
        await library.restoreBackup(url)
    }

    private func handleDroppedURLs(_ urls: [URL]) async {
        guard accessAllowed && !isTrash else { return }
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { await library.importFiles(files, folderID: currentFolder?.id) }
        for url in urls where !url.isFileURL { _ = await library.addLink(url.absoluteString, folderID: currentFolder?.id) }
    }
}
