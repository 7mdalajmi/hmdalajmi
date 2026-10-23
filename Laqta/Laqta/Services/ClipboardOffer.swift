//
//  ClipboardOffer.swift
//  Laqta
//
//  You copied a link an hour ago and never pasted it anywhere. When Laqta opens
//  it offers, once, to keep it — and then forgets the whole thing.
//
//  The check never reads the clipboard. `detectPatterns` answers only the
//  question "is there a web address in there?", which is why iOS shows no
//  "Laqta pasted from…" banner and why the card can say a link is waiting
//  without showing what it is. The contents are read once, at the moment you
//  tap Keep — a paste you asked for.
//

import Foundation
import Observation
import SwiftUI
import UIKit

@Observable
@MainActor
final class ClipboardOffer {
    /// True when there is a link waiting that you have not already answered about.
    private(set) var hasLink = false
    /// The clipboard state this offer belongs to. iOS bumps it on every copy.
    private(set) var changeCount = 0

    private var isChecking = false

    /// The last clipboard we asked about, so one "Not now" is not asked twice.
    private static var answeredCount: Int {
        get { AppGroup.defaults.integer(forKey: SettingsKey.clipboardAnsweredAt) }
        set { AppGroup.defaults.set(newValue, forKey: SettingsKey.clipboardAnsweredAt) }
    }

    /// Looks for a web address without reading one. Safe to call on every launch.
    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let pasteboard = UIPasteboard.general
        let count = pasteboard.changeCount
        changeCount = count
        guard count != Self.answeredCount else {
            hasLink = false
            return
        }
        let webURL: PartialKeyPath<UIPasteboard.DetectedValues> = \.probableWebURL
        let patterns = try? await pasteboard.detectedPatterns(for: [webURL])
        hasLink = patterns?.contains(webURL) ?? false
    }

    /// Reads the clipboard — only ever after the offer was accepted.
    func take() -> String? {
        answer()
        let pasteboard = UIPasteboard.general
        if let url = pasteboard.url { return url.absoluteString }
        guard let string = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else { return nil }
        return string
    }

    /// "Not now" — same clipboard is never raised again.
    func answer() {
        Self.answeredCount = changeCount
        hasLink = false
    }

    /// Forgets which clipboard was answered. Only the tests need this.
    static func forget() {
        AppGroup.defaults.removeObject(forKey: SettingsKey.clipboardAnsweredAt)
    }
}

// MARK: - The card on Home

struct ClipboardOfferCard: View {
    let onKeep: () -> Void
    let onDismiss: () -> Void

    @Environment(\.laqta) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "link")
                    .laqtaIconFont(15, weight: .semibold)
                    .foregroundStyle(palette.goldHi)
                Text("Still in your clipboard")
                    .textCase(.uppercase)
                    .laqtaFont(11, weight: .semibold)
                    .tracking(0.9)
                    .foregroundStyle(palette.gold)
                Spacer(minLength: 0)
            }
            Text("There is a link waiting. Keep it in Laqta?")
                .laqtaFont(15, weight: .semibold)
                .foregroundStyle(palette.ink)
                .adaptiveLineLimit(2, accessibility: 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Laqta has not looked at it. It only knows something link-shaped is there.")
                .laqtaFont(12)
                .foregroundStyle(palette.ink3)
                .adaptiveLineLimit(2, accessibility: 5)
                .frame(maxWidth: .infinity, alignment: .leading)
            AdaptiveButtonRow {
                Button(action: onKeep) {
                    Text("Keep It")
                        .laqtaFont(15, weight: .semibold)
                        .foregroundStyle(palette.goldInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(palette.accentFill, in: Capsule())
                }
                Button(action: onDismiss) {
                    Text("Not Now")
                        .laqtaFont(15, weight: .semibold)
                        .foregroundStyle(palette.goldHi)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Capsule().strokeBorder(palette.hair, lineWidth: 1))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.hair, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
