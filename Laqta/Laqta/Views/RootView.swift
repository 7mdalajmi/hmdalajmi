//
//  RootView.swift
//  Laqta
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

nonisolated enum Route: Hashable, Sendable {
    case folder(UUID)
    case viewer(folderID: UUID, startID: UUID)
    case link(UUID)
    case document(UUID)
    case search
    case trash
}

extension Route {
    /// Where an item opens.
    @MainActor
    static func destination(for item: Shot) -> Route? {
        switch item.kind {
        case .link: .link(item.id)
        case .document: .document(item.id)
        case .photo, .video: item.folderID.map { .viewer(folderID: $0, startID: item.id) }
        }
    }
}

extension Route {
    /// Screens that take the whole window on iPad (the sidebar hides).
    var isImmersive: Bool {
        switch self {
        case .viewer, .document: true
        default: false
        }
    }
}

/// On iPad, folders, Search and Recently Deleted open from the sidebar.
struct LibraryNavigator {
    var openFolder: (UUID) -> Void
    var openSearch: () -> Void
    var openTrash: () -> Void
}

extension EnvironmentValues {
    /// Shared namespace for the zoom transition between the grid and the viewer.
    @Entry var zoomNamespace: Namespace.ID? = nil
    @Entry var libraryNavigator: LibraryNavigator? = nil
}

/// The screen for a route, in the iPhone stack or the iPad detail column.
struct RouteDestination: View {
    let route: Route
    @Binding var path: [Route]

    @Environment(\.zoomNamespace) private var zoomNamespace

    var body: some View {
        switch route {
        case let .folder(folderID):
            FolderScreen(folderID: folderID, path: $path)
        case let .viewer(folderID, startID):
            zoomed(ShotViewer(folderID: folderID, startID: startID, path: $path), id: startID)
        case let .link(itemID):
            zoomed(LinkScreen(itemID: itemID, path: $path), id: itemID)
        case let .document(itemID):
            zoomed(DocumentScreen(itemID: itemID, path: $path), id: itemID)
        case .search:
            SearchScreen(path: $path)
        case .trash:
            RecentlyDeletedScreen(path: $path)
        }
    }

    @ViewBuilder
    private func zoomed<Content: View>(_ content: Content, id: UUID) -> some View {
        if let zoomNamespace {
            content.navigationTransition(.zoom(sourceID: id, in: zoomNamespace))
        } else {
            content
        }
    }
}

struct RootView: View {
    @AppObject(LibraryModel.self) private var library
    @AppObject(LockManager.self) private var lock
    @AppObject(IntelligenceCenter.self) private var intelligence
    @AppObject(ToastCenter.self) private var toasts
    @AppObject(CloudSyncModel.self) private var cloud
    @AppObject(BackupCenter.self) private var backups
    @AppObject(Maintenance.self) private var maintenance
    @AppObject(PurchaseCenter.self) private var purchases
    @AppObject(ReminderCenter.self) private var reminders
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    @AppStorage(SettingsKey.hideInAppSwitcher, store: AppGroup.defaults) private var hideInSwitcher = true

    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var path: [Route] = []
    @State private var sidebarSelection: SidebarItem? = .home
    @State private var curtainVisible = false
    @State private var openedBackup: OpenedBackup?
    @State private var dropImport = DropImportModel()
    @State private var showingWelcome = false

    private struct OpenedBackup: Identifiable {
        let url: URL
        var id: URL { url }
    }
    @Namespace private var zoomNamespace

    /// iPad gets the sidebar. An iPhone keeps one navigation stack, even in landscape on the
    /// larger models, so turning the phone doesn't rebuild every screen and its open sheets.
    private var usesSidebar: Bool {
        sizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        Group {
            if usesSidebar {
                LibrarySplitView(path: $path, selection: $sidebarSelection)
            } else {
                NavigationStack(path: $path) {
                    HomeScreen(path: $path)
                        .navigationDestination(for: Route.self) { route in
                            RouteDestination(route: route, path: $path)
                        }
                }
            }
        }
        .environment(\.zoomNamespace, zoomNamespace)
        .environment(dropImport)
        .dropImportSheet(dropImport)
        .toastHost(toasts)
        .alert("Laqta couldn't save the change", isPresented: Binding(
            get: { library.storageError != nil },
            set: { if !$0 { library.storageError = nil } }
        )) {
            Button("OK") { library.storageError = nil }
        } message: {
            Text(verbatim: library.storageError ?? "")
        }
        .overlay {
            if curtainVisible {
                PrivacyCurtain()
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            handle(phase)
        }
        .onOpenURL { url in
            // A backup file opened from the Files app.
            guard url.isFileURL, url.pathExtension.lowercased() == "laqtabackup" else { return }
            openedBackup = OpenedBackup(url: url)
        }
        // A tapped reminder opens its own shot, and nothing else.
        .onChange(of: reminders.tappedItemID) { _, tapped in
            guard let tapped else { return }
            reminders.clearTapped()
            openTapped(tapped)
        }
        .sheet(item: $openedBackup) { opened in
            BackupsScreen(openedFile: opened.url)
                .laqtaThemed()
        }
        // The thirty days: the card that starts them, and the sheet that ends them.
        .fullScreenCover(isPresented: $showingWelcome, onDismiss: {
            purchases.replayFirstRun = false
        }) {
            FirstRunSequence()
                .laqtaThemed()
        }
        .onChange(of: purchases.replayFirstRun) { _, replay in
            if replay { showingWelcome = true }
        }
        .sheet(item: Binding(
            get: { purchases.paywallReason },
            set: { purchases.paywallReason = $0 }
        )) { reason in
            PaywallSheet(reason: reason)
                .laqtaThemed()
        }
        .task {
            purchases.start()
            // A first run shows it once the library is on screen, never over a cold start.
            try? await Task.sleep(for: .seconds(1.2))
            if PurchaseCenter.Welcome.isPending, openedBackup == nil {
                showingWelcome = true
            }
        }
    }

    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .active:
            withAnimation(.easeOut(duration: 0.35)) { curtainVisible = false }
            library.checkForExternalChanges(context: modelContext)
            purgeTrashIfDue()
            Task {
                // A day may have passed in the background — but never change this
                // inside the first update, which runs while the views are being built.
                purchases.refreshAccess()
                await MediaStore.purgeStaging()
                if library.autoDeleteEnabled || library.pendingDeletionCount(context: modelContext) > 0 {
                    await library.runPhotoCleanup(context: modelContext)
                }
            }
            intelligence.processPending(context: modelContext)
            cloud.appDidBecomeActive(context: modelContext)
            Task {
                await YouTubeRefresher.refreshIfDue(context: modelContext)
                // Automatic backups wait a little, so opening the app stays quick.
                try? await Task.sleep(for: .seconds(8))
                await backups.runIfDue()
            }
        case .inactive:
            if hideInSwitcher {
                withAnimation(.easeIn(duration: 0.18)) { curtainVisible = true }
            }
        case .background:
            if hideInSwitcher { curtainVisible = true }
            maintenance.appDidEnterBackground()
            lock.lockAll()
            if path.contains(where: isPrivateRoute) {
                path.removeAll()
            }
            if case let .folder(folderID)? = sidebarSelection,
               LaqtaStore.folder(with: folderID, context: modelContext)?.isPrivate == true {
                sidebarSelection = .home
            }
        @unknown default:
            break
        }
    }

    /// Opens the shot a reminder was tapped for.
    ///
    /// A locked folder is not opened behind the user's back: the folder screen is
    /// pushed instead, and it asks for the face the way it always does.
    private func openTapped(_ itemID: UUID) {
        guard let item = LaqtaStore.item(with: itemID, context: modelContext),
              item.deletedAt == nil else { return }
        if let folderID = item.folderID,
           let folder = LaqtaStore.folder(with: folderID, context: modelContext),
           !lock.canShow(folder) {
            path = [.folder(folderID)]
            return
        }
        guard let route = Route.destination(for: item) else { return }
        path = [route]
    }

    /// Recently Deleted is emptied of expired items a few times a day.
    private func purgeTrashIfDue() {
        let last = AppGroup.defaults.double(forKey: SettingsKey.lastPurgeAt)
        guard Date.now.timeIntervalSince1970 - last > 6 * 3600 else { return }
        library.purgeExpiredTrash(context: modelContext)
    }

    /// Leave private folders when the app goes to the background.
    private func isPrivateRoute(_ route: Route) -> Bool {
        let folderID: UUID?
        switch route {
        case let .folder(id): folderID = id
        case let .viewer(id, _): folderID = id
        case let .link(itemID), let .document(itemID):
            folderID = LaqtaStore.item(with: itemID, context: modelContext)?.folderID
        case .search:
            return false
        case .trash:
            return true
        }
        guard let folderID else { return false }
        return LaqtaStore.folder(with: folderID, context: modelContext)?.isPrivate ?? false
    }
}

/// Shown instead of the app in the app switcher.
struct PrivacyCurtain: View {
    @Environment(\.laqta) private var palette

    var body: some View {
        ZStack {
            LaqtaBackground()
            VStack(spacing: 10) {
                Text(verbatim: "Laqta")
                    .laqtaDisplayFont(56, maxScale: 1.1)
                    .foregroundStyle(palette.goldHi)
                Image(systemName: "lock")
                    .laqtaIconFont(16, weight: .medium)
                    .foregroundStyle(palette.gold)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Marks the view as the origin of the zoom transition into the viewer.
    func zoomSource(id: UUID) -> some View {
        ZoomSourceModifierView(content: self, id: id)
    }
}

private struct ZoomSourceModifierView<Content: View>: View {
    let content: Content
    let id: UUID
    @Environment(\.zoomNamespace) private var namespace

    var body: some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}
