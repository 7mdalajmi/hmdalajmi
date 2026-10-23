//
//  FirstRunChapters.swift
//  Laqta
//
//  Eight chapters. The first two play themselves — that is the hook, and it asks for
//  nothing. The four after them wait for a tap. The last two always run: the welcome,
//  and only then the thirty days.
//

import Foundation
import SwiftUI

// MARK: - 1 · The arrival

struct ArrivalChapter: View {
    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0
    @State private var counted = false

    private let chips = ["Watch", "Rolex", "KWD 4,200", "Al-Tijara"]

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack(alignment: .top) {
                // The name rises from under the edge, settles, then carries on up
                // and becomes the header. It never leaves the screen again.
                Text(verbatim: "Laqta")
                    .laqtaDisplayFont(52, maxScale: 1.1)
                    .foregroundStyle(palette.goldHi)
                    .scaleEffect(beat >= 2 ? 0.66 : 1, anchor: .top)
                    .offset(y: wordmarkOffset(in: height))
                    .opacity(beat >= 1 ? 1 : 0)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                shot
                    .frame(width: 184, height: 252)
                    .offset(y: shotOffset(in: height))
                    .rotationEffect(.degrees(beat >= 3 ? 0 : 7))
                    .scaleEffect(shotScale, anchor: .top)
                    .opacity(beat >= 3 ? (beat >= 5 ? 0 : 1) : 0)
                    .animation(.spring(response: 0.9, dampingFraction: 1), value: beat)

                chipRow
                    .offset(y: height * 0.60)

                arrivedFolder
                    .padding(.horizontal, 20)
                    .offset(y: height * 0.55)
                    .opacity(beat == 5 ? 1 : 0)

                folderGrid
                    .padding(.horizontal, 20)
                    .offset(y: 112)
                    .opacity(beat >= 6 ? (beat >= 7 ? 0.42 : 1) : 0)
                    .scaleEffect(beat >= 7 ? 0.97 : 1, anchor: .top)

                closing
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 96)
                    .rise(beat >= 7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .task {
            await BeatPlayer(gaps: [0.05, 1.45, 0.18, 1.05, 1.7, 1.5, 1.1])
                .play($beat, reduceMotion: reduceMotion)
        }
        .task(id: beat) {
            guard beat == 5, !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.7)) { counted = true }
        }
    }

    private func wordmarkOffset(in height: CGFloat) -> CGFloat {
        if beat >= 2 { return 56 }
        if beat >= 1 { return height * 0.42 }
        return height * 0.66
    }

    private func shotOffset(in height: CGFloat) -> CGFloat {
        if beat >= 5 { return height * 0.56 }
        if beat >= 3 { return 132 }
        return height + 40
    }

    private var shotScale: CGFloat {
        if beat >= 5 { return 0.16 }
        if beat >= 3 { return 1 }
        return 0.82
    }

    private var shot: some View {
        DemoShot(cover: .bronze) {
            ZStack {
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: "Submariner\n126610LN")
                        .laqtaDisplayFont(26)
                        .foregroundStyle(Color(hex: 0xEFE7DA))
                    Text(verbatim: "KWD 4,200 · Al-Tijara")
                        .laqtaFont(12)
                        .foregroundStyle(palette.meta)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(18)
                DemoShotFooter(text: "Screenshot · 9:41")
                // Laqta reading it: one pass, top to bottom.
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.clear, palette.goldHi.opacity(0.22), .clear],
                        startPoint: .top, endPoint: .bottom))
                    .frame(height: 76)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(y: beat >= 4 ? 300 : -80)
                    .opacity(beat == 4 ? 1 : 0)
                    .animation(.easeInOut(duration: 1.1), value: beat)
            }
        }
        .accessibilityHidden(true)
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(chips.enumerated()), id: \.offset) { index, text in
                FirstRunChip(text: text)
                    .opacity(beat == 4 ? 1 : 0)
                    .offset(y: beat >= 4 ? 0 : 10)
                    .scaleEffect(beat >= 4 ? 1 : 0.9)
                    .animation(.spring(response: 0.44, dampingFraction: 0.66).delay(Double(index) * 0.17), value: beat)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var arrivedFolder: some View {
        DemoFolderCard(
            name: "Watches",
            detail: counted ? "4 shots · just now" : "3 shots · just now",
            cover: .sand,
            symbol: "folder"
        )
        .scaleEffect(counted ? 1.03 : 1)
    }

    private var folderGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Folders")
                .padding(.bottom, 2)
            card("Watches", "4 shots · just now", .sand, "folder", 0)
            card("Perfumes", "11 shots · 4 links", .stone, "drop", 1)
            card("Travel", "1 folder · 18 Sep", .teal, "airplane", 2)
        }
    }

    private func card(_ name: String, _ detail: String, _ cover: DemoCover, _ symbol: String, _ index: Int) -> some View {
        DemoFolderCard(name: name, detail: detail, cover: cover, symbol: symbol)
            .opacity(beat >= 6 ? 1 : 0)
            .offset(y: beat >= 6 ? 0 : 18)
            .scaleEffect(beat >= 6 ? 1 : 0.97)
            .animation(.spring(response: 0.56, dampingFraction: 0.74).delay(Double(index) * 0.11), value: beat)
    }

    private var closing: some View {
        VStack(spacing: 8) {
            Text("Share it once.\nLaqta does the rest.")
                .laqtaDisplayFont(29)
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
            Text("It reads the shot, names it, and files it — here on your phone.")
                .laqtaFont(13)
                .foregroundStyle(palette.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 26)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 2 · It reads what is inside

struct ReadsChapter: View {
    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0

    private let found: [(String, String)] = [
        ("calendar", "12 Oct, 02:40"), ("chair.lounge", "Seat 14A"),
        ("number", "KU 171"), ("airplane", "Paris")
    ]

    var body: some View {
        ChapterLayout(eyebrow: "Reads", captionShown: beat >= 5) {
            VStack(spacing: 18) {
                boardingPass
                    .frame(height: 246)
                    .padding(.horizontal, 58)
                    .rise(beat >= 1)
                HStack(spacing: 6) {
                    ForEach(Array(found.enumerated()), id: \.offset) { index, item in
                        FirstRunChip(text: item.1, systemImage: item.0)
                            .opacity(beat >= 3 ? 1 : 0)
                            // They lift out of the picture, so they arrive from above.
                            .offset(y: beat >= 3 ? 0 : -22)
                            .scaleEffect(beat >= 3 ? 1 : 0.86)
                            .animation(.spring(response: 0.56, dampingFraction: 0.66).delay(Double(index) * 0.25), value: beat)
                    }
                }
                .padding(.horizontal, 14)
            }
        } caption: {
            ChapterCaption(
                title: "It reads what is inside",
                detail: "Flights, prices, codes, the text in the picture — all of it pulled out on your phone, never sent anywhere."
            )
        }
        .task {
            await BeatPlayer(gaps: [0.05, 0.7, 0.62, 0.7, 0.8]).play($beat, reduceMotion: reduceMotion)
        }
    }

    private var boardingPass: some View {
        DemoShot(cover: .amber) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "BOARDING PASS")
                    .laqtaFont(11, weight: .semibold)
                    .tracking(1.2)
                    .foregroundStyle(palette.ink2)
                Text(verbatim: "KWI → CDG")
                    .laqtaDisplayFont(30)
                    .foregroundStyle(Color(hex: 0xEFE7DA))
                    .padding(.top, 8)
                underlined("12 Oct · 02:40", drawn: beat >= 2)
                    .padding(.top, 14)
                underlined("Seat 14A · KU 171", drawn: beat >= 3)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(20)
        }
        .accessibilityHidden(true)
    }

    /// A gold rule draws itself under the line Laqta is reading.
    private func underlined(_ text: String, drawn: Bool) -> some View {
        Text(verbatim: text)
            .laqtaFont(14)
            .foregroundStyle(Color(hex: 0xDDD3C2))
            .overlay(alignment: .bottomLeading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(palette.goldHi)
                        .frame(width: drawn ? proxy.size.width : 0, height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .offset(y: 3)
                        .animation(.easeInOut(duration: 0.48), value: drawn)
                }
            }
    }
}

// MARK: - 3 · Search a word you never typed

struct SearchChapter: View {
    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0
    @State private var typed = 0
    @Namespace private var cells

    private let query = "4200"
    private let grid: [DemoCover] = [.sand, .amber, .stone, .bronze, .teal, .plum, .sand, .stone, .bronze]
    private let matches = [1, 4]

    var body: some View {
        ChapterLayout(eyebrow: "Find", captionShown: beat >= 4) {
            VStack(spacing: 14) {
                searchField
                    .padding(.horizontal, 20)
                    .rise(beat >= 1)
                if beat >= 3 {
                    HStack(spacing: 8) {
                        ForEach(matches, id: \.self) { index in
                            DemoShot(cover: grid[index])
                                .matchedGeometryEffect(id: index, in: cells)
                                .frame(height: 112)
                        }
                    }
                    .padding(.horizontal, 20)
                    Text("2 shots mention “4,200”")
                        .laqtaFont(11.5)
                        .foregroundStyle(palette.gold)
                        .transition(.opacity)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(grid.indices, id: \.self) { index in
                            DemoShot(cover: grid[index])
                                .modifier(MatchedIf(active: matches.contains(index), key: index, namespace: cells))
                                .frame(height: 74)
                                .opacity(beat >= 1 ? 1 : 0)
                                .animation(.smooth(duration: 0.42).delay(Double(index) * 0.045), value: beat)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        } caption: {
            ChapterCaption(
                title: "Search a word you never typed",
                detail: "Laqta already read every shot, so the price on a receipt is what finds the receipt."
            )
        }
        .task {
            await BeatPlayer(gaps: [0.05, 0.85, 1.05, 0.9]).play($beat, reduceMotion: reduceMotion,
                                                                 animation: .spring(response: 0.58, dampingFraction: 0.82))
        }
        .task(id: beat) {
            guard beat == 2, !reduceMotion else {
                if reduceMotion { typed = query.count }
                return
            }
            for step in 1...query.count {
                try? await Task.sleep(for: .seconds(0.19))
                guard !Task.isCancelled else { return }
                typed = step
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .laqtaIconFont(14, weight: .medium)
                .foregroundStyle(palette.ink2)
            Text(verbatim: String(query.prefix(typed)))
                .laqtaFont(14)
                .foregroundStyle(palette.ink)
            Rectangle()
                .fill(palette.goldHi)
                .frame(width: 1.5, height: 16)
                .opacity(beat >= 3 ? 0 : 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.line, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

/// The two shots that survive the search keep their identity across the layout change;
/// the seven that do not are plain views and simply leave.
private struct MatchedIf: ViewModifier {
    let active: Bool
    let key: Int
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if active {
            content.matchedGeometryEffect(id: key, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - 4 · Not screenshots only

struct KindsChapter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.laqta) private var palette
    @State private var beat = 0

    private struct Kind: Identifiable {
        let id = UUID()
        let cover: DemoCover
        let title: String
        let badge: String?
        let symbol: String?
    }

    private let kinds: [Kind] = [
        Kind(cover: .teal, title: "Screen recording", badge: "0:42", symbol: "play.fill"),
        Kind(cover: .amber, title: "Contract.pdf", badge: "12 pages", symbol: "doc.text"),
        Kind(cover: .bronze, title: "How it is made", badge: "YouTube", symbol: "link"),
        Kind(cover: .stone, title: "A photo", badge: nil, symbol: nil)
    ]

    var body: some View {
        ChapterLayout(eyebrow: "Everything", captionShown: beat >= 2) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(Array(kinds.enumerated()), id: \.element.id) { index, kind in
                    card(kind, index: index)
                }
            }
            .padding(.horizontal, 20)
        } caption: {
            ChapterCaption(
                title: "Not screenshots only",
                detail: "Videos, screen recordings, PDFs and links land here too — a link keeps its title, its channel and its picture."
            )
        }
        .task {
            await BeatPlayer(gaps: [0.05, 0.95]).play($beat, reduceMotion: reduceMotion)
        }
    }

    private func card(_ kind: Kind, index: Int) -> some View {
        DemoShot(cover: kind.cover) {
            ZStack(alignment: .topLeading) {
                if let badge = kind.badge, let symbol = kind.symbol {
                    DemoBadge(text: badge, systemImage: symbol)
                        .padding(9)
                }
                DemoShotFooter(text: kind.title)
            }
        }
        .frame(height: 142)
        // Dealt out of the bottom edge, alternating which way they tilt.
        .opacity(beat >= 1 ? 1 : 0)
        .offset(y: beat >= 1 ? 0 : 210)
        .rotationEffect(.degrees(beat >= 1 ? 0 : (index.isMultiple(of: 2) ? -8 : 8)))
        .scaleEffect(beat >= 1 ? 1 : 0.8)
        .animation(.spring(response: 0.62, dampingFraction: 0.78).delay(Double(index) * 0.15), value: beat)
    }
}

// MARK: - 5 · A folder only you open

struct PrivateChapter: View {
    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0

    var body: some View {
        ChapterLayout(eyebrow: "Private", captionShown: beat >= 4) {
            VStack(spacing: 30) {
                DemoFolderCard(
                    name: "Private",
                    detail: beat >= 3 ? "9 shots · unlocked" : "Locked",
                    cover: .plum,
                    symbol: beat >= 3 ? "lock.open" : "lock",
                    blurCover: beat >= 3 ? 0 : 16,
                    minHeight: 130
                )
                .padding(.horizontal, 24)
                .rise(beat >= 1)
                .animation(.smooth(duration: 0.9), value: beat)

                faceID
                    .frame(width: 64, height: 64)
                    .opacity(beat == 2 ? 1 : 0)
                    .scaleEffect(beat >= 3 ? 1.25 : 1)
            }
        } caption: {
            ChapterCaption(
                title: "Some folders stay yours alone",
                detail: "Lock a folder and it needs your face to open — its cover stays blurred everywhere else in the app."
            )
        }
        .task {
            await BeatPlayer(gaps: [0.05, 0.8, 1.25, 0.65]).play($beat, reduceMotion: reduceMotion)
        }
    }

    /// The bracket draws itself, then the face inside it appears.
    private var faceID: some View {
        ZStack {
            FaceBracket()
                .trim(from: 0, to: beat >= 2 ? 1 : 0)
                .stroke(palette.goldHi, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .animation(.easeInOut(duration: 0.82), value: beat)
            Image(systemName: "faceid")
                .laqtaIconFont(26, weight: .light)
                .foregroundStyle(palette.goldHi)
                .opacity(beat >= 2 ? 0.9 : 0)
                .animation(.smooth(duration: 0.42).delay(0.55), value: beat)
        }
        .accessibilityHidden(true)
    }
}

/// Four corners of a Face ID frame, drawn as one path so it can be trimmed.
private nonisolated struct FaceBracket: Shape {
    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 3, radius: CGFloat = 12
        let box = rect.insetBy(dx: inset, dy: inset)
        let arm = min(box.width, box.height) * 0.28
        var path = Path()
        // top-left
        path.move(to: CGPoint(x: box.minX, y: box.minY + arm))
        path.addLine(to: CGPoint(x: box.minX, y: box.minY + radius))
        path.addQuadCurve(to: CGPoint(x: box.minX + radius, y: box.minY),
                          control: CGPoint(x: box.minX, y: box.minY))
        path.addLine(to: CGPoint(x: box.minX + arm, y: box.minY))
        // top-right
        path.move(to: CGPoint(x: box.maxX - arm, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX - radius, y: box.minY))
        path.addQuadCurve(to: CGPoint(x: box.maxX, y: box.minY + radius),
                          control: CGPoint(x: box.maxX, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.minY + arm))
        // bottom-right
        path.move(to: CGPoint(x: box.maxX, y: box.maxY - arm))
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: box.maxX - radius, y: box.maxY),
                          control: CGPoint(x: box.maxX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.maxX - arm, y: box.maxY))
        // bottom-left
        path.move(to: CGPoint(x: box.minX + arm, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX + radius, y: box.maxY))
        path.addQuadCurve(to: CGPoint(x: box.minX, y: box.maxY - radius),
                          control: CGPoint(x: box.minX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY - arm))
        return path
    }
}

// MARK: - 6 · Nothing leaves your phone

struct PrivacyChapter: View {
    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0

    var body: some View {
        ZStack {
            ChapterLayout(eyebrow: "On device", captionShown: beat >= 4) {
                VStack(spacing: 16) {
                    Text("The cloud")
                        .textCase(.uppercase)
                        .laqtaFont(11, weight: .semibold)
                        .tracking(1.2)
                        .foregroundStyle(palette.ink3)
                        .opacity(beat >= 3 ? 0.18 : 1)
                    Rectangle()
                        .fill(palette.hair)
                        .frame(width: 1.5, height: 54)
                        .opacity(beat == 2 ? 1 : 0)
                    DemoShot(cover: .bronze)
                        .frame(width: 120, height: 160)
                        // It drifts up toward the cloud, then springs home.
                        .offset(y: beat == 2 ? -112 : 0)
                        .scaleEffect(beat == 2 ? 0.86 : 1)
                        .opacity(beat >= 1 ? (beat == 2 ? 0.75 : 1) : 0)
                        .animation(.spring(response: 0.82, dampingFraction: beat >= 3 ? 0.66 : 1), value: beat)
                    FirstRunChip(text: "stays on this iPhone", systemImage: "iphone")
                        .rise(beat >= 3, by: 12)
                }
            } caption: {
                ChapterCaption(
                    title: "Nothing leaves your phone",
                    detail: "The reading, the naming, the search — all of it on device. iCloud is yours to switch on, and it is off until you do."
                )
            }
            // A gold line draws itself around the whole device and catches it.
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .trim(from: 0, to: beat >= 3 ? 1 : 0)
                .stroke(palette.goldHi.opacity(0.9), lineWidth: 1.6)
                .padding(7)
                .animation(.easeInOut(duration: 0.9), value: beat)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .task {
            await BeatPlayer(gaps: [0.05, 0.75, 0.9, 0.85]).play($beat, reduceMotion: reduceMotion)
        }
    }
}

// MARK: - 7 · Welcome

struct WelcomeChapter: View {
    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0

    private let holds = ["Shots", "Videos", "PDFs", "Links"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(verbatim: "Laqta")
                .laqtaDisplayFont(56, maxScale: 1.1)
                .foregroundStyle(palette.goldHi)
                .rise(beat >= 1)
            Text("Welcome — you will\nnot lose one again")
                .laqtaDisplayFont(30)
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 18)
                .rise(beat >= 2)
            Text("Take the shot. Share it to Laqta. Then forget it completely — it is read, named, filed, and the private ones need your face to open.")
                .laqtaFont(13.5)
                .foregroundStyle(palette.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .rise(beat >= 3)
            HStack(spacing: 7) {
                ForEach(Array(holds.enumerated()), id: \.offset) { index, text in
                    FirstRunChip(text: text)
                        .opacity(beat >= 4 ? 1 : 0)
                        .scaleEffect(beat >= 4 ? 1 : 0.84)
                        .animation(.spring(response: 0.5, dampingFraction: 0.66).delay(Double(index) * 0.12), value: beat)
                }
            }
            .padding(.top, 24)
            Spacer(minLength: 0)
            Text("Turn Laqta on in the Share sheet to begin")
                .laqtaFont(12)
                .foregroundStyle(palette.ink3)
                .padding(.bottom, 96)
                .rise(beat >= 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await BeatPlayer(gaps: [0.05, 0.42, 0.34, 0.54, 0.8]).play($beat, reduceMotion: reduceMotion)
        }
    }
}

// MARK: - 8 · Thirty days

struct TrialChapter: View {
    let price: String
    let isWorking: Bool
    let onStart: () -> Void
    let onLater: () -> Void

    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: "Laqta")
                .laqtaDisplayFont(34, maxScale: 1.1)
                .foregroundStyle(palette.goldHi)
                .padding(.top, 14)
                .rise(beat >= 1)
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Text(verbatim: "30")
                    .laqtaDisplayFont(118, maxScale: 1.1)
                    .foregroundStyle(palette.goldHi)
                    .scaleEffect(beat >= 2 ? 1 : 0.86)
                    .opacity(beat >= 2 ? 1 : 0)
                    .animation(.spring(response: 0.7, dampingFraction: 0.62), value: beat)
                Text("days, on us")
                    .laqtaDisplayFont(27)
                    .foregroundStyle(palette.ink)
                    .rise(beat >= 2)
            }
            Text("No card today, and nothing renews. On day thirty-one every shot is still here — keep it for one payment, once.")
                .laqtaFont(13.5)
                .foregroundStyle(palette.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
                .padding(.top, 26)
                .rise(beat >= 3)
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Button(action: onStart) {
                    LaqtaButtonLabel("Start My 30 Free Days", kind: .gold, fullWidth: true)
                }
                .buttonStyle(.pressable)
                .disabled(isWorking)
                .rise(beat >= 4)
                Button(action: onLater) {
                    LaqtaButtonLabel("Not Now", kind: .line, fullWidth: true)
                }
                .buttonStyle(.pressable)
                .disabled(isWorking)
                .rise(beat >= 5)
                Text(verbatim: priceLine)
                    .laqtaFont(11.5)
                    .foregroundStyle(palette.ink3)
                    .rise(beat >= 5)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await BeatPlayer(gaps: [0.05, 0.22, 0.48, 0.3, 0.16]).play($beat, reduceMotion: reduceMotion)
        }
    }

    private var priceLine: String {
        String(localized: "After the trial, \(price) once — not a subscription.")
    }
}

// MARK: - The frame the feature chapters share

/// Eyebrow at the top, the visual in the middle, the sentence at the bottom.
/// Every feature chapter sits in this, so nothing jumps between them.
struct ChapterLayout<Visual: View, Caption: View>: View {
    let eyebrow: LocalizedStringKey
    let captionShown: Bool
    @ViewBuilder var visual: Visual
    @ViewBuilder var caption: Caption

    var body: some View {
        VStack(spacing: 0) {
            ChapterEyebrow(text: eyebrow)
                .padding(.top, 18)
                .rise(captionShown, by: 8)
            Spacer(minLength: 12)
            visual
            Spacer(minLength: 12)
            caption
                .rise(captionShown)
                .padding(.bottom, 96)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
