//
//  FolderEditor.swift
//  Laqta — Shared
//
//  New Folder / Edit Folder: name, cover mood, icon and Face ID lock, with a live preview.
//

import Foundation
import SwiftData
import SwiftUI

struct FolderEditorSheet: View {
    /// `nil` creates a new folder.
    let folder: Folder?
    /// Set when the new folder belongs inside another one.
    var parentID: UUID?
    var onSaved: (Folder) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette

    @State private var name: String = ""
    @State private var tone: FolderTone = .tide
    @State private var symbol: String = "folder"
    @State private var symbolWasPicked = false
    @State private var toneWasPicked = false
    @State private var isLocked = false
    @State private var didLoad = false
    @State private var cover: CoverSource?
    @FocusState private var nameFocused: Bool

    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }) private var siblings: [Folder]

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Moods already on one of your folders — this one's own doesn't count
    /// against it, or renaming a folder could never keep its colour.
    private var takenTones: Set<FolderTone> {
        let mine = folder?.id
        return Set(siblings.filter { $0.id != mine }.map(\.tone))
    }

    private let symbols = [
        "folder", "airplane", "building.2", "drop", "fork.knife", "bag",
        "doc.text", "lightbulb", "graduationcap", "house", "car", "dumbbell",
        "heart", "star", "camera", "play.rectangle", "gift", "lock"
    ]

    /// What VoiceOver says for each icon.
    private static let symbolNames: [String: String] = [
        "folder": "Folder", "airplane": "Travel", "building.2": "City", "drop": "Water",
        "fork.knife": "Food", "bag": "Shopping", "doc.text": "Documents", "lightbulb": "Ideas",
        "graduationcap": "Study", "house": "Home", "car": "Car", "dumbbell": "Fitness",
        "heart": "Favorites", "star": "Star", "camera": "Photos", "play.rectangle": "Videos",
        "gift": "Gifts", "lock": "Lock"
    ]

    var body: some View {
        VStack(spacing: 0) {
            SheetBar(folder == nil ? (parentID == nil ? "New Folder" : "New Folder Inside") : "Edit Folder") {
                Button {
                    dismiss()
                } label: {
                    BarTextButtonLabel(title: "Cancel")
                }
            } trailing: {
                Button(action: save) {
                    BarTextButtonLabel(title: folder == nil ? "Create" : "Save", prominent: true)
                }
                .disabled(trimmedName.isEmpty)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    preview

                    TextField(text: $name, prompt: Text("Folder name").foregroundStyle(palette.ink3)) {
                        Text("Folder name")
                    }
                    .laqtaFont(18)
                    .foregroundStyle(palette.ink)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 52)
                    .background(palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.buttonBorder, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(verbatim: "Cover Mood · \(tone.title)")
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 20) {
                                ForEach(FolderTone.byFamily, id: \.family) { group in
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(verbatim: group.family.title)
                                            .textCase(.uppercase)
                                            .laqtaFont(9.5, weight: .semibold)
                                            .tracking(0.7)
                                            .foregroundStyle(palette.ink3)
                                            .lineLimit(1)
                                        // Two rows per family keeps the whole set
                                        // to one comfortable swipe.
                                        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                                            GridRow { swatches(group.tones.prefix(4)) }
                                            GridRow { swatches(group.tones.suffix(from: min(4, group.tones.count))) }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 4)
                        }
                        .scrollIndicators(.hidden)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Icon")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                            ForEach(symbols, id: \.self) { item in
                                Button {
                                    symbol = item
                                    symbolWasPicked = true
                                } label: {
                                    Image(systemName: item)
                                        .laqtaIconFont(17, weight: .medium)
                                        .foregroundStyle(item == symbol ? palette.goldInk : palette.goldHi)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .background(item == symbol ? palette.accentFill : palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.pressable)
                                .accessibilityLabel(Text(verbatim: "\(Self.symbolNames[item] ?? item) icon"))
                                .accessibilityAddTraits(item == symbol ? .isSelected : [])
                            }
                        }
                    }

                    Toggle(isOn: $isLocked.animation(.snappy)) {
                        HStack(spacing: 12) {
                            RowIcon(systemImage: "faceid")
                            RowText(title: Text("Lock with Face ID"), subtitle: Text("Hidden from search until unlocked"))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.line, lineWidth: 1))

                    Text("The cover becomes a soft blur of the newest shot, so nothing shows clearly.")
                        .laqtaFont(12)
                        .foregroundStyle(palette.ink2)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .background(palette.sheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(palette.sheet)
        .presentationCornerRadius(32)
        .onAppear(perform: load)
        .onChange(of: name) { _, newValue in
            if !symbolWasPicked {
                symbol = FolderSuggester.symbol(forName: newValue)
            }
            // Only for a folder being made: renaming an old one keeps its cover.
            if !toneWasPicked, folder == nil {
                withAnimation(.snappy) {
                    tone = FolderPalette.pick(name: newValue, taken: takenTones)
                }
            }
        }
    }

    /// One row of mood swatches inside a family's little grid.
    @ViewBuilder
    private func swatches(_ tones: some RandomAccessCollection<FolderTone>) -> some View {
        ForEach(Array(tones)) { item in
            Button {
                toneWasPicked = true
                withAnimation(.snappy) { tone = item }
            } label: {
                ToneMesh(tone: item)
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                    .padding(3)
                    .overlay {
                        if item == tone {
                            Circle().strokeBorder(palette.goldHi, lineWidth: 2)
                        }
                    }
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text(verbatim: item.title))
            .accessibilityAddTraits(item == tone ? .isSelected : [])
        }
    }

    private var preview: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                FolderNameText(name: trimmedName.isEmpty ? "مجلد جديد" : trimmedName, size: 28)
                    .opacity(trimmedName.isEmpty ? 0.45 : 1)
                Text(verbatim: folder == nil ? "Empty · Created just now" : LaqtaFormat.updated(folder?.lastUpdate ?? .now))
                    .laqtaFont(13)
                    .foregroundStyle(palette.meta)
            }
            Spacer(minLength: 8)
            FolderBadge(symbol: isLocked ? "lock" : symbol, halo: isLocked)
        }
        .padding(.leading, 20)
        .padding(.trailing, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background {
            ZStack {
                FolderCoverView(source: isLocked ? nil : cover, tone: tone)
                LinearGradient(
                    stops: [
                        .init(color: palette.veil1, location: 0),
                        .init(color: palette.veil2, location: 0.52),
                        .init(color: palette.veil3, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                GrainOverlay(opacity: 0.45)
            }
        }
        // The fields below say the same thing; VoiceOver skips the picture.
        .accessibilityHidden(true)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 1))
        .animation(.snappy, value: tone)
        .animation(.snappy, value: symbol)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let folder {
            name = folder.name
            tone = folder.tone
            toneWasPicked = true
            symbol = folder.badgeSymbol
            symbolWasPicked = true
            isLocked = folder.isLocked
            cover = LaqtaStore.coverSource(in: folder.id, context: modelContext)
        } else {
            // A mood no other folder is wearing, leaning toward whatever the
            // name turns out to mean once it is typed.
            tone = FolderPalette.pick(name: "", taken: takenTones)
            nameFocused = true
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        let target: Folder
        if let folder {
            target = folder
            target.name = trimmedName
            target.tone = tone
            target.symbol = symbol
            target.isLocked = isLocked
        } else {
            target = LibraryWriter.createFolder(name: trimmedName, tone: tone, symbol: symbol, locked: isLocked, parentID: parentID, context: modelContext)
        }
        // The sheet stays open when the save fails, so the button itself is the retry.
        guard modelContext.commit(folder == nil ? .newFolder : .folderEdit) else { return }
        if AppGroup.isRunningInExtension { AppGroup.markExternalChange() }
        dismiss()
        onSaved(target)
    }
}

/// Round glass badge on folder cards.
struct FolderBadge: View {
    let symbol: String
    var halo: Bool = false

    @Environment(\.laqta) private var palette

    var body: some View {
        let size: CGFloat = halo ? 46 : 40
        Image(systemName: symbol)
            .laqtaIconFont(16, weight: .medium)
            .foregroundStyle(palette.goldHi)
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
            .background(palette.badgeFill, in: Circle())
            .overlay(Circle().strokeBorder(palette.badgeBorder, lineWidth: 1))
            .background {
                if halo {
                    Circle()
                        .fill(palette.shimmer)
                        .padding(-6)
                }
            }
            .accessibilityHidden(true)
    }
}
