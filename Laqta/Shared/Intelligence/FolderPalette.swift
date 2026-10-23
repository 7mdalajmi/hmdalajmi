//
//  FolderPalette.swift
//  Laqta — Shared
//
//  Which of the fifty-six cover moods a new folder gets.
//
//  Two rules, in order. A folder whose name means something — Travel, عطور,
//  Receipts — leans toward the family that suits it, and a name that says a
//  colour outright gets that colour. Everything else falls to the name's own
//  fingerprint, so the same name always lands on the same mood.
//
//  Either way the choice comes out of what is *left*: a mood already on one of
//  your folders is passed over until the whole set has been used once.
//

import Foundation

nonisolated enum FolderPalette {
    // MARK: Naming a colour outright

    /// "Blue folder" should be blue. Arabic and English both.
    private static let colourWords: [(words: [String], family: FolderToneFamily)] = [
        (["blue", "navy", "sea", "ocean", "sky", "ازرق", "أزرق", "بحر", "سماء", "سماوي", "كحلي"], .blue),
        (["green", "mint", "اخضر", "أخضر", "زيتي", "نعناع"], .green),
        (["gold", "golden", "yellow", "sand", "beige", "cream", "ذهب", "ذهبي", "اصفر", "أصفر", "رملي", "بيج", "كريمي"], .gold),
        (["red", "orange", "brown", "copper", "احمر", "أحمر", "برتقالي", "بني", "نحاسي", "طيني"], .warm),
        (["purple", "violet", "indigo", "بنفسجي", "موف", "ارجواني", "أرجواني", "نيلي"], .violet),
        (["pink", "rose", "wine", "وردي", "زهري", "نبيتي", "خمري"], .rose),
        (["black", "grey", "gray", "silver", "stone", "اسود", "أسود", "رمادي", "فضي", "حجري"], .stone)
    ]

    /// What each of the suggester's categories leans toward, best first.
    private static let categoryFamilies: [String: [FolderToneFamily]] = [
        "travel": [.blue, .gold],
        "perfume": [.warm, .gold],
        "cities": [.blue, .stone],
        "food": [.warm, .gold],
        "shopping": [.gold, .rose],
        "tech": [.blue, .stone],
        "learning": [.green, .blue],
        "fitness": [.green, .blue],
        "documents": [.stone, .gold],
        "home": [.gold, .warm],
        "cars": [.stone, .blue],
        "fashion": [.rose, .violet],
        "watch": [.violet, .blue],
        "music": [.violet, .rose],
        "events": [.warm, .violet]
    ]

    // MARK: Choosing

    /// The families this name leans toward, most wanted first. Empty when the
    /// name means nothing in particular — which is most names.
    static func families(forName name: String) -> [FolderToneFamily] {
        let normalized = SearchIndex.normalize(name)
        guard !normalized.isEmpty else { return [] }

        // A named colour wins outright: it is the one thing the user said plainly.
        for entry in colourWords where entry.words.contains(where: { normalized.contains(SearchIndex.normalize($0)) }) {
            return [entry.family]
        }
        if let category = FolderSuggester.category(forName: name), let wanted = categoryFamilies[category.id] {
            return wanted
        }
        if normalized.contains("خاص") || normalized.contains("private") || normalized.contains("سري") {
            return [.stone]
        }
        return []
    }

    /// The mood for a folder called `name`, given the moods already in use.
    ///
    /// Deterministic: the same name with the same folders around it always gets
    /// the same answer, so nothing shuffles under the user between launches.
    static func pick(name: String, taken: Set<FolderTone>) -> FolderTone {
        let every = FolderTone.allCases
        // Once all fifty-six are out, start the set again rather than refusing.
        var free = every.filter { !taken.contains($0) }
        if free.isEmpty { free = every }

        let seed = fingerprint(SearchIndex.normalize(name))
        for family in families(forName: name) {
            let inFamily = free.filter { $0.family == family }
            if let choice = choose(from: inFamily, seed: seed) { return choice }
        }
        return choose(from: free, seed: seed) ?? .sand
    }

    /// Convenience for the common case: pick around the folders that exist.
    static func pick(name: String, existing: [FolderTone]) -> FolderTone {
        pick(name: name, taken: Set(existing))
    }

    private static func choose(from tones: [FolderTone], seed: UInt64) -> FolderTone? {
        guard !tones.isEmpty else { return nil }
        return tones[Int(seed % UInt64(tones.count))]
    }

    /// FNV-1a. Swift's own hashing is seeded per launch, which would move a
    /// folder's colour every time the app started.
    static func fingerprint(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
