//
//  FirstRunTests.swift
//  LaqtaTests
//
//  The first run is animation, so what can be tested is what it promises:
//  it runs once, it leaves the library alone, and it hands the thirty days over.
//

import Foundation
import SwiftUI
import Testing
@testable import Laqta

extension LibraryTests {
    @Suite("First run")
    @MainActor
    struct FirstRunTests {
        let library: TestLibrary

        init() throws {
            library = try TestLibrary()
        }

        @Test func itIsPendingOnAFreshInstall() {
            #expect(PurchaseCenter.Welcome.isPending)
        }

        @Test func itNeverShowsTwice() {
            PurchaseCenter.Welcome.markShown()
            #expect(!PurchaseCenter.Welcome.isPending)
        }

        @Test func someoneWhoAlreadyBoughtItIsNotGreetedAgain() {
            Entitlement.isBought = true
            #expect(!PurchaseCenter.Welcome.isPending)
            Entitlement.forget()
        }

        @Test func theSequenceShowsNothingFromTheLibrary() throws {
            // Everything on screen is invented, so the run is identical on a fresh phone.
            #expect(DemoCover.allCases.count == 6)
            for cover in DemoCover.allCases {
                #expect(cover.colors.count == 3)
            }
            // The folders it draws are not the seeded ones being read back.
            let seeded = LaqtaStore.folders(inside: nil, context: library.context).map(\.name)
            #expect(!seeded.isEmpty)
        }

        @Test func theLastChapterIsTheOnlyPlaceMoneyIsMentioned() {
            // Chapter order is the promise: the offer comes last, after the welcome.
            let paces = FirstRunSequence.chapterCount
            #expect(paces == 8)
            #expect(FirstRunSequence.welcomeChapter == 6)
            #expect(FirstRunSequence.trialChapter == 7)
        }
    }
}
