//
//  CloudSettingsSection.swift
//  Laqta
//
//  iCloud Sync and Backups in Settings.
//

import SwiftData
import SwiftUI

struct CloudSettingsSection: View {
    static let footer = "Sync keeps your folders, notes, photos, videos and PDFs on all your devices with Laqta. Backups keep copies in iCloud you can restore, even after deleting the app."

    @AppObject(CloudSyncModel.self) private var cloud
    @AppObject(BackupCenter.self) private var backups
    @Environment(\.modelContext) private var modelContext
    @Environment(\.laqta) private var palette

    @State private var confirmingOn = false
    @State private var confirmingOff = false
    @State private var showingAccountHelp = false
    @State private var showingBackups = false
    @State private var uploadBytes: Int64 = 0

    var body: some View {
        VStack(spacing: 0) {
            Toggle(isOn: syncBinding) {
                HStack(spacing: 12) {
                    RowIcon(systemImage: "icloud")
                    RowText(title: Text("iCloud Sync"), subtitle: Text(verbatim: syncSubtitle))
                }
            }
            .frame(minHeight: 56)
            .disabled(cloud.switching != .none)

            if case let .downloading(done, total) = cloud.switching {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                        .tint(palette.goldHi)
                    HStack {
                        Text("Downloading \(LaqtaFormat.number(done)) of \(LaqtaFormat.number(total)) to this device…")
                            .laqtaFont(12)
                            .foregroundStyle(palette.ink2)
                        Spacer()
                        Button("Cancel") {
                            cloud.cancelSwitching()
                        }
                        .laqtaFont(13, weight: .semibold)
                        .foregroundStyle(palette.goldHi)
                    }
                }
                .padding(.leading, 44)
                .padding(.bottom, 12)
            } else if cloud.switching == .turningOn || cloud.switching == .turningOff {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(palette.goldHi)
                    Text(cloud.switching == .turningOn ? "Turning on iCloud Sync…" : "Turning off iCloud Sync…")
                        .laqtaFont(12)
                        .foregroundStyle(palette.ink2)
                    Spacer()
                }
                .padding(.leading, 44)
                .padding(.bottom, 12)
            }

            RowSeparator()
            Button {
                showingBackups = true
            } label: {
                HStack(spacing: 12) {
                    RowIcon(systemImage: "clock.arrow.circlepath")
                    RowText(title: Text("Backups"), subtitle: Text(verbatim: backupSubtitle))
                    if backups.activity == .backingUp {
                        ProgressView(value: backups.progress)
                            .progressViewStyle(.circular)
                            .tint(palette.goldHi)
                    }
                    Image(systemName: "chevron.right")
                        .laqtaIconFont(13, weight: .semibold)
                        .foregroundStyle(palette.ink3)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            cloud.refreshStatus()
        }
        .alert("Sync with iCloud?", isPresented: $confirmingOn) {
            Button("Turn On") {
                Task { await cloud.turnOn() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: turnOnMessage)
        }
        .confirmationDialog("Turn off iCloud Sync on this device?", isPresented: $confirmingOff, titleVisibility: .visible) {
            Button("Download and Turn Off", role: .destructive) {
                Task { await cloud.turnOff() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Laqta first downloads your photos, videos and PDFs to this device. Your library stays in iCloud and on your other devices.")
        }
        .alert("iCloud isn't available", isPresented: $showingAccountHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sign in to iCloud in the Settings app and make sure iCloud Drive is on, then try again.")
        }
        .sheet(isPresented: $showingBackups) {
            BackupsScreen()
                .laqtaThemed()
        }
    }

    private var syncBinding: Binding<Bool> {
        Binding(
            get: { cloud.isEnabled },
            set: { wantsOn in
                if wantsOn {
                    guard cloud.isAccountAvailable else {
                        showingAccountHelp = true
                        return
                    }
                    uploadBytes = cloud.uploadSize(context: modelContext)
                    confirmingOn = true
                } else {
                    confirmingOff = true
                }
            }
        )
    }

    private var syncSubtitle: String {
        cloud.isEnabled ? cloud.statusText : String(localized: "Your library on all your devices")
    }

    private var backupSubtitle: String {
        if backups.activity == .backingUp { return backups.detail.isEmpty ? String(localized: "Backing up…") : backups.detail }
        if let error = backups.lastError, backups.frequency != .off { return error }
        guard backups.isICloudAvailable else { return "Sign in to iCloud to back up" }
        let schedule = backups.frequency == .off ? "Automatic backups off" : "\(backups.frequency.title) in iCloud"
        guard let last = backups.lastBackupAt else { return "\(schedule) · not backed up yet" }
        return "\(schedule) · last \(LaqtaFormat.relative(last))"
    }

    private var turnOnMessage: String {
        let size = uploadBytes > 0 ? " (\(LaqtaFormat.bytes(uploadBytes)))" : ""
        return "Your folders, notes, photos, videos and PDFs\(size) are stored in your private iCloud and appear on your other devices with Laqta. Only you can see them."
    }
}
