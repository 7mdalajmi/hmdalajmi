//
//  ReminderRouter.swift
//  Laqta
//
//  The other half of a reminder.
//
//  `ReminderCenter.schedule` has always written the shot's id into the notification's
//  `userInfo`, and until now nothing ever read it: tapping a reminder only launched
//  the app, and a reminder that fired while Laqta was already open was not shown at
//  all, because a notification is suppressed in the foreground unless a delegate says
//  otherwise. This is the delegate.
//

import Foundation
import UserNotifications

@MainActor
final class ReminderRouter: NSObject, UNUserNotificationCenterDelegate {
    private unowned let reminders: ReminderCenter

    init(reminders: ReminderCenter) {
        self.reminders = reminders
        super.init()
    }

    /// A reminder that arrives while Laqta is open is still a reminder.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// The tap. Everything else this notification carries is decoration; the id is
    /// the point.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let raw = response.notification.request.content.userInfo["itemID"] as? String,
              let itemID = UUID(uuidString: raw) else { return }
        reminders.noteTapped(itemID)
    }
}
