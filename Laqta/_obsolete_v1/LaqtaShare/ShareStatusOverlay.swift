//
//  ShareStatusOverlay.swift
//  لقطة — Share Extension
//

import Foundation
import SwiftUI

struct ShareStatusOverlay: View {
    let session: ShareSessionModel

    var body: some View {
        Group {
            switch session.phase {
            case .preparing, .ready:
                EmptyView()
            case .saving:
                card {
                    ProgressView()
                        .controlSize(.large)
                    Text("جارٍ الحفظ…")
                        .font(.headline)
                }
            case .removingOriginals:
                card {
                    ProgressView()
                        .controlSize(.large)
                    Text("حُفظت داخل لقطة")
                        .font(.headline)
                    Text("أكّد حذف الأصل من ألبوم الصور")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case let .done(folderName, count, removal):
                card {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(count == 1 ? "حُفظت في «\(folderName)»" : "حُفظت \(count) صور في «\(folderName)»")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if let note = removalNote(removal) {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            case let .failed(message):
                card {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Button("إغلاق") { session.cancel() }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: session.phase)
    }

    private func removalNote(_ removal: ShareSessionModel.RemovalOutcome) -> String? {
        switch removal {
        case .notRequested:
            nil
        case .removed:
            "وحُذف الأصل من ألبوم الصور"
        case .waitingForApp:
            "سيُحذف الأصل من ألبوم الصور عند فتح التطبيق"
        case .declined:
            "بقي الأصل في ألبوم الصور"
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.18))
                .ignoresSafeArea()
            VStack(spacing: 12) {
                content()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 300)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

struct ShareUnavailableView: View {
    let message: String
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("تعذّر فتح لقطة", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text("افتح تطبيق «لقطة» مرة واحدة ثم حاول مجددًا.\n\(message)")
            } actions: {
                Button("إغلاق", action: onClose)
                    .buttonStyle(.glassProminent)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
