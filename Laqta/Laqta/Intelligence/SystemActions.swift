//
//  SystemActions.swift
//  Laqta
//
//  Directions, calendar events, reminders, clipboard and location permission.
//

import CoreLocation
import EventKit
import EventKitUI
import Foundation
import MapKit
import Observation
import SwiftUI
import UIKit
import UserNotifications

// MARK: - Clipboard

enum Clipboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}

// MARK: - Directions

struct RouteSummary {
    let travelTime: Double
    let distance: Double
    let name: String
    let polyline: MKPolyline
}

enum Directions {
    static func mapItem(for place: PlaceRef) -> MKMapItem? {
        guard let latitude = place.latitude, let longitude = place.longitude else { return nil }
        let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        item.name = place.name
        return item
    }

    static func openDirections(to place: PlaceRef) {
        if let item = mapItem(for: place) {
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        } else {
            showInMaps(place)
        }
    }

    static func showInMaps(_ place: PlaceRef) {
        if let item = mapItem(for: place) {
            item.openInMaps(launchOptions: nil)
            return
        }
        let query = [place.name, place.detail].compactMap { $0 }.joined(separator: ", ")
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        if let url = components?.url {
            UIApplication.shared.open(url)
        }
    }

    static func searchInMaps(_ address: String) {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: address)]
        if let url = components?.url {
            UIApplication.shared.open(url)
        }
    }

    /// Driving route from the current location (needs location permission).
    static func route(to place: PlaceRef) async -> RouteSummary? {
        guard LocationAccess.shared.isAuthorized, let destination = mapItem(for: place) else { return nil }
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = destination
        request.transportType = .automobile
        guard let response = try? await MKDirections(request: request).calculate(),
              let route = response.routes.first else { return nil }
        return RouteSummary(
            travelTime: route.expectedTravelTime,
            distance: route.distance,
            name: route.name,
            polyline: route.polyline
        )
    }

    /// Only the travel time, for small buttons.
    static func travelTime(to place: PlaceRef) async -> Double? {
        guard LocationAccess.shared.isAuthorized, let destination = mapItem(for: place) else { return nil }
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = destination
        request.transportType = .automobile
        return try? await MKDirections(request: request).calculateETA().expectedTravelTime
    }
}

@Observable
final class LocationAccess: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAccess()

    private(set) var status: CLAuthorizationStatus = .notDetermined
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    var canAsk: Bool {
        status == .notDetermined
    }

    func requestIfNeeded() {
        guard status == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor in
            self.status = newStatus
        }
    }
}

// MARK: - Calendar

struct EventDraft: Identifiable {
    let id = UUID()
    let title: String
    let start: Date
    var allDay: Bool = false
    var notes: String?
    var actionKey: String = ""
}

/// Apple's event editor. Adding events this way needs no calendar permission.
struct EventEditView: UIViewControllerRepresentable {
    let draft: EventDraft
    var onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.allDay ? draft.start : draft.start.addingTimeInterval(3600)
        event.isAllDay = draft.allDay
        if let notes = draft.notes {
            event.notes = String(notes.prefix(1_000))
        }
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onComplete: (Bool) -> Void

        init(onComplete: @escaping (Bool) -> Void) {
            self.onComplete = onComplete
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onComplete(action == .saved)
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - Reminders

enum Reminders {
    /// A local notification the morning of the date (or an hour before a timed one).
    static func schedule(title: String, at date: Date, allDay: Bool = true) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }

        var fireDate = allDay
            ? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
            : date.addingTimeInterval(-3600)
        if fireDate < .now {
            fireDate = Date.now.addingTimeInterval(3600)
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "From your shots in Laqta"
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}
