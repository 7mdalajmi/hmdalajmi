//
//  FirstRunSequence.swift
//  Laqta
//
//  The first time Laqta opens. It shows what the app does before it mentions what it
//  costs: the arrival, five features, a welcome, and only at the end the thirty days.
//  Every chapter draws itself and then waits — nothing turns the page but the reader.
//
//  It runs once. The flag sits beside the trial date in the App Group, so reinstalling
//  does not play it again.
//

import Foundation
import SwiftUI

struct FirstRunSequence: View {
    @AppObject(PurchaseCenter.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var chapter = 0
    @State private var showContinue = false

    /// Nothing moves on by itself. Every chapter waits for Continue — a tap anywhere
    /// or a swipe left does the same — so the reading is at the reader's pace.
    /// The number is only how long the chapter's own animation needs before the
    /// button fades in, so it never appears over a half-drawn screen.
    private let settles: [Double] = [7.2, 2.6, 3.0, 1.7, 2.9, 3.2, 2.3, 0]

    /// The running order, named so the tests can hold it to its promise:
    /// the welcome before the offer, and the offer last.
    static let chapterCount = 8
    static let welcomeChapter = 6
    static let trialChapter = 7

    private var isLast: Bool { chapter == Self.trialChapter }
    /// Skip is there until the last chapter, and it goes straight to it.
    private var canSkip: Bool { !isLast }

    var body: some View {
        ZStack {
            LaqtaBackground()

            currentChapter
                .id(chapter)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: reduceMotion ? 0 : 26)),
                    removal: .opacity
                ))

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                if !isLast, showContinue {
                    continuePill
                        .padding(.bottom, 30)
                        .transition(.opacity.combined(with: .offset(y: 12)))
                }
            }
        }
        .background(palette.bg)
        .contentShape(Rectangle())
        .onTapGesture { if !isLast { advance() } }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard !isLast, value.translation.width < -40 else { return }
                    advance()
                }
        )
        .task(id: chapter) { await revealContinue() }
        .interactiveDismissDisabled()
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<Self.chapterCount, id: \.self) { index in
                    Capsule()
                        .fill(index == chapter ? palette.goldHi : palette.hair)
                        .frame(width: index == chapter ? 16 : 6, height: 3)
                        .opacity(index < chapter ? 0.55 : 1)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: chapter)
            .accessibilityLabel(Text("Step \(chapter + 1) of \(Self.chapterCount)"))

            Spacer(minLength: 0)

            if canSkip {
                Button {
                    // Straight to the last page; the offer is never skipped.
                    withAnimation(.smooth(duration: 0.4)) { chapter = Self.trialChapter }
                } label: {
                    Text("Skip")
                        .laqtaFont(13, weight: .semibold)
                        .foregroundStyle(palette.ink2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var continuePill: some View {
        Button(action: advance) {
            HStack(spacing: 7) {
                Text("Continue").laqtaFont(13.5, weight: .semibold)
                Image(systemName: "chevron.right").laqtaIconFont(11, weight: .bold)
            }
            .foregroundStyle(palette.goldHi)
            .padding(.horizontal, 18)
            .frame(minHeight: 40)
            .background(palette.field, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.buttonBorder, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }

    // MARK: Chapters

    @ViewBuilder
    private var currentChapter: some View {
        switch chapter {
        case 0: ArrivalChapter()
        case 1: ReadsChapter()
        case 2: SearchChapter()
        case 3: KindsChapter()
        case 4: PrivateChapter()
        case 5: PrivacyChapter()
        case 6: WelcomeChapter()
        default:
            TrialChapter(
                price: purchases.priceText,
                isWorking: purchases.isWorking,
                onStart: start,
                onLater: later
            )
        }
    }

    // MARK: Moving

    private func advance() {
        guard !isLast else { return }
        withAnimation(.smooth(duration: 0.42)) { chapter += 1 }
    }

    /// The button arrives once the chapter has finished drawing itself. Tapping the
    /// screen works from the first instant either way, so nobody is held back.
    private func revealContinue() async {
        showContinue = false
        guard !isLast else { return }
        let wait = reduceMotion ? 0.35 : settles[chapter]
        try? await Task.sleep(for: .seconds(wait))
        guard !Task.isCancelled else { return }
        withAnimation(.smooth(duration: 0.45)) { showContinue = true }
    }

    private func start() {
        Task {
            await purchases.startTrial()
            dismiss()
        }
    }

    private func later() {
        PurchaseCenter.Welcome.markShown()
        dismiss()
    }
}
