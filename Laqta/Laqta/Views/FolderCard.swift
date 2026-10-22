//
//  FolderCard.swift
//  Laqta
//
//  100 pt folder card: blurred cover, veil, grain, Amiri name and a glass badge.
//

import Foundation
import SwiftUI

struct FolderCard: View {
    let folder: Folder
    let stats: FolderStats
    /// False while a private folder is locked.
    let isUnlocked: Bool
    var highlighted: Bool = false
    /// Folders sitting inside this one.
    var subfolders: Int = 0

    @Environment(\.laqta) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isRecent: Bool {
        Date.now.timeIntervalSince(folder.lastUpdate) < 120
    }

    var body: some View {
        // The text sets the height (100 pt at standard sizes, taller at large text sizes);
        // the cover fills whatever space the text takes.
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                FolderNameText(name: folder.name, size: 28)
                HStack(spacing: 6) {
                    if isRecent {
                        Circle()
                            .fill(palette.goldHi)
                            .frame(width: 7, height: 7)
                            .background(Circle().fill(palette.shimmer).padding(-3))
                    }
                    Text(verbatim: meta)
                        .laqtaFont(13)
                        .foregroundStyle(palette.meta)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                }
            }
            Spacer(minLength: 8)
            FolderBadge(symbol: badgeSymbol, halo: folder.isPrivate && !isUnlocked)
        }
        .padding(.leading, 20)
        .padding(.trailing, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background {
            ZStack {
                FolderCoverView(source: isUnlocked ? stats.cover : nil, tone: folder.tone, heavy: folder.isPrivate)
                LinearGradient(
                    stops: [
                        .init(color: palette.veil1, location: 0),
                        .init(color: palette.veil2, location: 0.52),
                        .init(color: palette.veil3, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                GrainOverlay(opacity: 0.5)
                if highlighted {
                    GoldSweep()
                }
            }
        }
        .background(palette.sheet2)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(folder.name), \(meta)"))
        .accessibilityAddTraits(.isButton)
    }

    private var badgeSymbol: String {
        if folder.isPrivate {
            return isUnlocked ? "lock.open" : "lock"
        }
        return folder.badgeSymbol
    }

    private var meta: String {
        let updated = isRecent ? "Updated just now" : LaqtaFormat.updated(folder.lastUpdate)
        if folder.isPrivate, !isUnlocked {
            return "Locked · \(updated)"
        }
        guard subfolders > 0 else { return "\(stats.summary) · \(updated)" }
        let inside = LaqtaFormat.count(subfolders, "folder", "folders")
        // An empty parent reads better as "2 folders" than "2 folders · Empty".
        guard stats.total > 0 else { return "\(inside) · \(updated)" }
        return "\(inside) · \(stats.summary) · \(updated)"
    }
}

/// The light that runs across a folder after something was saved into it.
struct GoldSweep: View {
    @State private var progress: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: Color(hex: 0xFFECBE, alpha: 0.3), location: 0.48),
                    .init(color: .clear, location: 0.72)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: proxy.size.width)
            // Runs the way the language reads.
            .offset(x: progress * proxy.size.width * layoutDirection.sign)
        }
        .allowsHitTesting(false)
        .opacity(reduceMotion ? 0 : 1)
        .onAppear {
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 1.5).delay(0.42)) {
                progress = 1
            }
        }
    }
}
