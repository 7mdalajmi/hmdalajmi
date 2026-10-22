// cloudcheck stub: UserNotifications (an Objective-C framework) with the declaration headers the iOS 27.0
// SDK's Clang importer produces (audited against the interface swift-synthesize-interface prints).
// None of the classes is Sendable or actor-isolated; the completion handlers are @Sendable; the async
// variants generated from completion-handler methods are nonisolated(nonsending) (SE-0461), so they run on
// the caller's actor; results of imported methods are discardable.
// Implicit Clang-importer semantics, spelled out (checked against the real SDK with check.sh --compare and
// probes): every imported member is preconcurrency (Decl::preconcurrency()), so a closure argument that
// violates a @Sendable completion handler is a warning even in Swift 6 mode; members are therefore marked
// `@preconcurrency`, the types are not (on a Swift type that would also silence the "does not conform to
// Sendable" errors the real SDK reports for these classes). A completion-handler method that has an async
// variant and no availability attribute of its own gets `@available(*, renamed:)` pointing at it
// (ImportDecl.cpp addCompletionHandlerAttribute), so calling it from async code warns "consider using
// asynchronous alternative function" (not reproducible for add(_:withCompletionHandler:), see there).
@_exported import Foundation

public struct UNAuthorizationOptions : OptionSet, @unchecked Sendable {
    @preconcurrency public let rawValue: UInt
    @preconcurrency public init (rawValue: UInt) { self.rawValue = rawValue }
    @preconcurrency public static var badge: UNAuthorizationOptions { .init(rawValue: 1 << 0) }
    @preconcurrency public static var sound: UNAuthorizationOptions { .init(rawValue: 1 << 1) }
    @preconcurrency public static var alert: UNAuthorizationOptions { .init(rawValue: 1 << 2) }
    @preconcurrency public static var carPlay: UNAuthorizationOptions { .init(rawValue: 1 << 3) }
    @preconcurrency public static var criticalAlert: UNAuthorizationOptions { .init(rawValue: 1 << 4) }
    @preconcurrency public static var providesAppNotificationSettings: UNAuthorizationOptions { .init(rawValue: 1 << 5) }
    @preconcurrency public static var provisional: UNAuthorizationOptions { .init(rawValue: 1 << 6) }
}

public enum UNAuthorizationStatus : Int, @unchecked Sendable {
    case notDetermined = 0
    case denied = 1
    case authorized = 2
    case provisional = 3
    case ephemeral = 4
}

public enum UNNotificationSetting : Int, @unchecked Sendable {
    case notSupported = 0
    case disabled = 1
    case enabled = 2
}

public enum UNAlertStyle : Int, @unchecked Sendable {
    case none = 0
    case banner = 1
    case alert = 2
}

public enum UNNotificationInterruptionLevel : UInt, @unchecked Sendable {
    case passive = 0
    case active = 1
    case timeSensitive = 2
    case critical = 3
}

open class UNNotificationSettings : NSObject {
    @preconcurrency open var authorizationStatus: UNAuthorizationStatus { fatalError() }
    @preconcurrency open var soundSetting: UNNotificationSetting { fatalError() }
    @preconcurrency open var badgeSetting: UNNotificationSetting { fatalError() }
    @preconcurrency open var alertSetting: UNNotificationSetting { fatalError() }
    @preconcurrency open var notificationCenterSetting: UNNotificationSetting { fatalError() }
    @preconcurrency open var lockScreenSetting: UNNotificationSetting { fatalError() }
    @preconcurrency open var alertStyle: UNAlertStyle { fatalError() }
    @preconcurrency open var criticalAlertSetting: UNNotificationSetting { fatalError() }
    @preconcurrency open var timeSensitiveSetting: UNNotificationSetting { fatalError() }
    @preconcurrency open var providesAppNotificationSettings: Bool { fatalError() }
}

public struct UNNotificationSoundName : Hashable, Equatable, RawRepresentable, @unchecked Sendable {
    @preconcurrency public let rawValue: String
    @preconcurrency public init (_ rawValue: String) { self.rawValue = rawValue }
    @preconcurrency public init (rawValue: String) { self.rawValue = rawValue }
}

open class UNNotificationSound : NSObject {
    @preconcurrency open class var `default`: UNNotificationSound { fatalError() }
    @preconcurrency open class var defaultCritical: UNNotificationSound { fatalError() }
    @preconcurrency open class var defaultRingtone: UNNotificationSound { fatalError() }
    @preconcurrency public convenience init (named name: UNNotificationSoundName) { fatalError() }
    @preconcurrency @discardableResult open class func defaultCriticalSound(withAudioVolume volume: Float) -> Self { fatalError() }
}

open class UNNotificationContent : NSObject {
    @preconcurrency open var title: String { fatalError() }
    @preconcurrency open var subtitle: String { fatalError() }
    @preconcurrency open var body: String { fatalError() }
    @preconcurrency open var badge: NSNumber? { fatalError() }
    @preconcurrency open var sound: UNNotificationSound? { fatalError() }
    @preconcurrency open var threadIdentifier: String { fatalError() }
    @preconcurrency open var categoryIdentifier: String { fatalError() }
    @preconcurrency open var launchImageName: String { fatalError() }
    @preconcurrency open var userInfo: [AnyHashable : Any] { fatalError() }
    @preconcurrency open var targetContentIdentifier: String? { fatalError() }
    @preconcurrency open var interruptionLevel: UNNotificationInterruptionLevel { fatalError() }
    @preconcurrency open var relevanceScore: Double { fatalError() }
    @preconcurrency open var filterCriteria: String? { fatalError() }
}

open class UNMutableNotificationContent : UNNotificationContent {
    @preconcurrency override open var title: String { get { fatalError() } set {} }
    @preconcurrency override open var subtitle: String { get { fatalError() } set {} }
    @preconcurrency open override var body: String { get { fatalError() } set {} }
    @preconcurrency override open var badge: NSNumber? { get { fatalError() } set {} }
    @preconcurrency override open var sound: UNNotificationSound? { get { fatalError() } set {} }
    @preconcurrency override open var threadIdentifier: String { get { fatalError() } set {} }
    @preconcurrency override open var categoryIdentifier: String { get { fatalError() } set {} }
    @preconcurrency override open var launchImageName: String { get { fatalError() } set {} }
    @preconcurrency override open var userInfo: [AnyHashable : Any] { get { fatalError() } set {} }
    @preconcurrency override open var targetContentIdentifier: String? { get { fatalError() } set {} }
    @preconcurrency override open var interruptionLevel: UNNotificationInterruptionLevel { get { fatalError() } set {} }
    @preconcurrency override open var relevanceScore: Double { get { fatalError() } set {} }
    @preconcurrency override open var filterCriteria: String? { get { fatalError() } set {} }
}

open class UNNotificationTrigger : NSObject {
    @preconcurrency open var repeats: Bool { fatalError() }
}

open class UNCalendarNotificationTrigger : UNNotificationTrigger {
    @preconcurrency open var dateComponents: DateComponents { fatalError() }
    @preconcurrency public convenience init (dateMatching dateComponents: DateComponents, repeats: Bool) { fatalError() }
    @preconcurrency @discardableResult open func nextTriggerDate() -> Date? { fatalError() }
}

open class UNTimeIntervalNotificationTrigger : UNNotificationTrigger {
    @preconcurrency open var timeInterval: TimeInterval { fatalError() }
    @preconcurrency public convenience init (timeInterval: TimeInterval, repeats: Bool) { fatalError() }
    @preconcurrency @discardableResult open func nextTriggerDate() -> Date? { fatalError() }
}

open class UNNotificationRequest : NSObject {
    @preconcurrency open var identifier: String { fatalError() }
    @preconcurrency open var content: UNNotificationContent { fatalError() }
    @preconcurrency open var trigger: UNNotificationTrigger? { fatalError() }
    @preconcurrency public convenience init (identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) { fatalError() }
}

open class UNNotification : NSObject {
    @preconcurrency open var date: Date { fatalError() }
    @preconcurrency open var request: UNNotificationRequest { fatalError() }
}

open class UNUserNotificationCenter : NSObject {
    @available(*, unavailable)
    @preconcurrency public override init() { fatalError() }

    @preconcurrency @discardableResult open class func current() -> UNUserNotificationCenter { fatalError() }

    @preconcurrency open var supportsContentExtensions: Bool { fatalError() }

    @available(*, renamed: "requestAuthorization(options:)")
    @preconcurrency open func requestAuthorization(options: UNAuthorizationOptions = [],
                                   completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void) {}
    @preconcurrency @discardableResult open nonisolated(nonsending) func requestAuthorization(options: UNAuthorizationOptions = []) async throws -> Bool { fatalError() }

    @available(*, renamed: "notificationSettings()")
    @preconcurrency open func getNotificationSettings(completionHandler: @escaping @Sendable (UNNotificationSettings) -> Void) {}
    @preconcurrency @discardableResult open nonisolated(nonsending) func notificationSettings() async -> UNNotificationSettings { fatalError() }

    // HARNESS gap: the importer also links this method to add(_:), so calling it from async code warns
    // "consider using asynchronous alternative function" on Darwin. A Swift `@available(*, renamed:)` cannot
    // express that link for an optional completion handler (RenamedDeclRequest needs a non-optional one).
    @preconcurrency open func add(_ request: UNNotificationRequest,
                  withCompletionHandler completionHandler: (@Sendable ((any Error)?) -> Void)? = nil) {}
    @preconcurrency open nonisolated(nonsending) func add(_ request: UNNotificationRequest) async throws {}

    @available(*, renamed: "pendingNotificationRequests()")
    @preconcurrency open func getPendingNotificationRequests(completionHandler: @escaping @Sendable ([UNNotificationRequest]) -> Void) {}
    @preconcurrency @discardableResult open nonisolated(nonsending) func pendingNotificationRequests() async -> [UNNotificationRequest] { fatalError() }
    @preconcurrency open func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    @preconcurrency open func removeAllPendingNotificationRequests() {}

    @available(*, renamed: "deliveredNotifications()")
    @preconcurrency open func getDeliveredNotifications(completionHandler: @escaping @Sendable ([UNNotification]) -> Void) {}
    @preconcurrency @discardableResult open nonisolated(nonsending) func deliveredNotifications() async -> [UNNotification] { fatalError() }
    @preconcurrency open func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    @preconcurrency open func removeAllDeliveredNotifications() {}

    @preconcurrency open func setBadgeCount(_ newBadgeCount: Int,
                            withCompletionHandler completionHandler: (@Sendable ((any Error)?) -> Void)? = nil) {}
    @preconcurrency open nonisolated(nonsending) func setBadgeCount(_ newBadgeCount: Int) async throws {}
}
