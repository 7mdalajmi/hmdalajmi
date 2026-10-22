//
//  FolderSuggester.swift
//  Laqta — Shared
//
//  Suggests the folder for a new shot or link, or a new folder when none fits.
//

import Foundation

nonisolated struct FolderSnapshot: Sendable, Hashable {
    let id: UUID
    let name: String
    let isLocked: Bool
    let lastUpdate: Date
}

nonisolated struct FolderSuggestion: Sendable, Equatable {
    enum Target: Sendable, Equatable {
        case existing(UUID)
        case new(name: String, symbol: String, tone: FolderTone)
    }

    var target: Target
    var reason: String

    var existingID: UUID? {
        if case let .existing(id) = target { return id }
        return nil
    }
}

nonisolated struct FolderCategory: Sendable {
    let id: String
    /// Name used when Laqta suggests creating the folder.
    let folderName: String
    /// Folder names that already mean this category.
    let aliases: [String]
    let keywords: [String]
    let visionLabels: [String]
    let hosts: [String]
    let symbol: String
    let tone: FolderTone
    /// "city", "travel" — used in reasons.
    let noun: String
}

/// The plural nouns a suggestion's reason reads with.
///
/// They live in their own table: "shots" has to count ("12 لقطة") in one place and
/// read as a plural noun phrase ("مثل بقية لقطات السفر") in another, and a String
/// Catalog's key is the English string itself — so the two readings need two tables.
nonisolated enum SuggestionWords {
    static func plural(_ word: String) -> String {
        String(localized: String.LocalizationValue(stringLiteral: word), table: "Suggestions")
    }
}

nonisolated enum FolderSuggester {
    static let categories: [FolderCategory] = [
        FolderCategory(
            id: "travel", folderName: String(localized: "Travel"),
            aliases: ["السفر", "سفر", "رحلات", "رحلة", "سفرات", "travel", "trips", "trip"],
            keywords: ["flight", "boarding", "airport", "airline", "hotel", "booking", "reservation", "check-in", "passport", "visa", "trip", "travel", "itinerary", "resort", "airbnb", "vacation", "holiday", "trail", "waterfall", "national park", "island", "beach", "hiking", "رحلة", "طيران", "فندق", "حجز", "مطار", "تذكرة", "سفر", "جواز", "تأشيرة", "منتجع", "شاطئ", "جزيرة"],
            visionLabels: ["beach", "airplane", "aircraft", "airport", "resort", "swimming_pool", "suitcase", "waterfall", "mountain", "landscape", "hill", "cliff", "canyon", "glacier", "volcano", "lake", "island", "shore", "coast"],
            hosts: ["booking.com", "airbnb.com", "expedia.com", "tripadvisor.com", "skyscanner", "kayak.com", "agoda.com", "almosafer.com", "wego.com"],
            symbol: "airplane", tone: .ember, noun: String(localized: "travel")
        ),
        FolderCategory(
            id: "perfume", folderName: String(localized: "Perfume"),
            aliases: ["العطور", "عطور", "عطر", "العطر", "perfume", "perfumes", "fragrance", "fragrances"],
            keywords: ["perfume", "parfum", "fragrance", "eau de", "oud", "musk", "cologne", "notes of", "عطر", "عطور", "عود", "مسك", "بخور", "دهن", "معطر"],
            visionLabels: ["fragrance", "perfume", "cosmetics"],
            hosts: ["fragrantica.com", "sephora", "basenotes"],
            symbol: "drop", tone: .olive, noun: String(localized: "perfume")
        ),
        FolderCategory(
            id: "cities", folderName: String(localized: "Cities"),
            aliases: ["المدن", "مدن", "أماكن", "اماكن", "الأماكن", "cities", "places", "city"],
            keywords: ["city", "tower", "skyline", "landmark", "downtown", "district", "souq", "souk", "museum", "old town", "square", "guide to", "things to do", "مدينة", "برج", "سوق", "معلم", "متحف", "أماكن", "جولة"],
            visionLabels: ["cityscape", "skyscraper", "tower", "structure", "building", "bridge", "monument", "castle", "mosque"],
            hosts: ["visit", "timeout.com", "lonelyplanet.com"],
            symbol: "building.2", tone: .tide, noun: String(localized: "city")
        ),
        FolderCategory(
            id: "food", folderName: String(localized: "Food"),
            aliases: ["المطاعم", "مطاعم", "اكل", "أكل", "الأكل", "طبخ", "وصفات", "food", "restaurants", "recipes", "cafes", "كافيهات"],
            keywords: ["restaurant", "cafe", "coffee", "menu", "recipe", "food", "dinner", "lunch", "breakfast", "burger", "pizza", "machboos", "sushi", "brunch", "bakery", "مطعم", "مطاعم", "قهوة", "كافيه", "وصفة", "أكل", "اكل", "طبخ", "مجبوس", "فطور", "عشاء", "غداء"],
            visionLabels: ["food", "meal", "dessert", "drink", "coffee", "baked_goods", "sandwich", "pizza"],
            hosts: ["talabat.com", "deliveroo", "zomato.com", "opentable.com", "allrecipes.com"],
            symbol: "fork.knife", tone: .ember, noun: String(localized: "food")
        ),
        FolderCategory(
            id: "shopping", folderName: String(localized: "Shopping"),
            aliases: ["التسوق", "تسوق", "مشتريات", "المشتريات", "shopping", "wishlist", "shop"],
            keywords: ["add to cart", "buy now", "sale", "discount", "offer", "free delivery", "in stock", "order", "size guide", "خصم", "عرض", "شراء", "توصيل مجاني", "أضف إلى السلة", "السلة"],
            visionLabels: ["shoes", "handbag", "clothing", "watch", "jewelry"],
            hosts: ["amazon.", "noon.com", "shein.com", "ebay.", "aliexpress", "namshi.com", "ounass.com", "xcite.com"],
            symbol: "bag", tone: .sand, noun: String(localized: "shopping")
        ),
        FolderCategory(
            id: "tech", folderName: String(localized: "Tech"),
            aliases: ["التقنية", "تقنية", "برمجة", "البرمجة", "tech", "technology", "apps", "code"],
            keywords: ["iphone", "ipad", "macbook", "apple", "app store", "swiftui", "xcode", "developer", "software", "api", "github", "programming", "ai model", "تطبيق", "برمجة", "تقنية", "آيفون", "ايفون", "ذكاء اصطناعي"],
            visionLabels: ["computer", "laptop", "phone", "electronics"],
            hosts: ["github.com", "apple.com", "developer.apple.com", "stackoverflow.com", "theverge.com", "9to5mac.com", "macrumors.com"],
            symbol: "lightbulb", tone: .tide, noun: String(localized: "tech")
        ),
        FolderCategory(
            id: "learning", folderName: String(localized: "Learning"),
            aliases: ["تعلم", "تعلّم", "دروس", "الدروس", "دراسة", "learning", "courses", "study", "lessons"],
            keywords: ["course", "lesson", "tutorial", "learn", "lecture", "how to", "step by step", "explained", "درس", "دورة", "شرح", "تعلم", "محاضرة", "خطوات"],
            visionLabels: ["blackboard", "book"],
            hosts: ["coursera.org", "udemy.com", "khanacademy.org", "edx.org"],
            symbol: "graduationcap", tone: .olive, noun: String(localized: "learning")
        ),
        FolderCategory(
            id: "fitness", folderName: String(localized: "Fitness"),
            aliases: ["الرياضة", "رياضة", "تمارين", "fitness", "workout", "gym", "sport"],
            keywords: ["workout", "gym", "exercise", "training", "running", "fitness", "calories", "protein", "reps", "تمارين", "تمرين", "رياضة", "جيم", "نادي", "سعرات"],
            visionLabels: ["gym", "sport", "exercise_equipment", "running"],
            hosts: ["strava.com", "nike.com"],
            symbol: "dumbbell", tone: .dusk, noun: String(localized: "fitness")
        ),
        FolderCategory(
            id: "documents", folderName: String(localized: "Documents"),
            aliases: ["المستندات", "مستندات", "اوراق", "أوراق", "فواتير", "الفواتير", "documents", "bills", "papers"],
            keywords: ["invoice", "receipt", "bill", "warranty", "contract", "policy", "insurance", "statement", "certificate", "فاتورة", "إيصال", "ايصال", "ضمان", "عقد", "تأمين", "شهادة", "كشف حساب"],
            visionLabels: ["document", "receipt", "text"],
            hosts: [],
            symbol: "doc.text", tone: .sand, noun: String(localized: "document")
        ),
        FolderCategory(
            id: "home", folderName: String(localized: "Home"),
            aliases: ["البيت", "المنزل", "بيت", "home", "decor", "ديكور"],
            keywords: ["furniture", "decor", "sofa", "kitchen", "interior", "garden", "lamp", "rug", "أثاث", "ديكور", "مطبخ", "حديقة", "كنب"],
            visionLabels: ["interior_room", "furniture", "sofa", "kitchen", "bedroom"],
            hosts: ["ikea.", "homecentre", "westelm.com", "potterybarn"],
            symbol: "house", tone: .sand, noun: String(localized: "home")
        ),
        FolderCategory(
            id: "cars", folderName: String(localized: "Cars"),
            aliases: ["السيارات", "سيارات", "cars", "car"],
            keywords: ["horsepower", "engine", "sedan", "suv", "bmw", "mercedes", "toyota", "lexus", "porsche", "tesla", "سيارة", "سيارات", "محرك"],
            visionLabels: ["car", "vehicle", "sports_car", "wheel"],
            hosts: ["motor1.com", "caranddriver.com", "topgear.com"],
            symbol: "car", tone: .dusk, noun: String(localized: "car")
        ),
        FolderCategory(
            id: "fashion", folderName: String(localized: "Fashion"),
            aliases: ["الأزياء", "ازياء", "ملابس", "الملابس", "fashion", "outfits", "style"],
            keywords: ["dress", "outfit", "fashion", "jacket", "abaya", "dishdasha", "sneakers", "ملابس", "فستان", "عباية", "دشداشة", "أزياء"],
            visionLabels: ["clothing", "dress", "shoes", "fashion"],
            hosts: ["zara.com", "hm.com", "farfetch.com", "net-a-porter.com"],
            symbol: "tshirt", tone: .dusk, noun: String(localized: "fashion")
        ),
        FolderCategory(
            id: "watch", folderName: String(localized: "To Watch"),
            aliases: ["للمشاهدة", "مشاهدة", "أفلام", "افلام", "الأفلام", "مسلسلات", "فيديوهات", "to watch", "watch", "movies", "films", "watch later", "videos", "shows"],
            keywords: ["movie", "film", "trailer", "short film", "animation", "animated", "episode", "season", "series", "documentary", "netflix", "فيلم", "أفلام", "مسلسل", "حلقة", "وثائقي", "رسوم متحركة"],
            visionLabels: ["movie", "cinema", "television"],
            hosts: ["imdb.com", "netflix.com", "shahid.mbc.net", "primevideo.com", "tv.apple.com", "letterboxd.com"],
            symbol: "play.rectangle", tone: .dusk, noun: String(localized: "watch-later")
        ),
        FolderCategory(
            id: "music", folderName: String(localized: "Music"),
            aliases: ["الموسيقى", "موسيقى", "أغاني", "اغاني", "music", "songs"],
            keywords: ["song", "album", "music video", "official audio", "lyrics", "playlist", "concert", "acoustic", "أغنية", "ألبوم", "موسيقى", "كليب"],
            visionLabels: ["musical_instrument", "guitar", "piano", "concert"],
            hosts: ["spotify.com", "music.apple.com", "soundcloud.com", "anghami.com"],
            symbol: "music.note", tone: .dusk, noun: String(localized: "music")
        ),
        FolderCategory(
            id: "events", folderName: String(localized: "Events"),
            aliases: ["المواعيد", "مواعيد", "الحجوزات", "events", "tickets"],
            keywords: ["ticket", "concert", "appointment", "invitation", "event", "match", "admit one", "موعد", "حفلة", "دعوة", "فعالية", "مباراة"],
            visionLabels: ["ticket", "concert", "stage"],
            hosts: ["ticketmaster", "eventbrite", "platinumlist"],
            symbol: "calendar", tone: .ember, noun: String(localized: "event")
        )
    ]

    /// Picks an existing folder, or proposes a new one.
    static func suggest(
        text: String,
        title: String = "",
        labels: [String],
        host: String?,
        isLink: Bool,
        kindLabel: String?,
        folders: [FolderSnapshot],
        lastUsedFolderID: UUID?,
        itemNoun: String? = nil
    ) -> FolderSuggestion? {
        let haystack = SearchIndex.normalize(text)
        let heading = SearchIndex.normalize(title)
        let hostLower = host?.lowercased() ?? ""
        let itemNoun = itemNoun ?? SuggestionWords.plural(isLink ? "links" : "shots")

        // 1. A folder whose name appears in the content.
        for folder in folders where !folder.isLocked {
            let name = SearchIndex.normalize(folder.name)
            if name.count >= 3, haystack.contains(name) {
                return FolderSuggestion(target: .existing(folder.id), reason: lead(kindLabel, String(localized: "mentions \(folder.name)")))
            }
        }

        // 2. Category scores.
        var best: (category: FolderCategory, score: Int)?
        for category in categories {
            var score = 0
            for keyword in category.keywords {
                let word = SearchIndex.normalize(keyword)
                if !heading.isEmpty, heading.contains(word) {
                    score += 2
                } else if haystack.contains(word) {
                    score += keyword.count > 5 ? 2 : 1
                }
            }
            for label in labels where category.visionLabels.contains(label) {
                score += 2
            }
            if !hostLower.isEmpty, category.hosts.contains(where: { hostLower.contains($0) }) {
                score += 4
            }
            if score > (best?.score ?? 0) {
                best = (category, score)
            }
        }

        if let best, best.score >= 2 {
            let category = best.category
            if let folder = folder(for: category, in: folders) {
                return FolderSuggestion(
                    target: .existing(folder.id),
                    reason: lead(kindLabel, String(localized: "like your other \(category.noun) \(itemNoun)"))
                )
            }
            if !folders.contains(where: { SearchIndex.normalize($0.name) == SearchIndex.normalize(category.folderName) }) {
                return FolderSuggestion(
                    target: .new(name: category.folderName, symbol: category.symbol, tone: category.tone),
                    reason: lead(kindLabel, String(localized: "no \(category.noun) folder yet"))
                )
            }
        }

        // 3. Where the last item went.
        if let lastUsedFolderID, folders.contains(where: { $0.id == lastUsedFolderID }) {
            return FolderSuggestion(target: .existing(lastUsedFolderID), reason: String(localized: "Where you saved last time"))
        }
        if let recent = folders.filter({ !$0.isLocked }).max(by: { $0.lastUpdate < $1.lastUpdate }) {
            return FolderSuggestion(target: .existing(recent.id), reason: String(localized: "Your most recently updated folder"))
        }
        return nil
    }

    static func folder(for category: FolderCategory, in folders: [FolderSnapshot]) -> FolderSnapshot? {
        let aliases = Set(category.aliases.map { SearchIndex.normalize($0) })
        return folders.first { folder in
            let name = SearchIndex.normalize(folder.name)
            return aliases.contains(name) || aliases.contains { alias in alias.count >= 4 && name.contains(alias) }
        }
    }

    /// Icon for a folder name the user typed.
    /// The category a folder name belongs to, if any.
    ///
    /// Tried in three passes, strictest first: the name *is* one of the known
    /// names, the name *contains* one, or one of the category's own keywords
    /// appears in it — so "Flights" finds travel even though nobody listed it.
    static func category(forName name: String) -> FolderCategory? {
        let normalized = SearchIndex.normalize(name)
        guard !normalized.isEmpty else { return nil }

        for category in categories {
            let aliases = category.aliases.map { SearchIndex.normalize($0) }
            if aliases.contains(normalized) { return category }
        }
        for category in categories {
            let aliases = category.aliases.map { SearchIndex.normalize($0) }
            if aliases.contains(where: { $0.count >= 4 && normalized.contains($0) }) { return category }
        }
        // A folder name is a couple of words, so one keyword is enough here.
        for category in categories {
            let hit = category.keywords.contains { keyword in
                let word = SearchIndex.normalize(keyword)
                return word.count >= 4 && normalized.contains(word)
            }
            if hit { return category }
        }
        return nil
    }

    static func symbol(forName name: String) -> String {
        let normalized = SearchIndex.normalize(name)
        if normalized.contains("خاص") || normalized.contains("private") || normalized.contains("سري") {
            return "lock"
        }
        return category(forName: name)?.symbol ?? "folder"
    }

    /// Cover mood for a folder name the user typed.
    static func tone(forName name: String) -> FolderTone? {
        let normalized = SearchIndex.normalize(name)
        return categories.first { category in
            category.aliases.map { SearchIndex.normalize($0) }.contains(normalized)
        }?.tone
    }

    private static func lead(_ kindLabel: String?, _ tail: String) -> String {
        guard let kindLabel, !kindLabel.isEmpty else {
            return tail.prefix(1).uppercased() + tail.dropFirst()
        }
        return "\(kindLabel) · \(tail)"
    }
}
