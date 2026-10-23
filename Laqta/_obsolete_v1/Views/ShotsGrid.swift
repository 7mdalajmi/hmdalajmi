//
//  ShotsGrid.swift
//  لقطة
//

import Foundation
import SwiftData
import SwiftUI

struct ShotsGrid: View {
    let isSelecting: Bool
    @Binding var selection: Set<UUID>
    var onOpen: (Shot) -> Void

    @Environment(LibraryModel.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Query private var shots: [Shot]
    @State private var movingShotID: UUID? = nil
    @State private var shotPendingDeletion: Shot? = nil

    init(
        folderID: UUID,
        newestFirst: Bool,
        isSelecting: Bool,
        selection: Binding<Set<UUID>>,
        onOpen: @escaping (Shot) -> Void
    ) {
        self.isSelecting = isSelecting
        self._selection = selection
        self.onOpen = onOpen
        let target: UUID? = folderID
        _shots = Query(
            filter: #Predicate<Shot> { $0.folderID == target },
            sort: \Shot.addedAt,
            order: newestFirst ? .reverse : .forward
        )
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 3)]

    var body: some View {
        if shots.isEmpty {
            ContentUnavailableView {
                Label("لا توجد لقطات بعد", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("شارك صورة من تطبيق الصور واختر «لقطة»، أو اضغط + للإضافة من ألبوم الصور.")
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(shots) { shot in
                        cell(for: shot)
                    }
                }
                .padding(.horizontal, 3)

                Text(countFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            }
            .sheet(item: Binding(
                get: { movingShotID.map(MoveRequest.init(id:)) },
                set: { movingShotID = $0?.id }
            )) { request in
                MoveToFolderSheet(shotIDs: [request.id], currentFolderID: nil)
            }
            .confirmationDialog(
                "حذف اللقطة؟",
                isPresented: Binding(
                    get: { shotPendingDeletion != nil },
                    set: { if !$0 { shotPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("حذف", role: .destructive) {
                    if let shot = shotPendingDeletion {
                        withAnimation { library.delete([shot], context: modelContext) }
                    }
                    shotPendingDeletion = nil
                }
            } message: {
                Text("تُحذف من لقطة فقط، ولا يتأثر ألبوم الصور.")
            }
        }
    }

    private var countFooter: String {
        switch shots.count {
        case 1: "لقطة واحدة"
        case 2: "لقطتان"
        case 3...10: "\(shots.count) لقطات"
        default: "\(shots.count) لقطة"
        }
    }

    @ViewBuilder
    private func cell(for shot: Shot) -> some View {
        let isSelected = selection.contains(shot.id)
        Button {
            if isSelecting {
                if isSelected {
                    selection.remove(shot.id)
                } else {
                    selection.insert(shot.id)
                }
            } else {
                onOpen(shot)
            }
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ShotThumbnail(shot: shot)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if shot.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, isSelected ? LaqtaTheme.accent : .black.opacity(0.25))
                            .padding(6)
                    }
                }
                .overlay {
                    if isSelecting, isSelected {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.white.opacity(0.18))
                    }
                }
                .zoomSource(id: shot.id)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(shot.isScreenshot ? "لقطة شاشة" : "صورة"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            ShareLink(item: shot.fileURL) {
                Label("مشاركة", systemImage: "square.and.arrow.up")
            }
            Button {
                library.toggleFavorite(shot, context: modelContext)
            } label: {
                Label(shot.isFavorite ? "إزالة من المفضلة" : "مفضلة", systemImage: shot.isFavorite ? "heart.slash" : "heart")
            }
            Button {
                movingShotID = shot.id
            } label: {
                Label("نقل إلى مجلد", systemImage: "folder")
            }
            Divider()
            Button(role: .destructive) {
                shotPendingDeletion = shot
            } label: {
                Label("حذف", systemImage: "trash")
            }
        } preview: {
            ShotThumbnail(shot: shot)
                .frame(width: 280, height: 380)
        }
    }
}

private nonisolated struct MoveRequest: Identifiable, Sendable {
    let id: UUID
}
