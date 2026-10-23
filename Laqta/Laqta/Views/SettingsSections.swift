//
//  SettingsSections.swift
//  Laqta
//
//  The two heaviest groups in Settings, as views of their own.
//
//  They used to be computed properties on `SettingsScreen`, which meant their whole
//  nested generic type was folded into the type of one `body`. With nine groups the
//  combined type grew past what the Swift runtime could demangle, and the app died
//  inside the demangler the moment it drew the first theme tile. A `View` of its own
//  is a boundary: each one gets its own small type, and Settings' body gets short.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Appearance

struct AppearanceSettingsSection: View {
    @AppStorage(SettingsKey.appearance, store: AppGroup.defaults) private var appearanceRaw = AppearanceMode.noir.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .noir
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ThemeTile(mode: .noir, appearance: appearance) { choose(.noir) }
                ThemeTile(mode: .ivory, appearance: appearance) { choose(.ivory) }
            }
            .padding(.vertical, 14)
            RowSeparator(inset: 0)
            SwitchRow(
                title: "Match System",
                subtitle: "Noir after sunset, Ivory by day",
                systemImage: "moon",
                isOn: Binding(
                    get: { appearance == .system },
                    set: { matches in
                        withAnimation(.easeInOut(duration: 0.32)) {
                            appearanceRaw = matches
                                ? AppearanceMode.system.rawValue
                                : (colorScheme == .dark ? AppearanceMode.noir : .ivory).rawValue
                        }
                    }
                )
            )
        }
    }

    private func choose(_ mode: AppearanceMode) {
        withAnimation(.easeInOut(duration: 0.32)) { appearanceRaw = mode.rawValue }
    }
}

/// A small picture of the app in one of the two faces, with its own name under it.
struct ThemeTile: View {
    let mode: AppearanceMode
    let appearance: AppearanceMode
    let onPick: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.laqta) private var palette

    private static let barWidths: [CGFloat] = [34, 24, 30, 26]

    private var tilePalette: LaqtaPalette { mode == .noir ? .noir : .ivory }

    private var selected: Bool {
        appearance == mode || (appearance == .system && (colorScheme == .dark) == (mode == .noir))
    }

    private var name: String { mode == .noir ? "Noir" : "Ivory" }

    var body: some View {
        Button(action: onPick) {
            VStack(spacing: 8) {
                preview
                HStack(spacing: 8) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .laqtaIconFont(20)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            selected ? palette.goldInk : palette.ink3,
                            selected ? palette.accentFill : palette.ink3
                        )
                    Text(verbatim: name)
                        .laqtaFont(15, weight: .medium)
                        .foregroundStyle(palette.ink)
                }
            }
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityHint(Text("Appearance"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Laqta")
                .laqtaDisplayFont(20, maxScale: 1)
                .foregroundStyle(tilePalette.goldHi)
            ForEach(Array(FolderTone.allCases.prefix(4).enumerated()), id: \.offset) { index, tone in
                bar(tone: tone, width: Self.barWidths[index])
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 132)
        .background(
            LinearGradient(
                colors: [tilePalette.bgGlow, tilePalette.bg],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? palette.goldHi : palette.line, lineWidth: selected ? 2 : 1)
        )
        .accessibilityHidden(true)
    }

    private func bar(tone: FolderTone, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ToneMesh(tone: tone)
            LinearGradient(
                colors: [tilePalette.veil1, tilePalette.veil3],
                startPoint: .leading, endPoint: .trailing
            )
            Capsule()
                .fill(tilePalette.ink)
                .frame(width: width, height: 4)
                .padding(.leading, 8)
        }
        .frame(height: 12)
        .clipShape(Capsule())
    }
}

// MARK: - Storage

struct StorageSettingsSection: View {
    let items: [Shot]
    let folderCount: Int
    let storageBytes: Int64?
    let trashCount: Int
    let onOpenTrash: () -> Void
    let onCleanUp: () -> Void

    @Environment(\.laqta) private var palette

    var body: some View {
        let usage = StorageBreakdown(items: items)
        let total = max(storageBytes ?? usage.total, max(usage.total, 1))
        VStack(alignment: .leading, spacing: 0) {
            heading(usage)
            bar(usage, total: total)
            legendGrid(usage)
            RowSeparator(inset: 0)
            Button(action: onCleanUp) {
                SettingsValueRow(
                    icon: "sparkles",
                    title: Text("Clean Up Old Shots"),
                    value: String(localized: "Review")
                )
            }
            .buttonStyle(.plain)
            RowSeparator()
            Button {
                guard trashCount > 0 else { return }
                onOpenTrash()
            } label: {
                SettingsValueRow(
                    icon: "trash",
                    title: Text("Recently Deleted"),
                    value: trashCount == 0 ? String(localized: "Empty") : LaqtaFormat.count(trashCount, "item", "items")
                )
            }
            .buttonStyle(.plain)
            .disabled(trashCount == 0)
        }
    }

    private func heading(_ usage: StorageBreakdown) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: storageBytes.map(LaqtaFormat.bytes) ?? "…")
                .laqtaFont(22, weight: .semibold)
                .foregroundStyle(palette.ink)
                .contentTransition(.numericText())
            Text("used by Laqta")
                .laqtaFont(13)
                .foregroundStyle(palette.ink2)
            Spacer()
            Text(verbatim: "\(LaqtaFormat.count(folderCount, "folder", "folders")) · \(LaqtaFormat.count(usage.links, "link", "links"))")
                .laqtaFont(13)
                .foregroundStyle(palette.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
    }

    private func bar(_ usage: StorageBreakdown, total: Int64) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(usage.segments(palette: palette)) { segment in
                    Capsule()
                        .fill(segment.style)
                        .frame(width: max(4, proxy.size.width * CGFloat(segment.bytes) / CGFloat(total)))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 6)
        .background(palette.field, in: Capsule())
        .padding(.vertical, 10)
        .accessibilityHidden(true)
    }

    private func legendGrid(_ usage: StorageBreakdown) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10, alignment: .leading),
                GridItem(.flexible(), spacing: 10, alignment: .leading)
            ],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(usage.segments(palette: palette)) { segment in
                HStack(spacing: 5) {
                    Circle().fill(segment.style).frame(width: 7, height: 7)
                    Text(verbatim: "\(segment.title) · \(LaqtaFormat.bytes(segment.bytes))")
                        .laqtaFont(11)
                        .foregroundStyle(palette.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.bottom, 12)
    }
}

/// Two switches, out of SettingsScreen's own `body` for the reason at the top of this file.
struct SavingSettingsSection: View {
    @AppStorage(SettingsKey.skipDuplicates, store: AppGroup.defaults) private var skipDuplicates = true
    @AppStorage(SettingsKey.extractLinks, store: AppGroup.defaults) private var extractLinks = true

    var body: some View {
        VStack(spacing: 0) {
            SwitchRow(
                title: "Skip items already in Laqta",
                subtitle: "Save to Laqta points out copies you already have",
                systemImage: "square.on.square",
                isOn: $skipDuplicates
            )
            RowSeparator()
            SwitchRow(
                title: "Extract everything from links",
                subtitle: "Summary, chapters, places and prices",
                systemImage: "link",
                isOn: $extractLinks
            )
        }
    }
}
