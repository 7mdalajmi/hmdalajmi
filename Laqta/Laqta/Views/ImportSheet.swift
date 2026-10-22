//
//  ImportSheet.swift
//  Laqta
//
//  "Add to Laqta" inside the app: recent photos and videos, files (PDFs, scans) or a link,
//  then Save to Laqta.
//

import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

struct ImportSheet: View {
    enum Tab: String, Identifiable, CaseIterable {
        case photos
        case files
        case link

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .photos: "Photos"
            case .files: "Files"
            case .link: "Link"
            }
        }

        var systemImage: String {
            switch self {
            case .photos: "photo"
            case .files: "doc"
            case .link: "link"
            }
        }
    }

    let targetFolderID: UUID?
    var initialTab: Tab = .photos
    /// Prefills the Link field — used when the offer to keep what you copied is accepted.
    var initialLink: String = ""

    @Environment(\.dismiss) private var dismiss
    @AppObject(LibraryModel.self) private var library
    @AppObject(IntelligenceCenter.self) private var intelligence
    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.openURL) private var openURL

    @State private var tab: Tab = .photos
    @State private var recents = RecentPhotosModel()
    @State private var selectedAssets: [String] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var linkText = ""
    @State private var session: SaveSession?
    @State private var isLoadingPicked = false
    @State private var didSetTab = false
    @State private var showingFileImporter = false
    @State private var showingScanner = false
    @State private var fileError: String?
    @FocusState private var linkFocused: Bool

    private var linkURL: URL? {
        LinkClassifier.firstURL(in: linkText)
    }

    var body: some View {
        ZStack {
            if let session {
                SaveSheet(session: session)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)).combined(with: .opacity))
            } else {
                chooser
                    .transition(.opacity)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.sheet)
        .presentationCornerRadius(32)
        .interactiveDismissDisabled(session?.isBusy ?? false)
        .onAppear {
            guard !didSetTab else { return }
            didSetTab = true
            tab = initialTab
            if !initialLink.isEmpty { linkText = initialLink }
            // A link that arrived ready does not need the keyboard in the way.
            if tab == .link, initialLink.isEmpty { linkFocused = true }
        }
    }

    // MARK: Chooser

    private var chooser: some View {
        VStack(spacing: 0) {
            SheetBar("Add to Laqta") {
                Button {
                    dismiss()
                } label: {
                    BarTextButtonLabel(title: "Cancel")
                }
            } trailing: {
                EmptyView()
            }

            segmented
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

            switch tab {
            case .photos:
                photosTab
            case .files:
                filesTab
            case .link:
                linkTab
            }
        }
        .background(palette.sheet.ignoresSafeArea())
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .image, .movie],
            allowsMultipleSelection: true
        ) { result in
            handleFiles(result)
        }
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScannerView { pages in
                showingScanner = false
                handleScan(pages)
            }
            .ignoresSafeArea()
        }
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { item in
                Button {
                    withAnimation(.snappy) { tab = item }
                    linkFocused = item == .link
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                        .laqtaFont(14, weight: .semibold)
                        .foregroundStyle(tab == item ? palette.ink : palette.ink2)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 38)
                        .background {
                            if tab == item {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(palette.sheet2)
                                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(3)
        .background(palette.field, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
    }

    // MARK: Photos

    private var photosTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel("Recents")
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: SaveSession.itemLimit,
                    selectionBehavior: .ordered,
                    matching: .any(of: [.images, .videos]),
                    preferredItemEncoding: .current,
                    photoLibrary: .shared()
                ) {
                    Label("All Photos", systemImage: "photo.stack")
                        .accessibilityLabel(Text("Choose from all photos and videos"))
                        .labelStyle(SmallLabelStyle())
                }
                .foregroundStyle(palette.goldHi)
            }
            .padding(.horizontal, 16)

            if recents.canBrowse {
                RecentPhotosGrid(model: recents, selection: $selectedAssets)
            } else {
                accessCard
                    .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }

            Text("Laqta keeps its own copy of every photo and video, even after the original is deleted from Photos.")
                .laqtaFont(12)
                .foregroundStyle(palette.ink2)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) {
            if !selectedAssets.isEmpty {
                Button {
                    continueWithAssets()
                } label: {
                    if isLoadingPicked {
                        ProgressView()
                            .tint(palette.goldInk)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(palette.accentFill, in: Capsule())
                    } else {
                        LaqtaButtonLabel(
                            verbatim: continueTitle,
                            systemImage: "arrow.right",
                            fullWidth: true
                        )
                    }
                }
                .buttonStyle(.pressable)
                .disabled(isLoadingPicked)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selectedAssets.isEmpty)
        .task {
            recents.load(context: modelContext)
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            continueWithPicked(items)
        }
    }

    private var accessCard: some View {
        LaqtaCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .laqtaIconFont(26, weight: .light)
                    .foregroundStyle(palette.goldHi)
                Text("Show your recent photos and videos here")
                    .laqtaFont(16, weight: .semibold)
                    .foregroundStyle(palette.ink)
                Text("With access to Photos, Laqta shows your latest shots and deletes the exact original when you ask. You can also pick from All Photos without access.")
                    .laqtaFont(13)
                    .foregroundStyle(palette.ink2)
                if recents.status == .notDetermined {
                    Button {
                        Task { await recents.requestAccess(context: modelContext) }
                    } label: {
                        LaqtaButtonLabel("Allow Access", systemImage: "photo")
                    }
                    .buttonStyle(.pressable)
                    .padding(.top, 4)
                } else {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        LaqtaButtonLabel("Open Settings", systemImage: "gear", kind: .line)
                    }
                    .buttonStyle(.pressable)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var continueTitle: String {
        let assets = selectedAssets.compactMap { recents.asset(with: $0) }
        let videos = assets.filter { $0.mediaType == .video }.count
        let photos = assets.count - videos
        if videos == 0 { return photos == 1 ? "Continue with 1 photo" : "Continue with \(photos) photos" }
        if photos == 0 { return videos == 1 ? "Continue with 1 video" : "Continue with \(videos) videos" }
        return "Continue with \(assets.count) items"
    }

    private func continueWithAssets() {
        isLoadingPicked = true
        let identifiers = selectedAssets
        Task {
            var inputs: [SaveInput] = []
            for identifier in identifiers {
                guard let asset = recents.asset(with: identifier) else { continue }
                if let input = try? await AssetFiles.exportOriginal(asset) {
                    inputs.append(input)
                }
            }
            isLoadingPicked = false
            guard !inputs.isEmpty else { return }
            start(inputs)
        }
    }

    private func continueWithPicked(_ items: [PhotosPickerItem]) {
        isLoadingPicked = true
        Task {
            var inputs: [SaveInput] = []
            for item in items {
                if let picked = try? await item.loadTransferable(type: PickedMediaFile.self) {
                    inputs.append(.file(url: picked.url, name: picked.originalName, assetID: item.itemIdentifier))
                }
            }
            isLoadingPicked = false
            guard !inputs.isEmpty else { return }
            start(inputs)
        }
    }

    // MARK: Files

    private var filesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    showingFileImporter = true
                } label: {
                    fileOption(
                        symbol: "folder",
                        title: "Choose from Files",
                        subtitle: "PDFs, photos and videos from iCloud Drive or any folder"
                    )
                }
                .buttonStyle(.pressable)

                if VNDocumentCameraViewController.isSupported {
                    Button {
                        showingScanner = true
                    } label: {
                        fileOption(
                            symbol: "doc.viewfinder",
                            title: "Scan Documents",
                            subtitle: "Receipts, tickets and papers become one PDF"
                        )
                    }
                    .buttonStyle(.pressable)
                }

                if isLoadingPicked {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(palette.goldHi)
                        Text("Preparing files…")
                            .laqtaFont(14, weight: .medium)
                            .foregroundStyle(palette.goldHi)
                    }
                    .padding(.top, 4)
                }

                if let fileError {
                    Label(fileError, systemImage: "exclamationmark.triangle")
                        .laqtaFont(13)
                        .foregroundStyle(palette.goldHi)
                }

                SectionLabel("What Laqta reads in a PDF")
                    .padding(.top, 14)

                VStack(spacing: 0) {
                    readsRowContent("text.viewfinder", "The text, even in scans", "Read on this \(LaqtaDevice.name), page by page")
                    RowSeparator(inset: 50)
                    readsRowContent("calendar", "Dates, prices and codes", "Tickets, bookings and invoices land in Insights")
                    RowSeparator(inset: 50)
                    readsRowContent("sparkles", "A short summary", "Plus the sections, and answers to your questions")
                }

                Text("From Files, Mail or any app, you can also tap Share and choose Laqta.")
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func fileOption(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .laqtaIconFont(20, weight: .medium)
                .foregroundStyle(palette.goldInk)
                .frame(width: 46, height: 46)
                .background(palette.accentFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .laqtaFont(16, weight: .semibold)
                    .foregroundStyle(palette.ink)
                Text(subtitle)
                    .laqtaFont(13)
                    .foregroundStyle(palette.ink2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .laqtaIconFont(13, weight: .semibold)
                .foregroundStyle(palette.ink3)
        }
        .padding(14)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func handleFiles(_ result: Result<[URL], any Error>) {
        guard case let .success(urls) = result, !urls.isEmpty else { return }
        fileError = nil
        isLoadingPicked = true
        Task {
            var inputs: [SaveInput] = []
            for url in urls.prefix(SaveSession.itemLimit) {
                if let copy = try? await Task.detached(priority: .userInitiated, operation: { try PickedMediaFile.copyFromFiles(url) }).value {
                    inputs.append(.file(url: copy.url, name: copy.originalName, assetID: nil))
                }
            }
            isLoadingPicked = false
            guard !inputs.isEmpty else {
                fileError = "Laqta couldn't open the chosen files."
                return
            }
            start(inputs)
        }
    }

    private func handleScan(_ pages: [UIImage]) {
        guard !pages.isEmpty else { return }
        isLoadingPicked = true
        let title = "Scan \(LaqtaFormat.dateTime(.now))"
        let boxes = pages.map { ImageBox(image: $0) }
        Task {
            let result = try? await Task.detached(priority: .userInitiated) {
                try PickedMediaFile.pdf(from: boxes.map(\.image), title: title)
            }.value
            isLoadingPicked = false
            guard let result else {
                fileError = "Laqta couldn't make a PDF from the scan."
                return
            }
            start([.file(url: result.url, name: result.originalName, assetID: nil)])
        }
    }

    // MARK: Link

    private var linkTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .laqtaIconFont(15, weight: .medium)
                        .foregroundStyle(palette.ink2)
                    TextField(text: $linkText, prompt: Text("Paste or type a link").foregroundStyle(palette.ink3)) {
                        Text("Link")
                    }
                    .laqtaFont(16)
                    .foregroundStyle(palette.ink)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($linkFocused)
                    .onSubmit(readLink)

                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first {
                            linkText = first
                            if LinkClassifier.firstURL(in: first) != nil {
                                readLink()
                            }
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .tint(palette.sheet2)
                    .foregroundStyle(palette.ink)
                    .controlSize(.regular)
                }
                .padding(.leading, 14)
                .padding(.trailing, 7)
                .padding(.vertical, 6)
                .frame(minHeight: 54)
                .background(palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.buttonBorder, lineWidth: 1))

                AdaptiveButtonRow(spacing: 12) {
                    Text(verbatim: detectionText)
                        .laqtaFont(13)
                        .foregroundStyle(linkURL == nil ? palette.ink2 : palette.goldHi)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: readLink) {
                        LaqtaButtonLabel("Read Link", systemImage: "sparkles", kind: linkURL == nil ? .line : .gold)
                    }
                    .buttonStyle(.pressable)
                    .disabled(linkURL == nil)
                }

                SectionLabel("What Laqta reads")
                    .padding(.top, 14)

                VStack(spacing: 0) {
                    readsRow("play.rectangle", "YouTube, TikTok and Vimeo", "The title, the creator and the preview")
                    RowSeparator(inset: 50)
                    readsRow("bubble.left.and.text.bubble.right", "Instagram, X and Threads posts", "The caption, the account and any places")
                    RowSeparator(inset: 50)
                    readsRow("doc.text", "Articles and guides", "A summary, the sections and tips")
                    RowSeparator(inset: 50)
                    readsRow("bag", "Product pages", "The product, the price and the store")
                }

                Text("From any app, tap Share and choose Laqta. Laqta opens the link, then reads it on this \(LaqtaDevice.name).")
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var detectionText: String {
        guard let url = linkURL else { return "Videos, posts, articles and product pages" }
        let form = LinkClassifier.form(for: url, ogType: nil)
        return "\(form.label) · \(LinkDraft.displayHost(url))"
    }

    private func readsRow(_ symbol: String, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        readsRowContent(symbol, title, subtitle)
        #if DEBUG
            .onTapGesture {
                // Development only: fills a public sample link for each kind.
                let samples = [
                    "play.rectangle": "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
                    "bubble.left.and.text.bubble.right": "https://x.com/Apple/status/1936837113936699400",
                    "doc.text": "https://en.wikipedia.org/wiki/Kuwait_Towers",
                    "bag": "https://www.apple.com/shop/buy-iphone/iphone-air"
                ]
                linkText = samples[symbol] ?? ""
            }
        #endif
    }

    private func readsRowContent(_ symbol: String, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .laqtaIconFont(16, weight: .medium)
                .foregroundStyle(palette.goldHi)
                .frame(width: 36, height: 36)
                .background(palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .laqtaFont(15, weight: .medium)
                    .foregroundStyle(palette.ink)
                Text(subtitle)
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    private func readLink() {
        guard let url = linkURL else { return }
        linkFocused = false
        start([.link(url)])
    }

    // MARK: Session

    private func start(_ inputs: [SaveInput]) {
        let newSession = SaveSession(
            inputs: inputs,
            fixedFolderID: targetFolderID,
            onFinish: { finish() },
            onCancel: { cancelSession() }
        )
        withAnimation(.snappy) {
            session = newSession
        }
    }

    private func finish() {
        PickedMediaFile.cleanUp()
        if let id = AppGroup.defaults.string(forKey: SettingsKey.lastUsedFolderID).flatMap(UUID.init(uuidString:)) {
            library.noteLocalSave(to: id)
        }
        intelligence.processPending(context: modelContext)
        dismiss()
    }

    private func cancelSession() {
        PickedMediaFile.cleanUp()
        withAnimation(.snappy) {
            session = nil
            pickerItems = []
            selectedAssets = []
        }
    }
}

/// The system document scanner.
private struct DocumentScannerView: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void

        init(onFinish: @escaping ([UIImage]) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            onFinish([])
        }
    }
}
