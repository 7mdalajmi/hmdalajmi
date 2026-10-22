//
//  LibraryQuestion.swift
//  Laqta
//
//  Ask the library a question in plain words — "وين اللقطة اللي فيها ساعة بـ ٤٢٠٠؟"
//  — instead of guessing which word you typed on the day.
//
//  Two steps, both on the phone. The ordinary search narrows the whole library
//  down to a handful of likely shots; the on-device model is then shown only
//  those, numbered, and asked to answer from them and say which one it meant.
//  The model never sees the library, only the shortlist, and the question never
//  leaves the device.
//

import FoundationModels
import Foundation
import Observation

// MARK: - What the model is asked for

@Generable
nonisolated struct LibraryAnswer {
    @Guide(description: "One or two sentences answering the question, in the same language the question was asked in. If the shots do not say, reply that they do not.")
    var answer: String

    @Guide(description: "The number of the single best matching shot from the numbered list, or 0 when none of them match.")
    var best: Int

    @Guide(description: "Up to three more numbers from the list that are also close, separated by commas. An empty string when there are none.")
    var others: String
}

// MARK: - The shortlist

nonisolated struct LibraryCandidate: Sendable, Hashable, Identifiable {
    /// 1-based, as shown to the model.
    var number: Int
    var itemID: UUID
    var folderID: UUID?
    var title: String
    var folderName: String
    var savedOn: Date
    /// A short piece of what the shot actually says.
    var excerpt: String

    var id: UUID { itemID }
}

nonisolated struct LibraryReply: Sendable {
    var text: String
    var bestID: UUID?
    var otherIDs: [UUID]
}

// MARK: - Asking

nonisolated enum LibraryAsk {
    /// More than this and the shortlist stops fitting in the model's window.
    static let maxCandidates = 12
    /// Enough of each shot to recognise it by, not enough to drown the rest.
    static let excerptLimit = 260

    private static let questionWords: Set<String> = [
        "what", "where", "when", "which", "who", "how", "why", "did", "do", "is", "was", "show", "find",
        "وين", "شنو", "متى", "كم", "ليش", "أي", "اي", "من", "هل", "كيف", "وش", "ابغى", "أبغى", "ابي", "أبي"
    ]

    /// Worth offering the model, rather than a plain substring search.
    static func looksLikeAQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return false }
        if trimmed.hasSuffix("?") || trimmed.hasSuffix("؟") { return true }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard words.count >= 3 else { return false }
        let first = words[0].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "،,."))
        return questionWords.contains(first) || words.count >= 4
    }

    /// The numbered shortlist the model is shown. Nothing else reaches it.
    static func context(for candidates: [LibraryCandidate]) -> String {
        candidates.map { candidate in
            var line = "\(candidate.number). \(candidate.title)"
            if !candidate.folderName.isEmpty { line += " — \(candidate.folderName)" }
            line += " — saved \(LaqtaFormat.shortDate(candidate.savedOn))"
            let excerpt = candidate.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !excerpt.isEmpty {
                line += "\n   \(String(excerpt.prefix(excerptLimit)).replacingOccurrences(of: "\n", with: " "))"
            }
            return line
        }.joined(separator: "\n")
    }

    /// "2, 5, 9" → [2, 5, 9], dropping anything outside the list it was given.
    static func picks(in raw: String, within count: Int) -> [Int] {
        var seen = Set<Int>()
        return raw
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .filter { (1...max(count, 1)).contains($0) }
            .filter { seen.insert($0).inserted }
    }

    /// Turns what the model said back into shots from the shortlist it was shown.
    static func reply(from raw: LibraryAnswer, candidates: [LibraryCandidate]) -> LibraryReply {
        let byNumber = Dictionary(uniqueKeysWithValues: candidates.map { ($0.number, $0.itemID) })
        let best = (1...max(candidates.count, 1)).contains(raw.best) ? byNumber[raw.best] : nil
        let others = picks(in: raw.others, within: candidates.count)
            .compactMap { byNumber[$0] }
            .filter { $0 != best }
        return LibraryReply(
            text: raw.answer.trimmingCharacters(in: .whitespacesAndNewlines),
            bestID: best,
            otherIDs: Array(others.prefix(3))
        )
    }

    static let instructions = """
    You answer questions about shots someone saved on their own phone: screenshots, photos, PDFs and links. \
    You are given a short numbered list and nothing else. Answer only from that list and never invent a shot, \
    a price, a date or a name. Answer in the same language the question was asked in, in one or two sentences. \
    Keep names, prices and numbers exactly as they are written.
    """
}

// MARK: - What the search screen holds

@Observable
@MainActor
final class LibraryAskModel {
    /// Apple Intelligence lives on the app side, so asking does too.
    static var isAvailable: Bool { AIWriter.isAvailable }
    static var unavailableMessage: String { AIWriter.unavailableMessage }

    enum State: Equatable {
        case idle
        case thinking
        case answered(LibraryAnswerView)
        case failed(String)
    }

    /// The reply, flattened into what the view draws.
    struct LibraryAnswerView: Equatable {
        var question: String
        var text: String
        var bestID: UUID?
        var otherIDs: [UUID]
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    var isThinking: Bool { state == .thinking }

    func reset() {
        task?.cancel()
        task = nil
        state = .idle
    }

    func ask(_ question: String, candidates: [LibraryCandidate]) {
        task?.cancel()
        state = .thinking
        task = Task {
            do {
                let reply = try await Self.answer(question: question, candidates: candidates)
                guard !Task.isCancelled else { return }
                state = .answered(LibraryAnswerView(
                    question: question,
                    text: reply.text,
                    bestID: reply.bestID,
                    otherIDs: reply.otherIDs
                ))
            } catch {
                guard !Task.isCancelled else { return }
                if AIWriter.isRateLimited(error) {
                    state = .failed(String(localized: "Apple Intelligence is busy. Try again in a moment."))
                } else {
                    state = .failed(String(localized: "That one could not be answered on this phone."))
                }
            }
        }
    }

    // MARK: The model call

    private static func answer(question: String, candidates: [LibraryCandidate]) async throws -> LibraryReply {
        guard !candidates.isEmpty else {
            return LibraryReply(
                text: String(localized: "Nothing in the library comes close to that."),
                bestID: nil,
                otherIDs: []
            )
        }
        let list = LibraryAsk.context(for: candidates)
        let raw = try await shrinking(list, limit: 3_000) { text in
            let session = LanguageModelSession(instructions: LibraryAsk.instructions)
            let prompt = """
            Saved shots, numbered:
            \(text)

            Question: \(question)
            """
            return try await session.respond(to: prompt, generating: LibraryAnswer.self).content
        }
        return LibraryAsk.reply(from: raw, candidates: candidates)
    }

    /// Retries with less of the shortlist when the window is exceeded.
    private static func shrinking<T>(_ text: String, limit: Int, _ work: (String) async throws -> T) async throws -> T {
        var budget = limit
        while true {
            do {
                return try await work(String(text.prefix(budget)))
            } catch {
                let described = String(describing: error).lowercased()
                let overflow = described.contains("contextwindow") || described.contains("context window")
                guard overflow, budget > 700 else { throw error }
                budget /= 2
            }
        }
    }
}
