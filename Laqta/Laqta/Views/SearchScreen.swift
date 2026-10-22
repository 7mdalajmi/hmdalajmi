//
//  SearchScreen.swift
//  Laqta
//
//  Search inside text, speech, PDFs, places, sources, notes and links.
//  Private folders stay hidden until unlocked.
//

import Foundation
import SwiftData
import SwiftUI

struct SearchScreen: View {
    @Binding var path: [Route]

    @AppObject(LockManager.self) private var lock
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.laqta) private var palette

    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }) private var folders: [Folder]
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var suggestions: [String] = []
    @State private var ask = LibraryAskModel()
    @FocusState private var focused: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Worth offering the model rather than a plain word search.
    private var canAsk: Bool {
        LibraryAskModel.isAvailable && LibraryAsk.looksLikeAQuestion(trimmedQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .laqtaIconFont(15, weight: .medium)
                        .foregroundStyle(palette.ink2)
                    TextField(text: $query, prompt: Text("Places, text, notes, links…").foregroundStyle(palette.ink3)) {
                        Text("Search")
                    }
                    .laqtaFont(16)
                    .foregroundStyle(palette.ink)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark")
                                .laqtaIconFont(11, weight: .bold)
                                .foregroundStyle(palette.ink2)
                                .frame(width: 30, height: 30)
                                .background(palette.field, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Clear"))
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .padding(.vertical, 4)
                .frame(minHeight: 44)
                .background(palette.field, in: Capsule())
                .overlay(Capsule().strokeBorder(palette.buttonBorder, lineWidth: 1))

                Button("Cancel") {
                    dismiss()
                }
                .laqtaFont(16)
                .foregroundStyle(palette.goldHi)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        idle
                    } else {
                        if canAsk {
                            AskLibraryCard(question: trimmedQuery, model: ask) {
                                ask.ask(trimmedQuery, candidates: candidates())
                            } onOpen: { itemID in
                                openItem(itemID)
                            }
                        }
                        SectionLabel(verbatim: results.isEmpty ? String(localized: "No results") : LaqtaFormat.count(results.count, "result", "results"))
                            .padding(.bottom, 4)
                        ForEach(results) { result in
                            Button {
                                open(result)
                            } label: {
                                SearchRow(result: result, query: query, isLocked: isLocked(result))
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(LaqtaBackground())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            focused = true
            suggestions = SearchEngine.suggestions(context: modelContext, canShow: lock.canShow)
        }
        .task(id: query) {
            // A new question is a new question; the old answer goes with it.
            ask.reset()
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) {
                results = SearchEngine.search(query, context: modelContext)
            }
        }
    }

    // MARK: Asking

    /// The shortlist the model is shown: what the ordinary search already found,
    /// minus anything behind a lock, numbered from one.
    private func candidates() -> [LibraryCandidate] {
        var made: [LibraryCandidate] = []
        for result in results where !isLocked(result) {
            guard made.count < LibraryAsk.maxCandidates,
                  let item = LaqtaStore.item(with: result.id, context: modelContext) else { continue }
            made.append(LibraryCandidate(
                number: made.count + 1,
                itemID: item.id,
                folderID: item.folderID,
                title: item.displayTitle,
                folderName: result.folderName,
                savedOn: item.addedAt,
                excerpt: item.analysis?.text ?? item.searchText ?? result.snippet
            ))
        }
        return made
    }

    private func openItem(_ itemID: UUID) {
        guard let result = results.first(where: { $0.id == itemID }) else { return }
        open(result)
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !suggestions.isEmpty {
                SectionLabel("Try")
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            query = suggestion
                        } label: {
                            TagChip(text: suggestion, systemImage: "magnifyingglass", large: true)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(Text("Search for \(suggestion)"))
                    }
                }
            }
            Text("Search finds words inside your photos, videos and PDFs, places they show, your notes, and everything Laqta read from your links.")
                .laqtaFont(13)
                .foregroundStyle(palette.ink2)
                .padding(.top, 8)
        }
    }

    private func isLocked(_ result: SearchResult) -> Bool {
        guard let folder = folders.first(where: { $0.id == result.folderID }) else { return false }
        return !lock.canShow(folder)
    }

    private func open(_ result: SearchResult) {
        guard let folderID = result.folderID else { return }
        let go = {
            switch result.kind {
            case .link:
                path.append(.link(result.id))
            case .document:
                path.append(.document(result.id))
            case .photo, .video:
                path.append(.viewer(folderID: folderID, startID: result.id))
            }
        }
        if isLocked(result) {
            Task {
                if await lock.unlock(folderID) { go() }
            }
        } else {
            go()
        }
    }
}

struct SearchResult: Identifiable {
    let id: UUID
    let folderID: UUID?
    let folderName: String
    let kind: ItemKind
    var isLink: Bool { kind == .link }
    let title: String
    let snippet: String
    let why: String
    let whySymbol: String
    let thumbnailURL: URL
    let originalURL: URL?
    let hasThumbnail: Bool
    let site: String?
    /// YouTube thumbnails are shown from YouTube, whole and never blurred.
    var remoteURL: URL? = nil
    var isYouTube = false
}

enum SearchEngine {
    static func search(_ rawQuery: String, context: ModelContext) -> [SearchResult] {
        let query = SearchIndex.normalize(rawQuery.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return [] }
        let folders = LaqtaStore.foldersByUpdate(context)
        let names = Dictionary(folders.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let matchingFolders = Set(folders.filter { SearchIndex.normalize($0.name).contains(query) }.map(\.id))

        let descriptor = FetchDescriptor<Shot>(
            predicate: #Predicate<Shot> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        let items = ((try? context.fetch(descriptor)) ?? []).filter { item in
            item.folderID.map { names[$0] != nil } ?? true
        }
        var results: [SearchResult] = []
        for item in items {
            let index = item.searchText ?? SearchIndex.text(for: item, analysis: item.analysis)
            let inFolder = item.folderID.map { matchingFolders.contains($0) } ?? false
            guard index.contains(query) || inFolder else { continue }
            let match = explain(item, query: query) ?? (inFolder ? Match(snippet: item.displayTitle, why: "Folder", symbol: "folder") : nil)
            guard let match else { continue }
            results.append(SearchResult(
                id: item.id,
                folderID: item.folderID,
                folderName: item.folderID.flatMap { names[$0] } ?? "",
                kind: item.kind,
                title: item.displayTitle,
                snippet: match.snippet,
                why: match.why,
                whySymbol: match.symbol,
                thumbnailURL: item.thumbnailURL,
                originalURL: item.hasMediaFile && !item.isLink ? item.fileURL : nil,
                hasThumbnail: item.hasThumbnail || item.hasMediaFile || item.remoteImageURL != nil,
                site: item.linkSite,
                remoteURL: item.remoteImageURL,
                isYouTube: item.isYouTube
            ))
            if results.count >= 60 { break }
        }
        return results
    }

    struct Match {
        let snippet: String
        let why: String
        let symbol: String
    }

    private static func explain(_ item: Shot, query: String) -> Match? {
        let analysis = item.analysis
        func check(_ text: String?, why: String, symbol: String) -> Match? {
            guard let text, let snippet = snippet(in: text, query: query) else { return nil }
            return Match(snippet: snippet, why: why, symbol: symbol)
        }
        if let match = check(item.note, why: "Note", symbol: "note.text") { return match }
        if let place = analysis?.place {
            if let match = check([place.name, place.detail, place.category].compactMap { $0 }.joined(separator: " · "), why: "Place", symbol: "mappin.and.ellipse") { return match }
        }
        if item.isDocument {
            if let match = check(item.documentTitle ?? item.originalName, why: "PDF", symbol: "doc.richtext") { return match }
            for section in analysis?.sections ?? [] {
                let label = section.page.map { "Page \($0)" } ?? "Section"
                if let match = check(section.title, why: label, symbol: "list.bullet") { return match }
            }
        }
        if item.isVideoFile {
            for line in analysis?.transcript ?? [] {
                if let match = check(line.text, why: "Said at \(LaqtaFormat.duration(line.seconds))", symbol: "text.bubble") { return match }
            }
        }
        if item.isLink {
            if let match = check(item.linkTitle, why: item.linkForm.label, symbol: item.linkForm.systemImage) { return match }
            for chapter in analysis?.sections ?? [] {
                let label = chapter.seconds >= 0 ? "At \(LaqtaFormat.duration(chapter.seconds))" : "Section"
                if let match = check(chapter.title, why: label, symbol: "list.bullet") { return match }
            }
            for place in analysis?.places ?? [] {
                if let match = check([place.name, place.detail].compactMap { $0 }.joined(separator: " · "), why: "Place", symbol: "mappin.and.ellipse") { return match }
            }
            for price in analysis?.prices ?? [] {
                if let match = check("\(price.label) · \(price.value)", why: "Price", symbol: "tag") { return match }
            }
            if let match = check(analysis?.summary.joined(separator: " "), why: "Summary", symbol: "sparkles") { return match }
            if let match = check(item.linkDetails, why: "Description", symbol: "text.alignleft") { return match }
            if let match = check([item.linkSite, item.linkAuthor].compactMap { $0 }.joined(separator: " · "), why: "Site", symbol: "globe") { return match }
        }
        if let match = check(analysis?.title, why: analysis?.category ?? "Title", symbol: "sparkles") { return match }
        if let match = check(analysis?.text, why: "In text", symbol: "text.viewfinder") { return match }
        for entity in analysis?.entities ?? [] {
            if let match = check(entity.display, why: entity.kind == .price ? "Price" : "In text", symbol: entity.systemImage) { return match }
        }
        if let source = analysis?.source {
            if let match = check([source.headline, source.detail].compactMap { $0 }.joined(separator: " · "), why: "Source", symbol: source.systemImage) { return match }
        }
        if let match = check(analysis?.labels.joined(separator: " · "), why: "Photo", symbol: "photo") { return match }
        if let match = check(analysis?.summary.joined(separator: " "), why: "Summary", symbol: "sparkles") { return match }
        if let match = check(item.originalName, why: "File name", symbol: "doc") { return match }
        return nil
    }

    /// "…arakiya · Al-Qibla, Kuwait City"
    static func snippet(in text: String, query: String) -> String? {
        let flat = text.replacingOccurrences(of: "\n", with: " · ")
        let normalized = SearchIndex.normalize(flat)
        guard let range = normalized.range(of: query) else { return nil }
        let startOffset = normalized.distance(from: normalized.startIndex, to: range.lowerBound)
        let characters = Array(flat)
        guard startOffset <= characters.count else { return flat }
        let from = max(0, startOffset - 22)
        let to = min(characters.count, startOffset + query.count + 48)
        var result = String(characters[from..<to])
        if from > 0 { result = "…" + result }
        if to < characters.count { result += "…" }
        return result
    }

    static func suggestions(context: ModelContext, canShow: (Folder) -> Bool) -> [String] {
        let folders = LaqtaStore.foldersByUpdate(context)
        let hidden = Set(folders.filter { !canShow($0) }.map(\.id))
        var descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.tagsRaw != nil && $0.deletedAt == nil }, sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        descriptor.fetchLimit = 60
        let items = ((try? context.fetch(descriptor)) ?? []).filter { item in
            guard let folderID = item.folderID else { return true }
            return !hidden.contains(folderID)
        }
        var result: [String] = []
        func add(_ value: String?) {
            guard let value, !value.isEmpty, value.count <= 28, !result.contains(value) else { return }
            result.append(value)
        }
        for item in items {
            let analysis = item.analysis
            add(analysis?.place?.name)
            add(analysis?.category)
            add(item.linkSite)
            if result.count >= 8 { break }
        }
        return result
    }
}

private struct SearchRow: View {
    let result: SearchResult
    let query: String
    let isLocked: Bool

    @Environment(\.laqta) private var palette
    /// Amiri is taller than the system font; this keeps its line as tight as the text around it.
    @ScaledMetric(relativeTo: .footnote) private var folderLineHeight: CGFloat = 15

    var body: some View {
        HStack(spacing: 12) {
            thumb
            VStack(alignment: .leading, spacing: 3) {
                if isLocked {
                    Text("Match in a locked folder")
                        .laqtaFont(15, weight: .semibold)
                        .foregroundStyle(palette.ink)
                    Text("Unlock with Face ID to see it")
                        .laqtaFont(13)
                        .foregroundStyle(palette.ink2)
                } else {
                    Text(verbatim: result.title)
                        .laqtaFont(15, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .adaptiveLineLimit(1, accessibility: 2)
                    Text(highlighted)
                        .laqtaFont(13)
                        .foregroundStyle(palette.ink2)
                        .adaptiveLineLimit(1, accessibility: 2)
                }
                HStack(spacing: 5) {
                    Image(systemName: isLocked ? "lock" : result.whySymbol)
                        .laqtaIconFont(10, weight: .semibold)
                    Text(verbatim: isLocked ? "Private" : result.why)
                    Text(verbatim: "·")
                        .accessibilityHidden(true)
                    FolderNameText(name: result.folderName, size: 13, color: palette.goldHi)
                        .frame(height: folderLineHeight)
                }
                .laqtaFont(12)
                .foregroundStyle(palette.goldHi)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .laqtaIconFont(12, weight: .semibold)
                .foregroundStyle(palette.ink3)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 84)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.line).frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var highlighted: AttributedString {
        var value = AttributedString(result.snippet)
        let normalizedSnippet = SearchIndex.normalize(result.snippet)
        let normalizedQuery = SearchIndex.normalize(query.trimmingCharacters(in: .whitespaces))
        guard !normalizedQuery.isEmpty, let range = normalizedSnippet.range(of: normalizedQuery) else { return value }
        let offset = normalizedSnippet.distance(from: normalizedSnippet.startIndex, to: range.lowerBound)
        guard offset + normalizedQuery.count <= result.snippet.count else { return value }
        let start = value.index(value.startIndex, offsetByCharacters: offset)
        let end = value.index(start, offsetByCharacters: normalizedQuery.count)
        value[start..<end].backgroundColor = palette.hit
        value[start..<end].foregroundColor = palette.ink
        return value
    }

    @ViewBuilder
    private var thumb: some View {
        Group {
            if isLocked {
                palette.field
            } else if result.isYouTube, let remoteURL = result.remoteURL {
                ShotThumbnail(thumbnailURL: result.thumbnailURL, originalURL: nil, kind: .photo, remoteURL: remoteURL, fits: true)
                    .background(Color(hex: 0x0A0908))
            } else if result.hasThumbnail {
                ShotThumbnail(thumbnailURL: result.thumbnailURL, originalURL: result.originalURL, kind: result.kind.mediaKind ?? .photo, remoteURL: result.remoteURL)
            } else if result.isLink {
                GenericLinkArt(site: "")
            } else {
                palette.field
            }
        }
        .frame(width: 48, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            if isLocked {
                Image(systemName: "lock")
                    .laqtaIconFont(14, weight: .semibold)
                    .foregroundStyle(Color(hex: 0xF2E4C4))
            }
        }
    }
}
