//
//  MediaWaiting.swift
//  Laqta
//
//  Media synced from another device may still be in iCloud. These helpers ask iCloud
//  for it and update the view when it arrives.
//

import SwiftUI

enum MediaWaiter {
    /// Waits until the item's media file can be read on this device.
    static func waitForFile(named fileName: String) async -> URL? {
        guard !fileName.isEmpty else { return nil }
        var attempt = 0
        while !Task.isCancelled {
            // Recomputed each time: the iCloud container may be found after the view appeared.
            let url = MediaLocation.fileURL(named: fileName)
            if CloudFiles.isAvailable(url) { return url }
            if attempt % 15 == 0 { CloudMediaStore.requestDownload(of: fileName) }
            attempt += 1
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return nil
            }
        }
        return nil
    }

    static func isAvailable(fileName: String) -> Bool {
        guard !fileName.isEmpty else { return false }
        return CloudFiles.isAvailable(MediaLocation.fileURL(named: fileName))
    }
}

private struct MediaAvailabilityModifier: ViewModifier {
    let fileName: String
    @Binding var isAvailable: Bool

    func body(content: Content) -> some View {
        content.task(id: fileName) {
            if MediaWaiter.isAvailable(fileName: fileName) {
                isAvailable = true
                return
            }
            isAvailable = false
            if await MediaWaiter.waitForFile(named: fileName) != nil {
                withAnimation(.easeOut(duration: 0.2)) {
                    isAvailable = true
                }
            }
        }
    }
}

extension View {
    /// Keeps `isAvailable` up to date for a media file that may still be in iCloud.
    func tracksMediaAvailability(of fileName: String, isAvailable: Binding<Bool>) -> some View {
        modifier(MediaAvailabilityModifier(fileName: fileName, isAvailable: isAvailable))
    }
}

/// "Downloading from iCloud…" on a dark capsule.
struct CloudDownloadBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
            Text("Downloading from iCloud…")
                .laqtaFont(13, weight: .medium)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(Color.black.opacity(0.5), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
