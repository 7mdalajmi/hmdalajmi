//
//  PlaceResolver.swift
//  Laqta — Shared
//
//  Known places from GPS, addresses and names (MapKit).
//

import CoreLocation
import Foundation
import MapKit

enum PlaceResolver {
    private static let landmarkCategories: [MKPointOfInterestCategory] = [
        .landmark, .nationalMonument, .museum, .castle, .fortress, .park, .nationalPark,
        .stadium, .theater, .aquarium, .zoo, .amusementPark, .beach, .marina, .airport,
        .university, .planetarium, .musicVenue, .conventionCenter, .library
    ]

    /// Where a photo with GPS data was taken, preferring a landmark nearby.
    static func place(near latitude: Double, _ longitude: Double) async -> PlaceRef? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        var detail: String?
        var areaName: String?
        if let request = MKReverseGeocodingRequest(location: location),
           let item = try? await request.mapItems.first {
            detail = areaLine(for: item)
            areaName = usableName(item.name)
        }

        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 400)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: landmarkCategories)
        if let response = try? await MKLocalSearch(request: request).start() {
            let nearest = response.mapItems.min { first, second in
                first.location.distance(from: location) < second.location.distance(from: location)
            }
            if let nearest, let name = usableName(nearest.name), nearest.location.distance(from: location) < 400 {
                return PlaceRef(
                    name: name,
                    detail: areaLine(for: nearest) ?? detail,
                    category: categoryName(nearest.pointOfInterestCategory),
                    note: nil,
                    latitude: nearest.location.coordinate.latitude,
                    longitude: nearest.location.coordinate.longitude,
                    origin: "Landmark"
                )
            }
        }

        guard areaName != nil || detail != nil else { return nil }
        return PlaceRef(
            name: areaName ?? detail ?? "Pinned location",
            detail: detail,
            category: "Location",
            note: nil,
            latitude: latitude,
            longitude: longitude,
            origin: "GPS"
        )
    }

    /// A place by name ("Souq Al-Mubarakiya"), optionally near a city.
    static func search(_ name: String, near hint: (latitude: Double, longitude: Double)? = nil, context: String? = nil) async -> PlaceRef? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [name, context].compactMap { $0 }.joined(separator: " ")
        request.resultTypes = [.pointOfInterest, .address]
        if let hint {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: hint.latitude, longitude: hint.longitude),
                latitudinalMeters: 60_000,
                longitudinalMeters: 60_000
            )
        }
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first(where: { matches($0.name, name) }) else { return nil }
        return PlaceRef(
            name: item.name ?? name,
            detail: areaLine(for: item),
            category: categoryName(item.pointOfInterestCategory),
            note: nil,
            latitude: item.location.coordinate.latitude,
            longitude: item.location.coordinate.longitude,
            origin: "Mentioned"
        )
    }

    /// The result should really be the place that was asked for.
    private static func matches(_ found: String?, _ wanted: String) -> Bool {
        guard let found else { return false }
        let a = SearchIndex.normalize(found)
        let b = SearchIndex.normalize(wanted)
        if a.contains(b) || b.contains(a) { return true }
        let wantedWords = Set(b.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 })
        let foundWords = Set(a.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        guard !wantedWords.isEmpty else { return false }
        return Double(wantedWords.intersection(foundWords).count) / Double(wantedWords.count) >= 0.5
    }

    /// An address found in text.
    static func geocode(address: String) async -> PlaceRef? {
        guard let request = MKGeocodingRequest(addressString: address),
              let item = try? await request.mapItems.first else { return nil }
        return PlaceRef(
            name: item.name ?? EntityDetector.shortened(address, limit: 40),
            detail: areaLine(for: item),
            category: "Address",
            note: nil,
            latitude: item.location.coordinate.latitude,
            longitude: item.location.coordinate.longitude,
            origin: "From text"
        )
    }

    /// Skips names that are only a house number or a street address.
    static func usableName(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), name.count >= 3 else { return nil }
        let letters = name.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 3 else { return nil }
        if let first = name.first, first.isNumber { return nil }
        return name
    }

    static func areaLine(for item: MKMapItem) -> String? {
        if let city = item.addressRepresentations?.cityWithContext, !city.isEmpty {
            return city
        }
        return item.address?.shortAddress
    }

    static func categoryName(_ category: MKPointOfInterestCategory?) -> String? {
        guard let category else { return nil }
        let raw = category.rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
        // "NationalMonument" → "National monument"
        var words: [String] = []
        var current = ""
        for character in raw {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        guard let first = words.first else { return nil }
        return ([first] + words.dropFirst().map { $0.lowercased() }).joined(separator: " ")
    }
}

/// Keeps place names from the language model honest: a place only counts when the
/// item's own words name it. Given too little to go on, the model can invent a place,
/// and a map search would then turn a made-up "airport" into a real one nearby.
nonisolated enum PlaceGrounding {
    /// Words that name a kind of place rather than a place.
    static let genericWords: Set<String> = [
        "airport", "terminal", "gate", "restaurant", "cafe", "coffee", "shop", "store", "mall", "market",
        "hotel", "resort", "beach", "park", "garden", "museum", "gallery", "station", "city", "town",
        "village", "street", "road", "avenue", "building", "tower", "office", "home", "house", "apartment",
        "school", "university", "hospital", "clinic", "mosque", "church", "temple", "bank", "gym", "library",
        "center", "centre", "area", "place", "location", "downtown", "sign", "the", "and", "near"
    ]

    /// True when `name` is a specific place that `text` mentions.
    static func isMentioned(_ name: String, in text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        let specific = words(in: name).filter { $0.count > 2 && !genericWords.contains($0) }
        guard !specific.isEmpty else { return false }
        let foldedName = SearchIndex.normalize(name.trimmingCharacters(in: .whitespacesAndNewlines))
        if SearchIndex.normalize(text).contains(foldedName) { return true }
        let textWords = Set(words(in: text))
        let found = specific.filter { textWords.contains($0) }
        return found.count * 2 >= specific.count
    }

    private static func words(in text: String) -> [String] {
        SearchIndex.normalize(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
