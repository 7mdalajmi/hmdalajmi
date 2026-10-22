//
//  ComingUpStrip.swift
//  Laqta
//
//  What is about to happen, above everything else. Each row is a shot that
//  carried a date — a boarding pass, a renewal, a warranty — with the date it
//  read out of the picture turned into a countdown.
//
//  Tapping a row opens the shot. The bell opens the one choice worth making:
//  how early you want telling.
//

import Foundation
import SwiftData
import SwiftUI

struct ComingUpStrip: View {
    let dated: [DatedShot]
    let onOpen: (DatedShot) -> Void
    let onRemind: (DatedShot) -> Void

    @AppObject(ReminderCenter.self, otherwise: { ReminderCenter() }) private var reminders
    @Environment(\.laqta) private var palette

    var body: some View {
        if !dated.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Coming up")
                VStack(spacing: 10) {
                    ForEach(dated) { entry in
                        ComingUpRow(
                            dated: entry,
                            isScheduled: reminders.isScheduled(entry.itemID),
                            onOpen: { onOpen(entry) },
                            onRemind: { onRemind(entry) }
                        )
                    }
                }
            }
            .padding(.top, 22)
        }
    }
}

// MARK: - One row

private struct ComingUpRow: View {
    let dated: DatedShot
    let isScheduled: Bool
    let onOpen: () -> Void
    let onRemind: () -> Void

    @Environment(\.laqta) private var palette

    private var countdown: String { LaqtaFormat.dueIn(dated.date) }

    var body: some View {
        HStack(spacing: 13) {
            Button(action: onOpen) {
                HStack(spacing: 13) {
                    ShotThumbnail(
                        thumbnailURL: AppGroup.thumbnailsURL.appending(path: dated.thumbnailName),
                        originalURL: nil,
                        cornerRadius: 12
                    )
                        .frame(width: 52, height: 66)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(palette.cardBorder, lineWidth: 1)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: dated.title)
                            .laqtaFont(15, weight: .semibold)
                            .foregroundStyle(palette.ink)
                            .adaptiveLineLimit(1, accessibility: 2)
                        Text(verbatim: dated.detail ?? LaqtaFormat.eventDate(dated.date, allDay: dated.allDay))
                            .laqtaFont(12)
                            .foregroundStyle(palette.ink3)
                            .adaptiveLineLimit(1, accessibility: 2)
                    }
                    Spacer(minLength: 6)
                    Text(verbatim: countdown)
                        .laqtaFont(12, weight: .semibold)
                        .foregroundStyle(dated.isImminent() ? palette.goldInk : palette.goldHi)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if dated.isImminent() {
                                Capsule().fill(palette.accentFill)
                            } else {
                                Capsule().fill(palette.badgeFill)
                                    .overlay(Capsule().strokeBorder(palette.badgeBorder, lineWidth: 1))
                            }
                        }
                        .layoutPriority(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text(verbatim: "\(dated.title), \(countdown)"))

            Button(action: onRemind) {
                Image(systemName: isScheduled ? "bell.fill" : "bell")
                    .laqtaIconFont(16)
                    .foregroundStyle(isScheduled ? palette.goldHi : palette.ink3)
                    .frame(width: 34, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text(isScheduled ? "Change the reminder" : "Remind me"))
        }
    }
}

// MARK: - How early

struct ReminderPickerSheet: View {
    let dated: DatedShot
    let thumbnailURL: URL?

    @AppObject(ReminderCenter.self, otherwise: { ReminderCenter() }) private var reminders
    @AppObject(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.laqta) private var palette

    @State private var choice: ReminderLead = .dayBefore
    @State private var isWorking = false
    @State private var didLoad = false

    /// Leads whose moment has not already gone by for this particular date.
    private var available: [ReminderLead] {
        ReminderLead.allCases.filter { $0.fireDate(for: dated.date) != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetBar("Remind Me") {
                Button {
                    dismiss()
                } label: {
                    BarTextButtonLabel(title: "Cancel")
                }
            } trailing: {
                Button {
                    save()
                } label: {
                    BarTextButtonLabel(title: "Set", prominent: true)
                }
                .disabled(isWorking || available.isEmpty)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if available.isEmpty {
                        Text("Every reminder for this one has already gone by.")
                            .laqtaFont(13)
                            .foregroundStyle(palette.ink3)
                    } else {
                        LaqtaGroup {
                            ForEach(Array(available.enumerated()), id: \.element.id) { index, lead in
                                if index > 0 { RowSeparator() }
                                leadRow(lead)
                            }
                        }
                    }
                    footer
                    if reminders.isScheduled(dated.itemID) {
                        Button {
                            reminders.cancel(itemID: dated.itemID)
                            toasts.show("Reminder removed", systemImage: "bell.slash")
                            dismiss()
                        } label: {
                            Text("Remove the Reminder")
                                .laqtaFont(15, weight: .semibold)
                                .foregroundStyle(palette.ink2)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .overlay(Capsule().strokeBorder(palette.hair, lineWidth: 1))
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 26)
            }
        }
        .background(palette.sheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.sheet)
        .presentationCornerRadius(32)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            let stored = reminders.lead(for: dated.itemID)
            choice = available.contains(stored) ? stored : (available.first ?? stored)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: "\(dated.title) · \(LaqtaFormat.eventDate(dated.date, allDay: dated.allDay))")
                .textCase(.uppercase)
                .laqtaFont(11, weight: .semibold)
                .tracking(0.9)
                .foregroundStyle(palette.gold)
                .adaptiveLineLimit(2, accessibility: 4)
            Text("How early do you want telling?")
                .laqtaDisplayFont(26, bold: true)
                .foregroundStyle(palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func leadRow(_ lead: ReminderLead) -> some View {
        Button {
            choice = lead
        } label: {
            HStack(spacing: 12) {
                Image(systemName: choice == lead ? "largecircle.fill.circle" : "circle")
                    .laqtaIconFont(19)
                    .foregroundStyle(choice == lead ? palette.goldHi : palette.ink3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lead.title)
                        .laqtaFont(15, weight: choice == lead ? .semibold : .regular)
                        .foregroundStyle(choice == lead ? palette.goldHi : palette.ink)
                    if let fire = lead.fireDate(for: dated.date) {
                        Text(verbatim: LaqtaFormat.eventDate(fire))
                            .laqtaFont(12)
                            .foregroundStyle(palette.ink3)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(choice == lead ? [.isSelected, .isButton] : .isButton)
    }

    private var footer: some View {
        Text("Set once for this one, or pick what everything should use in Settings → Reminders.")
            .laqtaFont(12)
            .foregroundStyle(palette.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        guard !isWorking else { return }
        isWorking = true
        let lead = choice
        Task {
            reminders.setLead(lead, for: dated.itemID)
            let done = await reminders.schedule(dated, lead: lead, thumbnailURL: thumbnailURL)
            isWorking = false
            if done {
                toasts.show("Reminder set", systemImage: "bell.fill")
            } else {
                toasts.show("Notifications are off for Laqta", systemImage: "bell.slash")
            }
            dismiss()
        }
    }
}
