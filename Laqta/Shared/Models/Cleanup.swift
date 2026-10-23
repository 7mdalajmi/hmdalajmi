//
//  Cleanup.swift
//  Laqta — Shared
//
//  Three piles Laqta is fairly sure you do not need: shots you never once
//  opened, the same thing saved twice, and pictures it could read nothing out
//  of. It only ever proposes — the button moves them to the Trash, which holds
//  everything for thirty days.
//
//  The deciding is done here, on plain values, so the rules can be argued with
//  in a test instead of on a phone.
//

import Foundation

// MARK: - What a shot looks like to the scanner

nonisolated struct CleanupSubject: Sendable, Hashable, Identifiable {
    var itemID: UUID
    var byteCount: Int
    var addedAt: Date
    /// Set the first time the shot was opened, and never again.
    var viewedAt: Date?
    /// Same picture saved twice.
    var contentHash: String?
    /// Same moment out of Photos.
    var captureKey: String?
    var pixelWidth: Int
    var pixelHeight: Int
    /// How much readable text came out of it.
    var textLength: Int
    /// Whether Laqta has looked at it at all yet.
    var wasAnalyzed: Bool
    var isFavorite: Bool
    var hasNote: Bool
    /// A link or a PDF is never "blurry", and is never proposed on those grounds.
    var isPicture: Bool

    var id: UUID { itemID }

    var pixels: Int { pixelWidth * pixelHeight }

    /// Anything you marked or wrote on is yours, and is never proposed.
    var isSpokenFor: Bool { isFavorite || hasNote }
}

// MARK: - The piles

nonisolated enum CleanupPile: String, Sendable, CaseIterable, Identifiable {
    case neverOpened
    case duplicates
    case unreadable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neverOpened: "Never opened"
        case .duplicates: "Near-duplicates"
        case .unreadable: "Nothing readable"
        }
    }

    var detail: String {
        switch self {
        case .neverOpened: "Saved over six months ago and never once opened"
        case .duplicates: "The same thing saved two or three times"
        case .unreadable: "No text, no place, nothing Laqta could hold on to"
        }
    }

    var symbol: String {
        switch self {
        case .neverOpened: "eye.slash"
        case .duplicates: "square.on.square"
        case .unreadable: "questionmark.square.dashed"
        }
    }

    /// Only the first two are ticked to begin with. The third is a judgement call.
    var isOnByDefault: Bool { self != .unreadable }
}

nonisolated struct CleanupGroup: Sendable, Identifiable {
    var pile: CleanupPile
    var itemIDs: [UUID]
    var bytes: Int

    var id: String { pile.rawValue }
    var count: Int { itemIDs.count }
}

/// One family of near-identical shots: the one worth keeping, and the rest.
nonisolated struct SimilarGroup: Sendable, Identifiable {
    var keyID: UUID
    var keep: UUID
    var others: [UUID]

    var id: UUID { keyID }
    var count: Int { others.count + 1 }
}

// MARK: - The rules

nonisolated enum CleanupScanner {
    /// Six months untouched before Laqta will call a shot forgotten.
    static let neverOpenedDays = 180
    /// A picture it read nothing out of has to be old too — a shot taken an hour
    /// ago may simply not have been looked at yet.
    static let unreadableDays = 90

    static func scan(_ subjects: [CleanupSubject], now: Date = .now) -> [CleanupGroup] {
        var groups: [CleanupGroup] = []
        let duplicates = duplicateIDs(in: subjects)
        for pile in CleanupPile.allCases {
            let ids: [UUID]
            switch pile {
            case .neverOpened:
                ids = subjects.filter { isNeverOpened($0, now: now) && !duplicates.contains($0.itemID) }.map(\.itemID)
            case .duplicates:
                ids = subjects.filter { duplicates.contains($0.itemID) }.map(\.itemID)
            case .unreadable:
                ids = subjects.filter {
                    isUnreadable($0, now: now) && !duplicates.contains($0.itemID) && !isNeverOpened($0, now: now)
                }.map(\.itemID)
            }
            guard !ids.isEmpty else { continue }
            let byID = Dictionary(subjects.map { ($0.itemID, $0) }, uniquingKeysWith: { first, _ in first })
            let bytes = ids.reduce(0) { $0 + (byID[$1]?.byteCount ?? 0) }
            groups.append(CleanupGroup(pile: pile, itemIDs: ids, bytes: bytes))
        }
        return groups
    }

    static func isNeverOpened(_ subject: CleanupSubject, now: Date = .now) -> Bool {
        guard !subject.isSpokenFor, subject.viewedAt == nil else { return false }
        return subject.addedAt.addingTimeInterval(Double(neverOpenedDays) * 86_400) < now
    }

    static func isUnreadable(_ subject: CleanupSubject, now: Date = .now) -> Bool {
        guard !subject.isSpokenFor, subject.isPicture, subject.wasAnalyzed else { return false }
        guard subject.textLength == 0 else { return false }
        return subject.addedAt.addingTimeInterval(Double(unreadableDays) * 86_400) < now
    }

    // MARK: Near-duplicates

    /// Families of shots that are the same thing, with the one worth keeping named.
    static func similar(in subjects: [CleanupSubject]) -> [SimilarGroup] {
        var families: [String: [CleanupSubject]] = [:]
        for subject in subjects {
            // The exact same bytes first; failing that, the same moment out of Photos.
            guard let key = subject.contentHash ?? subject.captureKey, !key.isEmpty else { continue }
            families[key, default: []].append(subject)
        }
        return families.values
            .filter { $0.count > 1 }
            .compactMap { family -> SimilarGroup? in
                guard let keeper = best(of: family) else { return nil }
                let others = family.filter { $0.itemID != keeper.itemID && !$0.isSpokenFor }.map(\.itemID)
                guard !others.isEmpty else { return nil }
                return SimilarGroup(keyID: keeper.itemID, keep: keeper.itemID, others: others)
            }
            .sorted { $0.count > $1.count }
    }

    /// The one to keep: the readable one, then the biggest, then the one you kept first.
    static func best(of family: [CleanupSubject]) -> CleanupSubject? {
        family.max { lhs, rhs in
            if lhs.isSpokenFor != rhs.isSpokenFor { return rhs.isSpokenFor }
            if lhs.textLength != rhs.textLength { return lhs.textLength < rhs.textLength }
            if lhs.pixels != rhs.pixels { return lhs.pixels < rhs.pixels }
            return lhs.addedAt > rhs.addedAt
        }
    }

    private static func duplicateIDs(in subjects: [CleanupSubject]) -> Set<UUID> {
        Set(similar(in: subjects).flatMap(\.others))
    }
}
