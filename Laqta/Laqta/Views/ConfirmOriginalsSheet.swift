//
//  ConfirmOriginalsSheet.swift
//  Laqta
//
//  "Is this the one?" — before a photo leaves Photos on a guess.
//
//  An item saved from inside Laqta carries the asset's own identifier, and its
//  original is deleted without this sheet. An item shared from another app carries
//  nothing: Laqta works the original out from the file name, the pixel size and the
//  capture time, which is right nearly always and wrong often enough to matter. This
//  is where "nearly always" stops being good enough: the two photos sit next to each
//  other, and the user says.
//

import Photos
import SwiftData
import SwiftUI
import UIKit

struct ConfirmOriginalsSheet: View {
    @AppObject(LibraryModel.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            palette.sheet.ignoresSafeArea()
            VStack(spacing: 0) {
                SheetBar("Is this the original?") {
                    Button { dismiss() } label: {
                        BarTextButtonLabel(title: "Close")
                    }
                    .buttonStyle(.pressable)
                } trailing: {
                    Color.clear.frame(width: 1, height: 1)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("These were shared from another app, so Laqta had to work out which photo in Photos they came from. Nothing is deleted until you say it is the same one.")
                            .laqtaFont(13.5)
                            .foregroundStyle(palette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(library.originalsToConfirm) { candidate in
                            CandidateCard(candidate: candidate)
                        }
                        if library.originalsToConfirm.isEmpty {
                            Text("Nothing left to check.")
                                .laqtaFont(15)
                                .foregroundStyle(palette.ink2)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 20)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
            }
        }
    }
}

private struct CandidateCard: View {
    let candidate: LibraryModel.OriginalToConfirm

    @AppObject(LibraryModel.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette

    private var item: Shot? {
        LaqtaStore.item(with: candidate.id, context: modelContext)
    }

    var body: some View {
        LaqtaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    pane(title: Text("Saved in Laqta")) {
                        if let item {
                            ShotThumbnail(shot: item, cornerRadius: 10)
                        } else {
                            Rectangle().fill(palette.field)
                        }
                    }
                    pane(title: Text("Found in Photos")) {
                        PhotoAssetThumbnail(assetID: candidate.assetID)
                    }
                }
                if let item {
                    Text(verbatim: LaqtaFormat.dateTime(item.capturedAt ?? item.addedAt))
                        .laqtaFont(12)
                        .foregroundStyle(palette.ink3)
                }
                VStack(spacing: 10) {
                    Button {
                        Task { await library.confirmOriginal(candidate, context: modelContext) }
                    } label: {
                        LaqtaButtonLabel("Same Photo · Delete the Original", systemImage: "trash", fullWidth: true)
                    }
                    .buttonStyle(.pressable)
                    .disabled(library.isCleaningPhotos)
                    Button {
                        library.keepOriginal(candidate, context: modelContext)
                    } label: {
                        LaqtaButtonLabel("Keep It in Photos", kind: .line, fullWidth: true)
                    }
                    .buttonStyle(.pressable)
                    .disabled(library.isCleaningPhotos)
                }
            }
        }
    }

    private func pane<Content: View>(title: Text, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            title
                .laqtaFont(11.5, weight: .semibold)
                .foregroundStyle(palette.ink3)
            content()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(palette.hair, lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One asset from the Photos library, at thumbnail size.
private struct PhotoAssetThumbnail: View {
    let assetID: String

    @Environment(\.laqta) private var palette
    @State private var image: UIImage?
    @State private var isMissing = false

    var body: some View {
        Rectangle()
            .fill(palette.field)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .accessibilityIgnoresInvertColors()
                        .transition(.opacity)
                } else if isMissing {
                    Image(systemName: "photo.badge.exclamationmark")
                        .laqtaIconFont(18)
                        .foregroundStyle(palette.ink3)
                }
            }
            .clipped()
            .task(id: assetID) {
                guard image == nil else { return }
                let loaded = await PhotoLibraryService.thumbnail(for: assetID, pixelSize: 420)
                withAnimation(.easeOut(duration: 0.2)) {
                    image = loaded?.image
                    isMissing = loaded == nil
                }
            }
            .accessibilityLabel(Text("The photo Laqta found in Photos"))
    }
}
