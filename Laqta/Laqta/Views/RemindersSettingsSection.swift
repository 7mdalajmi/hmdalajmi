//
//  RemindersSettingsSection.swift
//  Laqta
//
//  One choice: how early you want telling about something with a date on it.
//  Set here for everything; any single shot can disagree from its own row.
//
//  This is a `View` of its own rather than a computed property on SettingsScreen
//  on purpose — see the note at the top of SettingsSections.swift.
//

import Foundation
import SwiftUI

struct RemindersSettingsSection: View {
    @AppObject(ReminderCenter.self, otherwise: { ReminderCenter() }) private var reminders
    @AppStorage(SettingsKey.showComingUp, store: AppGroup.defaults) private var showsComingUp = true
    @AppStorage(SettingsKey.offerClipboard, store: AppGroup.defaults) private var offersClipboard = true
    @Environment(\.laqta) private var palette

    static let footer = String(
        localized: "A reminder is one line on the lock screen with the shot attached. It is scheduled on this phone — nothing is registered anywhere."
    )

    var body: some View {
        VStack(spacing: 0) {
            SwitchRow(
                title: "Show what is coming up",
                subtitle: "Dated shots sit above your folders",
                systemImage: "calendar",
                isOn: $showsComingUp
            )
            RowSeparator()
            leadPicker
            RowSeparator()
            SwitchRow(
                title: "Offer to keep what you copied",
                subtitle: "Asked once when Laqta opens, never in the background",
                systemImage: "link",
                isOn: $offersClipboard
            )
        }
    }

    private var leadPicker: some View {
        HStack(spacing: 12) {
            RowIcon(systemImage: "bell")
            RowText(title: Text("Remind me"), subtitle: Text("Unless a shot says otherwise"))
            Spacer(minLength: 8)
            Menu {
                Picker("Remind me", selection: leadBinding) {
                    ForEach(ReminderLead.allCases) { lead in
                        Text(lead.title).tag(lead)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 5) {
                    Text(reminders.defaultLead.short)
                        .laqtaFont(15)
                        .foregroundStyle(palette.goldHi)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .laqtaIconFont(11, weight: .semibold)
                        .foregroundStyle(palette.ink3)
                }
                .fixedSize()
            }
            .accessibilityLabel(Text("Remind me"))
            .accessibilityValue(reminders.defaultLead.short)
        }
        .frame(minHeight: 58)
    }

    private var leadBinding: Binding<ReminderLead> {
        Binding(
            get: { reminders.defaultLead },
            set: { reminders.defaultLead = $0 }
        )
    }
}
