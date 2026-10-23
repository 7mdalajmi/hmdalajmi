//
//  LibraryDeduplicator.swift
//  Laqta
//
//  With iCloud sync, two devices can hold the same folder (the starter folders) or the
//  same item (a backup restored on both). Records with the same ID are merged into one.
//

import Foundation
import SwiftData

enum LibraryDeduplicator {
    /// Returns how many duplicate records were removed.
    @discardableResult
    static func run(context: ModelContext) -> Int {
        var removed = 0
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        for group in Dictionary(grouping: folders, by: \.id).values where group.count > 1 {
            guard let keep = group.max(by: { folderScore($0) < folderScore($1) }) else { continue }
            for other in group where other !== keep {
                merge(other, into: keep)
                context.delete(other)
                removed += 1
            }
        }

        let items = (try? context.fetch(FetchDescriptor<Shot>())) ?? []
        for group in Dictionary(grouping: items, by: \.id).values where group.count > 1 {
            guard let keep = group.max(by: { itemScore($0) < itemScore($1) }) else { continue }
            for other in group where other !== keep {
                merge(other, into: keep)
                // The files are shared (same names), so only the record goes.
                context.delete(other)
                removed += 1
            }
        }
        if removed > 0 {
            guard context.commit(.deduplicate) else { return 0 }
            DebugLog.write("dedupe: removed \(removed)")
        }
        return removed
    }

    private static func folderScore(_ folder: Folder) -> Double {
        var score = folder.lastUpdate.timeIntervalSince1970
        if folder.deletedAt == nil { score += 1e12 }
        return score
    }

    private static func merge(_ other: Folder, into keep: Folder) {
        if keep.parentID == nil { keep.parentID = other.parentID }
        keep.isLocked = keep.isLocked || other.isLocked
        if let date = other.updatedAt, date > (keep.updatedAt ?? .distantPast) {
            keep.updatedAt = date
        }
        if keep.deletedAt != nil, other.deletedAt == nil {
            keep.deletedAt = nil
            keep.deletionBatch = nil
        }
        if keep.sortRaw == nil { keep.sortRaw = other.sortRaw }
        if other.createdAt < keep.createdAt { keep.createdAt = other.createdAt }
    }

    private static func itemScore(_ item: Shot) -> Int {
        var score = 0
        if item.deletedAt == nil { score += 1_000 }
        if item.analysisData != nil { score += 100 }
        if item.analysisState == .done { score += 50 }
        if !item.note.isEmpty { score += 20 }
        if item.hasMediaFile { score += 10 }
        if item.mediaInCloud == true { score += 5 }
        return score
    }

    private static func merge(_ other: Shot, into keep: Shot) {
        if keep.note.isEmpty, !other.note.isEmpty {
            keep.note = other.note
            keep.noteUpdatedAt = other.noteUpdatedAt
        }
        keep.isFavorite = keep.isFavorite || other.isFavorite
        if let viewed = other.viewedAt, viewed > (keep.viewedAt ?? .distantPast) {
            keep.viewedAt = viewed
        }
        if keep.mediaInCloud != true, other.mediaInCloud == true {
            keep.mediaInCloud = true
        }
        if keep.analysisData == nil, other.analysisData != nil {
            keep.analysisData = other.analysisData
            keep.analysisStateRaw = other.analysisStateRaw
        }
        keep.refreshIndex()
    }
}
