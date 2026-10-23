//
//  ShareExtensionTests.swift
//  LaqtaTests
//
//  "Save to Laqta" is how most things get into Laqta, so the Share Extension has to ship
//  inside the app, and its activation rule has to match what people actually share —
//  including a whole screen of screenshots picked at once.
//

import Foundation
import Testing
@testable import Laqta

@Suite("Share Extension")
struct ShareExtensionTests {
    @Test func theExtensionShipsInsideTheApp() throws {
        let info = try Self.shareExtensionInfo()
        #expect(Self.extensionDictionary(info)["NSExtensionPointIdentifier"] as? String == "com.apple.share-services")
    }

    @Test func thePrincipalClassIsResolved() throws {
        let info = try Self.shareExtensionInfo()
        let principal = Self.extensionDictionary(info)["NSExtensionPrincipalClass"] as? String
        // A build setting left unresolved here means the extension launches into nothing.
        #expect(principal == "LaqtaShare.ShareViewController")
    }

    /// The rule decides whether Laqta is offered at all. A count limit here doesn't trim the
    /// selection — it removes Laqta from the share sheet entirely, which is what a limit of 30
    /// used to do to anyone sharing a screen full of screenshots. SaveSession does the trimming.
    @Test func everySharedSelectionOffersLaqta() throws {
        let info = try Self.shareExtensionInfo()
        let attributes = try #require(Self.extensionDictionary(info)["NSExtensionAttributes"] as? [String: Any])
        let rule = try #require(attributes["NSExtensionActivationRule"] as? String)
        #expect(!rule.contains("BETWEEN"))
        #expect(!rule.contains("@count <"))
        #expect(!rule.contains("@count =="))
        #expect(rule.components(separatedBy: "@count >= 1").count == 3)
        for type in ["public.image", "public.movie", "com.adobe.pdf", "public.plain-text", "public.url"] {
            #expect(rule.contains(type))
        }
    }

    @Test func theExtensionCarriesTheAppsVersion() throws {
        let info = try Self.shareExtensionInfo()
        let app = Bundle.main.infoDictionary ?? [:]
        // The App Store refuses an upload whose extension drifts from the app.
        #expect(info["CFBundleShortVersionString"] as? String == app["CFBundleShortVersionString"] as? String)
        #expect(info["CFBundleVersion"] as? String == app["CFBundleVersion"] as? String)
    }

    @Test func theExtensionSharesTheAppGroup() throws {
        let info = try Self.shareExtensionInfo()
        #expect(info["LaqtaAppGroupID"] as? String == AppGroup.identifier)
    }

    // MARK: Reading the embedded extension

    private static func shareExtensionInfo() throws -> [String: Any] {
        let plugIns = try #require(Bundle.main.builtInPlugInsURL)
        let appex = plugIns.appending(path: "LaqtaShare.appex")
        let bundle = try #require(Bundle(url: appex), "LaqtaShare.appex is not embedded in Laqta.app")
        return try #require(bundle.infoDictionary)
    }

    private static func extensionDictionary(_ info: [String: Any]) -> [String: Any] {
        info["NSExtension"] as? [String: Any] ?? [:]
    }
}
