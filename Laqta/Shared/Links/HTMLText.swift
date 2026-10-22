//
//  HTMLText.swift
//  Laqta — Shared
//
//  Small, forgiving HTML reader: meta tags, JSON-LD, readable text.
//

import Foundation

nonisolated struct PageInfo: Sendable {
    var title: String?
    var meta: [String: String] = [:]
    var description: String?
    var author: String?
    var published: Date?
    var duration: Double?
    var image: String?
    var ogType: String?
    var siteName: String?
    var price: String?
    var productName: String?
    var bodyText: String?
    var headings: [String] = []
    var ldDescription: String?
    var ldPlace: PlaceRef?
    var ingredients: [String] = []
}

nonisolated enum HTMLText {
    private static let metaTag = try? NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive])
    private static let attribute = try? NSRegularExpression(pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#)
    private static let titleTag = try? NSRegularExpression(pattern: #"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let ldScript = try? NSRegularExpression(pattern: #"<script[^>]*application/ld\+json[^>]*>(.*?)</script>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let dropBlocks = try? NSRegularExpression(pattern: #"<(script|style|noscript|svg|template|iframe|nav|footer|header|form|aside|button|select)\b[^>]*>.*?</\1>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let comments = try? NSRegularExpression(pattern: #"<!--.*?-->"#, options: [.dotMatchesLineSeparators])
    private static let breaks = try? NSRegularExpression(pattern: #"<(br|/p|/div|/li|/h[1-6]|/tr|/section|/article|/blockquote)\b[^>]*>"#, options: [.caseInsensitive])
    private static let tags = try? NSRegularExpression(pattern: #"<[^>]+>"#)
    private static let headingTag = try? NSRegularExpression(pattern: #"<h([23])[^>]*>(.*?)</h\1>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let articleTag = try? NSRegularExpression(pattern: #"<(article|main)\b[^>]*>(.*)</\1>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let bodyTag = try? NSRegularExpression(pattern: #"<body\b[^>]*>(.*)</body>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let spaces = try? NSRegularExpression(pattern: #"[ \t\u{00A0}]+"#)
    private static let blankLines = try? NSRegularExpression(pattern: #"\n\s*\n+"#)

    static func parse(_ html: String, readBody: Bool) -> PageInfo {
        var info = PageInfo()
        let ns = html as NSString
        let head = ns.length > 400_000 ? ns.substring(to: 400_000) : html

        // Meta tags.
        for match in metaTag?.matches(in: head, range: NSRange(location: 0, length: (head as NSString).length)) ?? [] {
            let tag = (head as NSString).substring(with: match.range)
            let attributes = attributesOf(tag)
            guard let content = attributes["content"], !content.isEmpty else { continue }
            let key = (attributes["property"] ?? attributes["name"] ?? attributes["itemprop"] ?? "").lowercased()
            guard !key.isEmpty, info.meta[key] == nil else { continue }
            info.meta[key] = decodeEntities(content)
        }

        if let match = titleTag?.firstMatch(in: head, range: NSRange(location: 0, length: (head as NSString).length)) {
            info.title = clean((head as NSString).substring(with: match.range(at: 1)))
        }

        info.ogType = info.meta["og:type"]
        info.siteName = info.meta["og:site_name"] ?? info.meta["application-name"]
        info.description = info.meta["og:description"] ?? info.meta["description"] ?? info.meta["twitter:description"]
        info.image = info.meta["og:image"] ?? info.meta["og:image:url"] ?? info.meta["twitter:image"] ?? info.meta["twitter:image:src"]
        info.author = info.meta["author"] ?? info.meta["article:author"] ?? info.meta["twitter:creator"]
        // A page can claim any duration it likes, including "inf" and "nan", both of
        // which Double() happily parses. Nothing past a week is a real video.
        if let seconds = info.meta["video:duration"] ?? info.meta["og:video:duration"],
           let value = Double(seconds), value.isFinite, value > 0, value < 86_400 * 7 {
            info.duration = value
        }
        if let published = info.meta["article:published_time"] ?? info.meta["og:published_time"] ?? info.meta["datepublished"] {
            info.published = parseDate(published)
        }
        if let amount = info.meta["product:price:amount"] ?? info.meta["og:price:amount"] {
            let currency = info.meta["product:price:currency"] ?? info.meta["og:price:currency"] ?? ""
            info.price = "\(amount) \(currency)".trimmingCharacters(in: .whitespaces)
        }

        readJSONLD(in: html, into: &info)

        if readBody {
            info.bodyText = readableText(html)
            info.headings = headings(in: html)
        }
        return info
    }

    static func attributesOf(_ tag: String) -> [String: String] {
        var result: [String: String] = [:]
        let ns = tag as NSString
        for match in attribute?.matches(in: tag, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let name = ns.substring(with: match.range(at: 1)).lowercased()
            let valueRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
            guard valueRange.location != NSNotFound else { continue }
            result[name] = ns.substring(with: valueRange)
        }
        return result
    }

    // MARK: JSON-LD

    private static func readJSONLD(in html: String, into info: inout PageInfo) {
        let ns = html as NSString
        for match in ldScript?.matches(in: html, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let raw = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { continue }
            visit(json, info: &info)
        }
    }

    private static func visit(_ node: Any, info: inout PageInfo) {
        if let array = node as? [Any] {
            for item in array { visit(item, info: &info) }
            return
        }
        guard let object = node as? [String: Any] else { return }
        if let graph = object["@graph"] {
            visit(graph, info: &info)
        }
        let types: [String]
        if let type = object["@type"] as? String {
            types = [type]
        } else {
            types = (object["@type"] as? [String]) ?? []
        }
        let lowered = Set(types.map { $0.lowercased() })

        if lowered.contains("videoobject") {
            if info.duration == nil, let duration = object["duration"] as? String {
                info.duration = isoDuration(duration)
            }
            if info.ldDescription == nil, let description = object["description"] as? String {
                info.ldDescription = decodeEntities(description)
            }
            if info.published == nil, let date = (object["uploadDate"] as? String) ?? (object["datePublished"] as? String) {
                info.published = parseDate(date)
            }
        }
        if !lowered.isDisjoint(with: ["article", "newsarticle", "blogposting", "report", "techarticle"]) {
            if info.author == nil { info.author = name(of: object["author"]) }
            if info.published == nil, let date = object["datePublished"] as? String {
                info.published = parseDate(date)
            }
            if info.ldDescription == nil, let description = object["description"] as? String {
                info.ldDescription = decodeEntities(description)
            }
        }
        if lowered.contains("product") {
            if info.productName == nil, let name = object["name"] as? String {
                info.productName = decodeEntities(name)
            }
            if info.price == nil {
                let offers = object["offers"]
                let offer = (offers as? [String: Any]) ?? ((offers as? [Any])?.first as? [String: Any])
                if let offer {
                    let amount = stringValue(offer["price"]) ?? stringValue(offer["lowPrice"])
                    let currency = stringValue(offer["priceCurrency"]) ?? ""
                    if let amount { info.price = "\(amount) \(currency)".trimmingCharacters(in: .whitespaces) }
                }
            }
        }
        if lowered.contains("recipe"), let ingredients = object["recipeIngredient"] as? [String] {
            info.ingredients = ingredients.map(decodeEntities)
        }
        let placeTypes: Set<String> = ["place", "restaurant", "hotel", "localbusiness", "touristattraction", "landmarksorhistoricalbuildings", "cafeorcoffeeshop", "store", "lodgingbusiness", "foodestablishment"]
        if !lowered.isDisjoint(with: placeTypes), info.ldPlace == nil, let name = object["name"] as? String {
            var place = PlaceRef(name: decodeEntities(name))
            if let address = object["address"] as? [String: Any] {
                let parts = [address["streetAddress"], address["addressLocality"], address["addressCountry"]]
                    .compactMap { stringValue($0) }
                    .filter { !$0.isEmpty }
                place.detail = parts.isEmpty ? nil : parts.joined(separator: ", ")
            } else if let address = object["address"] as? String {
                place.detail = address
            }
            if let geo = object["geo"] as? [String: Any],
               let latitude = doubleValue(geo["latitude"]),
               let longitude = doubleValue(geo["longitude"]) {
                place.latitude = latitude
                place.longitude = longitude
            }
            place.category = types.first
            place.origin = "Page"
            info.ldPlace = place
        }
    }

    private static func name(of value: Any?) -> String? {
        if let string = value as? String { return string }
        if let object = value as? [String: Any] { return object["name"] as? String }
        if let array = value as? [Any] { return array.lazy.compactMap { name(of: $0) }.first }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let object = value as? [String: Any] { return object["name"] as? String }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    // MARK: Text

    static func readableText(_ html: String, limit: Int = 60_000) -> String {
        var working = html
        if let match = articleTag?.firstMatch(in: working, range: NSRange(location: 0, length: (working as NSString).length)) {
            working = (working as NSString).substring(with: match.range(at: 2))
        } else if let match = bodyTag?.firstMatch(in: working, range: NSRange(location: 0, length: (working as NSString).length)) {
            working = (working as NSString).substring(with: match.range(at: 1))
        }
        if (working as NSString).length > 1_500_000 {
            working = (working as NSString).substring(to: 1_500_000)
        }
        working = replace(comments, in: working, with: " ")
        working = replace(dropBlocks, in: working, with: " ")
        working = replace(breaks, in: working, with: "\n")
        working = replace(tags, in: working, with: " ")
        working = decodeEntities(working)
        working = replace(spaces, in: working, with: " ")
        working = replace(blankLines, in: working, with: "\n\n")
        let lines = working.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 1 }
        return String(lines.joined(separator: "\n").prefix(limit))
    }

    static func headings(in html: String) -> [String] {
        let ns = html as NSString
        var result: [String] = []
        for match in headingTag?.matches(in: html, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let text = clean(replace(tags, in: ns.substring(with: match.range(at: 2)), with: " "))
            if text.count >= 3, text.count <= 90, !result.contains(text) { result.append(text) }
            if result.count >= 12 { break }
        }
        return result
    }

    static func clean(_ text: String) -> String {
        decodeEntities(text)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ expression: NSRegularExpression?, in text: String, with template: String) -> String {
        guard let expression else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
            "ndash": "–", "mdash": "—", "hellip": "…", "rsquo": "’", "lsquo": "‘",
            "rdquo": "”", "ldquo": "“", "middot": "·", "bull": "•", "copy": "©", "reg": "®", "trade": "™"
        ]
        while index < text.endIndex {
            let character = text[index]
            if character == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") {
                let entity = String(text[text.index(after: index)..<semicolon])
                var replacement: String?
                if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                    if let code = UInt32(entity.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                        replacement = String(Character(scalar))
                    }
                } else if entity.hasPrefix("#") {
                    if let code = UInt32(entity.dropFirst()), let scalar = Unicode.Scalar(code) {
                        replacement = String(Character(scalar))
                    }
                } else {
                    replacement = named[entity.lowercased()]
                }
                if let replacement {
                    result += replacement
                    index = text.index(after: semicolon)
                    continue
                }
            }
            result.append(character)
            index = text.index(after: index)
        }
        return result
    }

    // MARK: Values

    static func isoDuration(_ value: String) -> Double? {
        // PT1H2M3S
        guard value.uppercased().hasPrefix("PT") || value.uppercased().hasPrefix("P") else { return Double(value) }
        var total: Double = 0
        var number = ""
        var sawTime = false
        for character in value.uppercased() {
            if character.isNumber || character == "." {
                number.append(character)
                continue
            }
            let amount = Double(number) ?? 0
            number = ""
            switch character {
            case "T": sawTime = true
            case "H": total += amount * 3600
            case "M": total += sawTime ? amount * 60 : amount * 2_592_000
            case "S": total += amount
            case "D": total += amount * 86_400
            default: break
            }
        }
        return total > 0 ? total : nil
    }

    static func parseDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let full = ISO8601DateFormatter()
        if let date = full.date(from: trimmed) { return date }
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = full.date(from: trimmed) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd", "yyyy/MM/dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: String(trimmed.prefix(25))) { return date }
        }
        return nil
    }
}
