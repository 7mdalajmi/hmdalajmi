//
//  EntityDetectorTests.swift
//  LaqtaTests
//
//  Details Laqta finds in text on the device: flights, booking codes and prices.
//

import Foundation
import Testing
@testable import Laqta

@Suite("Details in text")
struct EntityDetectorTests {
    private let itinerary = """
    Flight
    Falcon Air FA 117 - Kuwait (KWI) to London Heathrow (LHR)
    Departure: Saturday 3 October 2026 at 8:05 AM
    Booking reference: QX7P2L
    Total paid: 238.500 KWD
    """

    private func displays(_ kind: DetectedEntity.Kind, in text: String) -> [String] {
        EntityDetector.detect(in: text).filter { $0.kind == kind }.map(\.display)
    }

    @Test func flightsKeepTheirAirlineCode() {
        let flights = displays(.flight, in: itinerary)
        #expect(flights.contains("FA 117"), "Found: \(flights)")
        #expect(!flights.contains("117"))
    }

    @Test("Booking codes", arguments: [
        ("Booking reference: QX7P2L", "QX7P2L"),
        ("Confirmation code: ABC123", "ABC123"),
        ("PNR: K7LM2Q", "K7LM2Q"),
        ("Your confirmation number is AB12CD", "AB12CD"),
        ("Booking reference: KLMNOP", "KLMNOP")
    ])
    func bookingCodes(_ text: String, _ code: String) {
        #expect(displays(.code, in: text) == [code])
    }

    @Test("Words are not codes", arguments: [
        "Your booking is confirmed",
        "Your reservation number is 12345678",
        "Order #88231"
    ])
    func notCodes(_ text: String) {
        #expect(displays(.code, in: text).isEmpty)
    }

    @Test func timesWithoutADayAreIgnored() {
        let dates = EntityDetector.detect(in: "Check out: 8 October 2026 by 11:00 AM").filter { $0.kind == .date }
        let days = Set(dates.compactMap(\.date).map { Calendar.current.component(.day, from: $0) })
        #expect(days == [8], "Found: \(dates.map(\.display))")
        #expect(EntityDetector.isBareTime("11:00 AM"))
        #expect(EntityDetector.isBareTime("by 3 PM"))
        #expect(EntityDetector.isBareTime("00:00:01.600"), "Video timecodes")
        #expect(!EntityDetector.isBareTime("Saturday 3 October 2026 at 8:05 AM"))
        #expect(!EntityDetector.isBareTime("tomorrow at 9:00"))
    }

    @Test func prices() {
        let prices = displays(.price, in: itinerary)
        let hasTotal = prices.contains { $0.contains("238.500") }
        #expect(hasTotal, "Found: \(prices)")
    }
}
