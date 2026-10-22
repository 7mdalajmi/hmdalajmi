//
//  TextIntelligence.swift
//  Laqta — Shared
//
//  Dates, places, prices, flights, links and codes found in text (on device).
//

import Foundation
import NaturalLanguage

nonisolated enum EntityDetector {
    private static let priceExpression = try? NSRegularExpression(
        pattern: #"(?i)(?:(?:KWD|KD|SAR|AED|QAR|BHD|OMR|USD|EUR|GBP|US\$|\$|€|£|د\.ك|ر\.س|د\.إ)\s?\d[\d,]*(?:[.,]\d{1,3})?)|(?:\d[\d,]*(?:[.,]\d{1,3})?\s?(?:KWD|KD|SAR|AED|QAR|BHD|OMR|USD|EUR|GBP|د\.ك|ر\.س|د\.إ|dinars?|riyals?|dirhams?|دينار|ريال|درهم)\b)"#
    )
    private static let codeExpression = try? NSRegularExpression(
        // "Booking reference: QX7P2L", "confirmation number is AB12CD", "PNR K7LM2Q".
        pattern: #"(?i)\b(?:booking|confirmation|reservation|order|pnr|reference|ref)(?:\s+(?:reference|ref|code|number|no\.?|id))*\s*(?:is\s+)?[:#]?\s*([A-Z0-9]{5,10})\b"#
    )
    /// "11:00 AM", "by 3 PM": a time with no day, which the detector would pin to today.
    private static let bareTimeExpression = try? NSRegularExpression(
        pattern: #"(?i)^\s*(?:at|by|from|until|till|before|after|around)?\s*\d{1,2}(?:[:.]\d{2}){0,2}(?:[.,]\d{1,3})?\s*(?:am|pm|a\.m\.|p\.m\.)?\s*$"#
    )
    private static let flightExpression = try? NSRegularExpression(
        pattern: #"\b(?:flight\s*)?([A-Z]{2}|[A-Z]\d|\d[A-Z])\s?(\d{2,4})\b"#
    )

    static func isBareTime(_ text: String) -> Bool {
        guard let bareTimeExpression else { return false }
        return bareTimeExpression.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func detect(in text: String, reference: Date? = nil) -> [DetectedEntity] {
        guard !text.isEmpty else { return [] }
        var entities: [DetectedEntity] = []
        var seen = Set<String>()

        func add(_ entity: DetectedEntity) {
            guard seen.insert(entity.id).inserted else { return }
            entities.append(entity)
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let types: NSTextCheckingResult.CheckingType = [.date, .address, .link, .phoneNumber, .transitInformation]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            for match in detector.matches(in: text, options: [], range: fullRange) {
                let matched = nsText.substring(with: match.range)
                switch match.resultType {
                case .date:
                    guard let date = match.date else { continue }
                    let hasTime = matched.contains(":") || matched.lowercased().contains("am") || matched.lowercased().contains("pm")
                    // Ignore bare times and years with no day.
                    guard matched.count >= 5, !isBareTime(matched) else { continue }
                    add(DetectedEntity(
                        kind: .date,
                        value: ISO8601DateFormatter().string(from: date),
                        display: LaqtaFormat.eventDate(date, allDay: !hasTime),
                        date: date,
                        duration: match.duration > 0 ? match.duration : nil,
                        allDay: !hasTime
                    ))
                case .address:
                    add(DetectedEntity(kind: .address, value: matched, display: shortened(matched, limit: 38)))
                case .link:
                    guard let url = match.url else { continue }
                    if url.scheme == "mailto" {
                        let address = url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
                        add(DetectedEntity(kind: .email, value: address, display: address))
                    } else if url.scheme == "http" || url.scheme == "https" {
                        add(DetectedEntity(kind: .link, value: url.absoluteString, display: LinkDraft.displayHost(url) + (url.path().count > 1 ? url.path() : "")))
                    }
                case .phoneNumber:
                    guard let number = match.phoneNumber else { continue }
                    add(DetectedEntity(kind: .phone, value: number, display: number))
                case .transitInformation:
                    let components = match.components ?? [:]
                    guard var flight = components[.flight] else { continue }
                    var airline = components[.airline] ?? ""
                    // Unknown airlines come back as a bare number: take the code from the text ("FA 117").
                    if airline.isEmpty || flight.allSatisfy(\.isNumber) {
                        let range = NSRange(location: 0, length: (matched as NSString).length)
                        if let codeMatch = flightExpression?.firstMatch(in: matched, options: [], range: range), codeMatch.numberOfRanges >= 3 {
                            airline = (matched as NSString).substring(with: codeMatch.range(at: 1))
                            flight = (matched as NSString).substring(with: codeMatch.range(at: 2))
                        }
                    }
                    let code = "\(airline) \(flight)".trimmingCharacters(in: .whitespaces)
                    add(DetectedEntity(kind: .flight, value: code.replacingOccurrences(of: " ", with: ""), display: code))
                default:
                    continue
                }
            }
        }

        // Flights written like "SH 204" next to flight words.
        let lower = text.lowercased()
        if lower.contains("flight") || lower.contains("boarding") || lower.contains("gate") || text.contains("رحلة") {
            for match in flightExpression?.matches(in: text, options: [], range: fullRange) ?? [] where match.numberOfRanges >= 3 {
                let airline = nsText.substring(with: match.range(at: 1))
                let number = nsText.substring(with: match.range(at: 2))
                // The flight word can be a heading on the line above ("Flight\nFalcon Air FA 117").
                let context = nsText.substring(with: NSRange(location: max(0, match.range.location - 32), length: min(32, match.range.location))).lowercased()
                guard context.contains("flight") || context.contains("flt") || nsText.substring(with: match.range).lowercased().hasPrefix("flight") else { continue }
                add(DetectedEntity(kind: .flight, value: airline + number, display: "\(airline) \(number)"))
            }
        }
        // "117" and "FA 117" are the same flight.
        let codedFlights = entities.filter { $0.kind == .flight && !$0.value.allSatisfy(\.isNumber) }.map(\.value)
        entities.removeAll { entity in
            entity.kind == .flight && entity.value.allSatisfy(\.isNumber) && codedFlights.contains { $0.hasSuffix(entity.value) }
        }

        for price in prices(in: text) {
            add(DetectedEntity(kind: .price, value: price, display: price))
        }

        for match in codeExpression?.matches(in: text, options: [], range: fullRange) ?? [] where match.numberOfRanges >= 2 {
            let code = nsText.substring(with: match.range(at: 1))
            // Codes have letters; letter-only codes are written in capitals ("KLMNOP", not "confirmed").
            guard code.contains(where: \.isLetter),
                  code.contains(where: \.isNumber) || (code.count >= 6 && code == code.uppercased()) else { continue }
            add(DetectedEntity(kind: .code, value: code, display: code))
        }

        return Array(entities.prefix(10))
    }

    static func prices(in text: String) -> [String] {
        guard let priceExpression else { return [] }
        let nsText = text as NSString
        var results: [String] = []
        for match in priceExpression.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
            let value = nsText.substring(with: match.range).trimmingCharacters(in: .whitespaces)
            if !results.contains(value) { results.append(value) }
            if results.count >= 8 { break }
        }
        return results
    }

    /// Lines that carry a price, as "label → price" rows.
    static func priceRows(in text: String, limit: Int = 6) -> [PriceRef] {
        var rows: [PriceRef] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.count < 160, let price = prices(in: line).first else { continue }
            var label = line.replacingOccurrences(of: price, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:·|•,()"))
            if label.isEmpty { label = "Price" }
            let row = PriceRef(label: shortened(label, limit: 60), value: price)
            if !rows.contains(row) { rows.append(row) }
            if rows.count >= limit { break }
        }
        return rows
    }

    static func shortened(_ text: String, limit: Int) -> String {
        let single = text.replacingOccurrences(of: "\n", with: ", ")
        guard single.count > limit else { return single }
        return String(single.prefix(limit - 1)) + "…"
    }
}

nonisolated enum PlaceNameFinder {
    /// Place names in free text (NaturalLanguage name tagging).
    static func names(in text: String, limit: Int = 8) -> [String] {
        guard !text.isEmpty else { return [] }
        let sample = String(text.prefix(12_000))
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = sample
        var counts: [String: Int] = [:]
        var order: [String] = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        tagger.enumerateTags(in: sample.startIndex..<sample.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            if tag == .placeName {
                let name = String(sample[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if name.count >= 3, name.count <= 48 {
                    if counts[name] == nil { order.append(name) }
                    counts[name, default: 0] += 1
                }
            }
            return true
        }
        // Keep the order they appear in, but drop names that are part of a longer one.
        let unique = order.filter { name in
            !order.contains { $0 != name && $0.localizedCaseInsensitiveContains(name) && counts[$0, default: 0] >= counts[name, default: 0] }
        }
        return Array(unique.prefix(limit))
    }
}

nonisolated enum ChapterParser {
    private static let expression = try? NSRegularExpression(
        pattern: #"(?m)^[\s\-•*▶►]*\(?((?:\d{1,2}:)?\d{1,2}:\d{2})\)?\s*[-–—:|]?\s*(.{2,90})$"#
    )

    /// "0:00 Intro" lines in a video description.
    static func chapters(in text: String) -> [Chapter] {
        guard let expression else { return [] }
        let nsText = text as NSString
        var chapters: [Chapter] = []
        for match in expression.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) where match.numberOfRanges >= 3 {
            let stamp = nsText.substring(with: match.range(at: 1))
            let title = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            guard let seconds = seconds(from: stamp), !title.isEmpty else { continue }
            if chapters.contains(where: { $0.seconds == seconds }) { continue }
            chapters.append(Chapter(seconds: seconds, title: title))
        }
        // Real chapter lists start at 0:00 and go forward.
        guard chapters.count >= 2 else { return [] }
        let sorted = chapters.sorted { $0.seconds < $1.seconds }
        return Array(sorted.prefix(24))
    }

    static func seconds(from stamp: String) -> Double? {
        let parts = stamp.split(separator: ":").compactMap { Double($0) }
        guard parts.count >= 2 else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}

nonisolated enum VisionLabels {
    /// Friendly names for common image classification labels.
    static func display(_ identifiers: [String]) -> [String] {
        var result: [String] = []
        for identifier in identifiers {
            let name = friendly(identifier)
            if !name.isEmpty, !result.contains(name) { result.append(name) }
            if result.count >= 3 { break }
        }
        return result
    }

    static func friendly(_ identifier: String) -> String {
        let map: [String: String] = [
            "sunset_sunrise": "Sunset", "sky": "Sky", "water_body": "Water", "sea": "Sea", "ocean": "Sea",
            "beach": "Beach", "desert": "Desert", "sand": "Sand", "mountain": "Mountains", "skyscraper": "Skyline",
            "cityscape": "City", "tower": "Tower", "structure": "Architecture", "building": "Building",
            "food": "Food", "meal": "Meal", "dessert": "Dessert", "drink": "Drink", "coffee": "Coffee",
            "document": "Document", "text": "Text", "receipt": "Receipt", "screenshot": "Screenshot",
            "bottle": "Bottle", "fragrance": "Perfume", "cosmetics": "Cosmetics", "people": "People",
            "portrait": "Portrait", "car": "Car", "vehicle": "Vehicle", "animal": "Animal", "cat": "Cat",
            "dog": "Dog", "plant": "Plants", "flower": "Flowers", "night_sky": "Night sky", "interior_room": "Interior",
            "map": "Map", "ticket": "Ticket", "shoes": "Shoes", "clothing": "Clothing"
        ]
        if let value = map[identifier] { return value }
        let words = identifier.split(separator: "_").map(String.init)
        guard let first = words.first, words.count <= 2 else { return "" }
        return ([first.capitalized] + words.dropFirst()).joined(separator: " ")
    }

    static let placeLike: Set<String> = [
        "structure", "tower", "skyscraper", "cityscape", "building", "bridge", "monument", "castle",
        "mosque", "church", "temple", "landmark", "sunset_sunrise", "beach", "desert", "mountain", "water_body"
    ]
}
