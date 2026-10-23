//
//  DocumentScreen.swift
//  Laqta
//
//  A saved PDF: the first page, actions, your note, and "What's inside" —
//  summary, contents, key details and questions. Opens in a full reader.
//

import Foundation
import PDFKit
import SwiftData
import SwiftUI

struct DocumentScreen: View {
    let itemID: UUID
    @Binding var path: [Route]

    @Environment(\.laqta) private var palette
    @Query private var matches: [Shot]

    init(itemID: UUID, path: Binding<[Route]>) {
        self.itemID = itemID
        self._path = path
        let target = itemID
        _matches = Query(filter: #Predicate<Shot> { $0.id == target })
    }

    var body: some View {
        if let item = matches.first, item.deletedAt == nil {
            DocumentContent(item: item)
        } else {
            ZStack {
                LaqtaBackground()
                Text("This PDF was deleted.")
                    .foregroundStyle(palette.ink2)
            }
        }
    }
}

private struct DocumentContent: View {
    let item: Shot

    @AppObject(LibraryModel.self) private var library
    @AppObject(IntelligenceCenter.self) private var intelligence
    @AppObject(ToastCenter.self) private var toasts
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.laqta) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }) private var folders: [Folder]
    @State private var localToasts = ToastCenter()
    @State private var reader: ReaderRequest?
    @State private var showingMove = false
    @State private var noteItem: Shot?

    private var analysis: ShotAnalysis { item.analysis ?? ShotAnalysis() }
    private var folder: Folder? { folders.first { $0.id == item.folderID } }
    private var isReading: Bool {
        intelligence.isRunning(item.id) || item.analysisState == .pending
    }
    @State private var mediaArrived = false

    private var isDownloaded: Bool {
        mediaArrived || MediaWaiter.isAvailable(fileName: item.fileName)
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    inlineReader
                        .frame(maxWidth: .infinity)
                    Divider()
                    ScrollView {
                        details
                            .padding(.top, 24)
                    }
                    .frame(width: 420)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero
                        details
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(LaqtaBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: ShareableFile(item: item), preview: SharePreview(Text(verbatim: item.shareFileName))) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(!isDownloaded)
            }
        }
        .toastHost(localToasts)
        .fullScreenCover(item: $reader) { request in
            DocumentReaderView(url: item.fileURL, title: item.displayTitle, startPage: request.page)
        }
        .sheet(isPresented: $showingMove) {
            MoveToFolderSheet(itemIDs: [item.id], currentFolderID: item.folderID)
                .laqtaThemed()
        }
        .sheet(item: $noteItem) { item in
            NoteEditorSheet(item: item)
                .laqtaThemed()
        }
        .tracksMediaAvailability(of: item.fileName, isAvailable: $mediaArrived)
        .task(id: item.id) {
            library.markViewed(item, context: modelContext)
            if item.analysisState == .pending, AppGroup.bool(SettingsKey.analyzeShots) {
                await intelligence.analyzeDocument(item, context: modelContext)
            }
        }
        .onDisappear {
            intelligence.markSeen(item.id)
        }
    }

    // MARK: Hero

    private var hero: some View {
        Button {
            reader = ReaderRequest(page: 1)
        } label: {
            ShotThumbnail(shot: item, cornerRadius: 6)
                .aspectRatio(pageAspect, contentMode: .fit)
                .frame(maxHeight: 360)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 12)
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 5) {
                        Image(systemName: "book")
                        Text("Read")
                    }
                    .laqtaFont(13, weight: .semibold)
                    .foregroundStyle(palette.goldInk)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(palette.accentFill, in: Capsule())
                    .padding(10)
                }
        }
        .buttonStyle(.pressable)
        .disabled(!isDownloaded)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [Color(hex: 0x2E2721), palette.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .accessibilityLabel(Text("Read \(item.displayTitle)"))
    }

    private var pageAspect: CGFloat {
        guard item.pixelWidth > 0, item.pixelHeight > 0 else { return 0.72 }
        return CGFloat(item.pixelWidth) / CGFloat(item.pixelHeight)
    }

    @ViewBuilder
    private var inlineReader: some View {
        if isDownloaded {
            PDFKitView(url: item.fileURL, startPage: 1)
                .background(Color(hex: 0x1B1815))
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Downloading from iCloud…")
                    .laqtaFont(14)
                    .foregroundStyle(palette.ink2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock
            actions
                .padding(.top, 16)
            if !item.note.isEmpty {
                NoteCard(note: item.note) { noteItem = item }
                    .padding(.top, 16)
            }
            insideHeader
                .padding(.top, 28)
            insideContent
                .padding(.top, 14)
            footer
                .padding(.top, 24)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(verbatim: "PDF")
                    .laqtaFont(10, weight: .heavy, maxScale: 1.25)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minHeight: 17)
                    .background(Color(hex: 0xB0412F), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(verbatim: kindLine)
                    .adaptiveLineLimit(1, accessibility: 2)
            }
            .laqtaFont(14)
            .foregroundStyle(palette.ink2)

            Text(verbatim: item.displayTitle)
                .laqtaFont(23, weight: .bold)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)

            Text(verbatim: metaLine)
                .laqtaFont(13)
                .foregroundStyle(palette.ink2)
        }
    }

    private var kindLine: String {
        var parts: [String] = []
        if let pages = item.documentPages { parts.append(LaqtaFormat.count(pages, "page", "pages")) }
        if let category = analysis.category, category != "Document" { parts.append(category) }
        return parts.joined(separator: " · ")
    }

    private var metaLine: String {
        var parts = [LaqtaFormat.bytes(Int64(item.byteCount))]
        if let created = item.capturedAt { parts.append("Created \(LaqtaFormat.shortDate(created))") }
        if let name = item.originalName, !name.isEmpty, name != item.displayTitle { parts.append(name) }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                readButton(fullWidth: false)
                noteButton(fullWidth: false)
                iconButtons
            }
            VStack(spacing: 10) {
                readButton(fullWidth: true)
                HStack(spacing: 8) {
                    noteButton(fullWidth: true)
                    iconButtons
                }
            }
        }
        .buttonStyle(.pressable)
    }

    private func readButton(fullWidth: Bool) -> some View {
        Button {
            reader = ReaderRequest(page: 1)
        } label: {
            LaqtaButtonLabel("Read", systemImage: "book", fullWidth: fullWidth)
        }
        .disabled(!isDownloaded)
    }

    private func noteButton(fullWidth: Bool) -> some View {
        Button {
            noteItem = item
        } label: {
            LaqtaButtonLabel(item.note.isEmpty ? "Add Note" : "Note", systemImage: "note.text", kind: .line, fullWidth: fullWidth)
        }
    }

    @ViewBuilder
    private var iconButtons: some View {
        Button {
            showingMove = true
        } label: {
            OutlineIconButtonLabel(systemImage: "folder.badge.plus")
        }
        .accessibilityLabel(Text("Move"))
        Button {
            trash()
        } label: {
            OutlineIconButtonLabel(systemImage: "trash")
        }
        .accessibilityLabel(Text("Delete"))
    }

    private func trash() {
        let target = item
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            library.trash([target], context: modelContext)
            toasts.show(String(localized: "Moved to Recently Deleted"), systemImage: "trash", actionTitle: String(localized: "Undo")) {
                library.restore([target], context: modelContext)
            }
        }
    }

    // MARK: What's inside

    private var insideHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                AIBadge(size: 32)
                Text("What's inside")
                    .laqtaFont(20, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .layoutPriority(1)
                    .accessibilityAddTraits(.isHeader)
                Rectangle()
                    .fill(palette.hair)
                    .frame(height: 1)
            }
            Text(verbatim: analysis.basis ?? String(localized: isReading ? "Reading the PDF on this device…" : "Not read yet"))
                .laqtaFont(12)
                .foregroundStyle(palette.ink2)
                .padding(.leading, 44)
        }
    }

    @ViewBuilder
    private var insideContent: some View {
        VStack(spacing: 12) {
            if isReading, analysis.summary.isEmpty, analysis.text == nil {
                LaqtaCard {
                    HStack(spacing: 10) {
                        ThinkingDots()
                        Text("Reading the pages…")
                            .laqtaFont(14, weight: .medium)
                            .foregroundStyle(palette.goldHi)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ShimmerLine(height: 12)
                        ShimmerLine(width: 260, height: 12)
                        ShimmerLine(width: 200, height: 12)
                    }
                    .padding(.top, 14)
                }
            } else if !AppGroup.bool(SettingsKey.analyzeShots) {
                LaqtaCard {
                    Text("Intelligence is off. Turn it on in Settings to read PDFs on this device.")
                        .laqtaFont(14)
                        .foregroundStyle(palette.ink2)
                }
            } else {
                if !analysis.summary.isEmpty {
                    LaqtaCard {
                        CardHeader("Summary", systemImage: "sparkles")
                        BulletList(items: analysis.summary, reveal: intelligence.isFresh(item.id))
                    }
                }
                if !analysis.entities.isEmpty {
                    LaqtaCard {
                        CardHeader("Key details", systemImage: "calendar.badge.clock")
                        EntityActions(
                            entities: Array(analysis.entities.prefix(16)),
                            eventTitle: analysis.title ?? item.displayTitle,
                            eventNotes: analysis.summary.joined(separator: "\n"),
                            toasts: localToasts
                        )
                    }
                }
                if !analysis.sections.isEmpty {
                    contentsCard
                }
                if !analysis.places.isEmpty {
                    placesCard
                }
                if let text = analysis.text, !text.isEmpty {
                    LaqtaCard {
                        CardHeader("Text", systemImage: "text.viewfinder") {
                            Button {
                                Clipboard.copy(text)
                                localToasts.show(String(localized: "Text copied"), systemImage: "doc.on.doc")
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .laqtaFont(13, weight: .semibold)
                                    .foregroundStyle(palette.goldHi)
                            }
                            .buttonStyle(.pressable)
                        }
                        ExpandableText(text: text)
                    }
                } else if item.analysisState == .done {
                    LaqtaCard {
                        Text(verbatim: analysis.source?.reason ?? String(localized: "Laqta couldn't find readable text in this PDF."))
                            .laqtaFont(14)
                            .foregroundStyle(palette.ink2)
                        Button {
                            item.analysisState = .pending
                            guard modelContext.commit(.analysis) else { return }
                            Task { await intelligence.analyzeDocument(item, context: modelContext) }
                        } label: {
                            LaqtaButtonLabel("Read Again", systemImage: "arrow.clockwise", kind: .line, small: true)
                        }
                        .buttonStyle(.pressable)
                        .padding(.top, 12)
                    }
                }
            }
            AskCard(item: item, title: "Ask about this PDF", suggestions: analysis.questions)
        }
        .animation(.snappy, value: analysis)
        .animation(.snappy, value: isReading)
    }

    private var contentsCard: some View {
        LaqtaCard {
            CardHeader(verbatim: analysis.sectionsTitle ?? String(localized: "Contents"), systemImage: "list.bullet")
            VStack(spacing: 0) {
                ForEach(Array(analysis.sections.enumerated()), id: \.offset) { index, section in
                    Button {
                        reader = ReaderRequest(page: section.page ?? 1)
                    } label: {
                        HStack(spacing: 12) {
                            Text(verbatim: section.page.map { String(localized: "p. \($0)") } ?? "\(index + 1)")
                                .laqtaFont(12, weight: .semibold, monospacedDigit: true)
                                .foregroundStyle(palette.goldHi)
                                .padding(.horizontal, 8)
                                .frame(minWidth: 40, minHeight: 26)
                                .background(palette.hit, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(verbatim: section.title)
                                .laqtaFont(14)
                                .foregroundStyle(palette.ink)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .laqtaIconFont(12, weight: .semibold)
                                .foregroundStyle(palette.ink3)
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .disabled(!isDownloaded)
                    .accessibilityHint(Text("Opens the PDF at this page"))
                    if index < analysis.sections.count - 1 {
                        RowSeparator(inset: 0)
                    }
                }
            }
        }
    }

    private var placesCard: some View {
        LaqtaCard {
            CardHeader("Places mentioned", systemImage: "mappin.and.ellipse")
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(analysis.places) { place in
                    Button {
                        Directions.openDirections(to: place)
                    } label: {
                        EntityChipLabel(text: place.name, systemImage: "mappin", done: false)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint(Text("Shows it in Maps"))
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .laqtaIconFont(12)
            Text("Saved to")
            if let folder {
                FolderNameText(name: folder.name, size: 15, color: palette.goldHi)
            }
            Text(verbatim: "· \(LaqtaFormat.shortDate(item.addedAt))")
                .lineLimit(1)
        }
        .laqtaFont(12)
        .foregroundStyle(palette.ink2)
        .frame(maxWidth: .infinity)
    }
}

private nonisolated struct ReaderRequest: Identifiable, Sendable {
    let page: Int
    var id: Int { page }
}

// MARK: - Reader

/// PDFKit inside SwiftUI.
struct PDFKitView: UIViewRepresentable {
    let url: URL
    var startPage: Int = 1
    var onPageChange: ((Int, Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChange: onPageChange)
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.backgroundColor = UIColor(red: 0.105, green: 0.094, blue: 0.082, alpha: 1)
        view.pageShadowsEnabled = true
        if let document = PDFDocument(url: url) {
            if document.isLocked, let password = UnlockedPDFPasswords.password(for: url) {
                document.unlock(withPassword: password)
            }
            view.document = document
            if startPage > 1, let page = document.page(at: startPage - 1) {
                view.go(to: page)
            }
            context.coordinator.report(view)
        }
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.onPageChange = onPageChange
    }

    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    final class Coordinator: NSObject {
        var onPageChange: ((Int, Int) -> Void)?

        init(onPageChange: ((Int, Int) -> Void)?) {
            self.onPageChange = onPageChange
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView else { return }
            report(view)
        }

        func report(_ view: PDFView) {
            guard let document = view.document, let page = view.currentPage else { return }
            onPageChange?(document.index(for: page) + 1, document.pageCount)
        }
    }
}

struct DocumentReaderView: View {
    let url: URL
    let title: String
    var startPage: Int = 1

    @Environment(\.dismiss) private var dismiss
    @Environment(\.laqta) private var palette
    @State private var page = 1
    @State private var pageCount = 0
    @State private var password = ""
    @State private var isLocked = false
    @State private var unlockFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if isLocked {
                    unlockView
                } else {
                    PDFKitView(url: url, startPage: startPage) { current, total in
                        page = current
                        pageCount = total
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .background(Color(red: 0.105, green: 0.094, blue: 0.082).ignoresSafeArea())
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                if pageCount > 0 {
                    ToolbarItem(placement: .bottomBar) {
                        Text("Page \(page) of \(pageCount)")
                            .laqtaFont(13, weight: .medium, monospacedDigit: true)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if let document = PDFDocument(url: url) {
                isLocked = document.isLocked
                pageCount = document.pageCount
                page = startPage
            }
        }
    }

    private var unlockView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.doc")
                .laqtaIconFont(40, weight: .light)
                .foregroundStyle(palette.goldHi)
            Text("This PDF is protected")
                .laqtaFont(18, weight: .semibold)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: 320)
                .onSubmit(unlock)
            if unlockFailed {
                Text("That password didn't work.")
                    .laqtaFont(13)
                    .foregroundStyle(palette.goldHi)
            }
            Button(action: unlock) {
                LaqtaButtonLabel("Unlock", systemImage: "lock.open")
            }
            .buttonStyle(.pressable)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unlock() {
        guard let document = PDFDocument(url: url) else { return }
        if document.unlock(withPassword: password) {
            // PDFKitView opens its own copy; unlocking there needs the same password.
            UnlockedPDFPasswords.store(password, for: url)
            isLocked = false
        } else {
            unlockFailed = true
        }
    }
}

/// Passwords typed during this launch, kept in memory only.
enum UnlockedPDFPasswords {
    private static var passwords: [URL: String] = [:]

    static func store(_ password: String, for url: URL) {
        passwords[url] = password
    }

    static func password(for url: URL) -> String? {
        passwords[url]
    }
}
