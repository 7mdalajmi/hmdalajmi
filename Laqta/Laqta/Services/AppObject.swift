//
//  AppObject.swift
//  Laqta
//
//  Views read Laqta's app-wide objects (library, intelligence, iCloud, backups…) from the
//  SwiftUI environment. SwiftUI sometimes evaluates a view, or runs one of its closures,
//  without that environment: a sheet whose screen was rebuilt, a view woken in the
//  background, a callback that fires after its view left. `@Environment(Type.self)` stops
//  the app there ("No Observable object of type … found"). `@AppObject` uses the app's
//  own instance instead.
//

import Observation
import SwiftUI

/// An app object that can also be made out of nothing.
///
/// It is the Release build's way out of a missing environment: a stand-in that holds
/// no library and no state does nothing useful, but the screen that asked for it is
/// then the only thing that misbehaves — instead of the app stopping dead.
protocol AppObjectStandIn: AnyObject {
    @MainActor static func makeStandIn() -> Self
}

/// The objects LaqtaApp creates once, for views that are evaluated without them.
enum AppObjects {
    private static var registry: [ObjectIdentifier: AnyObject] = [:]

    static func register(_ objects: AnyObject...) {
        for object in objects {
            registry[ObjectIdentifier(type(of: object))] = object
        }
    }

    static func registered<Object: AnyObject>(_ type: Object.Type) -> Object? {
        registry[ObjectIdentifier(type)] as? Object
    }
}

// Every object LaqtaApp registers can be made again. The ones that own something
// exclusive (the library on disk) make a stand-in that owns nothing instead.
extension LibraryStore: AppObjectStandIn {
    static func makeStandIn() -> LibraryStore { LibraryStore(standIn: true) }
}

extension LibraryModel: AppObjectStandIn {
    static func makeStandIn() -> LibraryModel { LibraryModel() }
}

extension LockManager: AppObjectStandIn {
    static func makeStandIn() -> LockManager { LockManager() }
}

extension IntelligenceCenter: AppObjectStandIn {
    static func makeStandIn() -> IntelligenceCenter { IntelligenceCenter() }
}

extension ToastCenter: AppObjectStandIn {
    static func makeStandIn() -> ToastCenter { ToastCenter() }
}

extension CloudSyncModel: AppObjectStandIn {
    static func makeStandIn() -> CloudSyncModel { CloudSyncModel() }
}

extension BackupCenter: AppObjectStandIn {
    static func makeStandIn() -> BackupCenter { BackupCenter() }
}

extension PurchaseCenter: AppObjectStandIn {
    static func makeStandIn() -> PurchaseCenter { PurchaseCenter() }
}

extension ReminderCenter: AppObjectStandIn {
    static func makeStandIn() -> ReminderCenter { ReminderCenter() }
}

extension DropImportModel: AppObjectStandIn {
    static func makeStandIn() -> DropImportModel { DropImportModel() }
}

extension Maintenance: AppObjectStandIn {
    /// Built from whatever the app has, and from stand-ins for whatever it doesn't.
    /// With a library that opened nothing, every piece of it is a no-op.
    static func makeStandIn() -> Maintenance {
        Maintenance(
            store: AppObjects.registered(LibraryStore.self) ?? LibraryStore(standIn: true),
            library: AppObjects.registered(LibraryModel.self) ?? LibraryModel(),
            intelligence: AppObjects.registered(IntelligenceCenter.self) ?? IntelligenceCenter(),
            cloud: AppObjects.registered(CloudSyncModel.self) ?? CloudSyncModel(),
            backups: AppObjects.registered(BackupCenter.self) ?? BackupCenter()
        )
    }
}

/// Holds the stand-in for one view. It has to be a reference, because `wrappedValue`
/// is a getter: without somewhere stable to keep it, every read of the property would
/// build another object, every read would observe a different one, and SwiftUI would
/// invalidate the view forever.
@MainActor
private final class StandInBox<Object: AnyObject> {
    var value: Object?
}

/// An app-wide object from the environment, or the app's own instance when the
/// environment doesn't have it.
@propertyWrapper
struct AppObject<Object: AnyObject & Observable>: DynamicProperty {
    @Environment(Object.self) private var environmentObject: Object?
    @State private var box = StandInBox<Object>()
    private let makeStandIn: @MainActor () -> Object

    /// The app's object, with the type's own stand-in behind it.
    ///
    /// The requirement is the fix: this used to end in `fatalError` when neither the
    /// environment nor the app had the object, which turned a missing environment —
    /// a sheet whose screen was rebuilt, a view woken in the background — into a
    /// crash. Now the compiler won't let a screen ask for an object that has no
    /// stand-in, so there is nothing left to crash over.
    init(_ type: Object.Type) where Object: AppObjectStandIn {
        makeStandIn = { Object.makeStandIn() }
    }

    /// For objects that belong to one window rather than the app: a detached instance
    /// stands in when neither the environment nor the app has one. It is made once
    /// and kept for as long as the view lives.
    init(_ type: Object.Type, otherwise makeStandIn: @escaping @MainActor () -> Object) {
        self.makeStandIn = makeStandIn
    }

    var wrappedValue: Object {
        if let environmentObject {
            return environmentObject
        }
        if let registered = AppObjects.registered(Object.self) {
            return registered
        }
        if let existing = box.value {
            return existing
        }
        let made = makeStandIn()
        box.value = made
        return made
    }
}
