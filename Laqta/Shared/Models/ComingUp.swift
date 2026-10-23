//
//  ComingUp.swift
//  Laqta — Shared
//
//  Laqta already reads the date out of a boarding pass, a renewal notice or a
//  warranty. This is what it does with it: the shots that have a day attached,
//  soonest first, above everything else in the library.
//
//  The dated value carries no live model object, so it can be handed to a
//  notification, held in state, or checked in a test without a database.
//

import Foundation

nonisolated struct DatedShot: Sendable, Hashable, Identifiable {
    var itemID: UUID
    var folderID: UUID?
    /// "Kuwait → Dubai"
    var title: String
    /// "Boarding pass · 12B"
    var detail: String?
    var date: Date
    var allDay: Bool
    var thumbnailName: String

    var id: UUID { itemID }

    /// Whole days from today until the day it happens. Today is 0.
    func daysAway(from now: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// True while it is close enough to deserve the gold treatment.
    func isImminent(from now: Date = .now) -> Bool {
        (0...2).contains(daysAway(from: now))
    }
}

nonisolated enum ComingUp {
    /// A year-old warranty is not news. Six months is as far as the strip looks.
    static let horizonDays = 190
    /// The strip is a glance, not a list.
    static let stripLimit = 3

    /// Should this date be shown at all?
    static func isWorthShowing(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: horizonDays, to: today) else { return false }
        // Something happening later today still counts; yesterday does not.
        return calendar.startOfDay(for: date) >= today && date < horizon
    }

    /// The soonest date worth showing on one item, if it has one.
    static func soonest(
        in entities: [DetectedEntity],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DetectedEntity? {
        entities
            .filter { $0.kind == .date }
            .compactMap { entity -> (DetectedEntity, Date)? in
                guard let date = entity.date, isWorthShowing(date, now: now, calendar: calendar) else { return nil }
                return (entity, date)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// Orders what the strip shows: soonest first, and never two rows for one shot.
    static func order(_ dated: [DatedShot]) -> [DatedShot] {
        var seen = Set<UUID>()
        return dated
            .sorted { $0.date < $1.date }
            .filter { seen.insert($0.itemID).inserted }
    }
}
