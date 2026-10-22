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
    private let makeStandIn: (@MainActor () -> Object)?

    init(_ type: Object.Type) {
        makeStandIn = nil
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
        if let makeStandIn {
            let made = makeStandIn()
            box.value = made
            return made
        }
        fatalError("\(Object.self) is missing: provide it with .environment(_:) or AppObjects.register(_:).")
    }
}
