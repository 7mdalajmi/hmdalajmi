//
//  AskLibraryCard.swift
//  Laqta
//
//  The card that sits above the search results when what you typed reads like a
//  question rather than a word. Asking is always a deliberate tap — the model is
//  never run on every keystroke.
//

import Foundation
import SwiftData
import SwiftUI

struct AskLibraryCard: View {
    let question: String
    let model: LibraryAskModel
    let onAsk: () -> Void
    let onOpen: (UUID) -> Void

    @Environment(\.laqta) private var palette
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            switch model.state {
            case .idle:
                askButton
            case .thinking:
                thinking
            case let .answered(reply):
                answer(reply)
            case let .failed(message):
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: message)
                        .laqtaFont(13)
                        .foregroundStyle(palette.ink2)
                    askButton
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.hair, lineWidth: 1))
        .padding(.bottom, 14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .laqtaIconFont(14, weight: .semibold)
                .foregroundStyle(palette.goldHi)
            Text("Ask your library")
                .textCase(.uppercase)
                .laqtaFont(11, weight: .semibold)
                .tracking(0.9)
                .foregroundStyle(palette.gold)
            Spacer(minLength: 0)
            Text("On device")
                .laqtaFont(10, weight: .semibold)
                .foregroundStyle(palette.ink3)
        }
    }

    private var askButton: some View {
        Button(action: onAsk) {
            HStack(spacing: 8) {
                Text(verbatim: "“\(question)”")
                    .laqtaFont(14, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .adaptiveLineLimit(2, accessibility: 4)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                Image(systemName: "arrow.up.circle.fill")
                    .laqtaIconFont(22)
                    .foregroundStyle(palette.goldHi)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Ask your library: \(question)"))
    }

    private var thinking: some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)
                .tint(palette.goldHi)
            Text("Reading your shots on this phone…")
                .laqtaFont(13)
                .foregroundStyle(palette.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func answer(_ reply: LibraryAskModel.LibraryAnswerView) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: reply.text)
                .laqtaFont(15)
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(palette.accentFill)
                        .frame(width: 2)
                        .offset(x: -11 * layoutDirection.sign)
                }
            if let best = reply.bestID {
                Button {
                    onOpen(best)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "photo")
                        Text("Open the one it means")
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .laqtaIconFont(11, weight: .semibold)
                    }
                    .laqtaFont(13, weight: .semibold)
                    .foregroundStyle(palette.goldHi)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
                    .background(palette.field, in: Capsule())
                    .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
                }
                .buttonStyle(.pressable)
            }
            if !reply.otherIDs.isEmpty {
                Text("\(LaqtaFormat.count(reply.otherIDs.count, "other shot", "other shots")) close to it — they are in the results below.")
                    .laqtaFont(11.5)
                    .foregroundStyle(palette.ink3)
            }
        }
    }
}
