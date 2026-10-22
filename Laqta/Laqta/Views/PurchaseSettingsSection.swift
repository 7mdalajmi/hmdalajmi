//
//  PurchaseSettingsSection.swift
//  Laqta
//
//  The "Laqta" group in Settings: where the thirty days stand, buying, restoring,
//  and watching the opening sequence again. It is its own view so Settings' body
//  stays one screen of layout and nothing here is rebuilt with the rest of it.
//

import Foundation
import SwiftUI

struct PurchaseSettingsSection: View {
    @AppObject(PurchaseCenter.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @Environment(\.laqta) private var palette

    /// Opens the purchase screen. Settings owns the sheet, so only one is ever up.
    private let onBuy: () -> Void

    init(onBuy: @escaping () -> Void) {
        self.onBuy = onBuy
    }

    var body: some View {
        let access = purchases.access
        VStack(spacing: 0) {
            Button(action: onBuy) {
                SettingsValueRow(
                    icon: access.isBought ? "checkmark.seal" : "sparkles",
                    title: access.isBought ? Text("The full app") : Text("Buy Laqta"),
                    value: stateText(access),
                    warn: access.isExpired
                )
            }
            .buttonStyle(.plain)
            .disabled(access.isBought)

            if !access.isBought {
                RowSeparator()
                Button {
                    Task { await purchases.restore() }
                } label: {
                    SettingsValueRow(icon: "arrow.clockwise", title: Text("Restore Purchase"), value: "")
                }
                .buttonStyle(.plain)
                .disabled(purchases.isWorking)
            }

            RowSeparator()
            Button {
                // Settings closes first, so the sequence has the whole screen to itself.
                dismiss()
                purchases.replayFirstRun = true
            } label: {
                SettingsValueRow(icon: "play.circle", title: Text("Watch the Introduction"), value: "")
            }
            .buttonStyle(.plain)
        }
    }

    private func stateText(_ access: LibraryAccess) -> String {
        switch access {
        case .bought:
            return String(localized: "Yours")
        case .expired:
            return String(localized: "Saving paused")
        case let .trial(days):
            return LaqtaFormat.count(days, "day", "days") + String(localized: " left")
        }
    }

    /// What the group says underneath, which changes with the state.
    static func footer(for access: LibraryAccess) -> String {
        switch access {
        case .bought:
            return String(localized: "Laqta is unlocked on every device signed in to your Apple Account. Thank you.")
        case .expired:
            return String(localized: "Everything you saved is still here and always will be. One payment lets new shots in again — it isn't a subscription.")
        case .trial:
            return String(localized: "One payment, never renewed. After the trial Laqta keeps everything you saved and stops taking new shots until you buy it.")
        }
    }
}

/// The same row Settings uses elsewhere, as a view rather than a method, so it can
/// be built outside `SettingsScreen`.
struct SettingsValueRow: View {
    let icon: String
    let title: Text
    let value: String
    var warn: Bool = false
    var chevron: String = "chevron.right"

    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(systemImage: icon)
            RowText(title: title)
            Text(verbatim: value)
                .laqtaFont(15)
                .foregroundStyle(warn ? palette.goldHi : palette.ink2)
                .multilineTextAlignment(.trailing)
            Image(systemName: chevron)
                .laqtaIconFont(13, weight: .semibold)
                .foregroundStyle(palette.ink3)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}
