import AppKit
import SwiftData
import SwiftUI

@main
struct LaqtaMacApp: App {
    @State private var library = MacLibrary()
    @FocusedValue(\.macWorkspaceActions) private var actions

    var body: some Scene {
        WindowGroup("Laqta — لقطة") {
            if let container = library.container {
                MacLibraryView(library: library)
                    .modelContainer(container)
                    .frame(minWidth: 940, minHeight: 620)
                    .environment(\.layoutDirection, .rightToLeft)
                    .environment(\.locale, Locale(identifier: "ar_KW"))
            } else {
                ContentUnavailableView {
                    Label("تعذر فتح المكتبة", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(library.launchError ?? "خطأ غير معروف")
                    Text("ملفاتك محفوظة. أصلح إعدادات التوقيع أو التخزين ثم أعد المحاولة.")
                } actions: {
                    Button("إعادة المحاولة") { library.open() }
                }
                .frame(width: 640, height: 400)
            }
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("استيراد ملفات…") { actions?.importFiles() }
                    .keyboardShortcut("o")
                    .disabled(library.isBusy)
                Button("إضافة رابط…") { actions?.addLink() }
                    .keyboardShortcut("l")
                    .disabled(library.isBusy)
                Button("مجلد جديد…") { actions?.newFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(library.isBusy)
            }
            CommandMenu("المكتبة") {
                Button("تصدير نسخة احتياطية…") { Task { await library.exportBackup() } }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(library.isBusy)
                Button("استعادة نسخة احتياطية…") { actions?.restoreBackup() }
                    .disabled(library.isBusy)
                Divider()
                Button("قفل المجلدات الخاصة") { library.lockAll() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("مزامنة ملفات iCloud الآن") { Task { await library.uploadPendingMedia() } }
                    .disabled(!library.syncActive || library.isBusy)
            }
        }
        Settings {
            MacSettingsView(library: library)
                .frame(width: 580, height: 430)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_KW"))
        }
    }
}

// The native app reuses the original SwiftData schema and backup format.
nonisolated struct CoverSource: Hashable, Sendable {
    let id: UUID
    let thumbnailURL: URL
    let originalURL: URL?
}

struct MacWorkspaceActions {
    var importFiles: () -> Void
    var addLink: () -> Void
    var newFolder: () -> Void
    var restoreBackup: () -> Void
}

private struct MacWorkspaceActionsKey: FocusedValueKey {
    typealias Value = MacWorkspaceActions
}

extension FocusedValues {
    var macWorkspaceActions: MacWorkspaceActions? {
        get { self[MacWorkspaceActionsKey.self] }
        set { self[MacWorkspaceActionsKey.self] = newValue }
    }
}
