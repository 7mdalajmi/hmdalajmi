//
//  PlaceGroundingTests.swift
//  LaqtaTests
//
//  A place written by the language model only counts when the item itself names it.
//

import Foundation
import Testing
@testable import Laqta

@Suite("Places the item names")
struct PlaceGroundingTests {
    @Test("Named in the text", arguments: [
        ("Souq Al-Mubarakiya", "Dinner at Souq Al Mubarakiya tonight"),
        ("Burj Khalifa", "BURJ KHALIFA · At the Top, level 124"),
        ("The Avenues", "Meet me at the Avenues mall"),
        ("Café de Flore", "Coffee at Cafe de Flore"),
        ("Kuwait Towers", "Kuwait Towers\nOpen daily 9 AM")
    ])
    func mentioned(_ name: String, _ text: String) {
        #expect(PlaceGrounding.isMentioned(name, in: text))
    }

    @Test("Not named in the text", arguments: [
        ("Kuwait International Airport", "Gate 12 · Boarding 10:40"),
        ("Airport", "Terminal 4 airport lounge"),
        ("Eiffel Tower", "")
    ])
    func notMentioned(_ name: String, _ text: String) {
        #expect(!PlaceGrounding.isMentioned(name, in: text))
    }

    @Test func noTextNamesNoPlace() {
        #expect(!PlaceGrounding.isMentioned("Kuwait International Airport", in: nil))
    }

    @MainActor
    @Test func inventedPlaceIsAnalyzedAgain() {
        var analysis = ShotAnalysis()
        analysis.usedLanguageModel = true
        analysis.title = "Sign at airport"
        analysis.place = PlaceRef(name: "Kuwait International Airport", category: "Airport", origin: "From text")
        #expect(LaqtaStore.hasUngroundedInsight(analysis))
    }

    @MainActor
    @Test func photoWithNothingToReadIsAnalyzedAgain() {
        var analysis = ShotAnalysis()
        analysis.usedLanguageModel = true
        analysis.title = "Sign at airport"
        analysis.questions = ["What does the sign say?"]
        #expect(LaqtaStore.hasUngroundedInsight(analysis))
    }

    @MainActor
    @Test func groundedPhotosAreKept() {
        var fromLocation = ShotAnalysis()
        fromLocation.usedLanguageModel = true
        fromLocation.place = PlaceRef(name: "Fosshóll, Iceland", detail: "Fosshóll, Iceland", category: "Location", latitude: 65.68, longitude: -17.55, origin: "GPS")
        #expect(!LaqtaStore.hasUngroundedInsight(fromLocation))

        var fromText = ShotAnalysis()
        fromText.usedLanguageModel = true
        fromText.text = "Welcome to Kuwait Towers"
        fromText.place = PlaceRef(name: "Kuwait Towers", category: "Landmark", origin: "From text")
        #expect(!LaqtaStore.hasUngroundedInsight(fromText))

        var address = ShotAnalysis()
        address.usedLanguageModel = true
        address.text = "Block 3, Street 5, Salmiya"
        address.place = PlaceRef(name: "Salem Al Mubarak Street", category: "Address", origin: "From text")
        #expect(!LaqtaStore.hasUngroundedInsight(address))

        var labelled = ShotAnalysis()
        labelled.usedLanguageModel = true
        labelled.labels = ["Plants"]
        labelled.title = "Green leaves"
        #expect(!LaqtaStore.hasUngroundedInsight(labelled))

        #expect(!LaqtaStore.hasUngroundedInsight(ShotAnalysis()))
    }
}
