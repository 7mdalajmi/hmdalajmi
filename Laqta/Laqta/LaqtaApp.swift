//
//  LaqtaApp.swift
//  Laqta
//
//  Keep your shots, videos, PDFs and links in private folders — straight from the share sheet.
//

import Foundation
import SwiftData
import SwiftUI

@main
struct LaqtaApp: App {
    @State private var store: LibraryStore
    @State private var library: LibraryModel
    @State private var lock: LockManager
    @State private var intelligence: IntelligenceCenter
    @State private var toasts: ToastCenter
    @State private var cloud: CloudSyncModel
    @State private var backups: BackupCenter
    @State private var maintenance: Maintenance
    @State private var purchases: PurchaseCenter
    @State private var reminders: ReminderCenter

    init() {
        let store = LibraryStore()
        let library = LibraryModel()
        let lock = LockManager()
        let intelligence = IntelligenceCenter()
        let toasts = ToastCenter()
        let cloud = CloudSyncModel()
        let backups = BackupCenter()
        let purchases = PurchaseCenter()
        let reminders = ReminderCenter()
        cloud.start(store: store, library: library)
        // Before the app finishes launching, or a tap on a reminder is lost.
        reminders.startRouting()
        backups.configure(store: store, library: library, intelligence: intelligence)
        let maintenance = Maintenance(
            store: store,
            library: library,
            intelligence: intelligence,
            cloud: cloud,
            backups: backups
        )
        // Views that SwiftUI evaluates without the environment below use these (see AppObject).
        AppObjects.register(store, library, lock, intelligence, toasts, cloud, backups, maintenance, purchases, reminders)
        _store = State(initialValue: store)
        _library = State(initialValue: library)
        _lock = State(initialValue: lock)
        _intelligence = State(initialValue: intelligence)
        _toasts = State(initialValue: toasts)
        _cloud = State(initialValue: cloud)
        _backups = State(initialValue: backups)
        _maintenance = State(initialValue: maintenance)
        _purchases = State(initialValue: purchases)
        _reminders = State(initialValue: reminders)
    }

    var body: some Scene {
        let maintenance = maintenance
        WindowGroup {
            AppRoot(store: store)
                .environment(store)
                .environment(library)
                .environment(lock)
                .environment(intelligence)
                .environment(toasts)
                .environment(cloud)
                .environment(backups)
                .environment(maintenance)
                .environment(purchases)
                .environment(reminders)
                .laqtaThemed()
                .environment(\.locale, LaqtaLocale.current)
                .environment(\.layoutDirection, .leftToRight)
        }
        .backgroundTask(.processingTask(BackgroundWork.maintenanceIdentifier)) {
            await maintenance.runInBackground()
        }
    }
}

private struct AppRoot: View {
    let store: LibraryStore

    var body: some View {
        if let container = store.container {
            RootView()
                .modelContainer(container)
                .transition(.opacity)
        } else if store.isReopening {
            ReopeningView()
                .transition(.opacity)
        } else {
            LaunchErrorView(message: store.launchError ?? "")
        }
    }
}

/// Shown for a moment while the library reopens with a new iCloud setting.
private struct ReopeningView: View {
    @Environment(\.laqta) private var palette

    var body: some View {
        ZStack {
            LaqtaBackground()
            VStack(spacing: 14) {
                Text(verbatim: "Laqta")
                    .laqtaDisplayFont(50, maxScale: 1.1)
                    .foregroundStyle(palette.goldHi)
                ProgressView()
                    .tint(palette.goldHi)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Opening your library"))
    }
}

private struct LaunchErrorView: View {
    let message: String
    @Environment(\.laqta) private var palette

    var body: some View {
        ZStack {
            LaqtaBackground()
            VStack(spacing: 14) {
                Text(verbatim: "Laqta")
                    .laqtaDisplayFont(50, maxScale: 1.1)
                    .foregroundStyle(palette.goldHi)
                Text("Laqta couldn't open your library.")
                    .laqtaFont(17, weight: .semibold)
                    .foregroundStyle(palette.ink)
                Text(verbatim: message)
                    .laqtaFont(13)
                    .foregroundStyle(palette.ink2)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
    }
}
