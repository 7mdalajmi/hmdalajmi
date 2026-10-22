//
//  MergeFoldersSheet.swift
//  Laqta
//
//  When sync brings a folder whose name is already in use, Home shows a card and this
//  sheet decides each one: put them together, or keep them apart for good.
//

import Foundation
import SwiftData
import SwiftUI

/// Sits above the folder list until the offer is answered.
struct MergeFoldersCard: View {
    let pairs: [FolderMergePair]
    let onReview: () -> Void
    let onKeepBoth: () -> Void

    @Environment(\.laqta) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.merge")
                    .laqtaIconFont(15, weight: .semibold)
                    .foregroundStyle(palette.goldHi)
                    .frame(width: 32, height: 32)
                    .background(palette.accentFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(palette.gold.opacity(0.4), lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title)
                        .laqtaFont(15, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Merging keeps everything in one folder. Nothing is deleted either way.")
                        .laqtaFont(12.5)
                        .foregroundStyle(palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            AdaptiveButtonRow {
                Button(action: onReview) {
                    LaqtaButtonLabel("Review", kind: .gold, small: true)
                }
                .buttonStyle(.pressable)
                Button(action: onKeepBoth) {
                    LaqtaButtonLabel("Keep Both", kind: .line, small: true)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.gold.opacity(0.45), lineWidth: 1)
        )
    }

    private var title: String {
        guard let first = pairs.first else { return "" }
        return pairs.count == 1
            ? "“\(first.name)” arrived twice"
            : String(localized: "\(LaqtaFormat.count(pairs.count, "folder name", "folder names")) arrived twice")
    }
}

struct MergeFoldersSheet: View {
    let pairs: [FolderMergePair]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette
    @AppObject(LibraryModel.self) private var library
    @AppObject(ToastCenter.self) private var toasts

    @State private var answered: Set<String> = []

    private var remaining: [FolderMergePair] {
        pairs.filter { !answered.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetBar("Same Name, Twice") {
                Button {
                    dismiss()
                } label: {
                    BarTextButtonLabel(title: "Done")
                }
            } trailing: {
                EmptyView()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("These folders share a name with folders already here. Deciding is up to you — a folder you keep apart won't be asked about again.")
                        .laqtaFont(13)
                        .foregroundStyle(palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(remaining) { pair in
                        row(pair)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .background(LaqtaBackground())
        .onChange(of: remaining.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }

    @ViewBuilder
    private func row(_ pair: FolderMergePair) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FolderNameText(name: pair.name, size: 22, maxScale: 1.4)

            HStack(alignment: .top, spacing: 12) {
                side("Here", count: pair.keepCount, since: pair.keepCreatedAt)
                Image(systemName: "plus")
                    .laqtaIconFont(12, weight: .semibold)
                    .foregroundStyle(palette.ink3)
                    .padding(.top, 14)
                side("From sync", count: pair.mergeCount, since: pair.mergeCreatedAt)
            }

            AdaptiveButtonRow {
                Button {
                    merge(pair)
                } label: {
                    LaqtaButtonLabel("Merge · \(LaqtaFormat.count(pair.total, "item", "items"))", kind: .gold, small: true)
                }
                .buttonStyle(.pressable)
                Button {
                    keepBoth(pair)
                } label: {
                    LaqtaButtonLabel("Keep Both", kind: .line, small: true)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.cardBorder, lineWidth: 1)
        )
    }

    private func side(_ label: LocalizedStringKey, count: Int, since: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .textCase(.uppercase)
                .laqtaFont(11, weight: .semibold)
                .tracking(0.8)
                .foregroundStyle(palette.gold)
                .adaptiveLineLimit(1, accessibility: 2)
            Text(verbatim: LaqtaFormat.count(count, "item", "items"))
                .laqtaFont(14, weight: .semibold, monospacedDigit: true)
                .foregroundStyle(palette.ink)
            Text("Since \(LaqtaFormat.shortDate(since))")
                .laqtaFont(11.5)
                .foregroundStyle(palette.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func merge(_ pair: FolderMergePair) {
        withAnimation {
            FolderMerge.merge(pair, context: modelContext)
            answered.insert(pair.id)
        }
        library.refresh()
        library.highlight(pair.keepID)
        toasts.show(String(localized: "“\(pair.name)” now holds \(LaqtaFormat.count(pair.total, "item", "items"))"), systemImage: "arrow.triangle.merge")
    }

    private func keepBoth(_ pair: FolderMergePair) {
        FolderMerge.decline(pair)
        withAnimation {
            _ = answered.insert(pair.id)
        }
    }
}
