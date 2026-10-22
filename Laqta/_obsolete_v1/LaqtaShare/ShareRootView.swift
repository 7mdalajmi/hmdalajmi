//
//  ShareRootView.swift
//  لقطة — Share Extension
//
//  واجهة المشاركة: معاينة الصور + شبكة المجلدات. لمسة واحدة على المجلد تحفظ الصورة فيه.
//

import Foundation
import SwiftData
import SwiftUI

struct ShareRootView: View {
    let session: ShareSessionModel

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Folder.sortIndex), SortDescriptor(\Folder.createdAt)])
    private var folders: [Folder]
    @State private var showingNewFolder = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SharePreviewStrip(session: session)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("اختر المجلد")
                            .font(.title3.weight(.bold))

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(folders) { folder in
                                Button {
                                    choose(folder)
                                } label: {
                                    ShareFolderTile(folder: folder, isQueued: session.queuedFolderID == folder.id)
                                }
                                .buttonStyle(.plain)
                                .disabled(session.isBusy)
                            }

                            Button {
                                showingNewFolder = true
                            } label: {
                                NewFolderTile()
                            }
                            .buttonStyle(.plain)
                            .disabled(session.isBusy)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("حفظ في لقطة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { session.cancel() }
                        .disabled(session.isBusy)
                }
            }
            .overlay {
                ShareStatusOverlay(session: session)
            }
            .sheet(isPresented: $showingNewFolder) {
                FolderEditor(folder: nil) { created in
                    choose(created)
                }
            }
        }
        .task {
            await session.prepare(context: modelContext)
        }
        .sensoryFeedback(.success, trigger: session.phase) { _, newValue in
            if case .done = newValue { return true }
            return false
        }
    }

    private func choose(_ folder: Folder) {
        Task {
            await session.choose(folder, context: modelContext)
        }
    }
}

// MARK: - Pieces

private struct SharePreviewStrip: View {
    let session: ShareSessionModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                let items = Array(session.staged.prefix(3).enumerated())
                if items.isEmpty {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 72, height: 96)
                        .overlay { ProgressView() }
                } else {
                    ForEach(items, id: \.element.id) { index, item in
                        PreviewCard(image: session.previews[item.id])
                            .rotationEffect(.degrees(Double(index) * 6 - 6))
                            .offset(x: CGFloat(index) * 6)
                            .zIndex(Double(-index))
                    }
                }
            }
            .frame(width: 96, height: 110)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.headline)
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var titleText: String {
        let count = max(session.incomingCount, session.staged.count)
        return count == 1 ? "صورة واحدة" : "\(count) صور"
    }

    private var subtitleText: String {
        switch session.phase {
        case .preparing: "جارٍ التجهيز…"
        default: "تُحفظ نسخة خاصة داخل لقطة"
        }
    }
}

private struct PreviewCard: View {
    let image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.quaternary)
            .frame(width: 72, height: 96)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}

private struct ShareFolderTile: View {
    let folder: Folder
    let isQueued: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                FolderIcon(symbol: folder.symbol, colorKey: folder.colorKey, size: 42)
                Spacer(minLength: 0)
                if isQueued {
                    ProgressView()
                } else if folder.isLocked, folder.symbol != "lock.fill" {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(folder.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            if isQueued {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(FolderPalette.color(for: folder.colorKey), lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("حفظ في \(folder.name)"))
    }
}

private struct NewFolderTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(LaqtaTheme.accent)
                .frame(width: 42, height: 42)
                .background(LaqtaTheme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12.6, style: .continuous))
            Text("مجلد جديد")
                .font(.headline)
                .foregroundStyle(LaqtaTheme.accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LaqtaTheme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
