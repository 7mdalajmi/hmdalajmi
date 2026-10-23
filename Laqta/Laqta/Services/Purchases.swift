//
//  Purchases.swift
//  Laqta
//
//  The App Store side of the thirty days. One product, bought once and kept for good:
//  the app itself, for the price on the button. There is no subscription here and
//  nothing renews.
//
//  The trial is not a product. It is counted from the day this Apple Account first
//  downloaded Laqta (`AppTransaction.originalPurchaseDate`), which no reinstall can
//  reset and no purchase sheet has to interrupt.
//

import Foundation
import StoreKit

@MainActor
@Observable
final class PurchaseCenter {
    /// What Laqta may do right now. Views read this.
    private(set) var access: LibraryAccess = Entitlement.current
    private(set) var unlock: Product?
    private(set) var isWorking = false
    /// Set when a purchase fails for a reason worth saying out loud.
    var lastError: String?
    /// Raised by whatever hits the wall: the dock, the share sheet, a drop.
    var paywallReason: PaywallReason?
    /// Set from Settings to watch the opening sequence again.
    var replayFirstRun = false

    private var updates: Task<Void, Never>?
    private var didStart = false

    enum PaywallReason: String, Identifiable {
        case saving
        case folder
        case ended
        case settings

        var id: String { rawValue }
    }

    /// The price as the App Store shows it in the user's country, or the one we listed.
    var priceText: String { unlock?.displayPrice ?? "$0.99" }

    var isBought: Bool { access.isBought }

    // MARK: Starting up

    func start() {
        guard !didStart, !AppEnvironment.isRunningTests else { return }
        didStart = true
        // Nothing in the App Store's answer should keep the library waiting.
        Entitlement.beginTrialIfNeeded()
        access = Entitlement.current
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handle(update)
            }
        }
        Task {
            await loadProducts()
            // The anchor, as early as possible: a reinstall must not look like a
            // fresh thirty days for even a moment.
            await noteStoreTrialStart()
            await refresh()
        }
    }

    /// Takes the day this Apple Account first got Laqta as the start of the thirty days.
    ///
    /// An unverified receipt is honoured too: `noteTrialStart` keeps the earliest date
    /// anything has claimed, so a tampered one can only shorten the trial, never
    /// stretch it. A build with no receipt at all (Xcode, no StoreKit configuration)
    /// simply keeps the stand-in date from its first launch.
    private func noteStoreTrialStart() async {
        do {
            switch try await AppTransaction.shared {
            case let .verified(appTransaction):
                Entitlement.noteTrialStart(appTransaction.originalPurchaseDate)
            case let .unverified(appTransaction, error):
                DebugLog.write("purchase: unverified app transaction — \(error.localizedDescription)")
                Entitlement.noteTrialStart(appTransaction.originalPurchaseDate)
            }
        } catch {
            DebugLog.write("purchase: no app transaction — \(error.localizedDescription)")
        }
    }

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: LaqtaProduct.all)
            for product in products where product.id == LaqtaProduct.unlock {
                unlock = product
            }
        } catch {
            DebugLog.write("purchase: products unavailable — \(error.localizedDescription)")
        }
    }

    /// Reads what this Apple ID owns and writes the answer where the extension can see it.
    func refresh() async {
        var bought = false
        var revoked = false
        var trialDate: Date?
        for await result in Transaction.currentEntitlements {
            guard let transaction = verified(result) else { continue }
            switch transaction.productID {
            case LaqtaProduct.unlock:
                if transaction.revocationDate == nil { bought = true } else { revoked = true }
            case LaqtaProduct.legacyTrial:
                // An early build's free trial purchase. Still read, never asked for.
                trialDate = transaction.purchaseDate
            default:
                break
            }
        }
        if let trialDate { Entitlement.noteTrialStart(trialDate) }
        // Silence is not a refund. Someone who paid keeps the app when the store says
        // nothing — on a plane, behind a bad network, mid-sign-in. Only Apple telling
        // us the purchase was revoked takes it away.
        if bought {
            Entitlement.isBought = true
        } else if revoked {
            Entitlement.isBought = false
        }
        AppGroup.defaults.set(Date.now.timeIntervalSince1970, forKey: SettingsKey.purchaseCheckedAt)
        refreshAccess()
    }

    /// Re-reads the stored answer — cheap, and how the banner counts down each day.
    func refreshAccess() {
        let now = Entitlement.current
        if now != access { access = now }
    }

    // MARK: Buying

    /// Starts the thirty days from the welcome card's own button.
    ///
    /// Nothing is bought. The card is the whole ceremony: it says what the thirty days
    /// are, the button says "Start My 30 Free Days", and tapping it starts them. The
    /// earlier build asked StoreKit to sell a free product here, which meant a system
    /// purchase sheet over a trial nobody was paying for — and if that product was
    /// missing from the store, the thirty days fell back to a counter on this phone
    /// that a reinstall wiped.
    @discardableResult
    func startTrial() async -> Bool {
        Welcome.markShown()
        guard !Entitlement.isBought else { return true }
        isWorking = true
        defer { isWorking = false }
        // Starts now, with or without a network.
        Entitlement.beginTrialIfNeeded()
        // And moves back to the day this Apple Account first got Laqta, if the App
        // Store says that was earlier.
        await noteStoreTrialStart()
        refreshAccess()
        return true
    }

    /// The one-time card that starts the thirty days.
    enum Welcome {
        static var isPending: Bool {
            !Entitlement.isBought && !AppGroup.defaults.bool(forKey: SettingsKey.didShowWelcome)
        }

        static func markShown() {
            AppGroup.defaults.set(true, forKey: SettingsKey.didShowWelcome)
        }
    }

    /// The one payment.
    @discardableResult
    func buy() async -> Bool {
        guard let unlock else {
            lastError = String(localized: "The App Store isn't answering. Try again in a moment.")
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await unlock.purchase()
            return await finish(result)
        } catch {
            lastError = error.localizedDescription
            DebugLog.write("purchase: failed — \(error.localizedDescription)")
            return false
        }
    }

    /// For a new phone, or the same one after a reinstall.
    @discardableResult
    func restore() async -> Bool {
        isWorking = true
        defer { isWorking = false }
        try? await AppStore.sync()
        await refresh()
        if !access.isBought {
            lastError = String(localized: "Nothing to restore on this Apple ID.")
        }
        return access.isBought
    }

    // MARK: Plumbing

    @discardableResult
    private func finish(_ result: Product.PurchaseResult) async -> Bool {
        switch result {
        case let .success(verification):
            guard let transaction = verified(verification) else {
                lastError = String(localized: "The App Store couldn't confirm that purchase.")
                return false
            }
            await transaction.finish()
            await refresh()
            return transaction.productID == LaqtaProduct.unlock
        case .userCancelled:
            return false
        case .pending:
            // Ask to Buy: the purchase lands later, through Transaction.updates.
            lastError = String(localized: "Waiting for approval. Laqta unlocks as soon as it arrives.")
            return false
        @unknown default:
            return false
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard let transaction = verified(result) else { return }
        await transaction.finish()
        await refresh()
    }

    private func verified(_ result: VerificationResult<Transaction>) -> Transaction? {
        switch result {
        case let .verified(transaction):
            return transaction
        case let .unverified(_, error):
            DebugLog.write("purchase: unverified — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Asking

    /// Called where a new shot, folder or import would have happened.
    /// Returns false and raises the paywall when the thirty days are over.
    func allowAdding(_ reason: PaywallReason = .saving) -> Bool {
        refreshAccess()
        guard access.canAddThings else {
            paywallReason = reason
            return false
        }
        return true
    }
}
