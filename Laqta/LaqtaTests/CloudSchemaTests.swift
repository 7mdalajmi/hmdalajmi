//
//  CloudSchemaTests.swift
//  LaqtaTests
//
//  Development builds create the CloudKit schema again whenever Laqta's model changes.
//

#if DEBUG
import CoreData
import Foundation
import SwiftData
import Testing
@testable import Laqta

@Suite("CloudKit schema")
struct CloudSchemaTests {
    @Test func laqtaModelHasEveryRecordType() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: [Folder.self, Shot.self]))
        let names = Set(model.entities.compactMap(\.name))
        #expect(names.isSuperset(of: ["Folder", "Shot"]))
        let shot = try #require(model.entitiesByName["Shot"])
        #expect(shot.propertiesByName["linkRefreshedAt"] != nil)
        let fingerprint = CloudSchema.fingerprint(of: model)
        #expect(fingerprint.count == 64)
        #expect(fingerprint == CloudSchema.fingerprint(of: model))
    }

    @Test func fingerprintIgnoresOrder() {
        let first = CloudSchema.fingerprint(of: Self.model(["title", "note", "createdAt"]))
        let second = CloudSchema.fingerprint(of: Self.model(["createdAt", "title", "note"]))
        #expect(first == second)
    }

    @Test func newFieldChangesTheFingerprint() {
        let before = CloudSchema.fingerprint(of: Self.model(["title", "note"]))
        let after = CloudSchema.fingerprint(of: Self.model(["title", "note", "rating"]))
        #expect(before != after)
    }

    private static func model(_ fields: [String]) -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = "Shot"
        entity.properties = fields.map { name in
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.type = .string
            attribute.isOptional = true
            return attribute
        }
        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }
}
#endif

#if DEBUG
extension LibraryTests {
    @Suite("Cloud sync safety")
    @MainActor
    struct CloudSyncSafetyTests {
        @Test func failedDownloadKeepsSyncOn() async throws {
            let library = try TestLibrary()
            let store = LibraryStore()
            let context = try #require(store.container?.mainContext)
            let folder = LibraryWriter.createFolder(name: "Trips", locked: false, context: context)
            let id = UUID()
            let staged = StagedMedia(
                id: id,
                fileURL: library.root.appending(path: "missing.jpg"),
                thumbnailURL: nil,
                hasLowResThumbnail: false,
                info: MediaInfo(kind: .photo),
                originalName: "Missing",
                byteCount: 10,
                sourceAssetID: nil,
                contentHash: nil
            )
            context.insert(Shot(staged: staged, files: StoredFiles(fileName: "\(id.uuidString).jpg", thumbnailName: ""), folderID: folder.id))
            try context.save()
            AppGroup.defaults.set(true, forKey: SettingsKey.cloudSync)
            CloudContainer.reset()
            let cloud = CloudSyncModel()
            let model = LibraryModel()
            cloud.start(store: store, library: model)
            let turnedOff = await cloud.turnOff()
            #expect(!turnedOff)
            #expect(AppGroup.bool(SettingsKey.cloudSync))
            #expect(cloud.switching == .none)
            guard case .failed = cloud.status else {
                Issue.record("Failed download should explain why sync stayed on")
                return
            }
        }
    }
}
#endif
