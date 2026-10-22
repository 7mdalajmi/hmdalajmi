//
//  InsightsSheet.swift
//  Laqta
//
//  Coming up, saved places and tidy-up suggestions, found in the library on this device.
//

import Foundation
import MapKit
import SwiftData
import SwiftUI

struct InsightsSheet: View {
    @Binding var path: [Route]

    @AppObject(IntelligenceCenter.self) private var intelligence
    @AppObject(LibraryModel.self) private var library
    @AppObject(LockManager.self) private var lock
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.laqta) private var palette

    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }) private var folders: [Folder]
    @State private var upcoming: [IntelligenceCenter.Upcoming] = []
    @State private var places: [SavedPlace] = []
    @State private var originals: [UUID] = []
    @State private var checkedOriginals = false
    @State private var eventDraft: EventDraft?
    @State private var added: Set<String> = []
    @State private var toasts = ToastCenter()

    struct SavedPlace: Identifiable {
        let place: PlaceRef
        let itemID: UUID
        let folderID: UUID?
        let route: Route?
        var id: String { place.id + itemID.uuidString }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AIBadge(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Insights")
                        .laqtaFont(20, weight: .semibold)
                        .foregroundStyle(palette.ink)
                    Text("Found in your library, privately on this device")
                        .laqtaFont(12)
                        .foregroundStyle(palette.ink2)
                }
                Spacer(minLength: 0)
                Button {
                    dismiss()
                } label: {
                    CircleIcon(systemImage: "xmark")
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("Close"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !upcoming.isEmpty {
                        SectionLabel("Coming up")
                        ForEach(upcoming) { entry in
                            upcomingRow(entry)
                        }
                    }
                    if !places.isEmpty {
                        SectionLabel("Saved places")
                            .padding(.top, 8)
                        placesCard
                    }
                    if !originals.isEmpty {
                        SectionLabel("Tidy up")
                            .padding(.top, 8)
                        tidyCard
                    }
                    if upcoming.isEmpty, places.isEmpty, originals.isEmpty, checkedOriginals {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .background(palette.sheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.sheet)
        .presentationCornerRadius(32)
        .toastHost(toasts)
        .task {
            load()
            originals = await library.originalsStillInPhotos(context: modelContext)
            checkedOriginals = true
        }
        .sheet(item: $eventDraft) { draft in
            EventEditView(draft: draft) { saved in
                if saved {
                    added.insert(draft.actionKey)
                    toasts.show("Added to Calendar · \(draft.title)")
                }
            }
            .ignoresSafeArea()
        }
    }

    private func load() {
        upcoming = intelligence.upcoming(context: modelContext)
        var found: [SavedPlace] = []
        var seen = Set<String>()
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.tagsRaw != nil && $0.deletedAt == nil }, sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        let liveFolders = Set(folders.map(\.id))
        for item in (try? modelContext.fetch(descriptor)) ?? [] where item.tags.contains(.place) {
            guard canShow(item.folderID), item.folderID.map(liveFolders.contains) ?? true, let analysis = item.analysis else { continue }
            let candidates = ([analysis.place].compactMap { $0 } + analysis.places).filter(\.hasCoordinate)
            for place in candidates where seen.insert(SearchIndex.normalize(place.name)).inserted {
                found.append(SavedPlace(place: place, itemID: item.id, folderID: item.folderID, route: Route.destination(for: item)))
            }
            if found.count >= 12 { break }
        }
        places = found
    }

    private func canShow(_ folderID: UUID?) -> Bool {
        guard let folderID, let folder = folders.first(where: { $0.id == folderID }) else { return true }
        return lock.canShow(folder)
    }

    // MARK: Rows

    private func upcomingRow(_ entry: IntelligenceCenter.Upcoming) -> some View {
        let visible = canShow(entry.item.folderID)
        let folder = folders.first { $0.id == entry.item.folderID }
        return HStack(spacing: 14) {
            Image(systemName: visible ? symbol(for: entry) : "lock")
                .laqtaIconFont(18, weight: .medium)
                .foregroundStyle(palette.goldHi)
                .frame(width: 44, height: 44)
                .background(palette.field, in: Circle())
                .overlay(Circle().strokeBorder(palette.line, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if visible {
                    Text(verbatim: entry.title)
                        .laqtaFont(16, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .adaptiveLineLimit(1, accessibility: 3)
                    Text(verbatim: "\(entry.entity.display) · \(LaqtaFormat.dueIn(entry.date))")
                        .laqtaFont(13)
                        .foregroundStyle(palette.ink2)
                } else {
                    Text("Private reminder")
                        .laqtaFont(16, weight: .semibold, maxScale: 1.25)
                        .foregroundStyle(palette.ink)
                    HStack(spacing: 4) {
                        Text("Something in")
                        FolderNameText(name: folder?.name ?? "", size: 13, color: palette.ink2)
                            .frame(minHeight: 15)
                        Text(verbatim: "is due \(LaqtaFormat.dueIn(entry.date))")
                    }
                    .laqtaFont(13)
                    .foregroundStyle(palette.ink2)
                    .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(visible ? .isButton : [])
            .accessibilityAction {
                open(entry, visible: visible)
            }
            Spacer(minLength: 8)
            if visible {
                let key = entry.id
                Button {
                    eventDraft = EventDraft(title: entry.title, start: entry.date, allDay: entry.entity.allDay, notes: entry.item.analysis?.text, actionKey: key)
                } label: {
                    LaqtaButtonLabel(added.contains(key) ? "Added" : "Add", systemImage: added.contains(key) ? "checkmark" : nil, small: true)
                }
                .buttonStyle(.pressable)
                .disabled(added.contains(key))
            } else if let folderID = entry.item.folderID {
                Button {
                    Task {
                        if await lock.unlock(folderID) { load() }
                    }
                } label: {
                    LaqtaButtonLabel("Unlock", kind: .line, small: true)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(14)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            open(entry, visible: visible)
        }
        .accessibilityElement(children: .contain)
    }

    private func open(_ entry: IntelligenceCenter.Upcoming, visible: Bool) {
        guard visible, let route = Route.destination(for: entry.item) else { return }
        dismiss()
        path.append(route)
    }

    private func symbol(for entry: IntelligenceCenter.Upcoming) -> String {
        let text = (entry.item.analysis?.category ?? "") + " " + entry.title
        let lower = text.lowercased()
        if lower.contains("flight") || lower.contains("boarding") { return "airplane" }
        if lower.contains("reservation") || lower.contains("hotel") { return "bed.double" }
        if lower.contains("warranty") || lower.contains("insurance") { return "checkmark.shield" }
        if lower.contains("ticket") || lower.contains("event") { return "ticket" }
        return "calendar"
    }

    private var placesCard: some View {
        LaqtaCard(padding: 12) {
            PlacesMap(places: places.map(\.place))
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(places) { saved in
                    Button {
                        dismiss()
                        if let route = saved.route {
                            path.append(route)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .laqtaIconFont(11, weight: .semibold)
                            Text(verbatim: saved.place.name)
                                .lineLimit(1)
                        }
                        .laqtaFont(13)
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(palette.field, in: Capsule())
                        .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.top, 12)
        }
    }

    private var tidyCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "trash")
                .laqtaIconFont(17, weight: .medium)
                .foregroundStyle(palette.goldHi)
                .frame(width: 44, height: 44)
                .background(palette.field, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: originals.count == 1 ? "1 original still in Photos" : "\(originals.count) originals still in Photos")
                    .laqtaFont(16, weight: .semibold)
                    .foregroundStyle(palette.ink)
                Text("Laqta already has copies.")
                    .laqtaFont(13)
                    .foregroundStyle(palette.ink2)
            }
            Spacer(minLength: 8)
            Button {
                let ids = originals
                Task {
                    await library.queueForDeletion(ids, context: modelContext)
                    originals = await library.originalsStillInPhotos(context: modelContext)
                }
            } label: {
                LaqtaButtonLabel("Review", kind: .line, small: true)
            }
            .buttonStyle(.pressable)
            .disabled(library.isCleaningPhotos)
        }
        .padding(14)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .laqtaIconFont(30, weight: .light)
                .foregroundStyle(palette.gold)
            Text("Nothing here yet")
                .laqtaFont(17, weight: .semibold)
                .foregroundStyle(palette.ink)
            Text("Save tickets, bookings, PDFs, places and links. Laqta gathers the dates and places it finds here.")
                .laqtaFont(14)
                .foregroundStyle(palette.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, 24)
    }
}

private struct PlacesMap: View {
    let places: [PlaceRef]
    @Environment(\.laqta) private var palette

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
            ForEach(places) { place in
                if let latitude = place.latitude, let longitude = place.longitude {
                    Annotation(place.name, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), anchor: .center) {
                        Image(systemName: "mappin")
                            .laqtaIconFont(11, weight: .bold)
                            .foregroundStyle(palette.goldInk)
                            .frame(width: 26, height: 26)
                            .background(palette.accentFill, in: Circle())
                            .overlay(Circle().strokeBorder(palette.sheet2, lineWidth: 2))
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 3)
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
    }
}
