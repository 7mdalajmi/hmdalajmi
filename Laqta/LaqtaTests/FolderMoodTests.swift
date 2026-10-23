//
//  FolderMoodTests.swift
//  LaqtaTests
//
//  Fifty-six moods, and the rules for handing one to a new folder: never a
//  colour already in use, leaning toward what the name means, and the same
//  answer every time so nothing shuffles between launches.
//

import Foundation
import Testing
@testable import Laqta

@Suite("Cover moods")
struct FolderMoodTests {
    @Test func thereAreFiftySixOfThem_allDifferent() {
        #expect(FolderTone.allCases.count >= 50)
        #expect(FolderTone.allCases.count == 56)
        let raws = Set(FolderTone.allCases.map(\.rawValue))
        #expect(raws.count == FolderTone.allCases.count)
        let titles = Set(FolderTone.allCases.map(\.title))
        #expect(titles.count == FolderTone.allCases.count)
    }

    @Test func everyMoodBuildsNineColoursAndNoneRepeatsAnother() {
        var seen: [String: FolderTone] = [:]
        for tone in FolderTone.allCases {
            let mesh = FolderTone.meshHexes(tone)
            #expect(mesh.count == 9, "\(tone.rawValue) is not a 3 × 3 mesh")
            // No placeholder slipped through the table.
            #expect(!tone.title.isEmpty)
            let key = mesh.map { String($0, radix: 16) }.joined(separator: "-")
            #expect(seen[key] == nil, "\(tone.rawValue) has the same mesh as \(seen[key]?.rawValue ?? "")")
            seen[key] = tone
        }
    }

    @Test func theFiveLaqtaShippedWithAreUntouched() {
        // Anyone's existing folders have to keep looking exactly as they did.
        #expect(FolderTone.meshHexes(.ember).first == 0x3D140E)
        #expect(FolderTone.meshHexes(.ember).last == 0xD89046)
        #expect(FolderTone.meshHexes(.tide).last == 0x1C4A57)
        #expect(FolderTone.meshHexes(.olive)[4] == 0x374320)
        #expect(FolderTone.meshHexes(.dusk).last == 0xD28570)
        #expect(FolderTone.meshHexes(.sand).first == 0x796449)
    }

    @Test func everyFamilyHoldsSomeAndTogetherTheyHoldAll() {
        let counted = FolderToneFamily.allCases.reduce(0) { $0 + $1.tones.count }
        #expect(counted == FolderTone.allCases.count)
        for family in FolderToneFamily.allCases {
            #expect(!family.tones.isEmpty, "\(family.rawValue) is empty")
        }
        #expect(FolderTone.byFamily.count == FolderToneFamily.allCases.count)
    }

    @Test func aGlowNeverOutShoutsTheGold() {
        // The cap that keeps the set together: nothing more saturated than
        // Laqta's own gold, give or take the five originals which predate it.
        let originals: Set<FolderTone> = [.ember, .tide, .olive, .dusk, .sand]
        for tone in FolderTone.allCases where !originals.contains(tone) {
            let glow = FolderTone.meshHexes(tone)[8]
            let red = Double((glow >> 16) & 0xFF)
            let green = Double((glow >> 8) & 0xFF)
            let blue = Double(glow & 0xFF)
            let chroma = (max(red, green, blue) - min(red, green, blue)) / 255
            #expect(chroma <= 0.42, "\(tone.rawValue) glows too hard: \(chroma)")
        }
    }

    @Test func blendingWalksFromOneColourToTheOther() {
        #expect(FolderTone.blend(0x000000, 0xFFFFFF, 0) == 0x000000)
        #expect(FolderTone.blend(0x000000, 0xFFFFFF, 1) == 0xFFFFFF)
        #expect(FolderTone.blend(0x000000, 0xFFFFFF, 0.5) == 0x808080)
        #expect(FolderTone.blend(0x204060, 0x204060, 0.5) == 0x204060)
    }

    @Test func oldColourKeysStillLandSomewhere() {
        #expect(FolderTone.fromLegacy("green") == .olive)
        #expect(FolderTone.fromLegacy("orange") == .ember)
        #expect(FolderTone.fromLegacy("anything else") == .sand)
    }
}

@Suite("Choosing a mood")
struct FolderPaletteTests {
    @Test func aNameThatSaysAColourGetsThatColour() {
        #expect(FolderPalette.families(forName: "Blue things") == [.blue])
        #expect(FolderPalette.families(forName: "أشياء زرقاء").first == .blue)
        #expect(FolderPalette.families(forName: "Gold") == [.gold])
        #expect(FolderPalette.families(forName: "وردي") == [.rose])
        #expect(FolderPalette.pick(name: "Green notes", taken: []).family == .green)
    }

    @Test func aNameThatMeansSomethingLeansThatWay() {
        #expect(FolderPalette.families(forName: "Travel").first == .blue)
        #expect(FolderPalette.families(forName: "العطور").first == .warm)
        #expect(FolderPalette.families(forName: "Receipts").first == .stone)
        #expect(FolderPalette.families(forName: "Private").first == .stone)
        // A name that means nothing in particular — which is most of them.
        #expect(FolderPalette.families(forName: "Zzzq").isEmpty)
    }

    @Test func whatIsAlreadyWornIsPassedOver() {
        let travel = FolderPalette.pick(name: "Travel", taken: [])
        let second = FolderPalette.pick(name: "Travel", taken: [travel])
        #expect(second != travel)
        // Still the family it wanted, just a different mood in it.
        #expect(second.family == travel.family)
    }

    @Test func itKeepsFindingOneUntilTheFamilyRunsOut() {
        var taken: Set<FolderTone> = []
        for _ in 0..<FolderToneFamily.blue.tones.count {
            let pick = FolderPalette.pick(name: "Travel", taken: taken)
            #expect(pick.family == .blue)
            #expect(!taken.contains(pick))
            taken.insert(pick)
        }
        // The blue family is spent, so it moves to the next one it wanted.
        let overflow = FolderPalette.pick(name: "Travel", taken: taken)
        #expect(overflow.family == .gold)
    }

    @Test func withEveryMoodTakenItStartsTheSetAgain() {
        let all = Set(FolderTone.allCases)
        // Never refuses to answer, even once all fifty-six are out.
        #expect(all.contains(FolderPalette.pick(name: "Anything", taken: all)))
    }

    @Test func theSameNameAlwaysGetsTheSameMood() {
        let once = FolderPalette.pick(name: "Boarding passes", taken: [.ember, .tide])
        let again = FolderPalette.pick(name: "Boarding passes", taken: [.ember, .tide])
        #expect(once == again)
        #expect(FolderPalette.fingerprint("Travel") == FolderPalette.fingerprint("Travel"))
        #expect(FolderPalette.fingerprint("Travel") != FolderPalette.fingerprint("Perfume"))
        // An empty name is still answerable — the editor asks before you type.
        #expect(FolderTone.allCases.contains(FolderPalette.pick(name: "", taken: [])))
    }

    @Test func differentNamesSpreadOutRatherThanStacking() {
        let names = ["Watches", "Perfume", "Travel", "Receipts", "Cars", "Music", "Home", "Food"]
        var taken: Set<FolderTone> = []
        for name in names {
            let pick = FolderPalette.pick(name: name, taken: taken)
            #expect(!taken.contains(pick), "\(name) reused a mood")
            taken.insert(pick)
        }
        #expect(taken.count == names.count)
    }
}

@Suite("Naming a folder")
struct FolderNameReadingTests {
    @Test func aNameFindsItsIcon() {
        #expect(FolderSuggester.symbol(forName: "Travel") == "airplane")
        #expect(FolderSuggester.symbol(forName: "السفر") == "airplane")
        #expect(FolderSuggester.symbol(forName: "العطور") == "drop")
        #expect(FolderSuggester.symbol(forName: "Cars") == "car")
        #expect(FolderSuggester.symbol(forName: "Private") == "lock")
        #expect(FolderSuggester.symbol(forName: "خاص") == "lock")
        #expect(FolderSuggester.symbol(forName: "Zzzz") == "folder")
    }

    @Test func aNameNobodyListedStillFindsItsCategoryThroughAKeyword() {
        // "Flights" is not one of travel's names, but it is one of its words.
        #expect(FolderSuggester.category(forName: "Flights")?.id == "travel")
        #expect(FolderSuggester.category(forName: "My hotel bookings")?.id == "travel")
        #expect(FolderSuggester.category(forName: "")?.id == nil)
    }
}
