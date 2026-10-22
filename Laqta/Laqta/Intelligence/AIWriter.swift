//
//  AIWriter.swift
//  Laqta
//
//  Apple's on-device language model (Foundation Models): titles, key points,
//  what's inside a link, and answers about a saved item.
//

import Foundation
import FoundationModels
import NaturalLanguage

@Generable
nonisolated struct PhotoInsight {
    @Guide(description: "A short English title for the saved image, two to five words, using the most specific name visible, for example 'Flight to London' or 'Oud Amber perfume'.")
    var title: String

    @Guide(description: "The name of one specific real place shown or mentioned, such as a landmark, restaurant, hotel or shop. An empty string when there is none.")
    var placeName: String

    @Guide(description: "Three short questions in English that someone might ask about this image.")
    var questions: [String]
}

@Generable
nonisolated struct KeyPoints {
    @Guide(description: "Three or four short bullet points in English. Each point is a single sentence.")
    var points: [String]
}

@Generable
nonisolated struct LinkInsight {
    @Guide(description: "Three to five short bullet points in English summarizing the content. Each point is a single sentence without web addresses.")
    var summary: [String]

    @Guide(description: "Real geographic places the content talks about: cities, neighborhoods, landmarks, restaurants, cafes, shops or hotels. Never companies, brands, software, people or websites. At most eight names, written as in the content. Empty when there are none.")
    var places: [String]

    @Guide(description: "Products or items with their prices exactly as written, like 'Oud Amber 100 ml: 38.000 KWD'. At most six. Empty when there are no prices.")
    var prices: [String]

    @Guide(description: "Up to four practical tips or recommendations from the content, in English, without web addresses. Empty when the content has no tips.")
    var tips: [String]

    @Guide(description: "Three short questions in English that someone might ask about this content.")
    var questions: [String]
}

@Generable
nonisolated struct ContentInsight {
    @Guide(description: "A short English title for the saved item, two to six words, using the most specific name in the content, for example 'Hotel booking in Paris' or 'Car insurance policy'.")
    var title: String

    @Guide(description: "Three to five short bullet points in English with the key facts: what it is, names, dates, amounts and next steps. Each point is a single sentence without web addresses.")
    var summary: [String]

    @Guide(description: "Real geographic places the content talks about: cities, neighborhoods, landmarks, restaurants, shops or hotels. Never companies, brands, software, people or websites. At most six names, written as in the content. Empty when there are none.")
    var places: [String]

    @Guide(description: "Three short questions in English that someone might ask about this content.")
    var questions: [String]
}

enum AIWriter {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var unavailableMessage: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return ""
        case let .unavailable(reason):
            switch reason {
            case .deviceNotEligible:
                return "This \(LaqtaDevice.name) doesn't support Apple Intelligence, so Laqta uses simpler on-device reading."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in Settings to get summaries and answers."
            case .modelNotReady:
                return "Apple Intelligence is still getting ready. Try again in a little while."
            @unknown default:
                return "Apple Intelligence isn't available right now."
            }
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }

    private static let instructions = """
    You help people understand things they saved on their iPhone or iPad: screenshots, photos, videos, PDFs and web links. \
    Use only the information in the provided content and never invent facts. Be brief and clear. \
    Write in English, but keep names of people, places, products and prices exactly as written.
    """

    // MARK: Requests

    static func photoInsight(context: String) async throws -> PhotoInsight {
        try await shrinking(context, limit: 2_400) { text in
            let session = LanguageModelSession(instructions: instructions)
            let prompt = "Here is what was found in a saved image.\n\n\(text)"
            return try await session.respond(to: prompt, generating: PhotoInsight.self).content
        }
    }

    static func keyPoints(for context: String, kind: String) async throws -> [String] {
        try await shrinking(context, limit: 2_800) { text in
            let session = LanguageModelSession(instructions: instructions)
            let prompt = "Give the key points of what this saved \(kind) says: the facts, names, dates, prices and next steps. Don't describe the file itself.\n\n\(text)"
            return try await session.respond(to: prompt, generating: KeyPoints.self).content.points
        }
    }

    static func linkInsight(title: String, site: String, kind: String, description: String?, body: String?) async throws -> LinkInsight {
        var notes = ""
        if let body, !body.isEmpty {
            if body.count > 2_600 {
                var pieces: [String] = []
                for chunk in chunks(of: body, size: 2_400, limit: 3) {
                    let piece = try? await shrinking(chunk, limit: 2_400) { text in
                        let session = LanguageModelSession(instructions: instructions)
                        let prompt = "Write compact notes, at most eight short lines, with the key facts, places, prices and tips in this part of a \(kind):\n\n\(text)"
                        return try await session.respond(to: prompt).content
                    }
                    if let piece { pieces.append(piece) }
                }
                notes = pieces.joined(separator: "\n")
            } else {
                notes = body
            }
        }
        let header = """
        A \(kind) from \(site).
        Title: \(title)
        Description: \(String((description ?? "").prefix(1_200)))
        """
        return try await shrinking(notes, limit: 2_200) { text in
            let session = LanguageModelSession(instructions: instructions)
            let prompt = "\(header)\nContent:\n\(text)\n\nExplain what is inside this \(kind)."
            return try await session.respond(to: prompt, generating: LinkInsight.self).content
        }
    }

    /// What a saved video (its speech and on-screen text) or PDF is about.
    static func contentInsight(kind: String, header: String, body: String) async throws -> ContentInsight {
        var notes = body
        if body.count > 2_600 {
            var pieces: [String] = []
            for chunk in chunks(of: body, size: 2_400, limit: 4) {
                let piece = try? await shrinking(chunk, limit: 2_400) { text in
                    let session = LanguageModelSession(instructions: instructions)
                    let prompt = "Write compact notes, at most eight short lines, with the key facts, names, dates, amounts and places in this part of a \(kind):\n\n\(text)"
                    return try await session.respond(to: prompt).content
                }
                if let piece { pieces.append(piece) }
            }
            if !pieces.isEmpty { notes = pieces.joined(separator: "\n") }
        }
        return try await shrinking(notes, limit: 2_200) { text in
            let session = LanguageModelSession(instructions: instructions)
            let prompt = "\(header)\nContent:\n\(text)\n\nExplain what is in this \(kind)."
            return try await session.respond(to: prompt, generating: ContentInsight.self).content
        }
    }

    static func answer(question: String, context: String, history: [(fromUser: Bool, text: String)]) async throws -> String {
        let conversation = history.suffix(4).map { ($0.fromUser ? "Question: " : "Answer: ") + $0.text }.joined(separator: "\n")
        return try await shrinking(context, limit: 2_400) { text in
            let session = LanguageModelSession(instructions: instructions + " Answer questions about the saved item in two or three sentences. If the content doesn't say, reply that it isn't shown.")
            let prompt = "Saved item:\n\(text)\n\n\(conversation)\nQuestion: \(question)"
            return try await session.respond(to: prompt).content
        }
    }

    // MARK: Helpers

    /// Retries with less text when the context window is exceeded.
    private static func shrinking<T>(_ text: String, limit: Int, _ work: (String) async throws -> T) async throws -> T {
        var budget = limit
        while true {
            do {
                return try await work(String(text.prefix(budget)))
            } catch {
                if isContextOverflow(error), budget > 600 {
                    budget /= 2
                    continue
                }
                throw error
            }
        }
    }

    private static func isContextOverflow(_ error: any Error) -> Bool {
        let description = String(describing: error).lowercased()
        return description.contains("contextwindow") || description.contains("context window")
    }

    /// The model is busy or limited (for example while the app is in the background).
    static func isRateLimited(_ error: any Error) -> Bool {
        let description = String(describing: error).lowercased()
        return description.contains("ratelimited") || description.contains("rate limited") || description.contains("concurrentrequests")
    }

    static func chunks(of text: String, size: Int, limit: Int) -> [String] {
        var result: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n") {
            if current.count + paragraph.count > size, !current.isEmpty {
                result.append(current)
                current = ""
                if result.count == limit { break }
            }
            current += String(paragraph.prefix(size)) + "\n"
        }
        if !current.isEmpty, result.count < limit {
            result.append(current)
        }
        return result
    }
}

/// Picks real sentences when the language model isn't available.
nonisolated enum ExtractiveSummary {
    static func points(from text: String, limit: Int = 4) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count >= 30, sentence.count <= 240, !sentence.contains("http"), !sentence.contains("#") {
                sentences.append(sentence)
            }
            return sentences.count < limit
        }
        if sentences.isEmpty {
            sentences = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count >= 12 }
                .prefix(limit)
                .map { $0 }
        }
        return sentences
    }
}

/// Text the model reads for an item.
enum PromptContext {
    /// Whether a photo gives the model anything to work with. Told only "a photo",
    /// the model describes things that aren't there.
    static func hasPhotoDetails(_ analysis: ShotAnalysis) -> Bool {
        if let text = analysis.text, !text.isEmpty { return true }
        return !analysis.labels.isEmpty || !analysis.entities.isEmpty || analysis.place != nil
    }

    static func photo(_ analysis: ShotAnalysis, kindLabel: String) -> String {
        var lines: [String] = []
        lines.append("Kind: \(kindLabel)")
        if let source = analysis.source, source.app != "Photos", source.app != "Screenshot" {
            lines.append("Source: \(source.app)")
        }
        if let category = analysis.category { lines.append("Category: \(category)") }
        if !analysis.labels.isEmpty { lines.append("Looks like: \(analysis.labels.joined(separator: ", "))") }
        if let place = analysis.place {
            lines.append("Place: \(place.name)" + (place.detail.map { ", \($0)" } ?? ""))
        }
        if !analysis.entities.isEmpty {
            lines.append("Details: " + analysis.entities.prefix(8).map(\.display).joined(separator: "; "))
        }
        if let text = analysis.text, !text.isEmpty {
            lines.append("Text in the image:\n\(text)")
        }
        return lines.joined(separator: "\n")
    }

    static func item(_ item: Shot, question: String? = nil) -> String {
        let analysis = item.analysis ?? ShotAnalysis()
        var context: String
        switch item.kind {
        case .photo:
            context = photo(analysis, kindLabel: item.kindLabel)
            if !analysis.summary.isEmpty {
                context = "Summary: " + analysis.summary.joined(separator: " ") + "\n" + context
            }
        case .video:
            context = video(item, analysis: analysis, question: question)
        case .document:
            context = document(item, analysis: analysis, question: question)
        case .link:
            context = link(item, analysis: analysis)
        }
        if !item.note.isEmpty {
            context = "The user's note: \(item.note)\n" + context
        }
        return context
    }

    static func video(_ item: Shot, analysis: ShotAnalysis, question: String?) -> String {
        var lines: [String] = ["Kind: \(item.kindLabel)"]
        if let duration = item.mediaDuration { lines.append("Length: \(LaqtaFormat.duration(duration))") }
        if let captured = item.capturedAt { lines.append("Recorded: \(LaqtaFormat.dateTime(captured))") }
        if let place = analysis.place { lines.append("Place: \(place.name)" + (place.detail.map { ", \($0)" } ?? "")) }
        if !analysis.labels.isEmpty { lines.append("Looks like: \(analysis.labels.joined(separator: ", "))") }
        if !analysis.summary.isEmpty { lines.append("Summary: " + analysis.summary.joined(separator: " ")) }
        if let transcript = analysis.transcript, !transcript.isEmpty {
            let spoken = transcript.map { "[\(LaqtaFormat.duration($0.seconds))] \($0.text)" }.joined(separator: "\n")
            lines.append("What is said:\n" + relevantExcerpt(of: spoken, for: question, limit: 1_400))
        }
        if let text = analysis.text, !text.isEmpty {
            lines.append("Text on screen:\n" + relevantExcerpt(of: text, for: question, limit: 700))
        }
        return lines.joined(separator: "\n")
    }

    static func document(_ item: Shot, analysis: ShotAnalysis, question: String?) -> String {
        var lines: [String] = ["Kind: PDF" + (analysis.category.map { " (\($0))" } ?? "")]
        lines.append("Title: \(item.displayTitle)")
        if let pages = item.documentPages { lines.append("Pages: \(pages)") }
        if !analysis.summary.isEmpty { lines.append("Summary: " + analysis.summary.joined(separator: " ")) }
        if !analysis.entities.isEmpty {
            lines.append("Details: " + analysis.entities.prefix(10).map(\.display).joined(separator: "; "))
        }
        if let text = analysis.text, !text.isEmpty {
            lines.append("Text:\n" + relevantExcerpt(of: text, for: question, limit: 1_800))
        }
        return lines.joined(separator: "\n")
    }

    static func link(_ item: Shot, analysis: ShotAnalysis) -> String {
        var lines: [String] = [
            "\(item.linkForm.label) from \(item.linkSite ?? "the web")",
            "Title: \(item.linkTitle ?? "")"
        ]
        if let author = item.linkAuthor { lines.append("By: \(author)") }
        if let duration = item.linkDuration { lines.append("Length: \(LaqtaFormat.duration(duration))") }
        if !analysis.summary.isEmpty { lines.append("Summary: " + analysis.summary.joined(separator: " ")) }
        if !analysis.sections.isEmpty {
            lines.append("Chapters: " + analysis.sections.map { chapter in
                chapter.seconds >= 0 ? "\(LaqtaFormat.duration(chapter.seconds)) \(chapter.title)" : chapter.title
            }.joined(separator: "; "))
        }
        if !analysis.places.isEmpty { lines.append("Places: " + analysis.places.map(\.name).joined(separator: ", ")) }
        if !analysis.prices.isEmpty { lines.append("Prices: " + analysis.prices.map { "\($0.label): \($0.value)" }.joined(separator: "; ")) }
        if !analysis.tips.isEmpty { lines.append("Tips: " + analysis.tips.joined(separator: " ")) }
        if let details = item.linkDetails { lines.append("Description: \(details)") }
        return lines.joined(separator: "\n")
    }

    /// The parts of a long text that share the most words with the question, in their original order.
    nonisolated static func relevantExcerpt(of text: String, for question: String?, limit: Int) -> String {
        guard text.count > limit else { return text }
        let paragraphs = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let question, !question.isEmpty else { return String(text.prefix(limit)) }
        let wanted = Set(words(in: question))
        guard !wanted.isEmpty else { return String(text.prefix(limit)) }
        let scored = paragraphs.enumerated().map { index, paragraph in
            (index: index, score: Set(words(in: paragraph)).intersection(wanted).count, paragraph: paragraph)
        }
        var chosen: [(index: Int, paragraph: String)] = []
        var total = 0
        for entry in scored.sorted(by: { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }) {
            guard entry.score > 0 || chosen.count < 3 else { break }
            if total + entry.paragraph.count > limit { continue }
            chosen.append((entry.index, entry.paragraph))
            total += entry.paragraph.count + 1
        }
        return chosen.sorted { $0.index < $1.index }.map(\.paragraph).joined(separator: "\n")
    }

    nonisolated static func words(in text: String) -> [String] {
        SearchIndex.normalize(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }
}
