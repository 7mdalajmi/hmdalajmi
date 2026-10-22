//
//  MoveToFolderSheet.swift
//  Laqta
//

import Foundation
import SwiftData
import SwiftUI

struct MoveToFolderSheet: View {
    let itemIDs: [UUID]
    let currentFolderID: UUID?
    var onMoved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppObject(LibraryModel.self) private var library
    @AppObject(LockManager.self) private var lock
    @Environment(\.laqta) private var palette
    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }) private var folders: [Folder]

    @State private var stats: [UUID: FolderStats] = [:]
    @State private var showingNewFolder = false

    /// Folders in tree order: each one followed by what sits inside it.
    private var sortedFolders: [(folder: Folder, depth: Int)] {
        var byParent: [UUID?: [Folder]] = [:]
        for folder in folders {
            byParent[folder.parentID, default: []].append(folder)
        }
        for key in byParent.keys {
            byParent[key]?.sort { $0.lastUpdate > $1.lastUpdate }
        }
        var result: [(Folder, Int)] = []
        var seen: Set<UUID> = []
        func walk(_ parent: UUID?, _ depth: Int) {
            for folder in byParent[parent] ?? [] where seen.insert(folder.id).inserted {
                result.append((folder, depth))
                walk(folder.id, depth + 1)
            }
        }
        walk(nil, 0)
        // Anything whose parent is missing still has to be reachable.
        for folder in folders where !seen.contains(folder.id) {
            result.append((folder, 0))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetBar(itemIDs.count == 1 ? "Move to Folder" : "Move \(itemIDs.count) Items") {
                Button {
                    dismiss()
                } label: {
                    BarTextButtonLabel(title: "Cancel")
                }
            } trailing: {
                Button {
                    showingNewFolder = true
                } label: {
                    CircleIcon(systemImage: "folder.badge.plus")
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("New Folder"))
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedFolders, id: \.folder.id) { entry in
                        let folder = entry.folder
                        Button {
                            move(to: folder)
                        } label: {
                            HStack {
                                SaveFolderRow(folder: folder, stats: lock.canShow(folder) ? stats[folder.id] : nil, showsChevron: folder.id != currentFolderID)
                                if folder.id == currentFolderID {
                                    Image(systemName: "checkmark")
                                        .laqtaIconFont(14, weight: .semibold)
                                        .foregroundStyle(palette.goldHi)
                                }
                            }
                            // A folder inside another one steps in, so the two never look alike.
                            .padding(.leading, CGFloat(min(entry.depth, 3)) * 18)
                        }
                        .buttonStyle(.pressable)
                        .disabled(folder.id == currentFolderID)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(palette.sheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.sheet)
        .presentationCornerRadius(32)
        .task {
            stats = FolderStatsLoader.stats(for: folders, context: modelContext)
        }
        .sheet(isPresented: $showingNewFolder) {
            FolderEditorSheet(folder: nil) { created in
                move(to: created)
            }
            .laqtaThemed()
        }
    }

    private func move(to folder: Folder) {
        let ids = itemIDs
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { ids.contains($0.id) })
        let items = (try? modelContext.fetch(descriptor)) ?? []
        library.move(items, to: folder, context: modelContext)
        onMoved()
        dismiss()
    }
}
