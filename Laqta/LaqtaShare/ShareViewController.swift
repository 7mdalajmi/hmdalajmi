//
//  ShareViewController.swift
//  Laqta — Share Extension
//
//  Hosts "Save to Laqta" for photos, screenshots and links shared from any app.
//
//  Two things matter here and nothing else does. It has to be on screen in the
//  first frame — an extension that opens the store, counts folders and reads
//  covers before it draws is an extension that feels broken — and it has to look
//  like a hand-off, not a takeover, so it sits on the bottom 62% of the screen
//  with the app you came from still visible behind it.
//
//  Coming and going are one motion each. The card rises while the system is still
//  presenting the extension, not after it has finished, and on the way out the
//  system's dismissal starts together with the card's, not after it.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

final class ShareViewController: UIViewController {

    /// Enough room to work in, little enough that where you came from stays visible.
    private static let heightFraction: CGFloat = 0.62
    private static let cornerRadius: CGFloat = 28

    private let backdrop = UIView()
    private let card = UIView()
    private let grabber = UIView()
    private var hostingController: UIViewController?
    private var saveSession: SaveSession?
    private var didPresent = false
    private var didMarkSheet = false
    private var isClosing = false

    // MARK: Lifecycle

    /// The system decides how a share extension reaches the screen, and its default
    /// style takes the host app's view out of the hierarchy — which is why everything
    /// above the card came out flat black instead of showing the app you shared from.
    /// `.overFullScreen` leaves it there. It has to be set before the controller is
    /// presented, so it belongs in init and nowhere later.
    override init(nibName: String?, bundle: Bundle?) {
        super.init(nibName: nibName, bundle: bundle)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        modalPresentationStyle = .overFullScreen
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        ShareTiming.begin()
        AppGroup.registerDefaults()
        let appearance = AppearanceMode.stored
        overrideUserInterfaceStyle = appearance.interfaceStyle
        view.backgroundColor = .clear
        view.isOpaque = false
        buildChrome()

        // After the thirty days the share sheet still opens, and says why nothing is saved.
        guard Entitlement.canAddThings else {
            install(AnyView(
                ShareLockedView { [weak self] in self?.cancel() }
                    .laqtaThemed()
                    .preferredColorScheme(appearance.colorScheme)
            ))
            return
        }

        let session = SaveSession(
            inputs: Self.inputs(from: extensionContext),
            onFinish: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancelRequest() }
        )
        saveSession = session

        // No store is opened on this thread. The sheet draws now; the library
        // arrives underneath it a moment later.
        install(AnyView(
            ShareRoot(session: session) { [weak self] in self?.cancel() }
                .laqtaThemed()
                .environment(\.locale, LaqtaLocale.current)
                .environment(\.layoutDirection, .leftToRight)
                .preferredColorScheme(appearance.colorScheme)
        ))
    }

    /// Everything between our view and the window belongs to the system, and at
    /// least one of those layers arrives painted opaque. Clearing the chain is what
    /// actually lets the app behind through; it cannot be done in `viewDidLoad`,
    /// because the chain does not exist yet.
    private func letTheHostShowThrough() {
        view.isOpaque = false
        view.backgroundColor = .clear
        var node = view.superview
        while let current = node {
            current.isOpaque = false
            current.backgroundColor = .clear
            node = current.superview
        }
        view.window?.isOpaque = false
        view.window?.backgroundColor = .clear
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        letTheHostShowThrough()
        guard !didPresent else { return }
        didPresent = true
        view.layoutIfNeeded()
        rise()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        letTheHostShowThrough()
        guard !didMarkSheet else { return }
        didMarkSheet = true
        ShareTiming.mark("sheet")
    }

    /// The card starts up as soon as the system starts showing the extension. Waiting
    /// for `viewDidAppear` meant the system's presentation ran first with nothing to
    /// see, and the card's own 0.42 s only began after it. Now the two overlap and the
    /// card has settled in 0.3 s. With Reduce Motion it fades in where it stands.
    private func rise() {
        if UIAccessibility.isReduceMotionEnabled {
            card.alpha = 0
            UIView.animate(withDuration: 0.16, delay: 0, options: [.allowUserInteraction]) {
                self.card.alpha = 1
            }
            return
        }
        card.transform = CGAffineTransform(translationX: 0, y: card.bounds.height)
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.94,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction]
        ) {
            self.card.transform = .identity
        }
    }

    // MARK: What was shared

    private static func inputs(from context: NSExtensionContext?) -> [SaveInput] {
        let extensionItems = (context?.inputItems ?? []).compactMap { $0 as? NSExtensionItem }
        let inputs = extensionItems
            .flatMap { $0.attachments ?? [] }
            .filter { ItemProviderLoader.kind(of: $0) != nil }
            .map { SaveInput.provider(ProviderBox(provider: $0)) }
        if !inputs.isEmpty { return inputs }

        // Some apps only put the link in the post text.
        let text = extensionItems.compactMap { $0.attributedContentText?.string }.joined(separator: "\n")
        if let url = LinkClassifier.firstURL(in: text) { return [.link(url)] }
        return []
    }

    // MARK: The card

    private func buildChrome() {
        // Nothing is painted over the app behind the card — not even a trace.
        // This view exists only to catch a tap outside the sheet.
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.backgroundColor = .clear
        view.addSubview(backdrop)

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x1B / 255, green: 0x18 / 255, blue: 0x15 / 255, alpha: 1)
                : UIColor(red: 0xFB / 255, green: 0xF8 / 255, blue: 0xF2 / 255, alpha: 1)
        }
        card.layer.cornerRadius = Self.cornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        card.clipsToBounds = true
        view.addSubview(card)

        grabber.translatesAutoresizingMaskIntoConstraints = false
        grabber.backgroundColor = UIColor(white: 0.55, alpha: 0.45)
        grabber.layer.cornerRadius = 2.5
        card.addSubview(grabber)

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            card.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: Self.heightFraction),

            grabber.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            grabber.topAnchor.constraint(equalTo: card.topAnchor, constant: 7),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5)
        ])

        backdrop.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backdropTapped)))
    }

    private func install(_ content: AnyView) {
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        let host = UIHostingController(rootView: content)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        card.insertSubview(host.view, belowSubview: grabber)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            host.view.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    // MARK: Leaving

    @objc private func backdropTapped() { cancel() }

    /// The card goes down and the request completes in the same moment, so the
    /// system's own dismissal runs alongside the card's instead of after it. The
    /// request used to wait for the card's 0.26 s first.
    private func close(_ done: @escaping () -> Void) {
        guard !isClosing else { return }
        isClosing = true
        view.isUserInteractionEnabled = false
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: reduceMotion ? 0.12 : 0.2, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            if reduceMotion {
                self.card.alpha = 0
            } else {
                self.card.transform = CGAffineTransform(translationX: 0, y: self.card.bounds.height)
            }
        }
        done()
    }

    private func finish() {
        close { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func cancel() {
        guard !(saveSession?.isBusy ?? false) else { return }
        if let saveSession {
            saveSession.cancel()
        } else {
            cancelRequest()
        }
    }

    private func cancelRequest() {
        close { [weak self] in
            let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
            self?.extensionContext?.cancelRequest(withError: error)
        }
    }
}

// MARK: - Opening without waiting for the library

/// Draws the sheet immediately, then swaps the real one in once the store is open.
private struct ShareRoot: View {
    let session: SaveSession
    var onClose: () -> Void

    @Environment(\.laqta) private var palette
    @State private var container: ModelContainer?
    @State private var failure: String?

    var body: some View {
        ZStack {
            palette.sheet.ignoresSafeArea()
            if let container {
                SaveSheet(session: session)
                    .modelContainer(container)
                    .saveFailureHost()
            } else if let failure {
                ShareUnavailableView(message: failure, onClose: onClose)
            } else {
                ShareOpeningView(onClose: onClose)
            }
        }
        .animation(.easeOut(duration: 0.18), value: container == nil)
        .task {
            // One real suspension, so the sheet is committed to the screen before
            // the store is touched. Opening it is main-thread work either way —
            // what changed is that it now happens behind a sheet that is already
            // there, instead of in front of a blank one.
            try? await Task.sleep(for: .milliseconds(1))
            do {
                let opened = try LaqtaStore.makeContainer()
                // Only a library that has never been opened needs seeding. Every
                // migration after that belongs to the app, not to a share.
                if !AppGroup.defaults.bool(forKey: SettingsKey.didSeedFolders) {
                    LaqtaStore.seedIfNeeded(opened.mainContext)
                }
                container = opened
                // The marks still reach DebugLog in a Debug build; nothing of
                // them is drawn on the sheet any more.
                ShareTiming.mark("library")
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

/// The same chrome the real sheet has, so the swap is invisible.
private struct ShareOpeningView: View {
    var onClose: () -> Void

    @Environment(\.laqta) private var palette

    var body: some View {
        VStack(spacing: 0) {
            SheetBar("Save to Laqta") {
                Button(action: onClose) {
                    LaqtaButtonLabel("Cancel", kind: .line, small: false)
                }
                .buttonStyle(.pressable)
            } trailing: {
                Color.clear.frame(width: 1, height: 1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The thirty days are over: nothing new is taken, and nothing already saved is touched.
private struct ShareLockedView: View {
    var onClose: () -> Void

    @Environment(\.laqta) private var palette

    var body: some View {
        VStack(spacing: 14) {
            Text(verbatim: "Laqta")
                .laqtaDisplayFont(44, maxScale: 1.1)
                .foregroundStyle(palette.goldHi)
            Image(systemName: "lock")
                .laqtaIconFont(15, weight: .medium)
                .foregroundStyle(palette.gold)
            Text("Your thirty days are over")
                .laqtaFont(17, weight: .semibold)
                .foregroundStyle(palette.ink)
            Text("Everything you saved is still in Laqta. Open the app and buy it once to start saving again.")
                .laqtaFont(13)
                .foregroundStyle(palette.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onClose) {
                LaqtaButtonLabel("Close")
            }
            .buttonStyle(.pressable)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.sheet.ignoresSafeArea())
    }
}

private struct ShareUnavailableView: View {
    let message: String
    var onClose: () -> Void

    @Environment(\.laqta) private var palette

    var body: some View {
        VStack(spacing: 14) {
            Text(verbatim: "Laqta")
                .laqtaDisplayFont(44, maxScale: 1.1)
                .foregroundStyle(palette.goldHi)
            Text("Open Laqta once, then try again.")
                .laqtaFont(17, weight: .semibold)
                .foregroundStyle(palette.ink)
            Text(verbatim: message)
                .laqtaFont(13)
                .foregroundStyle(palette.ink2)
                .multilineTextAlignment(.center)
            Button(action: onClose) {
                LaqtaButtonLabel("Close")
            }
            .buttonStyle(.pressable)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.sheet.ignoresSafeArea())
    }
}
