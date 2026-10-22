//
//  SaveFailureBar.swift
//  Laqta — Shared (App + Share Extension)
//
//  The bar that says a change didn't reach the library, and offers to do it again.
//
//  It sits at the bottom (toasts own the top) and stays until it is answered: a save
//  that failed is the one message that must not disappear on its own, because the
//  change it names is no longer on screen either.
//

import SwiftUI

extension EnvironmentValues {
    /// Set by the app: the way out when saving keeps failing (Restore from a backup).
    /// The Share Extension has none, so the sheet simply leaves the row out.
    @Entry var saveFailureRecovery: SaveFailureRecovery? = nil
}

/// Not Sendable: it carries a main-actor closure, like LibraryNavigator does.
nonisolated struct SaveFailureRecovery {
    var title: LocalizedStringKey
    var systemImage: String
    var action: @MainActor () -> Void

    init(title: LocalizedStringKey, systemImage: String = "clock.arrow.circlepath", action: @escaping @MainActor () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
}

private struct SaveFailureHostModifier: ViewModifier {
    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDetails = false

    private var center: SaveFailureCenter { .shared }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let failure = center.failure {
                    bar(failure)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .bottom).combined(with: .opacity))
                        .id(failure.id)
                }
            }
            .sheet(isPresented: $showingDetails) {
                SaveFailureDetails()
                    .laqtaThemed()
            }
    }

    private func bar(_ failure: SaveFailureCenter.Failure) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.icloud")
                .laqtaIconFont(14, weight: .semibold)
                .foregroundStyle(palette.goldHi)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Laqta couldn't save")
                    .laqtaFont(14, weight: .semibold)
                    .foregroundStyle(palette.ink)
                Text(verbatim: failure.message)
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
                    .adaptiveLineLimit(2, accessibility: nil)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            if failure.canRetry {
                Button {
                    center.retry()
                } label: {
                    Text("Try Again")
                        .laqtaFont(14, weight: .semibold)
                        .foregroundStyle(palette.goldInk)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background(palette.accentFill, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(center.isRetrying)
            }
            Button {
                showingDetails = true
            } label: {
                Image(systemName: "info.circle")
                    .laqtaIconFont(15, weight: .medium)
                    .foregroundStyle(palette.ink2)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text("What happened"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .laqtaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Shows the "couldn't save" bar above this screen.
    func saveFailureHost() -> some View {
        modifier(SaveFailureHostModifier())
    }
}

/// The whole story: what failed, what the store said, and the ways out.
struct SaveFailureDetails: View {
    @Environment(\.laqta) private var palette
    @Environment(\.saveFailureRecovery) private var recovery
    @Environment(\.dismiss) private var dismiss

    private var center: SaveFailureCenter { .shared }

    var body: some View {
        ZStack {
            palette.sheet.ignoresSafeArea()
            VStack(spacing: 0) {
                SheetBar("Laqta couldn't save") {
                    Button { dismiss() } label: {
                        BarTextButtonLabel(title: "Close")
                    }
                    .buttonStyle(.pressable)
                } trailing: {
                    Color.clear.frame(width: 1, height: 1)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let failure = center.failure {
                            Text(verbatim: failure.message)
                                .laqtaFont(17, weight: .semibold)
                                .foregroundStyle(palette.ink)
                            Text("Your library is unchanged. The change was put back, so what you see on screen is what Laqta has stored — nothing was saved halfway.")
                                .laqtaFont(14)
                                .foregroundStyle(palette.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                            if failure.attempts > 1 {
                                Text("It has failed \(failure.attempts) times in a row.")
                                    .laqtaFont(13)
                                    .foregroundStyle(palette.ink3)
                            }
                            Text("What the library said")
                                .laqtaFont(13, weight: .semibold)
                                .foregroundStyle(palette.ink2)
                                .padding(.top, 4)
                            Text(verbatim: failure.reason)
                                .laqtaFont(13, design: .monospaced)
                                .foregroundStyle(palette.ink3)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("A library that keeps refusing is usually a full device or an iCloud account that is out of room. Free some space, then try again.")
                                .laqtaFont(13)
                                .foregroundStyle(palette.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                            VStack(spacing: 10) {
                                if failure.canRetry {
                                    Button {
                                        center.retry()
                                        dismiss()
                                    } label: {
                                        LaqtaButtonLabel("Try Again", systemImage: "arrow.clockwise", fullWidth: true)
                                    }
                                    .buttonStyle(.pressable)
                                }
                                if let recovery {
                                    Button {
                                        recovery.action()
                                        dismiss()
                                    } label: {
                                        LaqtaButtonLabel(recovery.title, systemImage: recovery.systemImage, kind: .line, fullWidth: true)
                                    }
                                    .buttonStyle(.pressable)
                                }
                                Button {
                                    center.dismiss()
                                    dismiss()
                                } label: {
                                    LaqtaButtonLabel("Dismiss", kind: .soft, fullWidth: true)
                                }
                                .buttonStyle(.pressable)
                            }
                            .padding(.top, 6)
                        } else {
                            Text("Everything is saved.")
                                .laqtaFont(15)
                                .foregroundStyle(palette.ink2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}
