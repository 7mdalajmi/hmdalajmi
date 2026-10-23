import AppKit
import SwiftData
import SwiftUI

struct MacFolderSheet: View {
    @Bindable var library: MacLibrary
    let folder: Folder?
    let parentID: UUID?
    let folders: [Folder]
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var locked = false
    @State private var parent: UUID?

    private var destinations: [Folder] {
        folders.filter { candidate in
            !candidate.isInTrash && library.canAccess(candidate.id, folders: folders)
                && folder.map { !LaqtaStore.wouldLoop(moving: $0.id, into: candidate.id, folders: folders) } != false
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(folder == nil ? "مجلد جديد" : "تعديل المجلد").font(.title2.bold())
            Form {
                TextField("الاسم", text: $name)
                Picker("داخل", selection: $parent) {
                    Text("المكتبة الرئيسية").tag(UUID?.none)
                    ForEach(destinations) { folder in
                        Text(LaqtaStore.path(to: folder.id, in: folders).map(\.name).joined(separator: " / ")).tag(Optional(folder.id))
                    }
                }
                Toggle("مجلد خاص", isOn: $locked)
                Text("يفتح المجلد الخاص باستخدام Touch ID أو كلمة مرور الماك، ويختفي محتواه من البحث حتى تفتحه. وملفات المجلد المقفول تُشفَّر داخل النسخة الاحتياطية بمفتاح في Keychain ينتقل عبر iCloud Keychain إلى أجهزتك وحدها.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("إلغاء") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("حفظ") {
                    if let folder {
                        if library.save({ folder.name = name.trimmingCharacters(in: .whitespacesAndNewlines); folder.isLocked = locked; folder.parentID = parent; folder.touch() }) { dismiss() }
                    } else if library.createFolder(name: name, parent: parent, locked: locked) != nil { dismiss() }
                }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || library.isBusy)
            }
        }.padding(24).frame(width: 480)
        .disabled(library.isBusy)
        .onAppear { name = folder?.name ?? ""; locked = folder?.isLocked ?? false; parent = folder?.parentID ?? parentID }
    }
}

struct MacLinkSheet: View {
    @Bindable var library: MacLibrary
    let folderID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("إضافة رابط").font(.title2.bold())
            TextField("https://", text: $text).textFieldStyle(.roundedBorder)
            Text("يحفظ لقطة عنوان الصفحة ومحتواها المتاح للبحث، ويفتح الرابط الأصلي في متصفحك. صفحات تسجيل الدخول قد تعرض معلومات محدودة.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("إلغاء") { dismiss() }.keyboardShortcut(.cancelAction).disabled(library.isBusy)
                Button("لصق") { text = NSPasteboard.general.string(forType: .string) ?? "" }
                Spacer()
                if library.isBusy { ProgressView().controlSize(.small) }
                Button("حفظ الرابط") { Task { if await library.addLink(text, folderID: folderID) { dismiss() } } }
                    .keyboardShortcut(.defaultAction).disabled(library.isBusy || text.isEmpty)
            }
        }.padding(24).frame(width: 500)
    }
}

struct MacSettingsView: View {
    @Bindable var library: MacLibrary
    @AppStorage("macAppearance") private var appearance = "system"
    @AppStorage(SettingsKey.skipDuplicates, store: AppGroup.defaults) private var skipDuplicates = true
    @State private var cloudEnabled = CloudConfig.isSyncEnabled
    var body: some View {
        Form {
            Section("المظهر والاستيراد") {
                Picker("المظهر", selection: $appearance) {
                    Text("حسب النظام").tag("system")
                    Text("فاتح").tag("light")
                    Text("داكن").tag("dark")
                }
                Toggle("تجاوز الملفات والروابط المكررة", isOn: $skipDuplicates)
                Text("تنسخ لقطة الملفات إلى مكتبتها. تبقى الملفات الأصلية في Finder محفوظة.").font(.caption).foregroundStyle(.secondary)
            }
            Section("iCloud") {
                Toggle("مزامنة المكتبة مع iPhone وiPad", isOn: Binding(get: { cloudEnabled }, set: { enabled in
                    Task { await library.setCloudEnabled(enabled); cloudEnabled = CloudConfig.isSyncEnabled }
                })).disabled(library.isBusy || library.localDistribution)
                Text(library.syncActive ? "المزامنة مفعلة للمكتبة المفتوحة." : "المكتبة المفتوحة محفوظة محليًا.").font(.caption)
                Text("يتطلب توقيع التطبيق بحساب Apple يدعم App Group وحاوية iCloud الخاصة بلقطة. أعد فتح التطبيق بعد تغيير هذا الإعداد.").font(.caption).foregroundStyle(.secondary)
                if library.localDistribution {
                    Text("النسخة المسلّمة للتجربة المحلية تحفظ مكتبتها على هذا الماك؛ المزامنة معطلة حتى بناء نسخة موقعة من Xcode.").font(.caption).foregroundStyle(.secondary)
                }
                Button("مزامنة الملفات الآن") { Task { await library.uploadPendingMedia() } }.disabled(!library.syncActive || library.isBusy)
            }
            Section("النسخ الاحتياطية والخصوصية") {
                Button("تصدير نسخة احتياطية…") { Task { await library.exportBackup() } }
                Button("استعادة نسخة احتياطية…") {
                    Task {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.laqtaBackup]
                        if await panel.begin() == .OK, let url = panel.url { await library.restoreBackup(url) }
                    }
                }
                Button("قفل المجلدات الخاصة") { library.lockAll() }
                Text("تعمل النسخ بصيغة .laqtabackup المشتركة مع تطبيق iPhone، وتشمل الملفات والمجلدات والملاحظات. ملفات المجلدات المقفولة مشفَّرة داخلها؛ أما بقية الملفات فتُحفظ كما هي، فاحفظ النسخة في مكان تثق به.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .alert("لقطة", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button("حسنًا") { library.message = nil }
        } message: { Text(library.message ?? "") }
    }
}
