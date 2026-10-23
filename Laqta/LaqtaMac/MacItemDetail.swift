import AppKit
import AVKit
import PDFKit
import SwiftUI

struct MacThumbnail: View {
    let item: Shot
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: item.kindSymbol).foregroundStyle(.secondary) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: item.thumbnailName + (item.linkImageURL ?? "")) {
            if let remote = item.remoteImageURL {
                image = await RemoteImageLoader.image(at: remote, maxPixelSize: 160)?.image
            } else if item.hasThumbnail || item.hasMediaFile {
                image = await ImageLoader.thumbnail(at: item.thumbnailURL, original: item.hasMediaFile ? item.fileURL : nil,
                    kind: item.kind.mediaKind ?? .photo, duration: item.mediaDuration)?.image
            }
        }
    }
}

struct MacItemDetail: View {
    let item: Shot
    @Bindable var library: MacLibrary
    @State private var localURL: URL?
    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @State private var note = ""
    @State private var zoom: Double = 1
    @State private var loading = false
    @State private var reanalyzing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.originalName ?? item.displayTitle).font(.title2.bold()).textSelection(.enabled)
                        Text(item.kindLabel).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { _ = library.save { item.isFavorite.toggle() } } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                    }.help("تبديل المفضلة").disabled(library.isBusy)
                }
                preview
                if item.isPhoto {
                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: $zoom, in: 0.5...3)
                        Image(systemName: "plus.magnifyingglass")
                        Button("100%") { zoom = 1 }
                    }
                }
                if item.isLink, let url = item.url {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.linkTitle ?? url.absoluteString).font(.headline).textSelection(.enabled)
                        Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack {
                            Button("فتح في المتصفح") { library.openLink(item) }
                                .disabled(!MacWebLink.isAllowed(url))
                            Button("نسخ الرابط") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string) }
                        }
                        if let details = item.linkDetails, !details.isEmpty { Text(details).textSelection(.enabled) }
                    }
                }
                GroupBox("الملاحظات") {
                    VStack(alignment: .leading) {
                        TextEditor(text: $note).font(.body).frame(minHeight: 110).disabled(library.isBusy)
                        HStack {
                            if note != item.note { Text("تغييرات غير محفوظة").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("حفظ الملاحظة") { _ = library.save { item.setNote(note) }; note = item.note }
                                .disabled(note == item.note || library.isBusy)
                        }
                    }.padding(4)
                }
                if let analysis = item.analysis {
                    if let text = analysis.text, !text.isEmpty {
                        GroupBox("النص المستخرج") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                                Button("نسخ النص") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
                            }.padding(6)
                        }
                    }
                    if !analysis.entities.isEmpty {
                        GroupBox("معلومات من المحتوى") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(analysis.entities) { entity in
                                    HStack {
                                        Label(entity.display, systemImage: entity.systemImage).textSelection(.enabled)
                                        Spacer()
                                        Button("نسخ") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entity.value, forType: .string) }
                                    }
                                }
                            }.padding(6)
                        }
                    }
                    ForEach(analysis.tips, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    if let transcriptNote = analysis.transcriptNote { Text(transcriptNote).font(.caption).foregroundStyle(.secondary) }
                }
                GroupBox("تفاصيل الملف") {
                    VStack(spacing: 8) {
                        LabeledContent("تاريخ الإضافة", value: item.addedAt.formatted(date: .abbreviated, time: .shortened))
                        if item.byteCount > 0 { LabeledContent("الحجم", value: LaqtaFormat.bytes(Int64(item.byteCount))) }
                        if item.pixelWidth > 0 { LabeledContent("الأبعاد", value: "\(item.pixelWidth) × \(item.pixelHeight)") }
                        if let pages = item.documentPages { LabeledContent("الصفحات", value: String(pages)) }
                        if let camera = item.cameraModel { LabeledContent("الكاميرا", value: camera) }
                        if let date = item.capturedAt { LabeledContent("التقاط", value: date.formatted(date: .abbreviated, time: .shortened)) }
                    }.font(.caption).padding(6)
                }
                HStack {
                    Button("تصدير…") { Task { await library.exportItems([item]) } }.disabled(library.isBusy)
                    if !item.isLink {
                        Button(reanalyzing ? "جارٍ التحليل…" : "إعادة قراءة النص") {
                            Task {
                                reanalyzing = true
                                await library.reanalyze(item)
                                reanalyzing = false
                            }
                        }.disabled(reanalyzing || library.isBusy)
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 320)
        .task(id: item.id) {
            note = item.note
            _ = library.save { item.viewedAt = .now }
            guard item.hasMediaFile && !item.isLink else { return }
            loading = true
            localURL = await library.ensureLocalFile(item)
            if let url = localURL {
                if item.isPhoto { image = await ImageLoader.image(at: url, maxPixelSize: 5000)?.image }
                if item.isVideoFile { player = AVPlayer(url: url) }
            }
            loading = false
        }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder private var preview: some View {
        if loading {
            ProgressView("تجهيز الملف…").frame(maxWidth: .infinity, minHeight: 220)
        } else if item.isPhoto, let image {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 340 * zoom)
            }.frame(height: 340)
                .background(.quaternary.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: 10))
        } else if item.isVideoFile, let player {
            VideoPlayer(player: player).frame(height: 290).clipShape(RoundedRectangle(cornerRadius: 10))
        } else if item.isDocument, let localURL {
            MacPDFPreview(url: localURL).frame(height: 480)
        } else if item.isLink {
            MacThumbnail(item: item).frame(height: 210)
        } else {
            ContentUnavailableView("الملف غير متاح", systemImage: "icloud.and.arrow.down", description: Text("أعد فتح العنصر بعد اتصال iCloud."))
                .frame(height: 220)
        }
    }
}

struct MacPDFPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = PDFDocument(url: url)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
