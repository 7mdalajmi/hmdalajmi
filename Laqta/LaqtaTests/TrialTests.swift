//
//  TrialTests.swift
//  LaqtaTests
//
//  The thirty days: when they run out, what happens then, and what a turned-back
//  clock or a second install can't do about it.
//

import Foundation
import Testing
@testable import Laqta

@Suite("Trial")
struct TrialTests {
    private let start = Date(timeIntervalSince1970: 1_750_000_000)

    private func state(daysIn: Double, isBought: Bool = false) -> LibraryAccess {
        Entitlement.access(
            startedAt: start,
            isBought: isBought,
            now: start.addingTimeInterval(daysIn * 86_400)
        )
    }

    @Test func aFreshTrialHasEveryDay() {
        #expect(state(daysIn: 0) == .trial(daysLeft: 30))
        // Nothing recorded yet — the first launch hasn't finished, and Laqta stays open.
        #expect(Entitlement.access(startedAt: nil, isBought: false) == .trial(daysLeft: 30))
    }

    @Test func theDaysCountDown() {
        #expect(state(daysIn: 1) == .trial(daysLeft: 29))
        #expect(state(daysIn: 25) == .trial(daysLeft: 5))
        #expect(state(daysIn: 29.5) == .trial(daysLeft: 1))
    }

    @Test func theLastDayIsStillADay() {
        #expect(state(daysIn: 30 - 1.0 / 1440) == .trial(daysLeft: 1))
    }

    @Test func dayThirtyOneIsReadOnly() {
        #expect(state(daysIn: 30) == .expired)
        #expect(state(daysIn: 400) == .expired)
        #expect(state(daysIn: 30).canAddThings == false)
    }

    @Test func buyingOutlastsEverything() {
        #expect(state(daysIn: 400, isBought: true) == .bought)
        #expect(state(daysIn: 400, isBought: true).canAddThings)
    }

    @Test func turningTheClockBackBuysNothing() {
        let back = Entitlement.access(
            startedAt: start,
            isBought: false,
            now: start.addingTimeInterval(-90 * 86_400)
        )
        #expect(back == .trial(daysLeft: 30))
    }

    @Test func theStripSpeaksUpInTheLastDays() {
        #expect(!state(daysIn: 10).isRunningOut)
        #expect(state(daysIn: 25).isRunningOut)
        #expect(state(daysIn: 29).isRunningOut)
        // Expired reads its own way, so it isn't "running out" any more.
        #expect(!state(daysIn: 30).isRunningOut)
        #expect(state(daysIn: 30).isExpired)
    }

    @Test func onlyAddingEverStops() {
        #expect(state(daysIn: 5).canAddThings)
        #expect(state(daysIn: 0, isBought: true).canAddThings)
        #expect(!state(daysIn: 31).canAddThings)
    }

    @Test func theProductsAreTheOnesTheStoreLists() {
        #expect(LaqtaProduct.all == ["Hmdalajmi.Laqta.trial30", "Hmdalajmi.Laqta.unlock"])
        #expect(Entitlement.trialDays == 30)
    }
}

extension LibraryTests {
    /// These touch the App Group, so they run inside the temporary library like the rest.
    @Suite("Trial dates")
    @MainActor
    struct TrialStorageTests {
        /// A new one per test, so each starts with an empty App Group.
        let library: TestLibrary

        init() throws {
            library = try TestLibrary()
        }

        @Test func theEarliestDateWins() {
            let late = Date(timeIntervalSince1970: 1_760_000_000)
            Entitlement.noteTrialStart(late)
            #expect(Entitlement.trialStartedAt == late)

            // A receipt from the first install reaches back; a reinstall's later date doesn't.
            let early = late.addingTimeInterval(-40 * 86_400)
            Entitlement.noteTrialStart(early)
            #expect(Entitlement.trialStartedAt == early)
            Entitlement.noteTrialStart(late.addingTimeInterval(86_400))
            #expect(Entitlement.trialStartedAt == early)

            // Which means the second install is already out of days.
            #expect(Entitlement.access(startedAt: Entitlement.trialStartedAt, isBought: false, now: late) == .expired)
        }

        @Test func theFirstLaunchStartsTheClockOnce() {
            let first = Date(timeIntervalSince1970: 1_755_000_000)
            Entitlement.beginTrialIfNeeded(first)
            Entitlement.beginTrialIfNeeded(first.addingTimeInterval(9 * 86_400))
            #expect(Entitlement.trialStartedAt == first)
        }

        @Test func aFreshInstallIsInsideItsTrial() {
            #expect(Entitlement.trialStartedAt == nil)
            #expect(Entitlement.isBought == false)
            #expect(Entitlement.canAddThings)

            Entitlement.beginTrialIfNeeded()
            #expect(Entitlement.current.daysLeft == 30)
        }

        @Test func buyingIsRemembered() {
            Entitlement.noteTrialStart(Date(timeIntervalSince1970: 1_000_000))
            #expect(Entitlement.current == .expired)
            Entitlement.isBought = true
            #expect(Entitlement.current == .bought)
            #expect(Entitlement.canAddThings)
            Entitlement.forget()
            #expect(Entitlement.isBought == false)
        }
    }
}
