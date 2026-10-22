//
//  ReorderFoldersSheet.swift
//  لقطة
//

import Foundation
import SwiftData
import SwiftUI

struct ReorderFoldersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Folder.sortIndex), SortDescriptor(\Folder.createdAt)])
    private var folders: [Folder]

    var body: some View {
        NavigationStack {
            List {
                ForEach(folders) { folder in
                    FolderRow(folder: folder)
                }
                .onMove(perform: move)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("ترتيب المجلدات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = folders
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, folder) in ordered.enumerated() {
            folder.sortIndex = index
        }
        try? modelContext.save()
    }
}
