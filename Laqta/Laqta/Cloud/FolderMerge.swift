//
//  FolderMerge.swift
//  Laqta
//
//  Two devices can each make a folder with the same name, and sync then brings both.
//  Laqta folds them together quietly when one side is empty, and asks first when both
//  hold something. A refusal is remembered, and "Merge" stays in the folder's menu.
//

import Foundation
import SwiftData

/// Two folders carrying the same name.
nonisolated struct FolderMergePair: Identifiable, Sendable, Equatable {
    /// The folder that stays, with its name, icon and cover.
    let keepID: UUID
    /// The folder whose items move over; its record goes away.
    let mergeID: UUID
    let name: String
    let keepCount: Int
    let mergeCount: Int
    let keepCreatedAt: Date
    let mergeCreatedAt: Date

    var id: String { FolderMerge.key(keepID, mergeID) }
    var total: Int { keepCount + mergeCount }

    /// One side holds nothing, so there is nothing to weigh up: Laqta merges without asking.
    var isEmptySided: Bool { keepCount == 0 || mergeCount == 0 }
}

enum FolderMerge {

    // MARK: Finding

    /// Same-name folders, worked out from lists Home already has in hand.
    /// Names match exactly, apart from stray spaces at either end, and only inside the
    /// same parent — two folders called "Receipts" in different folders are different folders.
    static func pairs(folders: [Folder], counts: [UUID: Int]) -> [FolderMergePair] {
        let live = folders.filter { $0.deletedAt == nil }
        let grouped = Dictionary(grouping: live) { folder in
            "\(folder.parentID?.uuidString ?? "-")/\(name(of: folder))"
        }
        var result: [FolderMergePair] = []
        for group in grouped.values where group.count > 1 {
            guard !name(of: group[0]).isEmpty else { continue }
            // The fullest folder keeps its place, so the fewest items move.
            let ordered = group.sorted { keepsPlace($0, over: $1, counts) }
            guard let keep = ordered.first else { continue }
            for other in ordered.dropFirst() {
                result.append(FolderMergePair(
                    keepID: keep.id,
                    mergeID: other.id,
                    name: keep.name,
                    keepCount: counts[keep.id] ?? 0,
                    mergeCount: counts[other.id] ?? 0,
                    keepCreatedAt: keep.createdAt,
                    mergeCreatedAt: other.createdAt
                ))
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func pairs(context: ModelContext) -> [FolderMergePair] {
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        var counts: [UUID: Int] = [:]
        for folder in folders where folder.deletedAt == nil {
            counts[folder.id] = LaqtaStore.itemCount(in: folder.id, context: context)
        }
        return pairs(folders: folders, counts: counts)
    }

    /// The pairs worth a question: both sides hold items, and the answer isn't already known.
    static func needingAnswer(_ pairs: [FolderMergePair]) -> [FolderMergePair] {
        pairs.filter { !$0.isEmptySided && !isDeclined($0) }
    }

    /// The other folder with this name, whatever was answered before.
    static func twin(of folderID: UUID, folders: [Folder], counts: [UUID: Int]) -> FolderMergePair? {
        pairs(folders: folders, counts: counts).first { $0.keepID == folderID || $0.mergeID == folderID }
    }

    private static func name(of folder: Folder) -> String {
        folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func keepsPlace(_ folder: Folder, over other: Folder, _ counts: [UUID: Int]) -> Bool {
        let mine = counts[folder.id] ?? 0
        let theirs = counts[other.id] ?? 0
        if mine != theirs { return mine > theirs }
        if folder.createdAt != other.createdAt { return folder.createdAt < other.createdAt }
        return folder.id.uuidString < other.id.uuidString
    }

    // MARK: Merging

    /// Folds together every pair with an empty side. Returns how many folders went away.
    @discardableResult
    static func mergeEmptySided(context: ModelContext) -> Int {
        let ready = pairs(context: context).filter { $0.isEmptySided && !isDeclined($0) }
        for pair in ready {
            apply(pair, context: context)
        }
        if !ready.isEmpty {
            try? context.save()
            DebugLog.write("merge: folded \(ready.count) empty folder(s)")
        }
        return ready.count
    }

    static func merge(_ pair: FolderMergePair, context: ModelContext) {
        apply(pair, context: context)
        try? context.save()
        DebugLog.write("merge: joined “\(pair.name)” (\(pair.total) items)")
    }

    private static func apply(_ pair: FolderMergePair, context: ModelContext) {
        guard let keep = LaqtaStore.folder(with: pair.keepID, context: context),
              let other = LaqtaStore.folder(with: pair.mergeID, context: context),
              keep !== other else { return }
        // Items in Recently Deleted move too, so restoring one later still finds its folder.
        for item in everyItem(in: other.id, context: context) {
            item.folderID = keep.id
        }
        // Whatever sat inside the folder that goes away now sits inside the one that stays.
        for child in (try? context.fetch(FetchDescriptor<Folder>())) ?? [] where child.parentID == other.id {
            child.parentID = keep.id
        }
        keep.isLocked = keep.isLocked || other.isLocked
        if other.createdAt < keep.createdAt { keep.createdAt = other.createdAt }
        if keep.sortRaw == nil { keep.sortRaw = other.sortRaw }
        keep.touch(max(keep.lastUpdate, other.lastUpdate))
        context.delete(other)
        LibraryWriter.noteChange()
        forget(pair)
    }

    private static func everyItem(in folderID: UUID, context: ModelContext) -> [Shot] {
        let target: UUID? = folderID
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.folderID == target })
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Remembering a refusal

    /// Independent of which side was going to be kept.
    nonisolated static func key(_ first: UUID, _ second: UUID) -> String {
        [first.uuidString, second.uuidString].sorted().joined(separator: "+")
    }

    static func decline(_ pair: FolderMergePair) {
        var keys = declinedKeys.filter { $0 != pair.id }
        keys.append(pair.id)
        if keys.count > 200 { keys.removeFirst(keys.count - 200) }
        AppGroup.defaults.set(keys, forKey: SettingsKey.declinedFolderMerges)
    }

    static func isDeclined(_ pair: FolderMergePair) -> Bool {
        declinedKeys.contains(pair.id)
    }

    /// Drops a remembered refusal — after a merge, or when the user asks for one from the menu.
    static func forget(_ pair: FolderMergePair) {
        let keys = declinedKeys.filter { $0 != pair.id }
        AppGroup.defaults.set(keys, forKey: SettingsKey.declinedFolderMerges)
    }

    private static var declinedKeys: [String] {
        AppGroup.defaults.stringArray(forKey: SettingsKey.declinedFolderMerges) ?? []
    }
}
