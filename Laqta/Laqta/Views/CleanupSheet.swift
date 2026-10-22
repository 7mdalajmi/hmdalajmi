//
//  CleanupSheet.swift
//  Laqta
//
//  Settings → Storage → Clean up old shots. Three piles, with what each one
//  would free, and one button. Nothing is ever deleted here: everything goes to
//  Recently Deleted, which holds it for thirty days.
//

import Foundation
import SwiftData
import SwiftUI

extension Shot {
    /// The shot as the cleanup rules see it — no model object, no context.
    var cleanupSubject: CleanupSubject {
        CleanupSubject(
            itemID: id,
            byteCount: byteCount,
            addedAt: addedAt,
            viewedAt: viewedAt,
            contentHash: contentHash,
            captureKey: captureKey,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            textLength: analysis?.text?.count ?? 0,
            wasAnalyzed: analysisData != nil,
            isFavorite: isFavorite,
            hasNote: !note.isEmpty,
            isPicture: kind.mediaKind != nil
        )
    }
}

struct CleanupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette
    @AppObject(LibraryModel.self) private var library
    @AppObject(ToastCenter.self) private var toasts

    @Query(filter: #Predicate<Shot> { $0.deletedAt == nil }) private var items: [Shot]

    @State private var chosen: Set<String> = []
    @State private var didLoad = false
    @State private var showingSimilar = false
    @State private var confirming = false

    private var subjects: [CleanupSubject] { items.map(\.cleanupSubject) }
    private var groups: [CleanupGroup] { CleanupScanner.scan(subjects) }

    private var picked: [CleanupGroup] { groups.filter { chosen.contains($0.pile.rawValue) } }
    private var pickedIDs: Set<UUID> { Set(picked.flatMap(\.itemIDs)) }
    private var pickedBytes: Int { picked.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(spacing: 0) {
            SheetBar("Clean Up") {
                Button {
                    dismiss()
                } label: {
                    BarTextButtonLabel(title: "Close")
                }
            } trailing: {
                EmptyView()
            }

            if groups.isEmpty {
                empty
            } else {
                content
            }
        }
        .background(palette.sheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(palette.sheet)
        .presentationCornerRadius(32)
        .sheet(isPresented: $showingSimilar) {
            SimilarShotsSheet()
                .laqtaThemed()
        }
        .confirmationDialog(
            "Move \(pickedIDs.count) to Recently Deleted?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Move to Recently Deleted") { moveToTrash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They stay there for thirty days, and you can bring any of them back.")
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            chosen = Set(groups.filter(\.pile.isOnByDefault).map(\.pile.rawValue))
        }
    }

    // MARK: Pieces

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .laqtaIconFont(34)
                .foregroundStyle(palette.goldHi)
            Text("Nothing to let go of")
                .laqtaDisplayFont(26, bold: true)
                .foregroundStyle(palette.ink)
            Text("Laqta found no forgotten shots, no copies and nothing unreadable.")
                .laqtaFont(13)
                .foregroundStyle(palette.ink2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Three piles Laqta is fairly sure you do not need.")
                        .laqtaFont(13)
                        .foregroundStyle(palette.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 10) {
                        ForEach(groups) { group in
                            pileRow(group)
                        }
                    }

                    if groups.contains(where: { $0.pile == .duplicates }) {
                        Button {
                            showingSimilar = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.stack")
                                Text("Look at the copies first")
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .laqtaIconFont(12, weight: .semibold)
                            }
                            .laqtaFont(14, weight: .semibold)
                            .foregroundStyle(palette.goldHi)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .frame(maxWidth: .infinity)
                            .background(palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
                        }
                        .buttonStyle(.pressable)
                    }

                    Text("Favourites and anything you wrote a note on are never proposed.")
                        .laqtaFont(12)
                        .foregroundStyle(palette.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }

            VStack(spacing: 10) {
                Button {
                    confirming = true
                } label: {
                    Text(verbatim: buttonTitle)
                        .laqtaFont(16, weight: .semibold)
                        .foregroundStyle(palette.goldInk)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.accentFill, in: Capsule())
                        .opacity(pickedIDs.isEmpty ? 0.45 : 1)
                }
                .buttonStyle(.pressable)
                .disabled(pickedIDs.isEmpty)
                Text("Nothing is deleted. Recently Deleted holds them for thirty days.")
                    .laqtaFont(11.5)
                    .foregroundStyle(palette.ink3)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .background(palette.sheet)
        }
    }

    private var buttonTitle: String {
        guard !pickedIDs.isEmpty else { return String(localized: "Pick a pile") }
        let count = LaqtaFormat.count(pickedIDs.count, "shot", "shots")
        return "Move \(count) · \(LaqtaFormat.bytes(Int64(pickedBytes)))"
    }

    private func pileRow(_ group: CleanupGroup) -> some View {
        let isOn = chosen.contains(group.pile.rawValue)
        return Button {
            if isOn { chosen.remove(group.pile.rawValue) } else { chosen.insert(group.pile.rawValue) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .laqtaIconFont(20)
                    .foregroundStyle(isOn ? palette.goldHi : palette.ink3)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: group.pile.title)
                            .laqtaFont(15, weight: .semibold)
                            .foregroundStyle(palette.ink)
                        Spacer(minLength: 0)
                        Text(verbatim: "\(LaqtaFormat.count(group.count, "shot", "shots")) · \(LaqtaFormat.bytes(Int64(group.bytes)))")
                            .laqtaFont(12, weight: .semibold)
                            .foregroundStyle(palette.goldHi)
                            .layoutPriority(1)
                    }
                    Text(verbatim: group.pile.detail)
                        .laqtaFont(12)
                        .foregroundStyle(palette.ink3)
                        .adaptiveLineLimit(2, accessibility: 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isOn ? palette.hair : palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }

    private func moveToTrash() {
        let ids = pickedIDs
        let targets = items.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        library.trash(targets, context: modelContext)
        toasts.show(
            String(localized: "\(LaqtaFormat.count(targets.count, "shot", "shots")) moved to Recently Deleted"),
            systemImage: "trash"
        )
        dismiss()
    }
}

// MARK: - The same thing, more than once

struct SimilarShotsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette
    @AppObject(LibraryModel.self) private var library
    @AppObject(ToastCenter.self) private var toasts

    @Query(filter: #Predicate<Shot> { $0.deletedAt == nil }) private var items: [Shot]

    private var families: [SimilarGroup] {
        CleanupScanner.similar(in: items.map(\.cleanupSubject))
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetBar("Copies") {
                Button {
                    dismiss()
                } label: {
                    BarTextButtonLabel(title: "Close")
                }
            } trailing: {
                EmptyView()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Laqta compared these on the phone. The one it would keep is the one it can still read.")
                        .laqtaFont(13)
                        .foregroundStyle(palette.ink2)
                    ForEach(families) { family in
                        familyCard(family)
                    }
                    if families.isEmpty {
                        Text("No copies left.")
                            .laqtaFont(14)
                            .foregroundStyle(palette.ink3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .background(palette.sheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(palette.sheet)
        .presentationCornerRadius(32)
    }

    private func familyCard(_ family: SimilarGroup) -> some View {
        let shots = ([family.keep] + family.others).compactMap { id in items.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(verbatim: LaqtaFormat.count(family.count, "copy", "copies"))
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(shots) { shot in
                        VStack(spacing: 6) {
                            ShotThumbnail(shot: shot, cornerRadius: 14)
                                .frame(width: 84, height: 104)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(
                                            shot.id == family.keep ? palette.goldHi : palette.line,
                                            lineWidth: shot.id == family.keep ? 1.6 : 1
                                        )
                                )
                                .opacity(shot.id == family.keep ? 1 : 0.45)
                            Text(shot.id == family.keep ? "Keeps" : "Goes")
                                .laqtaFont(11, weight: .semibold)
                                .foregroundStyle(shot.id == family.keep ? palette.goldHi : palette.ink3)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            Button {
                drop(family)
            } label: {
                Text("Keep the best · let \(LaqtaFormat.count(family.others.count, "copy", "copies")) go")
                    .laqtaFont(14, weight: .semibold)
                    .foregroundStyle(palette.goldHi)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(Capsule().strokeBorder(palette.hair, lineWidth: 1))
            }
            .buttonStyle(.pressable)
        }
        .padding(14)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
    }

    private func drop(_ family: SimilarGroup) {
        let targets = items.filter { family.others.contains($0.id) }
        guard !targets.isEmpty else { return }
        library.trash(targets, context: modelContext)
        toasts.show(
            String(localized: "\(LaqtaFormat.count(targets.count, "copy", "copies")) moved to Recently Deleted"),
            systemImage: "trash"
        )
    }
}
