//
//  YouTubeRefresher.swift
//  Laqta
//
//  Loads a YouTube link's title, channel and thumbnail from YouTube's oEmbed when they
//  are missing (the link was saved offline, or came from an older backup), and notes
//  videos that were removed or made private.
//

import Foundation
import SwiftData

enum YouTubeRefresher {
    /// How often the app looks for links that still need their details.
    static let checkInterval: TimeInterval = 3_600

    static func links(context: ModelContext) -> [Shot] {
        let linkKind: Int? = ItemKind.link.rawValue
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { item in
            item.kindRaw == linkKind && item.deletedAt == nil
        })
        return ((try? context.fetch(descriptor)) ?? []).filter(\.isYouTube)
    }

    /// The link is still waiting for YouTube's details.
    static func needsDetails(_ item: Shot) -> Bool {
        guard item.isYouTube, item.linkUnavailable != true else { return false }
        if item.linkRefreshedAt == nil { return true }
        guard let url = item.url, YouTubeLink.videoID(from: url) != nil else { return false }
        let title = item.linkTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty || title == YouTubeReader.placeholderTitle
    }

    /// Runs `refreshMissing` at most once an hour.
    static func refreshIfDue(context: ModelContext, now: Date = .now) async {
        let last = AppGroup.defaults.double(forKey: SettingsKey.lastYouTubeRefresh)
        guard now.timeIntervalSince1970 - last > checkInterval else { return }
        AppGroup.defaults.set(now.timeIntervalSince1970, forKey: SettingsKey.lastYouTubeRefresh)
        await refreshMissing(context: context, now: now)
    }

    /// Loads the details of every YouTube link that doesn't have them yet.
    @discardableResult
    static func refreshMissing(context: ModelContext, now: Date = .now) async -> Int {
        let waiting = links(context: context).filter(needsDetails)
        guard !waiting.isEmpty else { return 0 }
        await refresh(waiting, context: context, now: now)
        return waiting.count
    }

    static func refresh(_ items: [Shot], context: ModelContext, now: Date = .now) async {
        var byVideo: [String: [Shot]] = [:]
        var pages: [Shot] = []
        for item in items where item.isYouTube {
            if let url = item.url, let videoID = YouTubeLink.videoID(from: url) {
                byVideo[videoID, default: []].append(item)
            } else {
                pages.append(item)
            }
        }
        if !byVideo.isEmpty {
            let results = await YouTubeReader.lookup(Array(byVideo.keys))
            for (videoID, group) in byVideo {
                for item in group {
                    apply(results[videoID] ?? .unknown, to: item, now: now)
                }
            }
        }
        for item in pages {
            guard let url = item.url else { continue }
            update(item, with: await YouTubeReader.read(url), now: now)
        }
        guard context.commit(.linkDetails) else { return }
        LibraryWriter.noteChange()
    }

    // MARK: Applying

    static func apply(_ lookup: YouTubeLookup, to item: Shot, now: Date) {
        guard let url = item.url else { return }
        var draft = LinkDraft(url: url)
        draft.isYouTube = true
        draft.form = .video
        switch lookup {
        case let .found(video):
            YouTubeReader.apply(video, to: &draft)
            update(item, with: draft, now: now)
        case .unavailable:
            // The title and channel stay, so the link still says what the video was.
            draft.isUnavailable = true
            item.linkUnavailable = true
            item.linkRefreshedAt = now
            item.store(analysis(for: draft, previous: item.analysis), state: .done)
        case .unknown:
            // Offline, or YouTube didn't answer: keep what's there and try again later.
            break
        }
    }

    static func update(_ item: Shot, with draft: LinkDraft, now: Date) {
        item.linkTitle = draft.title
        if let author = draft.author { item.linkAuthor = author }
        if let image = draft.imageURL { item.linkImageURL = image }
        item.linkFormRaw = draft.form.rawValue
        item.linkSite = "youtube.com"
        item.linkUnavailable = draft.isUnavailable ? true : nil
        item.linkRefreshedAt = draft.hasYouTubeDetails || draft.isUnavailable ? now : item.linkRefreshedAt
        item.deepAnalysis = true
        item.store(analysis(for: draft, previous: item.analysis), state: .done)
    }

    /// The stored analysis says where the details came from; chapters saved earlier stay.
    static func analysis(for draft: LinkDraft, previous: ShotAnalysis?) -> ShotAnalysis {
        var analysis = YouTubeDetails.analysis(for: draft, previous: previous)
        if analysis.sections.isEmpty, let previous, !previous.sections.isEmpty {
            analysis.sections = previous.sections
            analysis.sectionsTitle = previous.sectionsTitle ?? "Chapters"
        }
        return analysis
    }
}
