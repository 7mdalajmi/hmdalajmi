//
//  RecentlyDeletedScreen.swift
//  Laqta
//
//  Recently Deleted: folders and items kept for 30 days, with Recover and Delete.
//

import Foundation
import SwiftData
import SwiftUI

struct RecentlyDeletedScreen: View {
    @Binding var path: [Route]

    @AppObject(LibraryModel.self) private var library
    @AppObject(LockManager.self) private var lock
    @AppObject(ToastCenter.self) private var toasts
    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Query(
        filter: #Predicate<Shot> { $0.deletedAt != nil },
        sort: \Shot.deletedAt,
        order: .reverse
    ) private var items: [Shot]
    @Query(filter: #Predicate<Folder> { $0.deletedAt != nil }) private var deletedFolders: [Folder]
    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }) private var liveFolders: [Folder]

    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var previewItem: Shot?
    @State private var pendingAction: PendingAction?
    @State private var isUnlocked = false

    enum PendingAction: Identifiable {
        case deleteSelection
        case deleteAll
        case deleteFolder(Folder)
        case deleteItem(Shot)

        var id: String {
            switch self {
            case .deleteSelection: "selection"
            case .deleteAll: "all"
            case let .deleteFolder(folder): "folder-\(folder.id)"
            case let .deleteItem(item): "item-\(item.id)"
            }
        }
    }

    private var needsUnlock: Bool {
        guard lock.locksEnabled, !lock.trashUnlocked else { return false }
        let lockedIDs = Set((liveFolders + deletedFolders).filter(\.isPrivate).map(\.id))
        return items.contains { $0.folderID.map(lockedIDs.contains) ?? false }
    }

    private var columns: [GridItem] {
        let minimum: CGFloat = sizeClass == .regular ? 150 : 100
        return [GridItem(.adaptive(minimum: minimum), spacing: 4)]
    }

    /// Items shown one by one: those whose folder isn't itself waiting in Recently Deleted.
    private var looseItems: [Shot] {
        let batches = Dictionary(deletedFolders.compactMap { folder in folder.deletionBatch.map { (folder.id, $0) } }, uniquingKeysWith: { first, _ in first })
        return items.filter { item in
            guard let folderID = item.folderID, let batch = batches[folderID] else { return true }
            return item.deletionBatch != batch
        }
    }

    var body: some View {
        Group {
            if needsUnlock {
                lockedView
            } else {
                content
            }
        }
        .background(LaqtaBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .onChange(of: isSelecting) { _, selecting in
            if !selecting { selection.removeAll() }
        }
        .sheet(item: $previewItem) { item in
            TrashPreviewSheet(item: item, folderName: folderName(for: item)) {
                recover([item])
            } onDelete: {
                pendingAction = .deleteItem(item)
            }
            .laqtaThemed()
        }
        // Deleting one item or folder; "Delete All" and the selection are confirmed at their buttons.
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(get: { isSingleDeletion }, set: { if !$0, isSingleDeletion { pendingAction = nil } }),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(deleteButtonTitle(action), role: .destructive) {
                perform(action)
            }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 8)
                    .padding(.horizontal, 16)

                if items.isEmpty, deletedFolders.isEmpty {
                    emptyState
                        .padding(.top, 60)
                } else {
                    if !deletedFolders.isEmpty {
                        SectionLabel("Folders")
                            .padding(.horizontal, 16)
                            .padding(.top, 26)
                            .padding(.bottom, 8)
                        VStack(spacing: 10) {
                            ForEach(deletedFolders.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }) { folder in
                                DeletedFolderRow(
                                    folder: folder,
                                    count: items.filter { $0.folderID == folder.id && $0.deletionBatch == folder.deletionBatch }.count
                                ) {
                                    recover(folder)
                                } onDelete: {
                                    pendingAction = .deleteFolder(folder)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    if !looseItems.isEmpty {
                        SectionLabel(deletedFolders.isEmpty ? "Items" : "Other items")
                            .padding(.horizontal, 16)
                            .padding(.top, 26)
                            .padding(.bottom, 10)
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(looseItems) { item in
                                cell(item)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionBar
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recently Deleted")
                .laqtaDisplayFont(40)
                .foregroundStyle(palette.goldHi)
                .accessibilityAddTraits(.isHeader)
            Text("Items stay here for 30 days, then they're deleted for good. Your Photos library isn't touched.")
                .laqtaFont(14)
                .foregroundStyle(palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "trash")
                .laqtaIconFont(30, weight: .light)
                .foregroundStyle(palette.gold)
            Text("Nothing here")
                .laqtaFont(17, weight: .semibold)
                .foregroundStyle(palette.ink)
            Text("Deleted folders and items wait here before they're gone.")
                .laqtaFont(14)
                .foregroundStyle(palette.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    private var lockedView: some View {
        VStack(spacing: 16) {
            FolderBadge(symbol: "lock", halo: true)
            Text("Recently Deleted")
                .laqtaDisplayFont(34)
                .foregroundStyle(palette.goldHi)
            Text("It holds items from private folders.")
                .laqtaFont(14)
                .foregroundStyle(palette.ink2)
            Button {
                Task { _ = await lock.unlockTrash() }
            } label: {
                LaqtaButtonLabel("Unlock", systemImage: "faceid")
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            _ = await lock.unlockTrash()
        }
    }

    @ViewBuilder
    private func cell(_ item: Shot) -> some View {
        let isSelected = selection.contains(item.id)
        Button {
            if isSelecting {
                if isSelected { selection.remove(item.id) } else { selection.insert(item.id) }
            } else {
                previewItem = item
            }
        } label: {
            FolderItemCell(item: item, isSelecting: isSelecting, isSelected: isSelected, height: sizeClass == .regular ? 190 : 140, showsBadges: false)
                // PDFs and links show their title at the bottom, so their badge sits at the top.
                .overlay(alignment: item.isViewerMedia ? .bottomLeading : .topLeading) {
                    DaysLeftBadge(deletedAt: item.deletedAt)
                        .padding(6)
                }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(verbatim: "\(item.kindLabel), \(item.displayTitle), \(DaysLeftBadge.text(for: item.deletedAt))"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button {
                recover([item])
            } label: {
                Label("Recover", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                pendingAction = .deleteItem(item)
            } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
        }
    }

    private var selectionBar: some View {
        AdaptiveButtonRow(spacing: 10) {
            Button {
                recover(items.filter { selection.contains($0.id) })
                isSelecting = false
            } label: {
                LaqtaButtonLabel(verbatim: selection.isEmpty ? "Recover" : "Recover \(selection.count)", systemImage: "arrow.uturn.backward", kind: .line, fullWidth: true)
            }
            .disabled(selection.isEmpty)
            Button {
                pendingAction = .deleteSelection
            } label: {
                LaqtaButtonLabel(verbatim: selection.isEmpty ? "Delete" : "Delete \(selection.count)", systemImage: "trash", fullWidth: true)
            }
            .disabled(selection.isEmpty)
            .confirmationDialog(dialogTitle, isPresented: confirming(.deleteSelection), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { perform(.deleteSelection) }
            } message: {
                Text("This can't be undone.")
            }
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !(items.isEmpty && deletedFolders.isEmpty), !needsUnlock {
            ToolbarItem(placement: .topBarTrailing) {
                if isSelecting {
                    Button("Done") { isSelecting = false }
                        .fontWeight(.semibold)
                } else {
                    Menu {
                        Button {
                            isSelecting = true
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                        Button {
                            recoverAll()
                        } label: {
                            Label("Recover All", systemImage: "arrow.uturn.backward")
                        }
                        Divider()
                        Button(role: .destructive) {
                            pendingAction = .deleteAll
                        } label: {
                            Label("Delete All", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                    .confirmationDialog(dialogTitle, isPresented: confirming(.deleteAll), titleVisibility: .visible) {
                        Button("Delete All", role: .destructive) { perform(.deleteAll) }
                    } message: {
                        Text("This can't be undone.")
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func folderName(for item: Shot) -> String? {
        guard let folderID = item.folderID else { return nil }
        return (liveFolders + deletedFolders).first { $0.id == folderID }?.name
    }

    private func recover(_ items: [Shot]) {
        guard !items.isEmpty else { return }
        withAnimation {
            library.restore(items, context: modelContext)
        }
        toasts.show(items.count == 1 ? "Recovered" : "\(items.count) items recovered", systemImage: "arrow.uturn.backward")
    }

    private func recover(_ folder: Folder) {
        withAnimation {
            library.restore(folder: folder, context: modelContext)
        }
        toasts.show("“\(folder.name)” recovered", systemImage: "arrow.uturn.backward")
    }

    private func recoverAll() {
        withAnimation {
            for folder in deletedFolders {
                library.restore(folder: folder, context: modelContext)
            }
            library.restore(items.filter { $0.deletedAt != nil }, context: modelContext)
        }
        toasts.show("Everything was recovered", systemImage: "arrow.uturn.backward")
    }

    private var isSingleDeletion: Bool {
        switch pendingAction {
        case .deleteItem?, .deleteFolder?: true
        default: false
        }
    }

    /// Presents the confirmation for `action` next to the control that asked for it.
    private func confirming(_ action: PendingAction) -> Binding<Bool> {
        Binding(
            get: { pendingAction?.id == action.id },
            set: { if !$0, pendingAction?.id == action.id { pendingAction = nil } }
        )
    }

    private var dialogTitle: String {
        switch pendingAction {
        case .deleteSelection?:
            selection.count == 1 ? "Delete this item for good?" : "Delete \(selection.count) items for good?"
        case .deleteAll?:
            "Delete everything in Recently Deleted?"
        case let .deleteFolder(folder)?:
            "Delete “\(folder.name)” for good?"
        case .deleteItem?:
            "Delete this item for good?"
        case nil:
            ""
        }
    }

    private func deleteButtonTitle(_ action: PendingAction) -> String {
        switch action {
        case .deleteAll: "Delete All"
        default: "Delete"
        }
    }

    private func perform(_ action: PendingAction) {
        withAnimation {
            switch action {
            case .deleteSelection:
                library.deletePermanently(items.filter { selection.contains($0.id) }, context: modelContext)
                isSelecting = false
            case .deleteAll:
                library.emptyTrash(context: modelContext)
                isSelecting = false
            case let .deleteFolder(folder):
                library.deletePermanently(folder: folder, context: modelContext)
            case let .deleteItem(item):
                if previewItem?.id == item.id { previewItem = nil }
                library.deletePermanently([item], context: modelContext)
            }
        }
        pendingAction = nil
    }
}

// MARK: - Pieces

struct DaysLeftBadge: View {
    let deletedAt: Date?

    static func daysLeft(for deletedAt: Date?, now: Date = .now) -> Int {
        guard let deletedAt else { return 30 }
        let remaining = LibraryModel.trashRetention - now.timeIntervalSince(deletedAt)
        return max(0, Int((remaining / 86_400).rounded(.up)))
    }

    static func text(for deletedAt: Date?) -> String {
        let days = daysLeft(for: deletedAt)
        return days <= 1
            ? String(localized: "Deleted tomorrow")
            : String(localized: "\(days) days left")
    }

    var body: some View {
        let days = Self.daysLeft(for: deletedAt)
        Text(days <= 1 ? "1 day" : "\(days) days")
            .laqtaFont(10.5, weight: .semibold, monospacedDigit: true, maxScale: 1.25)
            .foregroundStyle(days <= 3 ? Color(hex: 0xFFB4A2) : .white)
            .padding(.horizontal, 7)
            .frame(minHeight: 20)
            .background(Color(hex: 0x0A0908, alpha: 0.62), in: Capsule())
            .accessibilityHidden(true)
    }
}

private struct DeletedFolderRow: View {
    let folder: Folder
    let count: Int
    let onRecover: () -> Void
    let onDelete: () -> Void

    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(spacing: 14) {
            FolderThumb(folder: folder, cover: nil, size: 50)
            VStack(alignment: .leading, spacing: 2) {
                FolderNameText(name: folder.name, size: 22)
                Text(verbatim: "\(LaqtaFormat.count(count, "item", "items")) · \(DaysLeftBadge.text(for: folder.deletedAt))")
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
            }
            Spacer(minLength: 8)
            Menu {
                Button(action: onRecover) {
                    Label("Recover", systemImage: "arrow.uturn.backward")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Permanently", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .laqtaIconFont(15, weight: .semibold)
                    .foregroundStyle(palette.goldHi)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .accessibilityLabel(Text("Actions for \(folder.name)"))
            Button(action: onRecover) {
                LaqtaButtonLabel("Recover", small: true)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 74)
        .background(palette.sheet2.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

private struct TrashPreviewSheet: View {
    let item: Shot
    let folderName: String?
    let onRecover: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.laqta) private var palette

    var body: some View {
        VStack(spacing: 0) {
            SheetBar("Recently Deleted") {
                Button {
                    dismiss()
                } label: {
                    BarTextButtonLabel(title: "Close")
                }
            } trailing: {
                EmptyView()
            }
            ScrollView {
                VStack(spacing: 18) {
                    FolderItemCell(item: item, height: 300, showsBadges: false)
                        .frame(maxWidth: 420)
                    VStack(spacing: 6) {
                        Text(verbatim: item.displayTitle)
                            .laqtaFont(18, weight: .semibold)
                            .foregroundStyle(palette.ink)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 4) {
                            Text(verbatim: item.kindLabel)
                            if let folderName {
                                Text(verbatim: "· from")
                                FolderNameText(name: folderName, size: 15, color: palette.goldHi)
                            }
                        }
                        .laqtaFont(13)
                        .foregroundStyle(palette.ink2)
                        Text("Deleted \(LaqtaFormat.relative(item.deletedAt ?? .now)) · \(DaysLeftBadge.text(for: item.deletedAt))")
                            .laqtaFont(13)
                            .foregroundStyle(palette.ink2)
                    }
                    AdaptiveButtonRow(spacing: 10) {
                        Button {
                            onRecover()
                            dismiss()
                        } label: {
                            LaqtaButtonLabel("Recover", systemImage: "arrow.uturn.backward", fullWidth: true)
                        }
                        Button {
                            dismiss()
                            onDelete()
                        } label: {
                            LaqtaButtonLabel("Delete", systemImage: "trash", kind: .line, fullWidth: true)
                        }
                    }
                    .buttonStyle(.pressable)
                    .frame(maxWidth: 420)
                }
                .padding(20)
            }
        }
        .background(palette.sheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.sheet)
        .presentationCornerRadius(32)
    }
}
