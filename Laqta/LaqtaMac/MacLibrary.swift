import AppKit
import Foundation
import LocalAuthentication
import Observation
import SwiftData
import UniformTypeIdentifiers

@Observable
@MainActor
final class MacLibrary {
    private(set) var container: ModelContainer?
    private(set) var launchError: String?
    private(set) var syncActive = false
    var localDistribution: Bool {
        Bundle.main.object(forInfoDictionaryKey: "LaqtaLocalDistribution") as? String == "YES"
    }
    var isBusy = false
    var progress: Double = 0
    var activity = ""
    var message: String?
    var unlockedFolders: Set<UUID> = []
    private var lockRevision: UInt64 = 0
    private let analyzeImports: Bool

    init(analyzeImports: Bool = true) {
        self.analyzeImports = analyzeImports
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["LAQTA_MAC_TEST_ROOT"], !path.isEmpty {
            AppGroup.useTestRoot(URL(filePath: path, directoryHint: .isDirectory))
        }
        #endif
        AppGroup.registerDefaults()
        open()
        if !AppEnvironment.isRunningTests {
            Task {
                if !localDistribution { _ = await CloudContainer.resolve() }
                await MediaStore.purgeStaging()
                await uploadPendingMedia()
            }
        }
    }

    func open() {
        do {
            let sync = !localDistribution && !AppEnvironment.isRunningTests && CloudConfig.isSyncEnabled && CloudConfig.isAccountAvailable
            let opened = try LaqtaStore.makeContainer(cloudSync: sync, inMemory: AppEnvironment.isRunningTests)
            opened.mainContext.autosaveEnabled = false
            if !AppEnvironment.isRunningTests { LaqtaStore.seedIfNeeded(opened.mainContext) }
            try opened.mainContext.save()
            container = opened
            syncActive = sync
            launchError = nil
        } catch {
            container = nil
            launchError = error.localizedDescription
        }
    }

    func canAccess(_ folderID: UUID?, folders: [Folder]) -> Bool {
        guard let folderID else { return true }
        let byID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var next: UUID? = folderID
        var seen: Set<UUID> = []
        while let id = next {
            guard seen.insert(id).inserted, let folder = byID[id],
                  !folder.isLocked || unlockedFolders.contains(id) else { return false }
            next = folder.parentID
        }
        return true
    }

    func unlock(_ folder: Folder, folders: [Folder]) async {
        let locked = LaqtaStore.path(to: folder.id, in: folders).filter { $0.isLocked && !unlockedFolders.contains($0.id) }
        guard !locked.isEmpty else { return }
        let revision = lockRevision
        let authentication = LAContext()
        authentication.localizedCancelTitle = "إلغاء"
        do {
            var error: NSError?
            guard authentication.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                throw error ?? CocoaError(.userCancelled) as NSError
            }
            guard try await authentication.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "فتح المجلدات الخاصة في لقطة") else { return }
            // A lock/sleep event during the authentication prompt revokes this attempt.
            guard revision == lockRevision else { return }
            unlockedFolders.formUnion(locked.map(\.id))
        } catch {
            message = error.localizedDescription
        }
    }

    func lockAll() { lockRevision &+= 1; unlockedFolders.removeAll() }

    private func requireAccess(to folderID: UUID?) throws {
        guard let context = container?.mainContext else { throw CocoaError(.fileReadUnknown) }
        let folders = try context.fetch(FetchDescriptor<Folder>())
        guard canAccess(folderID, folders: folders) else { throw MacLibraryError.privateFolder }
    }

    /// Explicit writes report errors and discard failed changes rather than pretending they saved.
    func save(_ changes: () -> Void) -> Bool {
        guard let context = container?.mainContext else { return false }
        changes()
        do {
            try context.save()
            LibraryWriter.noteChange()
            return true
        } catch {
            context.rollback()
            message = "تعذر حفظ التغيير: \(error.localizedDescription)"
            return false
        }
    }

    func createFolder(name: String, parent: UUID?, locked: Bool) -> Folder? {
        guard !isBusy, let context = container?.mainContext else { return nil }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        do { try requireAccess(to: parent) }
        catch { message = error.localizedDescription; return nil }
        let folder = LibraryWriter.createFolder(name: clean, locked: locked, parentID: parent, context: context)
        return save({}) ? folder : nil
    }

    func destination(folderID: UUID?) throws -> Folder {
        guard let context = container?.mainContext else { throw CocoaError(.fileReadUnknown) }
        if let folderID {
            try requireAccess(to: folderID)
            guard let folder = LaqtaStore.folder(with: folderID, context: context), !folder.isInTrash else {
                throw MacLibraryError.destinationUnavailable
            }
            return folder
        }
        let folders = try context.fetch(FetchDescriptor<Folder>())
        if let folder = folders.first(where: { !$0.isInTrash && canAccess($0.id, folders: folders) && $0.name == "الوارد" }) { return folder }
        return LibraryWriter.createFolder(name: "الوارد", symbol: "tray", locked: false, context: context)
    }

    func importFiles(_ urls: [URL], folderID: UUID?) async {
        guard !isBusy, let context = container?.mainContext else { return }
        do { try requireAccess(to: folderID) }
        catch { message = error.localizedDescription; return }
        isBusy = true; activity = "استيراد الملفات…"; progress = 0
        defer { isBusy = false }
        var imported = 0
        var duplicates = 0
        var failures: [String] = []
        var hashes: Set<String>
        do { hashes = Set(try context.fetch(FetchDescriptor<Shot>()).filter { !$0.isInTrash }.compactMap(\.contentHash)) }
        catch { message = error.localizedDescription; return }
        for (index, url) in urls.enumerated() {
                do {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    // Finder may supply a symbolic link. Copy the payload, so the library
                    // remains valid after the Finder source is moved or removed.
                    let staged = try await MediaStore.stageFile(at: url.resolvingSymlinksInPath(), originalName: url.lastPathComponent, sourceAssetID: nil)
                    defer { MediaStore.discard(staged) }
                    if AppGroup.bool(SettingsKey.skipDuplicates), staged.contentHash.map(hashes.contains) == true {
                        MediaStore.discard(staged)
                        duplicates += 1
                    } else {
                        let folder = try destination(folderID: folderID)
                        let shot = try LibraryWriter.addMedia(staged, to: folder, deleteOriginal: false, preliminary: nil, sourceName: "Finder", context: context)
                        let committedFiles = (shot.fileName, shot.thumbnailName)
                        do {
                            try context.save()
                        } catch {
                            context.rollback()
                            MediaStore.deleteStoredFiles(fileName: committedFiles.0, thumbnailName: committedFiles.1)
                            throw error
                        }
                        imported += 1
                        if let hash = staged.contentHash { hashes.insert(hash) }
                        if analyzeImports {
                            let result = await MacAnalyzer.analyze(url: shot.fileURL, kind: staged.kind)
                            _ = save { shot.store(result.analysis, state: result.completed ? .done : .failed) }
                        }
                    }
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
                progress = Double(index + 1) / Double(max(urls.count, 1))
            }
        message = "تم استيراد \(imported) ملف، وتجاوز \(duplicates) مكرر." + (failures.isEmpty ? "" : "\n" + failures.joined(separator: "\n"))
        isBusy = false
        await uploadPendingMedia()
    }

    func addLink(_ raw: String, folderID: UUID?) async -> Bool {
        guard !isBusy, let context = container?.mainContext else { return false }
        do { try requireAccess(to: folderID) }
        catch { message = error.localizedDescription; return false }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            message = "أدخل رابطًا صالحًا يبدأ بـ https:// أو http://."
            return false
        }
        isBusy = true; activity = "قراءة الرابط…"; progress = 0
        defer { isBusy = false }
        do {
            let key = DuplicateKey.link(for: url)
            if AppGroup.bool(SettingsKey.skipDuplicates), try context.fetch(FetchDescriptor<Shot>()).contains(where: { !$0.isInTrash && $0.linkKey == key }) {
                message = "هذا الرابط محفوظ في المكتبة."
                return true
            }
            let draft = await LinkReader.read(url, deep: true)
            defer { if let image = draft.image { MediaStore.discard(image) } }
            let folder = try destination(folderID: folderID)
            let shot = LibraryWriter.addLink(draft, to: folder, deep: true, context: context)
            var analysis = shot.analysis ?? ShotAnalysis()
            if !draft.isYouTube {
                analysis.text = draft.details
                analysis.entities = EntityDetector.detect(in: draft.details ?? draft.title)
                shot.store(analysis, state: .done)
            }
            let committedFiles = (shot.fileName, shot.thumbnailName)
            do { try context.save() }
            catch {
                context.rollback()
                MediaStore.deleteStoredFiles(fileName: committedFiles.0, thumbnailName: committedFiles.1)
                throw error
            }
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func trash(_ items: [Shot]) {
        guard !isBusy else { return }
        do { for item in items { try requireAccess(to: item.folderID) } }
        catch { message = error.localizedDescription; return }
        let batch = UUID()
        _ = save {
            for item in items { item.deletedAt = .now; item.deletionBatch = batch }
        }
    }

    func trash(_ folder: Folder, folders: [Folder], items: [Shot]) {
        guard !isBusy, canAccess(folder.id, folders: folders) else { return }
        let batch = UUID()
        let descendants = [folder] + LaqtaStore.descendants(of: folder.id, in: folders)
        let ids = Set(descendants.map(\.id))
        _ = save {
            for target in descendants where !target.isInTrash { target.deletedAt = .now; target.deletionBatch = batch }
            for shot in items where !shot.isInTrash && shot.folderID.map(ids.contains) == true { shot.deletedAt = .now; shot.deletionBatch = batch }
        }
    }

    func restore(_ items: [Shot], folders: [Folder]) {
        guard !isBusy, items.allSatisfy({ canAccess($0.folderID, folders: folders) }) else { return }
        _ = save {
            for item in items {
                item.deletedAt = nil; item.deletionBatch = nil
                if let id = item.folderID {
                    for folder in LaqtaStore.path(to: id, in: folders) { folder.deletedAt = nil; folder.deletionBatch = nil }
                }
            }
        }
    }

    func restore(_ folder: Folder, folders: [Folder], items: [Shot]) {
        guard !isBusy, canAccess(folder.id, folders: folders) else { return }
        let batch = folder.deletionBatch
        let descendants = [folder] + LaqtaStore.descendants(of: folder.id, in: folders).filter { batch != nil && $0.deletionBatch == batch }
        let ids = Set(descendants.map(\.id))
        _ = save {
            for ancestor in LaqtaStore.path(to: folder.id, in: folders) { ancestor.deletedAt = nil; ancestor.deletionBatch = nil }
            for target in descendants { target.deletedAt = nil; target.deletionBatch = nil }
            for item in items where item.folderID.map(ids.contains) == true && batch != nil && item.deletionBatch == batch {
                item.deletedAt = nil; item.deletionBatch = nil
            }
        }
    }

    func deletePermanently(_ items: [Shot]) {
        guard !isBusy, let context = container?.mainContext else { return }
        do { for item in items { try requireAccess(to: item.folderID) } }
        catch { message = error.localizedDescription; return }
        let files = items.filter(\.isInTrash).map { ($0.fileName, $0.thumbnailName) }
        if save({ for item in items where item.isInTrash { context.delete(item) } }) {
            for (file, thumbnail) in files {
                MediaStore.deleteStoredFiles(fileName: file, thumbnailName: thumbnail)
                CloudMediaStore.deleteFiles(fileName: file, thumbnailName: thumbnail)
            }
        }
    }

    func ensureLocalFile(_ shot: Shot) async -> URL? {
        if !shot.hasMediaFile { return nil }
        if await CloudMediaMover.download(fileName: shot.fileName, timeout: .seconds(60)) { return shot.fileURL }
        message = "الملف غير متاح على هذا الماك. تحقق من اتصال iCloud ثم أعد المحاولة."
        return nil
    }

    func exportItems(_ items: [Shot]) async {
        guard !isBusy else { return }
        isBusy = true; activity = "تصدير الملفات…"; progress = 0
        defer { isBusy = false }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "تصدير هنا"
        guard await panel.begin() == .OK, let destination = panel.url else { return }
        let access = destination.startAccessingSecurityScopedResource()
        defer { if access { destination.stopAccessingSecurityScopedResource() } }
        do {
            try await export(items, to: destination)
            message = "تم تصدير \(items.count) عنصر."
        } catch { message = error.localizedDescription }
    }

    /// Shared by the panel action and tests. Never overwrites another export.
    func export(_ items: [Shot], to destination: URL) async throws {
            for (index, item) in items.enumerated() {
                try requireAccess(to: item.folderID)
                let rawName = item.isLink ? "\(item.id.uuidString).webloc" : item.shareFileName
                let name = rawName.isEmpty || rawName == "." || rawName == ".." ? item.id.uuidString : rawName
                var target = destination.appending(path: name)
                var suffix = 1
                while FileManager.default.fileExists(atPath: target.path) {
                    let path = name as NSString
                    let base = path.deletingPathExtension
                    let ext = path.pathExtension
                    target = destination.appending(path: "\(base) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)"))
                    suffix += 1
                }
                if item.isLink {
                    guard let url = item.url, MacWebLink.isAllowed(url) else { throw MacLibraryError.invalidLink }
                    let data = try PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0)
                    try data.write(to: target, options: .atomic)
                } else {
                    guard let source = await ensureLocalFile(item) else { throw CocoaError(.fileReadNoSuchFile) }
                    try requireAccess(to: item.folderID)
                    try FileManager.default.copyItem(at: source, to: target)
                }
                progress = Double(index + 1) / Double(max(items.count, 1))
            }
    }

    func openLink(_ item: Shot) {
        do {
            try requireAccess(to: item.folderID)
            guard let url = item.url, MacWebLink.isAllowed(url) else { throw MacLibraryError.invalidLink }
            if !NSWorkspace.shared.open(url) { message = "تعذر فتح الرابط في المتصفح." }
        } catch { message = error.localizedDescription }
    }

    func exportBackup() async {
        guard !isBusy, let context = container?.mainContext else { return }
        isBusy = true; activity = "إنشاء النسخة الاحتياطية…"; progress = 0
        defer { isBusy = false }
        let revision = lockRevision
        let folders: [Folder]
        do { folders = try context.fetch(FetchDescriptor<Folder>()) }
        catch { message = error.localizedDescription; return }
        let locked = folders.filter { $0.isLocked && !unlockedFolders.contains($0.id) }
        if !locked.isEmpty {
            let authentication = LAContext()
            do {
                guard try await authentication.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "تصدير نسخة احتياطية تشمل مجلداتك الخاصة") else { return }
            } catch { message = error.localizedDescription; return }
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.laqtaBackup]
        panel.nameFieldStringValue = "Laqta \(Date.now.formatted(.iso8601.year().month().day())).laqtabackup"
        guard await panel.begin() == .OK, let destination = panel.url else { return }
        let access = destination.startAccessingSecurityScopedResource()
        defer { if access { destination.stopAccessingSecurityScopedResource() } }
        do {
            guard revision == lockRevision else { throw MacLibraryError.privateFolder }
            let all = try context.fetch(FetchDescriptor<Shot>()).filter { !$0.isInTrash && $0.hasMediaFile }
            for shot in all { guard await ensureLocalFile(shot) != nil else { throw CocoaError(.fileReadNoSuchFile) } }
            let snapshot = LibrarySnapshotter.snapshot(context: context)
            let device = BackupDevice.current
            let info = BackupInfo(id: BackupInfo.makeID(date: .now), format: BackupInfo.currentFormat, createdAt: .now,
                appVersion: "1.1", deviceName: device.name, deviceID: device.id, folderCount: snapshot.folders.count,
                itemCount: snapshot.items.count, mediaBytes: 0)
            let file = try await BackupEngine.export(snapshot, info: info) { [weak self] progress, text in
                Task { @MainActor in self?.progress = progress; self?.activity = text }
            }
            defer { BackupEngine.cleanUpExports() }
            guard revision == lockRevision else { throw MacLibraryError.privateFolder }
            // Replace the selected file atomically, after the complete archive has been created.
            let bytes = try Data(contentsOf: file, options: .mappedIfSafe)
            try bytes.write(to: destination, options: .atomic)
            message = "تم حفظ نسخة احتياطية كاملة ومتوافقة مع نسخة iPhone."
        } catch { message = error.localizedDescription }
    }

    func restoreBackup(_ url: URL) async {
        guard !isBusy, let context = container?.mainContext else { return }
        isBusy = true; activity = "قراءة النسخة الاحتياطية…"; progress = 0
        defer { isBusy = false }
        do {
            let prepared = try await BackupEngine.prepareRestore(fromFile: url) { [weak self] progress, text in
                Task { @MainActor in self?.progress = progress / 2; self?.activity = text }
            }
            defer { BackupEngine.finish(prepared) }
            let result = try await BackupRestorer.restore(prepared, context: context) { value, text in
                progress = value; activity = text
            }
            message = "تمت الاستعادة. \(result.message)"
        } catch { message = error.localizedDescription }
    }

    func uploadPendingMedia() async {
        guard syncActive, CloudConfig.isSyncEnabled, CloudContainer.rootURL != nil, !isBusy,
              let context = container?.mainContext else { return }
        isBusy = true; activity = "مزامنة ملفات iCloud…"; progress = 0
        defer { isBusy = false }
        do {
            let items = try context.fetch(FetchDescriptor<Shot>()).filter { !$0.isInTrash && $0.hasMediaFile && $0.mediaInCloud != true }
            for item in items {
                let result = await CloudMediaMover.upload(fileName: item.fileName, thumbnailName: item.thumbnailName)
                if result == .moved || result == .alreadyInCloud { _ = save { item.mediaInCloud = true } }
                else if result == .failed { message = "تعذر رفع بعض ملفات iCloud. ستبقى الملفات المحلية محفوظة، ويمكنك إعادة المزامنة من القائمة."; break }
            }
        } catch { message = error.localizedDescription }
    }

    func reanalyze(_ shot: Shot) async {
        guard !isBusy, let kind = shot.kind.mediaKind else { return }
        do { try requireAccess(to: shot.folderID) }
        catch { message = error.localizedDescription; return }
        isBusy = true; activity = "قراءة النص…"; progress = 0
        defer { isBusy = false }
        guard let url = await ensureLocalFile(shot) else { return }
        let result = await MacAnalyzer.analyze(url: url, kind: kind)
        _ = save {
            if result.completed { shot.store(result.analysis, state: .done) }
            else {
                // A temporary OS/model error must not erase earlier OCR or iPhone analysis.
                var previous = shot.analysis ?? result.analysis
                previous.tips = Array(Set(previous.tips + result.analysis.tips)).sorted()
                shot.store(previous, state: .failed)
            }
        }
    }

    func setCloudEnabled(_ enabled: Bool) async {
        guard !isBusy, let context = container?.mainContext else { return }
        guard !localDistribution else {
            message = "هذه نسخة للتجربة المحلية. المزامنة متاحة عند بناء المشروع بتوقيع Apple مع صلاحيات iCloud وApp Group."
            return
        }
        if enabled && (!CloudConfig.isAccountAvailable || !AppGroup.isConfigured) {
            message = "فعّل iCloud Drive وسجّل التطبيق بتوقيع يدعم App Group وiCloud أولًا."
            return
        }
        isBusy = true; activity = enabled ? "تجهيز iCloud…" : "تنزيل الملفات قبل إيقاف iCloud…"
        defer { isBusy = false }
        do {
            if !enabled {
                for shot in try context.fetch(FetchDescriptor<Shot>()) where shot.hasMediaFile {
                    guard await CloudMediaMover.download(fileName: shot.fileName, timeout: .seconds(60)) else {
                        message = "لم يتم إيقاف iCloud: بعض الملفات لم تكتمل على الماك. أعد المحاولة بعد تنزيلها."
                        return
                    }
                }
            }
            try context.save()
            AppGroup.defaults.set(enabled, forKey: SettingsKey.cloudSync)
            message = "تم حفظ الإعداد. أغلق التطبيق وافتحه لتطبيق تغيير مزامنة iCloud بأمان."
        } catch { message = error.localizedDescription }
    }
}

nonisolated private enum MacLibraryError: LocalizedError {
    case privateFolder, destinationUnavailable, invalidLink
    var errorDescription: String? {
        switch self {
        case .privateFolder: "المجلد مقفل أو غير مكتمل. افتحه ثم أعد المحاولة."
        case .destinationUnavailable: "المجلد المحدد لم يعد متاحًا. اختر مجلدًا آخر."
        case .invalidLink: "الرابط المحفوظ غير صالح للمتصفح. تُفتح روابط http وhttps فقط."
        }
    }
}

nonisolated enum MacWebLink {
    static func isAllowed(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
    }
}
