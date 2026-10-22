//
//  BackupsScreen.swift
//  Laqta
//
//  Back up now, automatic backups, backups in iCloud, and backup files.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupsScreen: View {
    /// A backup file opened from the Files app.
    var openedFile: URL?

    @AppObject(BackupCenter.self) private var backups
    @Environment(\.dismiss) private var dismiss
    @Environment(\.laqta) private var palette

    @State private var exportFile: BackupFile?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingRestore: BackupInfo?
    @State private var pendingDelete: BackupInfo?
    @State private var pendingFile: URL?
    @State private var didHandleOpenedFile = false

    var body: some View {
        VStack(spacing: 0) {
            SheetBar("Backups") {
                EmptyView()
            } trailing: {
                Button {
                    dismiss()
                } label: {
                    BarTextButtonLabel(title: "Done", prominent: true)
                }
                .buttonStyle(.pressable)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    statusCard
                    section("Automatic Backups", footer: "Laqta backs up to iCloud when your library changed, and keeps the newest backups of this device.") {
                        automaticSection
                    }
                    section("In iCloud", footer: iCloudFooter) {
                        iCloudList
                    }
                    section("Backup Files", footer: "A backup file holds your whole library in one file. Save it to Files, a computer or a drive, and restore it on any device.") {
                        fileSection
                    }
                    Text("Restoring adds what's missing from your library. Nothing in Laqta is replaced or deleted.")
                        .laqtaFont(12)
                        .foregroundStyle(palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(palette.sheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(palette.sheet)
        .presentationCornerRadius(32)
        .task {
            await backups.loadBackups()
        }
        .onAppear {
            if let openedFile, !didHandleOpenedFile {
                didHandleOpenedFile = true
                pendingFile = openedFile
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            item: exportFile,
            contentTypes: [.laqtaBackup],
            defaultFilename: exportFile?.url.deletingPathExtension().lastPathComponent
        ) { result in
            backups.finishExport(result)
            exportFile = nil
        } onCancellation: {
            backups.finishExport(nil)
            exportFile = nil
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.laqtaBackup]) { result in
            switch result {
            case let .success(url):
                pendingFile = url
            case let .failure(error):
                backups.notice = BackupCenter.Notice(title: "Couldn't open the file", text: error.localizedDescription)
            }
        }
        .confirmationDialog(
            restoreTitle,
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Restore") {
                if let info = pendingRestore {
                    backups.restore(info)
                }
                pendingRestore = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRestore = nil
            }
        } message: {
            Text("Items from this backup that aren't in Laqta are added. Nothing is replaced or deleted.")
        }
        .confirmationDialog(
            "Restore from this file?",
            isPresented: Binding(get: { pendingFile != nil }, set: { if !$0 { pendingFile = nil } }),
            titleVisibility: .visible
        ) {
            Button("Restore") {
                if let url = pendingFile {
                    backups.restore(fileAt: url)
                }
                pendingFile = nil
            }
            Button("Cancel", role: .cancel) {
                pendingFile = nil
            }
        } message: {
            Text("\(pendingFile?.lastPathComponent ?? "")\nItems that aren't in Laqta are added. Nothing is replaced or deleted.")
        }
        .confirmationDialog(
            "Delete this backup?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Backup", role: .destructive) {
                if let info = pendingDelete {
                    Task { await backups.delete(info) }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("It's removed from iCloud on all your devices. Your library isn't affected.")
        }
        .alert(
            backups.notice?.title ?? "",
            isPresented: Binding(get: { backups.notice != nil }, set: { if !$0 { backups.notice = nil } }),
            presenting: backups.notice
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(verbatim: notice.text)
        }
    }

    // MARK: Sections

    private func section<Content: View>(_ title: LocalizedStringKey, footer: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .textCase(.uppercase)
                .laqtaFont(12, weight: .semibold)
                .tracking(0.96)
                .foregroundStyle(palette.gold)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            LaqtaGroup {
                content()
            }
            Text(verbatim: footer)
                .laqtaFont(12)
                .foregroundStyle(palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var statusCard: some View {
        LaqtaCard {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(palette.field, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: backups.isBusy ? backups.progress : 1)
                        .stroke(palette.goldHi, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.25), value: backups.progress)
                    Image(systemName: statusSymbol)
                        .laqtaIconFont(20, weight: .semibold)
                        .foregroundStyle(palette.goldHi)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 58, height: 58)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: statusTitle)
                        .laqtaFont(17, weight: .semibold)
                        .foregroundStyle(palette.ink)
                    Text(verbatim: statusDetail)
                        .laqtaFont(13)
                        .foregroundStyle(palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 10) {
                if backups.isBusy {
                    Button {
                        backups.cancel()
                    } label: {
                        LaqtaButtonLabel("Stop", systemImage: "stop.fill", kind: .line, fullWidth: true)
                    }
                } else {
                    Button {
                        backups.backUpNow()
                    } label: {
                        LaqtaButtonLabel("Back Up Now", systemImage: "icloud.and.arrow.up", fullWidth: true)
                    }
                    .disabled(!backups.isICloudAvailable)
                }
            }
            .buttonStyle(.pressable)
            .padding(.top, 14)
        }
    }

    private var statusSymbol: String {
        switch backups.activity {
        case .idle:
            if !backups.isICloudAvailable { "icloud.slash" }
            else if backups.lastError != nil { "exclamationmark.icloud" }
            else if backups.lastBackupAt == nil { "icloud" }
            else { "checkmark.icloud" }
        case .backingUp: "icloud.and.arrow.up"
        case .exporting: "doc.zipper"
        case .restoring: "arrow.counterclockwise.icloud"
        }
    }

    private var statusTitle: String {
        switch backups.activity {
        case .backingUp: return String(localized: "Backing up…")
        case .exporting: return String(localized: "Making a backup file…")
        case .restoring: return String(localized: "Restoring…")
        case .idle:
            guard backups.isICloudAvailable else { return String(localized: "iCloud isn't available") }
            guard let last = backups.lastBackupAt else { return String(localized: "Not backed up yet") }
            return String(localized: "Backed up \(LaqtaFormat.relative(last))")
        }
    }

    private var statusDetail: String {
        if backups.isBusy {
            return backups.detail.isEmpty ? "\(Int((backups.progress * 100).rounded()))%" : backups.detail
        }
        guard backups.isICloudAvailable else {
            return "Sign in to iCloud and turn on iCloud Drive to back up. You can still save a backup file."
        }
        if let error = backups.lastError {
            return "The last backup didn't finish: \(error)"
        }
        var parts: [String] = []
        if let bytes = backups.iCloudBytes, bytes > 0 { parts.append("\(LaqtaFormat.bytes(bytes)) in iCloud") }
        parts.append("You can leave Laqta while it backs up.")
        return parts.joined(separator: " · ")
    }

    private var automaticSection: some View {
        @Bindable var backups = backups
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                RowIcon(systemImage: "calendar")
                RowText(title: Text("Back up to iCloud"))
                Menu {
                    Picker("Back up to iCloud", selection: $backups.frequency) {
                        ForEach(BackupFrequency.allCases) { frequency in
                            Text(verbatim: frequency.title).tag(frequency)
                        }
                    }
                } label: {
                    menuLabel(backups.frequency.title)
                }
            }
            .frame(minHeight: 56)
            RowSeparator()
            HStack(spacing: 12) {
                RowIcon(systemImage: "square.stack.3d.up")
                RowText(title: Text("Keep"), subtitle: Text("Older backups of this device are removed"))
                Menu {
                    Picker("Keep", selection: $backups.keepCount) {
                        ForEach([1, 3, 5, 10], id: \.self) { count in
                            Text(verbatim: LaqtaFormat.count(count, "backup", "backups")).tag(count)
                        }
                    }
                } label: {
                    menuLabel(LaqtaFormat.count(backups.keepCount, "backup", "backups"))
                }
            }
            .frame(minHeight: 56)
        }
    }

    private func menuLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: text)
            Image(systemName: "chevron.up.chevron.down")
                .laqtaIconFont(11, weight: .semibold)
        }
        .laqtaFont(15)
        .foregroundStyle(palette.goldHi)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var iCloudList: some View {
        if backups.isLoading, backups.backups.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(palette.goldHi)
                Text("Looking for backups…")
                    .laqtaFont(14)
                    .foregroundStyle(palette.ink2)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        } else if backups.backups.isEmpty {
            Text(backups.isICloudAvailable ? "No backups yet." : "iCloud isn't available on this device.")
                .laqtaFont(14)
                .foregroundStyle(palette.ink2)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(backups.backups.enumerated()), id: \.element.id) { index, info in
                    BackupRow(info: info, isLatest: index == 0)
                        .contextMenu {
                            restoreAndDeleteButtons(info)
                        }
                        .overlay(alignment: .trailing) {
                            Menu {
                                restoreAndDeleteButtons(info)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .laqtaIconFont(20)
                                    .foregroundStyle(palette.goldHi)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .disabled(backups.isBusy)
                            .accessibilityLabel(Text("Backup options"))
                        }
                    if index < backups.backups.count - 1 {
                        RowSeparator()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func restoreAndDeleteButtons(_ info: BackupInfo) -> some View {
        Button {
            pendingRestore = info
        } label: {
            Label("Restore", systemImage: "arrow.counterclockwise")
        }
        Button(role: .destructive) {
            pendingDelete = info
        } label: {
            Label("Delete Backup", systemImage: "trash")
        }
    }

    private var fileSection: some View {
        VStack(spacing: 0) {
            Button {
                Task {
                    if let file = await backups.exportBackup() {
                        exportFile = file
                        showingExporter = true
                    }
                }
            } label: {
                actionRow(icon: "square.and.arrow.up", title: "Save a Backup File", busy: backups.activity == .exporting)
            }
            .buttonStyle(.plain)
            .disabled(backups.isBusy)
            RowSeparator()
            Button {
                showingImporter = true
            } label: {
                actionRow(icon: "square.and.arrow.down", title: "Restore from a File", busy: false)
            }
            .buttonStyle(.plain)
            .disabled(backups.isBusy)
        }
    }

    private func actionRow(icon: String, title: LocalizedStringKey, busy: Bool) -> some View {
        HStack(spacing: 12) {
            RowIcon(systemImage: icon)
            RowText(title: Text(title))
            if busy {
                ProgressView()
                    .tint(palette.goldHi)
            } else {
                Image(systemName: "chevron.forward")
                    .laqtaIconFont(13, weight: .semibold)
                    .foregroundStyle(palette.ink3)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var iCloudFooter: String {
        var text = "Backups from all your devices appear here. Media files are shared between backups, so each backup only adds what changed."
        if backups.waitingBackups > 0 {
            text += " \(LaqtaFormat.count(backups.waitingBackups, "backup is", "backups are")) still downloading from iCloud."
        }
        return text
    }

    private var restoreTitle: String {
        guard let info = pendingRestore else { return "" }
        return "Restore the backup from \(LaqtaFormat.dateTime(info.createdAt))?"
    }
}

private struct BackupRow: View {
    let info: BackupInfo
    let isLatest: Bool

    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(systemImage: info.deviceName.localizedCaseInsensitiveContains("ipad") ? "ipad" : "iphone")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: LaqtaFormat.dateTime(info.createdAt))
                        .laqtaFont(15, weight: .medium)
                        .foregroundStyle(palette.ink)
                    if isLatest {
                        Text("Latest")
                            .laqtaFont(10.5, weight: .semibold, maxScale: 1.25)
                            .foregroundStyle(palette.goldInk)
                            .padding(.horizontal, 6)
                            .frame(minHeight: 18)
                            .background(palette.accentFill, in: Capsule())
                    }
                }
                Text(verbatim: subtitle)
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 44)
        }
        .frame(minHeight: 60)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        [
            info.deviceName,
            LaqtaFormat.count(info.itemCount, "item", "items"),
            LaqtaFormat.count(info.folderCount, "folder", "folders"),
            info.mediaBytes > 0 ? LaqtaFormat.bytes(info.mediaBytes) : nil
        ].compactMap { $0 }.joined(separator: " · ")
    }
}
