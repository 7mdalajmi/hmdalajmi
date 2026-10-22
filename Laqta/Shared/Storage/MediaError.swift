//
//  MediaError.swift
//  Laqta — Shared
//

import Foundation

nonisolated enum MediaError: LocalizedError {
    case unsupportedItem
    case noData
    case unreadable(MediaKind)
    case storageUnavailable
    case notEnoughSpace(needed: Int64)
    case tooManyItems(limit: Int)
    /// The Share Extension has a fraction of the app's memory and a watchdog with it.
    case tooLargeToShare(limit: Int64)

    var errorDescription: String? {
        switch self {
        case .unsupportedItem:
            "Laqta can save photos, videos, PDFs and links."
        case .noData:
            "The app you shared from didn't send the file."
        case let .unreadable(kind):
            switch kind {
            case .photo: "This image couldn't be read."
            case .video: "This video couldn't be read."
            case .document: "This PDF couldn't be opened."
            }
        case .storageUnavailable:
            "Shared storage isn't available. Check the App Group in Signing & Capabilities."
        case let .notEnoughSpace(needed):
            "There isn't enough free space on this device to save \(LaqtaFormat.bytes(needed))."
        case let .tooManyItems(limit):
            "Laqta can save up to \(limit) items at a time."
        case let .tooLargeToShare(limit):
            "The share sheet can take files up to \(LaqtaFormat.bytes(limit)). Open Laqta and import this one there instead — the app has no limit."
        }
    }

    /// A refusal, not a reason to try another way of loading the same item.
    static func isTooLargeToShare(_ error: any Error) -> Bool {
        guard let error = error as? MediaError, case .tooLargeToShare = error else { return false }
        return true
    }
}
