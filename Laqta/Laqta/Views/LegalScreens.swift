//
//  LegalScreens.swift
//  Laqta
//
//  Privacy Policy and Terms of Use, readable inside the app (App Review 5.1.1).
//

import Foundation
import SwiftUI

nonisolated enum LegalLinks {
    static let googlePrivacy = URL(string: "https://policies.google.com/privacy")!
    static let appleEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let applePrivacy = URL(string: "https://www.apple.com/legal/privacy/")!

    /// Optional web copy of the privacy policy (Info.plist `LaqtaPrivacyPolicyURL`).
    static var privacyPolicyWeb: URL? {
        infoURL("LaqtaPrivacyPolicyURL")
    }

    /// Optional support page (Info.plist `LaqtaSupportURL`).
    static var support: URL? {
        infoURL("LaqtaSupportURL")
    }

    private static func infoURL(_ key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: value),
              url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }
}

enum LegalDocument: String, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "Privacy Policy"
        case .terms: "Terms of Use"
        }
    }

    static let effectiveDate = "September 17, 2026"

    struct Section: Identifiable {
        let title: String
        let paragraphs: [String]
        var links: [(title: String, url: URL)] = []

        var id: String { title }
    }

    var summary: String {
        switch self {
        case .privacy:
            "Laqta doesn't collect your data. There are no accounts, ads, analytics or trackers, and the developer can't see your library."
        case .terms:
            "Laqta is licensed to you under Apple's standard terms. These notes cover what's specific to Laqta."
        }
    }

    var sections: [Section] {
        switch self {
        case .privacy: Self.privacySections
        case .terms: Self.termsSections
        }
    }

    private static let privacySections: [Section] = [
        Section(
            title: "Your library stays on your device",
            paragraphs: [
                "The photos, videos, PDFs, links, notes and folders you keep in Laqta are stored in the app's private storage on your iPhone or iPad. They are never sent to the developer.",
                "Private folders can be locked with Face ID or your passcode. Face ID is handled by iOS; Laqta never sees your face data."
            ]
        ),
        Section(
            title: "Analysis happens on your device",
            paragraphs: [
                "Laqta reads text, recognizes objects and places, transcribes speech and writes summaries using Apple frameworks and Apple Intelligence that run on your device.",
                "To find a place on the map, Laqta sends the place name or address to Apple Maps. Apple's privacy policy applies to that request."
            ],
            links: [("Apple Privacy Policy", LegalLinks.applePrivacy)]
        ),
        Section(
            title: "iCloud (optional)",
            paragraphs: [
                "If you turn on iCloud Sync or iCloud Backups, your library is stored in your own private iCloud account using Apple's CloudKit and iCloud Drive. Only you can access it, and Apple's privacy policy applies.",
                "You can delete this data at any time in Settings → your name → iCloud → Storage → Laqta."
            ]
        ),
        Section(
            title: "Links you save",
            paragraphs: [
                "When you save a link, Laqta opens it from your device to read its title, preview image and text, just like a web browser would. The website receives your device's IP address and a standard browser request. Laqta doesn't use cookies to track you and doesn't let others place ads or trackers in the app."
            ]
        ),
        Section(
            title: "YouTube links",
            paragraphs: [
                "For a YouTube video, Laqta asks YouTube's public oEmbed service for the title, channel and thumbnail instead of opening the page. The request contains only the video's link and is sent from your device to Google. Laqta doesn't ask you to sign in to Google or YouTube.",
                "The title and channel are stored with the link. The thumbnail is shown from YouTube and isn't saved."
            ],
            links: [("Google Privacy Policy", LegalLinks.googlePrivacy)]
        ),
        Section(
            title: "Permissions",
            paragraphs: [
                "Photos: to add photos and videos, and, only when you turn it on, to remove originals after Laqta keeps its copy. iOS asks you to confirm every deletion.",
                "Camera: to scan documents into PDFs.",
                "Calendar: to add an event you choose. Laqta can't read your calendar.",
                "Location: to show travel time to a place while you use the app. Your location isn't stored.",
                "Speech: to transcribe videos on your device."
            ]
        ),
        Section(
            title: "Keeping and deleting data",
            paragraphs: [
                "Items you delete stay in Recently Deleted for 30 days, then are removed for good. Deleting Laqta removes everything it stored on your device. Backups you made in iCloud or exported to Files stay until you delete them."
            ]
        ),
        Section(
            title: "Children",
            paragraphs: [
                "Laqta isn't directed at children and doesn't knowingly collect information from anyone."
            ]
        ),
        Section(
            title: "Changes and contact",
            paragraphs: [
                "If this policy changes, the new version will appear here with a new date. For questions, use the support link on Laqta's App Store page."
            ]
        )
    ]

    private static let termsSections: [Section] = [
        Section(
            title: "License",
            paragraphs: [
                "Laqta is licensed, not sold, under Apple's Licensed Application End User License Agreement."
            ],
            links: [("Apple Standard EULA", LegalLinks.appleEULA)]
        ),
        Section(
            title: "Your content",
            paragraphs: [
                "What you save in Laqta belongs to you. Keep only content you have the right to keep, and respect the terms of the apps and websites it comes from. Laqta saves links and their details for your reference; it doesn't download videos from YouTube or other services."
            ]
        ),
        Section(
            title: "Intelligence",
            paragraphs: [
                "Summaries, suggestions and transcripts are generated automatically and can be incomplete or wrong. Check important details, such as dates, prices and addresses, before you rely on them."
            ]
        ),
        Section(
            title: "Backups",
            paragraphs: [
                "Laqta offers iCloud backups and exports to help protect your library. Keep more than one copy of anything you can't replace."
            ]
        )
    ]
}

struct LegalDocumentScreen: View {
    let document: LegalDocument

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.laqta) private var palette

    var body: some View {
        VStack(spacing: 0) {
            SheetBar(LocalizedStringKey(document.title)) {
                EmptyView()
            } trailing: {
                Button {
                    dismiss()
                } label: {
                    BarTextButtonLabel(title: "Done", prominent: true)
                }
                .buttonStyle(.pressable)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: document.title)
                            .laqtaDisplayFont(36)
                            .foregroundStyle(palette.goldHi)
                            .accessibilityAddTraits(.isHeader)
                        Text(verbatim: "Effective \(LegalDocument.effectiveDate)")
                            .laqtaFont(12)
                            .foregroundStyle(palette.ink3)
                        Text(verbatim: document.summary)
                            .laqtaFont(16, weight: .medium)
                            .foregroundStyle(palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }

                    ForEach(document.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: section.title)
                                .laqtaFont(15, weight: .semibold)
                                .foregroundStyle(palette.goldHi)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.paragraphs, id: \.self) { paragraph in
                                Text(verbatim: paragraph)
                                    .laqtaFont(14)
                                    .foregroundStyle(palette.ink)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(section.links, id: \.title) { link in
                                Button {
                                    openURL(link.url)
                                } label: {
                                    Label(link.title, systemImage: "arrow.up.right")
                                        .laqtaFont(14, weight: .semibold)
                                        .foregroundStyle(palette.goldHi)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(.isLink)
                            }
                        }
                    }

                    if document == .privacy, let web = LegalLinks.privacyPolicyWeb {
                        Button {
                            openURL(web)
                        } label: {
                            LaqtaButtonLabel("Open on the Web", systemImage: "safari", kind: .line, fullWidth: true)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(palette.sheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(palette.sheet)
        .presentationCornerRadius(32)
    }
}
