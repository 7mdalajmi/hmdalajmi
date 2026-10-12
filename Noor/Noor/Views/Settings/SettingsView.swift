import SwiftUI

/// App settings (a sheet from the library): canvas surround, haptics, the default export format,
/// storage used with "Clear Thumbnail Cache", and About.
///
/// Every change is written straight into `AppModel.settings`, which saves itself.
@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var usage: LibraryStorageUsage?
    @State private var isClearingCache = false

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    Picker("Canvas Surround", selection: $app.settings.surround) {
                        ForEach(CanvasSurround.allCases) { surround in
                            SettingsSurroundRow(surround: surround)
                                .tag(surround)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Canvas Surround")
                } footer: {
                    Text("The background around your photo while you edit. Grey is the most neutral for judging tones.")
                }
                .listRowBackground(Theme.surface2)

                Section {
                    Toggle("Haptics", isOn: $app.settings.haptics)
                } footer: {
                    Text("Subtle taps when a slider reaches its default and when you switch tools.")
                }
                .listRowBackground(Theme.surface2)

                Section {
                    Picker("Default Format", selection: $app.settings.defaultExport.format) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(SettingsView.title(of: format))
                                .tag(format)
                        }
                    }
                } header: {
                    Text("Export")
                } footer: {
                    Text(SettingsView.summary(of: app.settings.defaultExport.format))
                }
                .listRowBackground(Theme.surface2)

                storageSection
                    .listRowBackground(Theme.surface2)

                aboutSection
                    .listRowBackground(Theme.surface2)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface1)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                usage = await app.library.storageUsage()
            }
        }
        .tint(Theme.accent)
    }

    // MARK: Storage

    private var storageSection: some View {
        Section {
            LabeledContent("Photos and Edits") {
                byteCount(usage?.originals)
            }
            LabeledContent("Thumbnail Cache") {
                byteCount(usage?.thumbnails)
            }
            Button {
                Task { await clearThumbnailCache() }
            } label: {
                HStack {
                    Text("Clear Thumbnail Cache")
                    Spacer(minLength: Theme.Space.s)
                    if isClearingCache {
                        ProgressView()
                    }
                }
            }
            .disabled(isClearingCache || usage == nil || usage?.thumbnails == 0)
        } header: {
            Text("Storage")
        } footer: {
            Text("Thumbnails are small previews that Noor recreates when needed. Clearing them never touches your photos or edits.")
        }
    }

    @ViewBuilder
    private func byteCount(_ bytes: Int64?) -> some View {
        if let bytes {
            Text(verbatim: bytes.formatted(.byteCount(style: .file)))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        } else {
            ProgressView()
        }
    }

    private func clearThumbnailCache() async {
        isClearingCache = true
        await app.library.clearThumbnailCache()
        usage = await app.library.storageUsage()
        isClearingCache = false
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            LabeledContent("Version") {
                Text(verbatim: SettingsView.versionString)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("Noor never changes your originals: every edit is kept as a recipe, and every export is rendered fresh from the original at full quality.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        } header: {
            Text("About")
        }
    }

    /// "1.0 (12)" from the bundle. Not localized.
    private static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: Export format labels

    private static func title(of format: ExportFormat) -> LocalizedStringKey {
        switch format {
        case .original: return "Same as Original"
        case .heif10: return "HEIF 10-bit"
        case .tiff16: return "TIFF 16-bit"
        case .png16: return "PNG 16-bit"
        case .jpeg: return "JPEG 8-bit"
        case .heif8: return "HEIF 8-bit"
        }
    }

    private static func summary(of format: ExportFormat) -> LocalizedStringKey {
        switch format {
        case .original:
            return "The same kind of file as the original, at its best quality. Unedited photos are copied byte for byte."
        case .heif10:
            return "The best lossy format. Keeps wide color and HDR."
        case .tiff16:
            return "A lossless 16-bit master. Large files."
        case .png16:
            return "Lossless 16-bit, widely supported."
        case .jpeg:
            return "8-bit and lossy, but opens everywhere."
        case .heif8:
            return "8-bit and lossy, like the iPhone camera."
        }
    }
}

// MARK: - Surround row

/// A picker row: a swatch of the surround colour with its name and use.
private struct SettingsSurroundRow: View {
    let surround: CanvasSurround

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                .fill(Theme.surround(surround))
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                        .stroke(Theme.trackInactive, lineWidth: 1)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var title: LocalizedStringKey {
        switch surround {
        case .dark: return "Dark"
        case .black: return "Black"
        case .grey: return "Grey"
        }
    }

    private var detail: LocalizedStringKey {
        switch surround {
        case .dark: return "Default, easy on the eyes"
        case .black: return "Deepest contrast on OLED screens"
        case .grey: return "Neutral mid-grey for judging tones"
        }
    }
}
