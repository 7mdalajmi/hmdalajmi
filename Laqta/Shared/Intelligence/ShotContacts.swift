//
//  ShotContacts.swift
//  Laqta — Shared
//
//  What a shot says about a real place: its name, where it is, how to call it,
//  and the accounts written on the sign. Pure text work — no Vision, no network,
//  no UIKit — so the share extension and the tests can both use it.
//

import Foundation

// MARK: - A handle written in the picture

nonisolated struct SocialHandle: Sendable, Hashable, Identifiable {
    nonisolated enum Service: String, Sendable, Hashable {
        case instagram, x, tiktok, snapchat

        var label: String {
            switch self {
            case .instagram: "Instagram"
            case .x: "X"
            case .tiktok: "TikTok"
            case .snapchat: "Snapchat"
            }
        }

        var symbol: String {
            switch self {
            case .instagram: "camera.circle"
            case .x: "bubble.left.and.text.bubble.right"
            case .tiktok: "music.note"
            case .snapchat: "bolt.circle"
            }
        }

        fileprivate var host: String {
            switch self {
            case .instagram: "instagram.com"
            case .x: "x.com"
            case .tiktok: "tiktok.com"
            case .snapchat: "snapchat.com"
            }
        }
    }

    var service: Service
    /// Without the "@".
    var handle: String
    /// True when a full profile address was written out, rather than a bare "@name".
    var isExplicit: Bool

    var id: String { "\(service.rawValue)|\(handle)" }
    var display: String { "@\(handle)" }

    var url: URL? {
        let path = service == .tiktok ? "/@\(handle)" : "/\(handle)"
        return URL(string: "https://www.\(service.host)\(path)")
    }
}

// MARK: - Everything the shot offers to act on

nonisolated struct ShotContacts: Sendable, Hashable {
    /// The best name for whatever this shot is of.
    var name: String?
    /// "Salmiya, Block 10 · Kuwait"
    var area: String?
    var address: String?
    var phone: String?
    var email: String?
    var handles: [SocialHandle] = []
    /// Web addresses written in the picture, profile links removed.
    var links: [String] = []
    var latitude: Double?
    var longitude: Double?
    /// The recognised text itself, for the Copy button.
    var text: String?

    var hasCoordinate: Bool { latitude != nil && longitude != nil }

    /// Is there enough here to be worth a button of its own?
    var isWorthShowing: Bool {
        name != nil || phone != nil || !handles.isEmpty || !links.isEmpty || address != nil
    }

    /// What Google should be asked about.
    var searchQuery: String? {
        let parts = [name, area ?? address].compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    var googleSearchURL: URL? {
        guard let query = searchQuery else { return nil }
        return ShotContacts.google(path: "/search", query: query)
    }

    /// Google Maps' documented universal link. Coordinates win when the shot carried them.
    var googleMapsURL: URL? {
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        var items = [URLQueryItem(name: "api", value: "1")]
        if let latitude, let longitude {
            items.append(URLQueryItem(name: "query", value: "\(latitude),\(longitude)"))
        } else if let query = searchQuery ?? address {
            items.append(URLQueryItem(name: "query", value: query))
        } else {
            return nil
        }
        components?.queryItems = items
        return components?.url
    }

    var phoneURL: URL? {
        guard let phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard digits.count >= 5 else { return nil }
        return URL(string: "tel:\(digits)")
    }

    private static func google(path: String, query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com\(path)")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

// MARK: - Reading them out of an analysis

nonisolated enum ContactReader {
    /// Handles that are really just words people write after an "@".
    private static let notHandles: Set<String> = [
        "gmail", "hotmail", "yahoo", "outlook", "icloud", "me", "home", "work",
        "email", "mail", "www", "http", "https", "all", "everyone", "here"
    ]

    /// A profile address written out in full — the only certain signal.
    private static let profileHosts: [(String, SocialHandle.Service)] = [
        ("instagram.com", .instagram),
        ("instagr.am", .instagram),
        ("tiktok.com", .tiktok),
        ("snapchat.com", .snapchat),
        ("twitter.com", .x),
        ("x.com", .x)
    ]

    static func read(_ analysis: ShotAnalysis?) -> ShotContacts {
        guard let analysis else { return ShotContacts() }
        var contacts = ShotContacts()
        let text = analysis.text

        contacts.text = text
        if let place = analysis.place {
            contacts.name = place.name
            contacts.area = place.distinctDetail
            contacts.latitude = place.latitude
            contacts.longitude = place.longitude
        } else if let first = analysis.places.first {
            contacts.name = first.name
            contacts.area = first.distinctDetail
            contacts.latitude = first.latitude
            contacts.longitude = first.longitude
        }
        if contacts.name == nil {
            contacts.name = analysis.title
        }

        for entity in analysis.entities {
            switch entity.kind {
            case .phone where contacts.phone == nil:
                contacts.phone = entity.value
            case .email where contacts.email == nil:
                contacts.email = entity.value
            case .address where contacts.address == nil:
                contacts.address = entity.value
            case .link:
                if let handle = handle(fromURL: entity.value) {
                    contacts.append(handle)
                } else {
                    contacts.links.append(entity.value)
                }
            default:
                break
            }
        }

        // A sign usually writes the profile out; a shop window often writes only "@name".
        if let text {
            for handle in handles(in: text) { contacts.append(handle) }
        }
        contacts.links = Array(LinkedHashSet(contacts.links).values.prefix(4))
        return contacts
    }

    /// Every handle written in a block of text, explicit addresses first.
    static func handles(in text: String) -> [SocialHandle] {
        var found: [SocialHandle] = []
        let words = text.split(whereSeparator: { $0.isWhitespace || $0 == "\n" || $0 == "," || $0 == "|" })
        for word in words {
            let token = String(word).trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}<>\"'،؛.,:;!؟?"))
            guard !token.isEmpty else { continue }
            if let handle = handle(fromURL: token) {
                found.append(handle)
            } else if let handle = bareHandle(token) {
                found.append(handle)
            }
        }
        return found.sorted { lhs, rhs in
            lhs.isExplicit == rhs.isExplicit ? lhs.handle < rhs.handle : lhs.isExplicit
        }
    }

    /// "https://instagram.com/altijara.kw" → Instagram, @altijara.kw
    static func handle(fromURL raw: String) -> SocialHandle? {
        let lowered = raw.lowercased()
        guard let match = profileHosts.first(where: { lowered.contains($0.0) }) else { return nil }
        guard let range = lowered.range(of: match.0) else { return nil }
        var rest = String(lowered[range.upperBound...])
        while rest.hasPrefix("/") || rest.hasPrefix("@") { rest.removeFirst() }
        // Drop a query string, a fragment, and anything past the account itself.
        let account = rest.prefix { character in
            character.isLetter || character.isNumber || character == "." || character == "_" || character == "-"
        }
        let handle = String(account)
        guard isPlausible(handle) else { return nil }
        return SocialHandle(service: match.1, handle: handle, isExplicit: true)
    }

    /// "@altijara.kw" on a sign. Read as Instagram — that is what a bare handle
    /// almost always means on a shopfront — but marked as a guess.
    static func bareHandle(_ token: String) -> SocialHandle? {
        guard token.hasPrefix("@") else { return nil }
        let handle = String(token.dropFirst()).lowercased()
        // "name@gmail.com" arrives here only when the "@" leads, so this catches "@gmail.com".
        guard !handle.contains("@"), isPlausible(handle) else { return nil }
        let head = handle.split(separator: ".").first.map(String.init) ?? handle
        guard !notHandles.contains(head) else { return nil }
        return SocialHandle(service: .instagram, handle: handle, isExplicit: false)
    }

    private static func isPlausible(_ handle: String) -> Bool {
        guard handle.count >= 3, handle.count <= 30 else { return false }
        guard handle.contains(where: \.isLetter) else { return false }
        let allowed = handle.allSatisfy { character in
            character.isLetter || character.isNumber || character == "." || character == "_" || character == "-"
        }
        return allowed && !handle.hasPrefix(".") && !handle.hasSuffix(".")
    }
}

nonisolated private extension ShotContacts {
    mutating func append(_ handle: SocialHandle) {
        if let index = handles.firstIndex(where: { $0.service == handle.service && $0.handle == handle.handle }) {
            // An address written out beats a bare "@name" for the same account.
            if handle.isExplicit { handles[index] = handle }
            return
        }
        guard handles.count < 3 else { return }
        handles.append(handle)
    }
}

/// Keeps the first spelling of each value and the order they arrived in.
nonisolated private struct LinkedHashSet {
    var values: [String] = []

    init(_ items: [String]) {
        var seen = Set<String>()
        for item in items where seen.insert(item.lowercased()).inserted {
            values.append(item)
        }
    }
}
