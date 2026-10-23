//
//  FoldersScreen.swift
//  لقطة
//
//  الشاشة الرئيسية: المجلدات + أحدث اللقطات.
//

import Foundation
import SwiftData
import SwiftUI

struct FoldersScreen: View {
    @Binding var path: [Route]

    @Environment(LibraryModel.self) private var library
    @Environment(LockManager.self) private var lock
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Folder.sortIndex), SortDescriptor(\Folder.createdAt)])
    private var folders: [Folder]

    @Query(FoldersScreen.recentDescriptor)
    private var recentShots: [Shot]

    @State private var showingNewFolder = false
    @State private var showingSettings = false
    @State private var showingReorder = false
    @State private var editingFolder: Folder? = nil
    @State private var folderPendingDeletion: Folder? = nil

    static var recentDescriptor: FetchDescriptor<Shot> {
        var descriptor = FetchDescriptor<Shot>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        descriptor.fetchLimit = 40
        return descriptor
    }

    private let columns = [GridItem(.adaptive(minimum: 158), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if recentShots.isEmpty {
                    OnboardingCard()
                } else {
                    recentSection
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("المجلدات")
                        .font(.title2.weight(.bold))

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(folders) { folder in
                            Button {
                                open(folder)
                            } label: {
                                FolderCard(folder: folder, isUnlocked: lock.isUnlocked(folder.id))
                                    .id(library.refreshToken)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                folderMenu(folder)
                            }
                        }

                        Button {
                            showingNewFolder = true
                        } label: {
                            AddFolderCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle("لقطة")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Label("الإعدادات", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingNewFolder = true
                    } label: {
                        Label("مجلد جديد", systemImage: "folder.badge.plus")
                    }
                    Button {
                        showingReorder = true
                    } label: {
                        Label("ترتيب المجلدات", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Label("إضافة", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewFolder) {
            FolderEditor(folder: nil)
        }
        .sheet(item: $editingFolder) { folder in
            FolderEditor(folder: folder)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsScreen()
        }
        .sheet(isPresented: $showingReorder) {
            ReorderFoldersSheet()
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("حذف المجلد ولقطاته", role: .destructive) {
                if let folder = folderPendingDeletion {
                    withAnimation {
                        library.delete(folder: folder, context: modelContext)
                    }
                }
                folderPendingDeletion = nil
            }
            Button("إلغاء", role: .cancel) {
                folderPendingDeletion = nil
            }
        } message: {
            Text("تُحذف النسخ المحفوظة داخل لقطة فقط، ولا يتأثر ألبوم الصور.")
        }
    }

    // MARK: Recent

    private var visibleRecent: [Shot] {
        let lockedIDs = Set(folders.filter { $0.isLocked && !lock.isUnlocked($0.id) }.map(\.id))
        return recentShots
            .filter { shot in
                guard let folderID = shot.folderID else { return false }
                return !lockedIDs.contains(folderID)
            }
            .prefix(16)
            .map { $0 }
    }

    @ViewBuilder
    private var recentSection: some View {
        let items = visibleRecent
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("أحدث اللقطات")
                    .font(.title2.weight(.bold))
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(items) { shot in
                            Button {
                                if let folderID = shot.folderID {
                                    path.append(.viewer(folderID: folderID, startID: shot.id))
                                }
                            } label: {
                                ShotThumbnail(shot: shot, cornerRadius: 18)
                                    .frame(width: 104, height: 150)
                                    .zoomSource(id: shot.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .padding(.horizontal, -16)
                .id(library.refreshToken)
            }
        }
    }

    // MARK: Actions

    @ViewBuilder
    private func folderMenu(_ folder: Folder) -> some View {
        Button {
            editingFolder = folder
        } label: {
            Label("تعديل", systemImage: "pencil")
        }
        if folder.isLocked, lock.isUnlocked(folder.id) {
            Button {
                lock.lock(folder.id)
            } label: {
                Label("قفل الآن", systemImage: "lock")
            }
        }
        Divider()
        Button(role: .destructive) {
            folderPendingDeletion = folder
        } label: {
            Label("حذف", systemImage: "trash")
        }
    }

    private var deletionTitle: String {
        guard let folder = folderPendingDeletion else { return "" }
        let count = LaqtaStore.shotCount(in: folder.id, context: modelContext)
        return count == 0 ? "حذف «\(folder.name)»؟" : "حذف «\(folder.name)» مع \(count) لقطة؟"
    }

    private func open(_ folder: Folder) {
        let folderID = folder.id
        if folder.isLocked {
            Task {
                if await lock.unlock(folderID) {
                    path.append(.folder(folderID))
                }
            }
        } else {
            path.append(.folder(folderID))
        }
    }
}

// MARK: - Cards

private struct AddFolderCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 30, weight: .semibold))
            Text("مجلد جديد")
                .font(.headline)
        }
        .foregroundStyle(LaqtaTheme.accent)
        .frame(maxWidth: .infinity)
        .frame(height: 188)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(LaqtaTheme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
        }
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct OnboardingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("ابدأ من قائمة المشاركة", systemImage: "square.and.arrow.up")
                .font(.headline)
                .foregroundStyle(LaqtaTheme.accent)
            VStack(alignment: .leading, spacing: 8) {
                step("١", "صوّر الشاشة أو افتح أي صورة في تطبيق الصور.")
                step("٢", "اضغط زر المشاركة واختر «لقطة».")
                step("٣", "اختر المجلد — تُحفظ نسخة خاصة هنا فورًا.")
            }
            Text("إن لم يظهر «لقطة» في القائمة: مرّر الأيقونات إلى آخرها واضغط «المزيد» ثم فعّله.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(LaqtaTheme.accent, in: Circle())
            Text(text)
                .font(.subheadline)
        }
    }
}

extension View {
    /// Marks the view as the origin of the zoom transition into the viewer.
    @ViewBuilder
    func zoomSource(id: UUID) -> some View {
        ZoomSourceModifierView(content: self, id: id)
    }
}

private struct ZoomSourceModifierView<Content: View>: View {
    let content: Content
    let id: UUID
    @Environment(\.zoomNamespace) private var namespace

    var body: some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}
