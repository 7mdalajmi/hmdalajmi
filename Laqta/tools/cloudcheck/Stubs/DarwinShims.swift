// cloudcheck HARNESS-ONLY shims, compiled into every module checked against the stubs (not with --sdk).
// They stand in for Darwin Foundation behaviour that Linux Foundation lacks; nothing here is an app bug.
// Every declaration is `nonisolated` so the app's MainActor default isolation does not change it.

// SHIM: on Darwin, URLSession, URLRequest, HTTPURLResponse... are part of Foundation. On Linux they live
// in FoundationNetworking. (An @_exported import in one file is visible to the whole module.)
@_exported import FoundationNetworking

// SHIM: Darwin's Foundation re-exports the ObjectiveC module (Selector).
@_exported import ObjectiveC

// SHIM: Darwin's Foundation re-exports Observation (`@Observable` works after a plain `import Foundation`).
@_exported import Observation

import Foundation

extension FileManager {
    // SHIM: Darwin-only API (App Groups). As the iOS 27.0 SDK imports it (an Objective-C method, so its
    // result is discardable):
    // open func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL?
    @discardableResult
    nonisolated func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? { nil }
}
