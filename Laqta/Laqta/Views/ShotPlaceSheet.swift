//
//  ShotPlaceSheet.swift
//  Laqta
//
//  What the shot is of, and what you can do about it. Opened from the bar at the
//  bottom of a shot, beside Share and Move: the place, a map, a search, a phone
//  number, and the accounts written in the picture itself.
//
//  Nothing here is looked up on the internet. Every line comes out of text Laqta
//  already read on the phone, so the sheet only offers what the picture says.
//

import Foundation
import SwiftData
import SwiftUI
import Translation

struct ShotPlaceSheet: View {
    let item: Shot

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.laqta) private var palette
    @AppObject(ToastCenter.self) private var toasts

    private var contacts: ShotContacts { ContactReader.read(item.analysis) }

    var body: some View {
        VStack(spacing: 0) {
            SheetBar("In This Shot") {
                EmptyView()
            } trailing: {
                Button {
                    dismiss()
                } label: {
                    BarTextButtonLabel(title: "Done", prominent: true)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PlaceHeadline(contacts: contacts, fallback: item.displayTitle)
                    PlaceLinkGrid(contacts: contacts) { url in
                        openURL(url)
                    }
                    PlaceTextCard(text: contacts.text) { text in
                        Clipboard.copy(text)
                        toasts.show(String(localized: "Text copied"), systemImage: "doc.on.doc")
                    }
                    if contacts.handles.contains(where: { !$0.isExplicit }) {
                        Text("A handle written on its own is read as Instagram — that is what it nearly always means on a sign.")
                            .laqtaFont(12)
                            .foregroundStyle(palette.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .background(palette.sheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.sheet)
        .presentationCornerRadius(32)
    }
}

// MARK: - The name

private struct PlaceHeadline: View {
    let contacts: ShotContacts
    let fallback: String

    @Environment(\.laqta) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Recognised in this shot")
                .padding(.bottom, 4)
            Text(verbatim: contacts.name ?? fallback)
                .laqtaDisplayFont(28, bold: true)
                .foregroundStyle(palette.ink)
                .adaptiveLineLimit(2, accessibility: 3)
            if let line = detailLine {
                Text(verbatim: line)
                    .laqtaFont(13)
                    .foregroundStyle(palette.ink2)
                    .adaptiveLineLimit(2, accessibility: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailLine: String? {
        let parts = [contacts.area, contacts.address]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        // The area and the address often say the same thing twice.
        if parts.count == 2, parts[1].localizedCaseInsensitiveContains(parts[0]) {
            return parts[1]
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - The buttons

private struct PlaceLinkGrid: View {
    let contacts: ShotContacts
    let open: (URL) -> Void

    private let columns = [GridItem(.adaptive(minimum: 148), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(entries) { entry in
                Button {
                    open(entry.url)
                } label: {
                    PlaceLinkLabel(entry: entry)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text(verbatim: "\(entry.title), \(entry.detail)"))
            }
        }
    }

    private var entries: [PlaceLink] {
        var links: [PlaceLink] = []
        if let url = contacts.googleMapsURL {
            links.append(PlaceLink(
                id: "maps",
                symbol: "mappin.and.ellipse",
                title: "Google Maps",
                detail: contacts.area ?? contacts.address ?? contacts.name ?? "Open the map",
                url: url
            ))
        }
        if let url = contacts.googleSearchURL, let query = contacts.searchQuery {
            links.append(PlaceLink(id: "google", symbol: "magnifyingglass", title: "Google", detail: query, url: url))
        }
        for handle in contacts.handles {
            guard let url = handle.url else { continue }
            links.append(PlaceLink(
                id: handle.id,
                symbol: handle.service.symbol,
                title: handle.service.label,
                detail: handle.display,
                url: url
            ))
        }
        if let url = contacts.phoneURL, let phone = contacts.phone {
            links.append(PlaceLink(id: "call", symbol: "phone", title: "Call", detail: phone, url: url))
        }
        if let email = contacts.email, let url = URL(string: "mailto:\(email)") {
            links.append(PlaceLink(id: "email", symbol: "envelope", title: "Email", detail: email, url: url))
        }
        for link in contacts.links.prefix(2) {
            guard let url = URL(string: link.hasPrefix("http") ? link : "https://\(link)") else { continue }
            links.append(PlaceLink(id: link, symbol: "safari", title: "Open Link", detail: LinkDraft.displayHost(url), url: url))
        }
        return links
    }
}

private struct PlaceLink: Identifiable {
    let id: String
    let symbol: String
    /// Proper nouns and account names — never run through the string catalog.
    let title: String
    let detail: String
    let url: URL
}

private struct PlaceLinkLabel: View {
    let entry: PlaceLink

    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.symbol)
                .laqtaIconFont(17)
                .foregroundStyle(palette.goldHi)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.title)
                    .laqtaFont(13, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .adaptiveLineLimit(1, accessibility: 2)
                Text(verbatim: entry.detail)
                    .laqtaFont(11)
                    .foregroundStyle(palette.ink3)
                    .adaptiveLineLimit(1, accessibility: 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
    }
}

// MARK: - The text itself

private struct PlaceTextCard: View {
    let text: String?
    let copy: (String) -> Void

    @Environment(\.laqta) private var palette
    @State private var translating = false

    var body: some View {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Text in the shot") {
                    HStack(spacing: 14) {
                        Button {
                            translating = true
                        } label: {
                            Label("Translate", systemImage: "translate")
                                .laqtaFont(12, weight: .semibold)
                                .foregroundStyle(palette.goldHi)
                        }
                        .buttonStyle(.pressable)
                        Button {
                            copy(text)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .laqtaFont(12, weight: .semibold)
                                .foregroundStyle(palette.goldHi)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                Text(verbatim: text)
                    .laqtaFont(13)
                    .foregroundStyle(palette.ink2)
                    .textSelection(.enabled)
                    .adaptiveLineLimit(8, accessibility: 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                    .background(palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
            }
            // Apple's own translation. The language pack downloads once and then
            // works with no signal at all — nothing is sent anywhere.
            .translationPresentation(isPresented: $translating, text: text)
        }
    }
}
