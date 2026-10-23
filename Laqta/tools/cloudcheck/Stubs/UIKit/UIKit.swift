// cloudcheck stub: the parts of UIKit the apps reach (directly or through SwiftUI), with the headers of the
// declarations as the iOS 27.0 SDK's Clang importer produces them (audited against the interface that
// swift-synthesize-interface prints for UIKit, plus UIKit's Swift overlay): UIKit classes are @MainActor
// (NS_SWIFT_UI_ACTOR); UIColor, UIFont and UIImage are nonisolated and @unchecked Sendable; results of
// imported methods are discardable; imported async methods of nonisolated types are nonisolated(nonsending).
//
// HARNESS limits (no Objective-C runtime on Linux):
//  - `@objc optional` protocol requirements are modelled as requirements with default implementations.
//  - Overriding these methods from an *extension* is legal on Darwin (they are @objc) but rejected on Linux;
//    preprocess.py renames such overrides and check.sh lists any remaining diagnostic as harness-only.
//  - Per-target availability (`@available(iOSApplicationExtension, unavailable)`, used by the widget) is
//    not enforced; `check.sh --sdk` enforces it.
//
// Implicit Clang-importer semantics, spelled out (checked against the real SDK with check.sh --compare and
// probes): every imported declaration is preconcurrency (Decl::preconcurrency()), so calls whose closure
// arguments violate @Sendable/@MainActor, and uses of main-actor members from nonisolated code, are
// warnings even in Swift 6 mode. Members are therefore marked `@preconcurrency`, and the main-actor
// classes and protocols say `@MainActor(unsafe)` (isolation flagged preconcurrency, inherited by members,
// subclasses and the app's extensions). The types themselves are NOT marked `@preconcurrency`: on a Swift
// type that would also silence "does not conform to Sendable" errors, which the real SDK reports for its
// Objective-C classes. The declarations from UIKit's Swift overlay (`openNotificationSettingsURLString`,
// the AttributedString scope) are ordinary Swift declarations.
@_exported import Foundation
@_exported import CoreGraphics
@_exported import ObjectiveC

// MARK: - Responders and events

@MainActor(unsafe) open class UIResponder : NSObject {
    @preconcurrency open var next: UIResponder? { nil }
    @preconcurrency open var canBecomeFirstResponder: Bool { false }
    @preconcurrency @discardableResult open func becomeFirstResponder() -> Bool { false }
    @preconcurrency open var canResignFirstResponder: Bool { true }
    @preconcurrency @discardableResult open func resignFirstResponder() -> Bool { true }
    @preconcurrency open var isFirstResponder: Bool { false }

    @preconcurrency nonisolated public static let keyboardWillShowNotification: NSNotification.Name = Notification.Name("UIKeyboardWillShowNotification")
    @preconcurrency nonisolated public static let keyboardDidShowNotification: NSNotification.Name = Notification.Name("UIKeyboardDidShowNotification")
    @preconcurrency nonisolated public static let keyboardWillHideNotification: NSNotification.Name = Notification.Name("UIKeyboardWillHideNotification")
    @preconcurrency nonisolated public static let keyboardDidHideNotification: NSNotification.Name = Notification.Name("UIKeyboardDidHideNotification")
    @preconcurrency nonisolated public static let keyboardWillChangeFrameNotification: NSNotification.Name = Notification.Name("UIKeyboardWillChangeFrameNotification")
    @preconcurrency nonisolated public static let keyboardDidChangeFrameNotification: NSNotification.Name = Notification.Name("UIKeyboardDidChangeFrameNotification")
    @preconcurrency nonisolated public static let keyboardFrameBeginUserInfoKey: String = "UIKeyboardFrameBeginUserInfoKey"
    @preconcurrency nonisolated public static let keyboardFrameEndUserInfoKey: String = "UIKeyboardFrameEndUserInfoKey"
    @preconcurrency nonisolated public static let keyboardAnimationDurationUserInfoKey: String = "UIKeyboardAnimationDurationUserInfoKey"
    @preconcurrency nonisolated public static let keyboardAnimationCurveUserInfoKey: String = "UIKeyboardAnimationCurveUserInfoKey"
}

@MainActor(unsafe) open class UIEvent : NSObject {}

@MainActor(unsafe) open class UITouch : NSObject {}

open class UIPress : NSObject {}

// MARK: - Application

@MainActor(unsafe) open class UIApplication : UIResponder {
    @preconcurrency open class var shared: UIApplication { fatalError() }

    /// `UIKIT_EXTERN NSString *const UIApplicationOpenSettingsURLString NS_SWIFT_NAME(UIApplication.openSettingsURLString)`
    @preconcurrency nonisolated public static let openSettingsURLString: String = "app-settings:"
    /// iOS 16+
    nonisolated public static let openNotificationSettingsURLString: String = "app-settings:notifications"

    public enum State : Int, @unchecked Sendable {
        case active = 0
        case inactive = 1
        case background = 2
    }

    public struct OpenExternalURLOptionsKey : Hashable, Equatable, RawRepresentable, @unchecked Sendable {
        @preconcurrency public let rawValue: String
        @preconcurrency public init (rawValue: String) { self.rawValue = rawValue }
        @preconcurrency public static let universalLinksOnly: UIApplication.OpenExternalURLOptionsKey = OpenExternalURLOptionsKey(rawValue: "UIApplicationOpenURLOptionUniversalLinksOnly")
    }

    @preconcurrency open var applicationState: UIApplication.State { fatalError() }
    @preconcurrency open var isIdleTimerDisabled: Bool { get { fatalError() } set {} }

    @discardableResult
    @preconcurrency open func sendAction(_ action: Selector, to target: Any?, from sender: Any?, for event: UIEvent?) -> Bool { false }

    @preconcurrency @discardableResult nonisolated open func canOpenURL(_ url: URL) -> Bool { false }

    @preconcurrency open func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey : Any] = [:], completionHandler completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {}
    @preconcurrency @discardableResult open func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey : Any] = [:]) async -> Bool { false }
}

// MARK: - Views and controllers

@MainActor(unsafe) open class UIView : UIResponder {
    @preconcurrency public init (frame: CGRect) { super.init() }
    @preconcurrency public required init?(coder: NSCoder) { super.init() }
    @preconcurrency override public convenience init () { self.init(frame: .zero) }

    @preconcurrency open var frame: CGRect { get { fatalError() } set {} }
    @preconcurrency open var bounds: CGRect { get { fatalError() } set {} }
    @preconcurrency open var center: CGPoint { get { fatalError() } set {} }
    @preconcurrency open var backgroundColor: UIColor? { get { fatalError() } set {} }
    @preconcurrency open var tintColor: UIColor! { get { fatalError() } set {} }
    @preconcurrency open var isHidden: Bool { get { fatalError() } set {} }
    @preconcurrency open var alpha: CGFloat { get { fatalError() } set {} }
    @preconcurrency open var isUserInteractionEnabled: Bool { get { fatalError() } set {} }
    @preconcurrency open var superview: UIView? { fatalError() }
    @preconcurrency open var subviews: [UIView] { fatalError() }
    @preconcurrency open var gestureRecognizers: [UIGestureRecognizer]? { get { fatalError() } set {} }

    @preconcurrency open func addSubview(_ view: UIView) {}
    @preconcurrency open func removeFromSuperview() {}
    @preconcurrency open func layoutSubviews() {}
    @preconcurrency open func setNeedsLayout() {}
    @preconcurrency open func layoutIfNeeded() {}
    @preconcurrency open func addGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {}
    @preconcurrency open func removeGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {}
    @preconcurrency @discardableResult open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { true }
}

@MainActor(unsafe) open class UIViewController : UIResponder {
    @preconcurrency public init (nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) { super.init() }
    @preconcurrency public required init?(coder: NSCoder) { super.init() }
    @preconcurrency public convenience override init() { self.init(nibName: nil, bundle: nil) }

    @preconcurrency open var view: UIView! { get { fatalError() } set {} }
    @preconcurrency open var title: String? { get { fatalError() } set {} }
    @preconcurrency open var navigationController: UINavigationController? { fatalError() }
    @preconcurrency open var presentedViewController: UIViewController? { fatalError() }
    @preconcurrency open var presentingViewController: UIViewController? { fatalError() }

    @preconcurrency open func loadView() {}
    @preconcurrency open func viewDidLoad() {}
    @preconcurrency open func viewWillAppear(_ animated: Bool) {}
    @preconcurrency open func viewDidAppear(_ animated: Bool) {}
    @preconcurrency open func viewWillDisappear(_ animated: Bool) {}
    @preconcurrency open func viewDidDisappear(_ animated: Bool) {}
    @preconcurrency open func viewWillLayoutSubviews() {}
    @preconcurrency open func viewDidLayoutSubviews() {}

    @preconcurrency open func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {}
    @preconcurrency open func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {}
}

@MainActor(unsafe) open class UINavigationController : UIViewController {
    @preconcurrency public init (rootViewController: UIViewController) { super.init(nibName: nil, bundle: nil) }
    @preconcurrency override public init (nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) { super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil) }
    @preconcurrency public required init?(coder aDecoder: NSCoder) { fatalError() }

    @preconcurrency open var viewControllers: [UIViewController] { get { fatalError() } set {} }
    @preconcurrency open var topViewController: UIViewController? { fatalError() }
    @preconcurrency open var visibleViewController: UIViewController? { fatalError() }
    @preconcurrency open var interactivePopGestureRecognizer: UIGestureRecognizer? { fatalError() }
    @preconcurrency open var isNavigationBarHidden: Bool { get { fatalError() } set {} }

    @preconcurrency open func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {}
    @preconcurrency open func pushViewController(_ viewController: UIViewController, animated: Bool) {}
    @preconcurrency @discardableResult open func popViewController(animated: Bool) -> UIViewController? { nil }
    @preconcurrency @discardableResult open func popToRootViewController(animated: Bool) -> [UIViewController]? { nil }
}

// MARK: - Gestures

@MainActor(unsafe) open class UIGestureRecognizer : NSObject {
    @preconcurrency public init (target: Any?, action: Selector?) { super.init() }
    @preconcurrency override public convenience init () { self.init(target: nil, action: nil) }

    public enum State : Int, @unchecked Sendable {
        case possible = 0
        case began = 1
        case changed = 2
        case ended = 3
        case cancelled = 4
        case failed = 5
        @preconcurrency public static var recognized: UIGestureRecognizer.State { .ended }
    }

    @preconcurrency weak open var delegate: (any UIGestureRecognizerDelegate)?
    @preconcurrency open var isEnabled: Bool { get { fatalError() } set {} }
    @preconcurrency open var view: UIView? { fatalError() }
    @preconcurrency open var state: UIGestureRecognizer.State { get { fatalError() } set {} }
    @preconcurrency open var cancelsTouchesInView: Bool { get { fatalError() } set {} }

    @preconcurrency open func addTarget(_ target: Any, action: Selector) {}
    @preconcurrency @discardableResult open func location(in view: UIView?) -> CGPoint { fatalError() }
}

/// SDK: `NS_SWIFT_UI_ACTOR @protocol UIGestureRecognizerDelegate <NSObject>`, every method `@optional`.
/// HARNESS: optional requirements = requirements with default implementations below.
@MainActor(unsafe) public protocol UIGestureRecognizerDelegate : NSObjectProtocol {
    @preconcurrency @discardableResult func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
    @preconcurrency @discardableResult func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
    @preconcurrency @discardableResult func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool
    @preconcurrency @discardableResult func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool
    @preconcurrency @discardableResult func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool
    @preconcurrency @discardableResult func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool
    @preconcurrency @discardableResult func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool
}

extension UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { true }
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { true }
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool { true }
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool { true }
}

// MARK: - Device and haptics

public enum UIUserInterfaceIdiom : Int, @unchecked Sendable {
    case unspecified = -1
    case phone = 0
    case pad = 1
    case tv = 2
    case carPlay = 3
    case mac = 5
    case vision = 6
}

/// iOS 27 SDK: main actor only (see claude/lessons.md).
@MainActor(unsafe) open class UIDevice : NSObject {
    @preconcurrency open class var current: UIDevice { fatalError() }
    @preconcurrency open var name: String { fatalError() }
    @preconcurrency open var model: String { fatalError() }
    @preconcurrency open var systemName: String { fatalError() }
    @preconcurrency open var systemVersion: String { fatalError() }
    @preconcurrency open var userInterfaceIdiom: UIUserInterfaceIdiom { fatalError() }
    @preconcurrency open var identifierForVendor: UUID? { fatalError() }
}

@MainActor(unsafe) open class UIFeedbackGenerator : NSObject {
    @preconcurrency open func prepare() {}
}

@MainActor(unsafe) open class UIImpactFeedbackGenerator : UIFeedbackGenerator {
    public enum FeedbackStyle : Int, @unchecked Sendable {
        case light = 0
        case medium = 1
        case heavy = 2
        case soft = 3
        case rigid = 4
    }
    @preconcurrency public init (style: UIImpactFeedbackGenerator.FeedbackStyle) { super.init() }
    @preconcurrency public convenience override init() { self.init(style: .medium) }
    @preconcurrency open func impactOccurred() {}
    @preconcurrency open func impactOccurred(intensity: CGFloat) {}
}

@MainActor(unsafe) open class UINotificationFeedbackGenerator : UIFeedbackGenerator {
    public enum FeedbackType : Int, @unchecked Sendable {
        case success = 0
        case warning = 1
        case error = 2
    }
    @preconcurrency open func notificationOccurred(_ notificationType: UINotificationFeedbackGenerator.FeedbackType) {}
}

@MainActor(unsafe) open class UISelectionFeedbackGenerator : UIFeedbackGenerator {
    @preconcurrency open func selectionChanged() {}
}

// MARK: - Keyboard

public enum UIKeyboardType : Int, @unchecked Sendable {
    case `default` = 0
    case asciiCapable = 1
    case numbersAndPunctuation = 2
    case URL = 3
    case numberPad = 4
    case phonePad = 5
    case namePhonePad = 6
    case emailAddress = 7
    case decimalPad = 8
    case twitter = 9
    case webSearch = 10
    case asciiCapableNumberPad = 11
    @preconcurrency public static var alphabet: UIKeyboardType { .asciiCapable }
}

// MARK: - Colours, fonts, images (thread-safe, Sendable, not main-actor)

open class UIColor : NSObject, @unchecked Sendable {
    @preconcurrency public init (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { super.init() }
    @preconcurrency public init (white: CGFloat, alpha: CGFloat) { super.init() }
    @preconcurrency public init (hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) { super.init() }
    @preconcurrency public init?(named name: String) { super.init() }
    @preconcurrency open class var clear: UIColor { fatalError() }
    @preconcurrency open class var black: UIColor { fatalError() }
    @preconcurrency open class var white: UIColor { fatalError() }
    @preconcurrency open class var red: UIColor { fatalError() }
    @preconcurrency open class var label: UIColor { fatalError() }
    @preconcurrency open class var secondaryLabel: UIColor { fatalError() }
    @preconcurrency open class var systemBackground: UIColor { fatalError() }
    @preconcurrency @discardableResult open func withAlphaComponent(_ alpha: CGFloat) -> UIColor { fatalError() }
}

open class UIFont : NSObject, @unchecked Sendable {
    public struct TextStyle : Hashable, Equatable, RawRepresentable, @unchecked Sendable {
        @preconcurrency public let rawValue: String
        @preconcurrency public init (rawValue: String) { self.rawValue = rawValue }
        @preconcurrency public static let largeTitle: UIFont.TextStyle = TextStyle(rawValue: "UICTFontTextStyleTitle0")
        @preconcurrency public static let title1: UIFont.TextStyle = TextStyle(rawValue: "UICTFontTextStyleTitle1")
        @preconcurrency public static let title2: UIFont.TextStyle = TextStyle(rawValue: "UICTFontTextStyleTitle2")
        @preconcurrency public static let title3: UIFont.TextStyle = TextStyle(rawValue: "UICTFontTextStyleTitle3")
        @preconcurrency public static let headline: UIFont.TextStyle = TextStyle(rawValue: "UICTFontTextStyleHeadline")
        @preconcurrency public static let subheadline: UIFont.TextStyle = TextStyle(rawValue: "UICTFontTextStyleSubhead")
        @preconcurrency public static let body = TextStyle(rawValue: "UICTFontTextStyleBody")
        @preconcurrency public static let callout: UIFont.TextStyle = TextStyle(rawValue: "UICTFontTextStyleCallout")
        @preconcurrency public static let footnote: UIFont.TextStyle = TextStyle(rawValue: "UICTFontTextStyleFootnote")
        @preconcurrency public static let caption1: UIFont.TextStyle = TextStyle(rawValue: "UICTFontTextStyleCaption1")
        @preconcurrency public static let caption2: UIFont.TextStyle = TextStyle(rawValue: "UICTFontTextStyleCaption2")
    }
    @preconcurrency public init?(name fontName: String, size fontSize: CGFloat) { super.init() }
    @preconcurrency @discardableResult open class func systemFont(ofSize fontSize: CGFloat) -> UIFont { fatalError() }
    @preconcurrency @discardableResult open class func preferredFont(forTextStyle style: UIFont.TextStyle) -> UIFont { fatalError() }
    @preconcurrency open var pointSize: CGFloat { fatalError() }
    @preconcurrency open var fontName: String { fatalError() }
}

open class UIImage : NSObject, @unchecked Sendable {
    @preconcurrency public init?(named name: String) { super.init() }
    @preconcurrency public init?(systemName name: String) { super.init() }
    @preconcurrency public init ?(data: Data) { super.init() }
    @preconcurrency public init ?(contentsOfFile path: String) { super.init() }
    @preconcurrency open var size: CGSize { fatalError() }
    @preconcurrency open var scale: CGFloat { fatalError() }
    @preconcurrency @discardableResult public func pngData() -> Data? { nil }
    @preconcurrency @discardableResult public func jpegData(compressionQuality: CGFloat) -> Data? { nil }
}

// MARK: - AttributedString scope (iOS 15+)

extension AttributeScopes {
    public var uiKit: AttributeScopes.UIKitAttributes.Type { AttributeScopes.UIKitAttributes.self }

    public struct UIKitAttributes : AttributeScope, ~Sendable {
        public let font: AttributeScopes.UIKitAttributes.FontAttribute
        public let foregroundColor: AttributeScopes.UIKitAttributes.ForegroundColorAttribute
        public let backgroundColor: AttributeScopes.UIKitAttributes.BackgroundColorAttribute
        public let foundation: AttributeScopes.FoundationAttributes
    }
}

extension AttributeScopes.UIKitAttributes {
    @frozen public enum FontAttribute {
        public typealias Value = UIFont
        public static let name: String = "NSFont"
    }
    @frozen public enum ForegroundColorAttribute {
        public typealias Value = UIColor
        public static let name: String = "NSColor"
    }
    @frozen public enum BackgroundColorAttribute {
        public typealias Value = UIColor
        public static let name: String = "NSBackgroundColor"
    }
}

extension AttributeDynamicLookup {
    @_disfavoredOverload public subscript <T>(dynamicMember keyPath: KeyPath<AttributeScopes.UIKitAttributes, T>) -> T where T : AttributedStringKey {
        self[T.self]
    }
}


// MARK: - Conformances the SDK declares in extensions (generated by the stub audit)
extension AttributeScopes.UIKitAttributes.BackgroundColorAttribute: Sendable {}
extension AttributeScopes.UIKitAttributes.FontAttribute: Sendable {}
extension AttributeScopes.UIKitAttributes.ForegroundColorAttribute: Sendable {}