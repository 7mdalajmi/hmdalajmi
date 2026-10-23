//
//  CloudSchema.swift
//  Laqta
//
//  Development builds create Laqta's complete CloudKit schema (every record type and
//  field) before the library opens with iCloud Sync, so "Deploy Schema Changes" in
//  CloudKit Console sends all of it to Production, including fields no record uses yet.
//  Release builds never touch the schema.
//

#if DEBUG
import CoreData
import CryptoKit
import Foundation
import SwiftData

enum CloudSchema {
    private static let doneKey = "cloudSchemaInitializedModel"

    /// Runs once per model version, on a device signed in to iCloud.
    static func initializeIfNeeded() {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [Folder.self, Shot.self]) else { return }
        let fingerprint = fingerprint(of: model)
        guard AppGroup.defaults.string(forKey: doneKey) != fingerprint else { return }
        do {
            try autoreleasepool {
                try AppGroup.prepareDirectories()
                let description = NSPersistentStoreDescription(url: AppGroup.storeURL)
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: CloudConfig.containerIdentifier
                )
                // Load synchronously, so the schema is created only after the store is open.
                description.shouldAddStoreAsynchronously = false
                let container = NSPersistentCloudKitContainer(name: "Laqta", managedObjectModel: model)
                container.persistentStoreDescriptions = [description]
                let loading = LoadResult()
                container.loadPersistentStores { _, error in
                    loading.error = error
                }
                if let error = loading.error { throw error }
                try container.initializeCloudKitSchema(options: [])
                // Close the store again before SwiftData opens it.
                for store in container.persistentStoreCoordinator.persistentStores {
                    try container.persistentStoreCoordinator.remove(store)
                }
            }
            AppGroup.defaults.set(fingerprint, forKey: doneKey)
            DebugLog.write("cloud: development schema initialized")
        } catch {
            DebugLog.write("cloud: schema initialization failed \(error)")
        }
    }

    /// Entity and property names: changes whenever the model does.
    static func fingerprint(of model: NSManagedObjectModel) -> String {
        let description = model.entities
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
            .map { entity in
                let properties = entity.properties.map(\.name).sorted().joined(separator: ",")
                return "\(entity.name ?? ""):\(properties)"
            }
            .joined(separator: ";")
        return SHA256.hash(data: Data(description.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Holds the result of the synchronous store load.
    private nonisolated final class LoadResult: @unchecked Sendable {
        var error: (any Error)?
    }
}
#endif
