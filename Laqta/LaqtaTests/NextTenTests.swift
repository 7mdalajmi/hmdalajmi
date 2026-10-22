//
//  NextTenTests.swift
//  LaqtaTests
//
//  The rules behind the new features, argued with here rather than on a phone:
//  what counts as a handle written on a sign, what counts as coming up, when a
//  reminder fires, what Laqta is willing to call forgotten, and what reads as a
//  question rather than a word.
//

import Foundation
import Testing
@testable import Laqta

// MARK: - Handles and links written in a shot

@Suite("Shot contacts")
struct ShotContactsTests {
    private func analysis(text: String, entities: [DetectedEntity] = [], place: PlaceRef? = nil) -> ShotAnalysis {
        var made = ShotAnalysis()
        made.text = text
        made.entities = entities
        made.place = place
        return made
    }

    @Test func aProfileAddressNamesItsService() {
        let handle = ContactReader.handle(fromURL: "https://www.instagram.com/altijara.kw/?hl=en")
        #expect(handle?.service == .instagram)
        #expect(handle?.handle == "altijara.kw")
        #expect(handle?.isExplicit == true)
        #expect(handle?.url?.absoluteString == "https://www.instagram.com/altijara.kw")

        #expect(ContactReader.handle(fromURL: "https://tiktok.com/@laqta.app")?.service == .tiktok)
        // TikTok wants the "@" back in the path.
        #expect(ContactReader.handle(fromURL: "https://tiktok.com/@laqta.app")?.url?.absoluteString == "https://www.tiktok.com/@laqta.app")
        #expect(ContactReader.handle(fromURL: "https://x.com/laqta")?.service == .x)
        #expect(ContactReader.handle(fromURL: "https://example.com/altijara") == nil)
    }

    @Test func aBareHandleIsReadAsInstagramButMarkedAsAGuess() {
        let handle = ContactReader.bareHandle("@altijara.kw")
        #expect(handle?.service == .instagram)
        #expect(handle?.isExplicit == false)
        #expect(handle?.display == "@altijara.kw")
    }

    @Test func wordsAfterAnAtSignAreNotHandles() {
        #expect(ContactReader.bareHandle("@gmail.com") == nil)
        #expect(ContactReader.bareHandle("@me") == nil)
        #expect(ContactReader.bareHandle("@ab") == nil)
        #expect(ContactReader.bareHandle("altijara.kw") == nil)
        // An address arrives with its name in front, so the "@" never leads.
        #expect(ContactReader.bareHandle("hi@example.com") == nil)
    }

    @Test func aWrittenOutAddressBeatsABareHandleForTheSameAccount() {
        let contacts = ContactReader.read(analysis(
            text: "AL-TIJARA WATCHES @altijara.kw 2244 7788",
            entities: [
                DetectedEntity(kind: .link, value: "https://instagram.com/altijara.kw", display: "instagram.com"),
                DetectedEntity(kind: .phone, value: "2244 7788", display: "2244 7788")
            ]
        ))
        #expect(contacts.handles.count == 1)
        #expect(contacts.handles.first?.isExplicit == true)
        #expect(contacts.phone == "2244 7788")
        #expect(contacts.phoneURL?.absoluteString == "tel:22447788")
        #expect(contacts.isWorthShowing)
    }

    @Test func googleIsAskedAboutTheNameAndTheArea() {
        let contacts = ContactReader.read(analysis(
            text: "Al-Tijara Watches",
            place: PlaceRef(name: "Al-Tijara Watches", detail: "Salmiya, Kuwait")
        ))
        #expect(contacts.searchQuery == "Al-Tijara Watches Salmiya, Kuwait")
        let maps = contacts.googleMapsURL?.absoluteString ?? ""
        #expect(maps.hasPrefix("https://www.google.com/maps/search/?api=1&query="))
        #expect(maps.contains("Al-Tijara"))
        #expect(contacts.googleSearchURL?.absoluteString.hasPrefix("https://www.google.com/search?q=") == true)
    }

    @Test func coordinatesBeatAWrittenAddressOnTheMap() {
        let contacts = ContactReader.read(analysis(
            text: "Kuwait Towers",
            place: PlaceRef(name: "Kuwait Towers", detail: "Sharq", latitude: 29.3897, longitude: 48.0015)
        ))
        #expect(contacts.googleMapsURL?.absoluteString.contains("query=29.3897,48.0015") == true)
    }

    @Test func aShotWithNothingInItOffersNothing() {
        #expect(ContactReader.read(nil).isWorthShowing == false)
        #expect(ContactReader.read(analysis(text: "hello")).isWorthShowing == false)
    }
}

// MARK: - Things with a date on them

@Suite("Coming up")
struct ComingUpTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func days(_ value: Double) -> Date { now.addingTimeInterval(value * 86_400) }

    private func dateEntity(_ date: Date) -> DetectedEntity {
        DetectedEntity(kind: .date, value: "\(date)", display: "14 Sep", date: date)
    }

    @Test func yesterdayIsGoneAndNextYearIsNotNews() {
        #expect(ComingUp.isWorthShowing(days(2), now: now))
        // Earlier today still counts — the day has not finished.
        #expect(ComingUp.isWorthShowing(now.addingTimeInterval(-3_600), now: now))
        #expect(!ComingUp.isWorthShowing(days(-2), now: now))
        #expect(!ComingUp.isWorthShowing(days(400), now: now))
    }

    @Test func theSoonestDateOnAShotIsTheOneShown() {
        let entities = [
            dateEntity(days(30)),
            dateEntity(days(-5)),
            dateEntity(days(3)),
            DetectedEntity(kind: .price, value: "KWD 4,200", display: "KWD 4,200")
        ]
        let soonest = ComingUp.soonest(in: entities, now: now)
        #expect(soonest?.date == days(3))
        #expect(ComingUp.soonest(in: [dateEntity(days(-5))], now: now) == nil)
        #expect(ComingUp.soonest(in: [], now: now) == nil)
    }

    @Test func oneRowPerShot_soonestFirst() {
        let id = UUID()
        let made = [
            DatedShot(itemID: UUID(), folderID: nil, title: "Later", detail: nil, date: days(9), allDay: true, thumbnailName: "a"),
            DatedShot(itemID: id, folderID: nil, title: "Soon", detail: nil, date: days(2), allDay: true, thumbnailName: "b"),
            DatedShot(itemID: id, folderID: nil, title: "Same shot again", detail: nil, date: days(4), allDay: true, thumbnailName: "b")
        ]
        let ordered = ComingUp.order(made)
        #expect(ordered.count == 2)
        #expect(ordered.first?.title == "Soon")
        #expect(ordered.last?.title == "Later")
    }

    @Test func imminentMeansWithinTwoDays() {
        func shot(_ date: Date) -> DatedShot {
            DatedShot(itemID: UUID(), folderID: nil, title: "x", detail: nil, date: date, allDay: true, thumbnailName: "t")
        }
        #expect(shot(days(1)).isImminent(from: now))
        #expect(!shot(days(6)).isImminent(from: now))
        #expect(shot(days(2)).daysAway(from: now) == 2)
    }
}

// MARK: - The nudge before it

@Suite("Reminders")
struct ReminderLeadTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .now
    }

    @Test func eachLeadFiresOnItsOwnDay() {
        let flight = date(2026, 9, 14, 9)   // 09:40 on the 14th, near enough
        let now = date(2026, 9, 1)

        let dayBefore = ReminderLead.dayBefore.fireDate(for: flight, now: now, calendar: calendar)
        #expect(calendar.component(.day, from: dayBefore ?? .now) == 13)
        #expect(calendar.component(.hour, from: dayBefore ?? .now) == 9)

        let twoDays = ReminderLead.twoDays.fireDate(for: flight, now: now, calendar: calendar)
        #expect(calendar.component(.day, from: twoDays ?? .now) == 12)

        let morningOf = ReminderLead.morningOf.fireDate(for: flight, now: now, calendar: calendar)
        #expect(calendar.component(.day, from: morningOf ?? .now) == 14)
        // The morning of starts earlier, because the day has already begun.
        #expect(calendar.component(.hour, from: morningOf ?? .now) == 7)
    }

    @Test func aMomentThatHasPassedIsNotOffered() {
        let flight = date(2026, 9, 14)
        let now = date(2026, 9, 13, 20)   // the evening before
        #expect(ReminderLead.twoDays.fireDate(for: flight, now: now, calendar: calendar) == nil)
        #expect(ReminderLead.dayBefore.fireDate(for: flight, now: now, calendar: calendar) == nil)
        #expect(ReminderLead.morningOf.fireDate(for: flight, now: now, calendar: calendar) != nil)
    }

    @Test func aLateFlightFallsBackToTheNextUsableLead() {
        let flight = date(2026, 9, 14)
        // Saved the day before: "two days before" has gone, so it steps down.
        let now = date(2026, 9, 13, 6)
        #expect(ReminderLead.usable(from: .twoDays, for: flight, now: now, calendar: calendar) == .dayBefore)
        // Saved on the day itself, before seven.
        #expect(ReminderLead.usable(from: .twoDays, for: flight, now: date(2026, 9, 14, 5), calendar: calendar) == .morningOf)
        // Saved after it has already happened.
        #expect(ReminderLead.usable(from: .twoDays, for: flight, now: date(2026, 9, 15), calendar: calendar) == nil)
    }

    @Test func theHeadlineCountsFromTheDayItFires() {
        let flight = date(2026, 9, 14)
        let dated = DatedShot(
            itemID: UUID(), folderID: nil, title: "Kuwait → Dubai",
            detail: "Boarding pass", date: flight, allDay: false, thumbnailName: "t"
        )
        #expect(ReminderCenter.headline(for: dated, firing: date(2026, 9, 13), calendar: calendar) == "Kuwait → Dubai is tomorrow")
        #expect(ReminderCenter.headline(for: dated, firing: date(2026, 9, 14, 7), calendar: calendar) == "Kuwait → Dubai is today")
        #expect(ReminderCenter.headline(for: dated, firing: date(2026, 9, 12), calendar: calendar) == "Kuwait → Dubai is in 2 days")
    }
}

// MARK: - Clean up old shots

@Suite("Cleanup")
struct CleanupTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func days(_ value: Double) -> Date { now.addingTimeInterval(-value * 86_400) }

    private func subject(
        added: Double,
        viewed: Date? = nil,
        hash: String? = nil,
        text: Int = 0,
        analyzed: Bool = true,
        favorite: Bool = false,
        note: Bool = false,
        pixels: Int = 1_000,
        picture: Bool = true
    ) -> CleanupSubject {
        CleanupSubject(
            itemID: UUID(),
            byteCount: 1_000_000,
            addedAt: days(added),
            viewedAt: viewed,
            contentHash: hash,
            captureKey: nil,
            pixelWidth: pixels,
            pixelHeight: 1,
            textLength: text,
            wasAnalyzed: analyzed,
            isFavorite: favorite,
            hasNote: note,
            isPicture: picture
        )
    }

    @Test func forgottenMeansOldAndNeverOnceOpened() {
        #expect(CleanupScanner.isNeverOpened(subject(added: 200), now: now))
        // Opened, even once, and it is yours.
        #expect(!CleanupScanner.isNeverOpened(subject(added: 200, viewed: days(10)), now: now))
        // Saved last week — not forgotten, just new.
        #expect(!CleanupScanner.isNeverOpened(subject(added: 7), now: now))
    }

    @Test func aFavouriteOrANoteIsNeverProposed() {
        #expect(!CleanupScanner.isNeverOpened(subject(added: 400, favorite: true), now: now))
        #expect(!CleanupScanner.isNeverOpened(subject(added: 400, note: true), now: now))
        #expect(!CleanupScanner.isUnreadable(subject(added: 400, note: true), now: now))
    }

    @Test func aLinkIsNeverCalledUnreadable() {
        #expect(CleanupScanner.isUnreadable(subject(added: 200), now: now))
        #expect(!CleanupScanner.isUnreadable(subject(added: 200, picture: false), now: now))
        // Not looked at yet is not the same as nothing in it.
        #expect(!CleanupScanner.isUnreadable(subject(added: 200, analyzed: false), now: now))
        #expect(!CleanupScanner.isUnreadable(subject(added: 200, text: 40), now: now))
    }

    @Test func copiesKeepTheOneThatCanStillBeRead() {
        let readable = subject(added: 3, hash: "same", text: 120, pixels: 800)
        let bigger = subject(added: 3, hash: "same", text: 0, pixels: 4_000)
        let blurred = subject(added: 3, hash: "same", text: 0, pixels: 500)
        let alone = subject(added: 3, hash: "other")

        let families = CleanupScanner.similar(in: [bigger, readable, blurred, alone])
        #expect(families.count == 1)
        #expect(families.first?.keep == readable.itemID)
        #expect(families.first?.others.count == 2)
        #expect(families.first?.count == 3)
    }

    @Test func withNothingReadableTheBiggestCopyWins() {
        let big = subject(added: 3, hash: "same", pixels: 4_000)
        let small = subject(added: 3, hash: "same", pixels: 400)
        #expect(CleanupScanner.best(of: [small, big])?.itemID == big.itemID)
    }

    @Test func aShotOnlyEverLandsInOnePile() {
        let copyKeeper = subject(added: 300, hash: "same", text: 50)
        let copyOther = subject(added: 300, hash: "same", text: 0)
        let forgotten = subject(added: 300)
        let groups = CleanupScanner.scan([copyKeeper, copyOther, forgotten], now: now)

        let everyID = groups.flatMap(\.itemIDs)
        #expect(everyID.count == Set(everyID).count)
        let duplicates = groups.first { $0.pile == .duplicates }
        #expect(duplicates?.itemIDs == [copyOther.itemID])
        #expect(groups.first { $0.pile == .neverOpened }?.itemIDs.contains(copyOther.itemID) == false)
    }

    @Test func nothingToProposeIsAnEmptyAnswer() {
        #expect(CleanupScanner.scan([subject(added: 1, viewed: days(0), text: 20)], now: now).isEmpty)
        #expect(CleanupScanner.similar(in: [subject(added: 1)]).isEmpty)
    }
}

// MARK: - Ask your library

@Suite("Ask the library")
struct LibraryAskTests {
    @Test func aQuestionIsMoreThanAWord() {
        #expect(LibraryAsk.looksLikeAQuestion("وين اللقطة اللي فيها ساعة بـ ٤٢٠٠؟"))
        #expect(LibraryAsk.looksLikeAQuestion("where is the watch receipt"))
        #expect(LibraryAsk.looksLikeAQuestion("submariner?"))
        #expect(!LibraryAsk.looksLikeAQuestion("rolex"))
        #expect(!LibraryAsk.looksLikeAQuestion("4200"))
        #expect(!LibraryAsk.looksLikeAQuestion(""))
    }

    @Test func theShortlistIsNumberedForTheModel() {
        let made = [
            LibraryCandidate(number: 1, itemID: UUID(), folderID: nil, title: "Submariner",
                             folderName: "Watches", savedOn: Date(timeIntervalSince1970: 1_750_000_000),
                             excerpt: "KWD 4,200\nAl-Tijara"),
            LibraryCandidate(number: 2, itemID: UUID(), folderID: nil, title: "Boarding pass",
                             folderName: "Travel", savedOn: Date(timeIntervalSince1970: 1_750_000_000), excerpt: "")
        ]
        let context = LibraryAsk.context(for: made)
        #expect(context.hasPrefix("1. Submariner — Watches — saved "))
        #expect(context.contains("2. Boarding pass"))
        // A newline inside a shot would look like a new numbered entry.
        #expect(context.contains("KWD 4,200 Al-Tijara"))
    }

    @Test func onlyNumbersFromTheListItWasGivenCount() {
        #expect(LibraryAsk.picks(in: "2, 5, 9", within: 10) == [2, 5, 9])
        #expect(LibraryAsk.picks(in: "3 and 3 and 12", within: 10) == [3])
        #expect(LibraryAsk.picks(in: "", within: 10).isEmpty)
        #expect(LibraryAsk.picks(in: "none", within: 10).isEmpty)
        #expect(LibraryAsk.picks(in: "0", within: 10).isEmpty)
    }
}
