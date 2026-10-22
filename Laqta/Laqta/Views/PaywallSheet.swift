//
//  PaywallSheet.swift
//  Laqta
//
//  The strip on Home counts the thirty days down, and this sheet is where Laqta is
//  bought — once, with no renewal. The first run lives in Views/FirstRun.
//

import Foundation
import SwiftUI

// MARK: - Paywall

struct PaywallSheet: View {
    var reason: PurchaseCenter.PaywallReason = .settings

    @AppObject(PurchaseCenter.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @Environment(\.laqta) private var palette
    @State private var legalDocument: LegalDocument?

    var body: some View {
        PurchaseLayout(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle
        ) {
            VStack(alignment: .leading, spacing: 14) {
                KeepsRow(
                    systemImage: "checkmark.seal",
                    title: "Everything you saved stays",
                    detail: "Folders, shots, notes and backups are untouched, with or without buying."
                )
                KeepsRow(
                    systemImage: "square.and.arrow.down",
                    title: "Saving comes back",
                    detail: "The share sheet, Import and new folders work again the moment you buy."
                )
                KeepsRow(
                    systemImage: "infinity",
                    title: "One payment, no renewal",
                    detail: "Not a subscription. Every update after this one is included."
                )
                if let error = purchases.lastError {
                    Text(verbatim: error)
                        .laqtaFont(12.5)
                        .foregroundStyle(palette.goldHi)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } actions: {
            Button {
                Task {
                    if await purchases.buy() { dismiss() }
                }
            } label: {
                LaqtaButtonLabel(verbatim: buyTitle, kind: .gold, fullWidth: true)
            }
            .buttonStyle(.pressable)
            .disabled(purchases.isWorking)
            HStack(spacing: 10) {
                Button {
                    Task { await purchases.restore() }
                } label: {
                    LaqtaButtonLabel("Restore", kind: .line, small: true, fullWidth: true)
                }
                .buttonStyle(.pressable)
                Button {
                    dismiss()
                } label: {
                    LaqtaButtonLabel(verbatim: closeTitle, kind: .line, small: true, fullWidth: true)
                }
                .buttonStyle(.pressable)
            }
            .disabled(purchases.isWorking)
            HStack(spacing: 14) {
                Button("Terms of Use") { legalDocument = .terms }
                Text(verbatim: "·")
                Button("Privacy Policy") { legalDocument = .privacy }
            }
            .laqtaFont(12)
            .foregroundStyle(palette.ink3)
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .sheet(item: $legalDocument) { document in
            LegalDocumentScreen(document: document)
                .laqtaThemed()
        }
    }

    private var eyebrow: LocalizedStringKey {
        switch purchases.access {
        case .bought: "Thank you"
        case .expired: "The thirty days are over"
        case .trial: "Your trial"
        }
    }

    private var title: LocalizedStringKey {
        switch purchases.access {
        case .bought: "Laqta is yours"
        case .expired: "Keep saving to Laqta"
        case .trial: "Keep Laqta for good"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch (purchases.access, reason) {
        case (.bought, _):
            "Everything is unlocked on every device signed in to your Apple Account."
        case (.expired, .saving):
            "Laqta still has everything you saved — open it, search it, share it. Buying it once lets new shots in again."
        case (.expired, .folder):
            "New folders need the full app. What's already here stays exactly as it is."
        case (.expired, _):
            "Nothing was deleted. One payment brings saving back and keeps it."
        case let (.trial(days), _):
            days == 1
                ? "One day left. Buying now costs the same and never asks again."
                : "\(days) days left. You can buy it whenever you like — the price doesn't change."
        }
    }

    private var buyTitle: String {
        purchases.access.isBought
            ? String(localized: "Done")
            : String(localized: "Buy Laqta · \(purchases.priceText)")
    }

    private var closeTitle: String {
        purchases.access.isExpired
            ? String(localized: "Keep Browsing")
            : String(localized: "Later")
    }
}

// MARK: - The strip on Home

struct TrialStrip: View {
    let access: LibraryAccess
    let onOpen: () -> Void

    @Environment(\.laqta) private var palette

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: access.isExpired ? "lock" : "hourglass")
                    .laqtaIconFont(14, weight: .semibold)
                    .foregroundStyle(access.isExpired ? palette.goldInk : palette.goldHi)
                    .frame(width: 30, height: 30)
                    .background(
                        access.isExpired ? palette.accentFill : palette.field,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: headline)
                        .laqtaFont(14, weight: .semibold)
                        .foregroundStyle(palette.ink)
                    Text(verbatim: detail)
                        .laqtaFont(12)
                        .foregroundStyle(palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .laqtaIconFont(12, weight: .semibold)
                    .foregroundStyle(palette.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(highlighted ? palette.gold.opacity(0.45) : palette.line, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(verbatim: "\(headline). \(detail)"))
    }

    private var highlighted: Bool { access.isExpired || access.isRunningOut }

    private var headline: String {
        switch access {
        case .bought: String(localized: "Laqta is yours")
        case .expired: String(localized: "Saving is paused")
        case let .trial(days):
            days == 1
                ? String(localized: "Last day of your trial")
                : String(localized: "\(days) days left in your trial")
        }
    }

    private var detail: String {
        switch access {
        case .bought: String(localized: "Thank you.")
        case .expired: String(localized: "Everything is still here. Buy Laqta to save new shots again.")
        case .trial: String(localized: "One payment, no subscription. Tap to see it.")
        }
    }
}

// MARK: - Shared layout

private struct PurchaseLayout<Inside: View, Actions: View>: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder var content: Inside
    @ViewBuilder var actions: Actions

    @Environment(\.laqta) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Laqta")
                    .laqtaDisplayFont(44, maxScale: 1.15)
                    .foregroundStyle(palette.goldHi)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 34)
                Text(eyebrow)
                    .textCase(.uppercase)
                    .laqtaFont(11.5, weight: .semibold)
                    .tracking(1.1)
                    .foregroundStyle(palette.gold)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 18)
                Text(title)
                    .laqtaFont(23, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
                Text(subtitle)
                    .laqtaFont(14)
                    .foregroundStyle(palette.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                content
                    .padding(.top, 26)

                VStack(spacing: 10) {
                    actions
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(LaqtaBackground())
        .presentationDetents([.large])
        .presentationBackground(palette.bg)
        .presentationCornerRadius(32)
    }
}

private struct KeepsRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(systemImage: systemImage)
            RowText(title: Text(title), subtitle: Text(detail))
        }
    }
}
