//
//  SettingsScreen.swift
//  Laqta
//
//  Appearance, iCloud, Saving, Photos, Intelligence, Privacy, Storage and About.
//

import Foundation
import Photos
import SwiftData
import SwiftUI
import UIKit

struct SettingsScreen: View {
    /// Opens Recently Deleted (the sheet closes first).
    var onOpenTrash: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @AppObject(LibraryModel.self) private var library
    @AppObject(IntelligenceCenter.self) private var intelligence
    @AppObject(PurchaseCenter.self) private var purchases
    @Environment(\.laqta) private var palette

    @AppStorage(SettingsKey.autoDeleteFromPhotos, store: AppGroup.defaults) private var autoDelete = false
    @AppStorage(SettingsKey.analyzeShots, store: AppGroup.defaults) private var analyzeShots = true
    @AppStorage(SettingsKey.recognizePlaces, store: AppGroup.defaults) private var recognizePlaces = true
    @AppStorage(SettingsKey.readText, store: AppGroup.defaults) private var readText = true
    @AppStorage(SettingsKey.findSource, store: AppGroup.defaults) private var findSource = true
    @AppStorage(SettingsKey.transcribeVideos, store: AppGroup.defaults) private var transcribeVideos = true
    @AppStorage(SettingsKey.lockPrivateFolders, store: AppGroup.defaults) private var lockPrivate = true
    @AppStorage(SettingsKey.hideInAppSwitcher, store: AppGroup.defaults) private var hideInSwitcher = true

    @Query(SettingsScreen.storageDescriptor) private var items: [Shot]
    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }) private var folders: [Folder]

    @State private var authorization: PHAuthorizationStatus = .notDetermined
    @State private var storageBytes: Int64?
    @State private var confirmingCleanup = false
    @State private var legalDocument: LegalDocument?
    @State private var showingPaywall = false
    @State private var showingCleanup = false

    static var storageDescriptor: FetchDescriptor<Shot> {
        var descriptor = FetchDescriptor<Shot>()
        descriptor.propertiesToFetch = [\.byteCount, \.isScreenshot, \.kindRaw, \.libraryStatusRaw, \.deletedAt]
        return descriptor
    }

    private var cleanupTitle: String {
        pendingCount == 1 ? "Delete 1 original from Photos?" : "Delete \(pendingCount) originals from Photos?"
    }

    private var pendingCount: Int {
        items.filter { $0.libraryStatus == .pendingDeletion && $0.deletedAt == nil }.count
    }

    private var trashCount: Int {
        items.filter { $0.deletedAt != nil }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        CircleIcon(systemImage: "xmark")
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(Text("Close"))
                    Spacer()
                }
                .padding(.top, 18)

                Text("Settings")
                    .laqtaDisplayFont(44)
                    .foregroundStyle(palette.goldHi)
                    .accessibilityAddTraits(.isHeader)

                group("Appearance") { AppearanceSettingsSection() }
                group("iCloud", footer: CloudSettingsSection.footer) { CloudSettingsSection() }
                group("Saving") { SavingSettingsSection() }
                group("Photos", footer: "iOS asks you to confirm before Laqta deletes anything. Deleted photos stay in Recently Deleted for 30 days.") { photosSection }
                group("Intelligence", footer: intelligenceFooter) { intelligenceSection }
                group("Privacy") { privacySection }
                group("Reminders", footer: RemindersSettingsSection.footer) {
                    RemindersSettingsSection()
                }
                group("Storage") {
                    StorageSettingsSection(
                        items: items,
                        folderCount: folders.count,
                        storageBytes: storageBytes,
                        trashCount: trashCount,
                        onOpenTrash: {
                            dismiss()
                            onOpenTrash()
                        },
                        onCleanUp: { showingCleanup = true }
                    )
                }
                group("Laqta", footer: PurchaseSettingsSection.footer(for: purchases.access)) {
                    PurchaseSettingsSection { showingPaywall = true }
                }
                group("About") { aboutSection }
                versionFooter
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(LaqtaBackground())
        .presentationDetents([.large])
        .presentationBackground(palette.bg)
        .presentationCornerRadius(32)
        .task {
            authorization = PhotoLibraryService.authorizationStatus
            storageBytes = await MediaStore.storageUsage()
        }
        .onChange(of: autoDelete) { _, enabled in
            guard enabled else { return }
            Task { await requestPhotosAccessIfNeeded() }
        }
        .onChange(of: analyzeShots) { _, enabled in
            if enabled { intelligence.processPending(context: modelContext) }
        }
        .alert(cleanupTitle, isPresented: $confirmingCleanup) {
            Button("Review") {
                Task { await library.runPhotoCleanup(context: modelContext, userInitiated: true) }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Laqta already has its own copies. iOS shows the photos before anything is deleted.")
        }
        .alert(
            "Photos",
            isPresented: Binding(
                get: { library.lastCleanupMessage != nil },
                set: { if !$0 { library.lastCleanupMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: library.lastCleanupMessage ?? "")
        }
        .sheet(item: $legalDocument) { document in
            LegalDocumentScreen(document: document)
                .laqtaThemed()
        }
        .sheet(isPresented: $showingCleanup) {
            CleanupSheet()
                .laqtaThemed()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet(reason: .settings)
                .laqtaThemed()
        }
    }

    // MARK: Sections

    private func group<Content: View>(_ title: LocalizedStringKey, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .textCase(.uppercase)
                .laqtaFont(12, weight: .semibold)
                .tracking(0.96)
                .foregroundStyle(palette.gold)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            LaqtaGroup {
                content()
            }
            if let footer, !footer.isEmpty {
                Text(verbatim: footer)
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var photosSection: some View {
        VStack(spacing: 0) {
            SwitchRow(title: "Delete originals after saving", subtitle: "iOS asks you to confirm each time", systemImage: "trash", isOn: $autoDelete)
            RowSeparator()
            Button {
                if authorization == .notDetermined {
                    Task { await requestPhotosAccessIfNeeded() }
                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                valueRow(icon: "photo", title: "Photos Access", value: authorizationText, warn: autoDelete && authorization != .authorized)
            }
            .buttonStyle(.plain)
            RowSeparator()
            Button {
                if pendingCount > 0 { confirmingCleanup = true }
            } label: {
                HStack(spacing: 12) {
                    RowIcon(systemImage: "clock")
                    RowText(title: Text("Waiting to delete"))
                    if library.isCleaningPhotos {
                        ProgressView().tint(palette.goldHi)
                    } else {
                        Text(pendingCount, format: .number)
                            .laqtaFont(15)
                            .foregroundStyle(palette.ink2)
                    }
                    Image(systemName: "chevron.right")
                        .laqtaIconFont(13, weight: .semibold)
                        .foregroundStyle(palette.ink3)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(pendingCount == 0 || library.isCleaningPhotos)
        }
    }

    private func valueRow(icon: String, title: LocalizedStringKey, value: String, warn: Bool = false, chevron: String = "chevron.right") -> some View {
        HStack(spacing: 12) {
            RowIcon(systemImage: icon)
            RowText(title: Text(title))
            Text(verbatim: value)
                .laqtaFont(15)
                .foregroundStyle(warn ? palette.goldHi : palette.ink2)
                .multilineTextAlignment(.trailing)
            Image(systemName: chevron)
                .laqtaIconFont(13, weight: .semibold)
                .foregroundStyle(palette.ink3)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var intelligenceSection: some View {
        VStack(spacing: 0) {
            SwitchRow(title: "Analyze shots", subtitle: "Suggested folders, actions and search", systemImage: "sparkles", isOn: $analyzeShots)
            Group {
                RowSeparator()
                SwitchRow(title: "Recognize places", subtitle: "Landmarks, addresses and directions", systemImage: "mappin.and.ellipse", isOn: $recognizePlaces)
                RowSeparator()
                SwitchRow(title: "Read text", subtitle: "Dates, prices, codes and links", systemImage: "text.viewfinder", isOn: $readText)
                RowSeparator()
                SwitchRow(title: "Read speech", subtitle: "Transcripts and moments in your videos", systemImage: "waveform", isOn: $transcribeVideos)
                RowSeparator()
                SwitchRow(title: "Find the source", subtitle: "Which app or site a shot came from", systemImage: "globe", isOn: $findSource)
            }
            .disabled(!analyzeShots)
            .opacity(analyzeShots ? 1 : 0.45)
        }
    }

    private var intelligenceFooter: String {
        var text = "Photos, videos and PDFs are analyzed on this device. Places are looked up in Apple Maps, and links are opened to read what's inside."
        if !intelligence.modelAvailable {
            text += " " + intelligence.modelMessage
        }
        return text
    }

    private var privacySection: some View {
        VStack(spacing: 0) {
            SwitchRow(title: "Lock private folders", subtitle: "Face ID or your passcode opens them", systemImage: "faceid", isOn: $lockPrivate)
            RowSeparator()
            SwitchRow(title: "Hide in app switcher", subtitle: "Shows the Laqta cover instead of your shots", systemImage: "rectangle.on.rectangle", isOn: $hideInSwitcher)
        }
    }

    /// The app's own line: what it is called, and which update this is.
    ///
    /// The number is read from the bundle, never typed here — 1.0 for the first
    /// release, 1.1 for the next, and so on. Bump MARKETING_VERSION in the project
    /// and this follows on its own.
    private var identityBlock: some View {
        VStack(spacing: 5) {
            Text(verbatim: "لقطة")
                .font(LaqtaFont.arabic(26))
                .foregroundStyle(palette.gold)
            Text(verbatim: "Laqta")
                .laqtaDisplayFont(44)
                .foregroundStyle(palette.goldHi)
            Text(verbatim: "v\(appVersion)  ·  build \(buildNumber)")
                .laqtaFont(13)
                .foregroundStyle(palette.ink3)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Laqta, version \(appVersion), build \(buildNumber)"))
    }

    private var aboutSection: some View {
        VStack(spacing: 0) {
            identityBlock
            RowSeparator()
            Button {
                legalDocument = .privacy
            } label: {
                valueRow(icon: "hand.raised", title: "Privacy Policy", value: "")
            }
            .buttonStyle(.plain)
            RowSeparator()
            Button {
                legalDocument = .terms
            } label: {
                valueRow(icon: "doc.text", title: "Terms of Use", value: "")
            }
            .buttonStyle(.plain)
            if let support = LegalLinks.support {
                RowSeparator()
                Button {
                    openURL(support)
                } label: {
                    valueRow(icon: "questionmark.circle", title: "Support", value: "", chevron: "arrow.up.right")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var versionFooter: some View {
        VStack(spacing: 6) {
            Text("Built for iOS 27")
                .laqtaFont(12)
                .foregroundStyle(palette.ink3)
            if !AppGroup.isConfigured {
                Label("App Group isn't set up. Check Signing & Capabilities in Xcode.", systemImage: "exclamationmark.triangle")
                    .laqtaFont(12)
                    .foregroundStyle(palette.goldHi)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: Helpers

    private var authorizationText: String {
        switch authorization {
        case .authorized: "Full Access"
        case .limited: "Limited"
        case .denied: "Off"
        case .restricted: "Restricted"
        case .notDetermined: "Not Asked"
        @unknown default: "Unknown"
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private func requestPhotosAccessIfNeeded() async {
        if PhotoLibraryService.authorizationStatus == .notDetermined {
            authorization = await PhotoLibraryService.requestAccess()
        } else {
            authorization = PhotoLibraryService.authorizationStatus
        }
    }
}

/// Space used by each kind of item.
struct StorageBreakdown {
    var photos: Int64 = 0
    var screenshots: Int64 = 0
    var videos: Int64 = 0
    var documents: Int64 = 0
    var deleted: Int64 = 0
    var links = 0

    init(items: [Shot]) {
        for item in items {
            let bytes = Int64(item.byteCount)
            if item.deletedAt != nil {
                deleted += bytes
                continue
            }
            switch item.kind {
            case .photo:
                if item.isScreenshot { screenshots += bytes } else { photos += bytes }
            case .video:
                videos += bytes
            case .document:
                documents += bytes
            case .link:
                links += 1
            }
        }
    }

    var total: Int64 { photos + screenshots + videos + documents + deleted }

    struct Segment: Identifiable {
        let id: String
        let title: String
        let bytes: Int64
        let style: AnyShapeStyle
    }

    func segments(palette: LaqtaPalette) -> [Segment] {
        var result = [
            Segment(
                id: "photos",
                title: "Photos",
                bytes: photos,
                style: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xC9A45E), Color(hex: 0xF1DDB0)], startPoint: .leading, endPoint: .trailing))
            ),
            Segment(id: "screenshots", title: "Screenshots", bytes: screenshots, style: AnyShapeStyle(palette.goldHi.opacity(0.62))),
            Segment(id: "videos", title: "Videos", bytes: videos, style: AnyShapeStyle(palette.gold.opacity(0.5))),
            Segment(id: "documents", title: "PDFs", bytes: documents, style: AnyShapeStyle(palette.goldHi.opacity(0.32)))
        ]
        if deleted > 0 {
            result.append(Segment(id: "deleted", title: "Deleted", bytes: deleted, style: AnyShapeStyle(palette.ink3.opacity(0.5))))
        }
        return result
    }
}
