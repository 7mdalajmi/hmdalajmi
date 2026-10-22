// cloudcheck stub: Apple's XCTest and XCUIAutomation (Xcode 27, iOS) as Swift sees them. XCTest is an
// Objective-C framework (plus a small Swift overlay: the XCTAssert functions, fulfillment(of:)...), so the
// declarations below mirror the Clang importer's view, as printed by Apple's XCTest documentation:
//  - XCTest/XCTestCase are not actor-isolated. Their life-cycle methods (setUp/tearDown...) are nonisolated,
//    and their async variants, imported from completion-handler methods, are nonisolated(nonsending).
//    Swift 6.4 rule for overrides in a @MainActor subclass, in a module without `-default-isolation
//    MainActor` (the tour): an override whose isolation is only inferred from the class falls back to the
//    overridden method's isolation (nonisolated) instead of being an error; an explicit @MainActor on the
//    override is an error for the synchronous methods. With `-default-isolation MainActor` the override
//    gets the default isolation and the mismatch is an error (checked with Operation.main() against the
//    real SDK).
//  - XCUIApplication, XCUIElement, XCUIElementQuery, XCUIScreen, XCUIScreenshot and the two query/screenshot
//    protocols are @MainActor (NS_SWIFT_UI_ACTOR); XCTContext.runActivity is @MainActor @preconcurrency.
//  - Values returned by Objective-C methods are discardable, as for every imported method.
// Built into the stub module directory, this module shadows the toolchain's corelibs XCTest, whose API and
// isolation differ from Apple's. Bodies are placeholders.
// Implicit Clang-importer semantics, spelled out as in Stubs/UIKit: the Objective-C members are marked
// `@preconcurrency` and the main-actor classes and protocols say `@MainActor(unsafe)`, so main-actor calls
// from nonisolated test code are warnings, as on Darwin; `wait(for:timeout:)` is noasync (Xcode 14.3+).
// HARNESS gap: when an inferred override of setUp()/tearDown() in a @MainActor test class falls back to
// the overridden method's isolation, Swift marks that isolation preconcurrency only for an Objective-C
// base, so main-actor state used inside such an override is an error here and a warning in Xcode (seen
// with Foundation's Operation.main() against the real SDK). The Objective-C-ness itself (@objc) cannot be
// expressed on Linux.
@_exported import Foundation
@_exported import ObjectiveC
import UIKit

open class XCTest: NSObject {
    @preconcurrency open var name: String { "" }
    @preconcurrency open var testCaseCount: Int { 0 }
    @preconcurrency open func setUp() {}
    @preconcurrency open func tearDown() {}
    @preconcurrency open func setUpWithError() throws {}
    @preconcurrency open func tearDownWithError() throws {}
    @preconcurrency open func setUp(completion: @escaping @Sendable ((any Error)?) -> Void) {}
    @preconcurrency nonisolated(nonsending) open func setUp() async throws {}
    @preconcurrency open func tearDown(completion: @escaping @Sendable ((any Error)?) -> Void) {}
    @preconcurrency nonisolated(nonsending) open func tearDown() async throws {}
}

open class XCTestExpectation: NSObject, @unchecked Sendable {
    @preconcurrency public init(description expectationDescription: String) { super.init() }
    @preconcurrency open var expectationDescription: String { get { "" } set {} }
    @preconcurrency open var isInverted: Bool { get { false } set {} }
    @preconcurrency open var expectedFulfillmentCount: Int { get { 1 } set {} }
    @preconcurrency open func fulfill() {}
}

public protocol XCTActivity: NSObjectProtocol {
    @preconcurrency var name: String { get }
    @preconcurrency func add(_ attachment: XCTAttachment)
}

open class XCTestCase: XCTest {
    @preconcurrency public override init() { super.init() }
    @preconcurrency public init(selector: Selector) { super.init() }

    @preconcurrency open var continueAfterFailure: Bool { get { true } set {} }
    @preconcurrency open var executionTimeAllowance: TimeInterval { get { 600 } set {} }

    @preconcurrency open class func setUp() {}
    @preconcurrency open class func tearDown() {}

    @preconcurrency open func addTeardownBlock(_ block: @escaping @Sendable () async throws -> Void) {}
    @preconcurrency open func addTeardownBlock(_ block: @escaping @MainActor @Sendable () throws -> Void) {}

    @preconcurrency @discardableResult open func expectation(description: String) -> XCTestExpectation { XCTestExpectation(description: description) }
    @available(*, noasync, message: "Use await fulfillment(of:timeout:enforceOrder:) instead")
    @preconcurrency open func wait(for expectations: [XCTestExpectation], timeout seconds: TimeInterval) {}
    @available(*, noasync, message: "Use await fulfillment(of:timeout:enforceOrder:) instead")
    @preconcurrency open func wait(for expectations: [XCTestExpectation], timeout seconds: TimeInterval, enforceOrder enforceOrderOfFulfillment: Bool) {}
    /// Swift overlay (`@nonobjc`). UNVERIFIED isolation: the documentation shows no global actor; modelled
    /// permissively as nonisolated(nonsending) (runs on the caller's actor, so `self` is not sent). If the
    /// overlay's method is a plain (@concurrent) nonisolated async method, Xcode reports "sending 'self'
    /// risks causing data races" for calls from nonisolated async tests of a non-Sendable test class.
    nonisolated(nonsending) public func fulfillment(of expectations: [XCTestExpectation], timeout seconds: TimeInterval = .infinity,
                            enforceOrder enforceOrderOfFulfillment: Bool = false) async {}
    @preconcurrency open func measure(_ block: () -> Void) {}
}
extension XCTestCase: XCTActivity {
    @preconcurrency public func add(_ attachment: XCTAttachment) {}
}

open class XCTAttachment: NSObject {
    public enum Lifetime: Int, @unchecked Sendable {
        case keepAlways = 0
        case deleteOnSuccess = 1
    }
    @preconcurrency public convenience init(screenshot: XCUIScreenshot) { self.init(data: Data()) }
    @preconcurrency public init(data payload: Data) { super.init() }
    @preconcurrency public convenience init(data payload: Data, uniformTypeIdentifier identifier: String) { self.init(data: payload) }
    @preconcurrency public convenience init(string: String) { self.init(data: Data()) }
    @preconcurrency public convenience init(contentsOfFile url: URL) { self.init(data: Data()) }
    @preconcurrency public convenience init(image: UIImage) { self.init(data: Data()) }
    @preconcurrency open var name: String? { get { nil } set {} }
    @preconcurrency open var lifetime: XCTAttachment.Lifetime { get { .deleteOnSuccess } set {} }
    @preconcurrency open var userInfo: [AnyHashable: Any]? { get { nil } set {} }
}

open class XCTContext: NSObject {
    @MainActor @preconcurrency
    open class func runActivity<Result>(named name: String, block: @MainActor (any XCTActivity) throws -> Result) rethrows -> Result {
        fatalError()
    }
}

// MARK: - Assertions (Swift overlay)

public func XCTAssert(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                      file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                          file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                           file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertEqual<T: Equatable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                         _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertNotEqual<T: Equatable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                            _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "",
                         file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertNotNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "",
                            file: StaticString = #filePath, line: UInt = #line) {}
public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTUnwrap<T>(_ expression: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "",
                         file: StaticString = #filePath, line: UInt = #line) throws -> T { fatalError() }

// MARK: - UI testing (XCUIAutomation, re-exported by XCTest)

@MainActor(unsafe)
public protocol XCUIScreenshotProviding: NSObjectProtocol {
    @preconcurrency func screenshot() -> XCUIScreenshot
}

@MainActor(unsafe)
open class XCUIScreenshot: NSObject {
    @preconcurrency open var image: UIImage { fatalError() }
    @preconcurrency open var pngRepresentation: Data { fatalError() }
}

@MainActor(unsafe)
open class XCUIScreen: NSObject, XCUIScreenshotProviding {
    @preconcurrency open class var main: XCUIScreen { fatalError() }
    @preconcurrency open class var screens: [XCUIScreen] { fatalError() }
    @preconcurrency @discardableResult open func screenshot() -> XCUIScreenshot { fatalError() }
}

@MainActor(unsafe)
public protocol XCUIElementTypeQueryProvider {
    @preconcurrency var touchBars: XCUIElementQuery { get }
    @preconcurrency var groups: XCUIElementQuery { get }
    @preconcurrency var windows: XCUIElementQuery { get }
    @preconcurrency var sheets: XCUIElementQuery { get }
    @preconcurrency var alerts: XCUIElementQuery { get }
    @preconcurrency var dialogs: XCUIElementQuery { get }
    @preconcurrency var buttons: XCUIElementQuery { get }
    @preconcurrency var navigationBars: XCUIElementQuery { get }
    @preconcurrency var tabBars: XCUIElementQuery { get }
    @preconcurrency var tabs: XCUIElementQuery { get }
    @preconcurrency var toolbars: XCUIElementQuery { get }
    @preconcurrency var tables: XCUIElementQuery { get }
    @preconcurrency var cells: XCUIElementQuery { get }
    @preconcurrency var collectionViews: XCUIElementQuery { get }
    @preconcurrency var scrollViews: XCUIElementQuery { get }
    @preconcurrency var staticTexts: XCUIElementQuery { get }
    @preconcurrency var textFields: XCUIElementQuery { get }
    @preconcurrency var secureTextFields: XCUIElementQuery { get }
    @preconcurrency var textViews: XCUIElementQuery { get }
    @preconcurrency var images: XCUIElementQuery { get }
    @preconcurrency var switches: XCUIElementQuery { get }
    @preconcurrency var toggles: XCUIElementQuery { get }
    @preconcurrency var links: XCUIElementQuery { get }
    @preconcurrency var pickers: XCUIElementQuery { get }
    @preconcurrency var pickerWheels: XCUIElementQuery { get }
    @preconcurrency var datePickers: XCUIElementQuery { get }
    @preconcurrency var segmentedControls: XCUIElementQuery { get }
    @preconcurrency var sliders: XCUIElementQuery { get }
    @preconcurrency var steppers: XCUIElementQuery { get }
    @preconcurrency var menus: XCUIElementQuery { get }
    @preconcurrency var menuItems: XCUIElementQuery { get }
    @preconcurrency var keyboards: XCUIElementQuery { get }
    @preconcurrency var keys: XCUIElementQuery { get }
    @preconcurrency var otherElements: XCUIElementQuery { get }
    @preconcurrency func descendants(matching type: XCUIElement.ElementType) -> XCUIElementQuery
    @preconcurrency func children(matching type: XCUIElement.ElementType) -> XCUIElementQuery
}

@MainActor(unsafe)
open class XCUIElement: NSObject, XCUIElementTypeQueryProvider, XCUIScreenshotProviding {
    public enum ElementType: UInt, @unchecked Sendable {
        case any = 0, other, application, group, window, sheet, drawer, alert, dialog, button, radioButton, radioGroup
        case checkBox, disclosureTriangle, popUpButton, comboBox, menuButton, toolbarButton, popover, keyboard, key
        case navigationBar, tabBar, tabGroup, toolbar, statusBar, table, tableRow, tableColumn, outline, outlineRow
        case browser, collectionView, slider, pageIndicator, progressIndicator, activityIndicator, segmentedControl
        case picker, pickerWheel, `switch`, toggle, link, image, icon, searchField, scrollView, scrollBar, staticText
        case textField, secureTextField, datePicker, textView, menu, menuItem, menuBar, menuBarItem, map, webView
        case incrementArrow, decrementArrow, timeline, ratingIndicator, valueIndicator, splitGroup, splitter
        case relevanceIndicator, colorWell, helpTag, matte, dockItem, ruler, rulerMarker, grid, levelIndicator, cell
        case layoutArea, layoutItem, handle, stepper, tab, touchBar, statusItem
    }

    @preconcurrency init(__harness: Void) { super.init() }
    @available(*, unavailable)
    @preconcurrency public override init() { super.init() }

    @preconcurrency open var exists: Bool { fatalError() }
    @preconcurrency open var isHittable: Bool { fatalError() }
    @preconcurrency open var identifier: String { fatalError() }
    @preconcurrency open var label: String { fatalError() }
    @preconcurrency open var title: String { fatalError() }
    @preconcurrency open var value: Any? { fatalError() }
    @preconcurrency open var placeholderValue: String? { fatalError() }
    @preconcurrency open var isEnabled: Bool { fatalError() }
    @preconcurrency open var isSelected: Bool { fatalError() }
    @preconcurrency open var hasFocus: Bool { fatalError() }
    @preconcurrency open var frame: CGRect { fatalError() }
    @preconcurrency open var elementType: XCUIElement.ElementType { fatalError() }

    @preconcurrency @discardableResult open func waitForExistence(timeout: TimeInterval) -> Bool { false }
    @preconcurrency @discardableResult open func waitForNonExistence(timeout: TimeInterval) -> Bool { false }
    @preconcurrency open func tap() {}
    @preconcurrency open func doubleTap() {}
    @preconcurrency open func press(forDuration duration: TimeInterval) {}
    @preconcurrency open func swipeUp() {}
    @preconcurrency open func swipeDown() {}
    @preconcurrency open func swipeLeft() {}
    @preconcurrency open func swipeRight() {}
    @preconcurrency open func typeText(_ text: String) {}
    @preconcurrency @discardableResult open func screenshot() -> XCUIScreenshot { fatalError() }

    @preconcurrency open var touchBars: XCUIElementQuery { fatalError() }
    @preconcurrency open var groups: XCUIElementQuery { fatalError() }
    @preconcurrency open var windows: XCUIElementQuery { fatalError() }
    @preconcurrency open var sheets: XCUIElementQuery { fatalError() }
    @preconcurrency open var alerts: XCUIElementQuery { fatalError() }
    @preconcurrency open var dialogs: XCUIElementQuery { fatalError() }
    @preconcurrency open var buttons: XCUIElementQuery { fatalError() }
    @preconcurrency open var navigationBars: XCUIElementQuery { fatalError() }
    @preconcurrency open var tabBars: XCUIElementQuery { fatalError() }
    @preconcurrency open var tabs: XCUIElementQuery { fatalError() }
    @preconcurrency open var toolbars: XCUIElementQuery { fatalError() }
    @preconcurrency open var tables: XCUIElementQuery { fatalError() }
    @preconcurrency open var cells: XCUIElementQuery { fatalError() }
    @preconcurrency open var collectionViews: XCUIElementQuery { fatalError() }
    @preconcurrency open var scrollViews: XCUIElementQuery { fatalError() }
    @preconcurrency open var staticTexts: XCUIElementQuery { fatalError() }
    @preconcurrency open var textFields: XCUIElementQuery { fatalError() }
    @preconcurrency open var secureTextFields: XCUIElementQuery { fatalError() }
    @preconcurrency open var textViews: XCUIElementQuery { fatalError() }
    @preconcurrency open var images: XCUIElementQuery { fatalError() }
    @preconcurrency open var switches: XCUIElementQuery { fatalError() }
    @preconcurrency open var toggles: XCUIElementQuery { fatalError() }
    @preconcurrency open var links: XCUIElementQuery { fatalError() }
    @preconcurrency open var pickers: XCUIElementQuery { fatalError() }
    @preconcurrency open var pickerWheels: XCUIElementQuery { fatalError() }
    @preconcurrency open var datePickers: XCUIElementQuery { fatalError() }
    @preconcurrency open var segmentedControls: XCUIElementQuery { fatalError() }
    @preconcurrency open var sliders: XCUIElementQuery { fatalError() }
    @preconcurrency open var steppers: XCUIElementQuery { fatalError() }
    @preconcurrency open var menus: XCUIElementQuery { fatalError() }
    @preconcurrency open var menuItems: XCUIElementQuery { fatalError() }
    @preconcurrency open var keyboards: XCUIElementQuery { fatalError() }
    @preconcurrency open var keys: XCUIElementQuery { fatalError() }
    @preconcurrency open var otherElements: XCUIElementQuery { fatalError() }
    @preconcurrency @discardableResult open func descendants(matching type: XCUIElement.ElementType) -> XCUIElementQuery { fatalError() }
    @preconcurrency @discardableResult open func children(matching type: XCUIElement.ElementType) -> XCUIElementQuery { fatalError() }
}

@MainActor(unsafe)
open class XCUIElementQuery: NSObject, XCUIElementTypeQueryProvider {
    @preconcurrency open var element: XCUIElement { fatalError() }
    @preconcurrency open var count: Int { fatalError() }
    @preconcurrency open var firstMatch: XCUIElement { fatalError() }
    @preconcurrency open var allElementsBoundByIndex: [XCUIElement] { fatalError() }
    @preconcurrency @discardableResult open func element(boundBy index: Int) -> XCUIElement { fatalError() }
    @preconcurrency @discardableResult open func element(matching predicate: NSPredicate) -> XCUIElement { fatalError() }
    @preconcurrency @discardableResult open func element(matching elementType: XCUIElement.ElementType, identifier: String?) -> XCUIElement { fatalError() }
    @preconcurrency open subscript(key: String) -> XCUIElement { fatalError() }
    @preconcurrency @discardableResult open func matching(_ predicate: NSPredicate) -> XCUIElementQuery { fatalError() }
    @preconcurrency @discardableResult open func matching(_ elementType: XCUIElement.ElementType, identifier: String?) -> XCUIElementQuery { fatalError() }
    @preconcurrency @discardableResult open func matching(identifier: String) -> XCUIElementQuery { fatalError() }
    @preconcurrency @discardableResult open func containing(_ predicate: NSPredicate) -> XCUIElementQuery { fatalError() }
    @preconcurrency @discardableResult open func containing(_ elementType: XCUIElement.ElementType, identifier: String?) -> XCUIElementQuery { fatalError() }

    @preconcurrency open var touchBars: XCUIElementQuery { fatalError() }
    @preconcurrency open var groups: XCUIElementQuery { fatalError() }
    @preconcurrency open var windows: XCUIElementQuery { fatalError() }
    @preconcurrency open var sheets: XCUIElementQuery { fatalError() }
    @preconcurrency open var alerts: XCUIElementQuery { fatalError() }
    @preconcurrency open var dialogs: XCUIElementQuery { fatalError() }
    @preconcurrency open var buttons: XCUIElementQuery { fatalError() }
    @preconcurrency open var navigationBars: XCUIElementQuery { fatalError() }
    @preconcurrency open var tabBars: XCUIElementQuery { fatalError() }
    @preconcurrency open var tabs: XCUIElementQuery { fatalError() }
    @preconcurrency open var toolbars: XCUIElementQuery { fatalError() }
    @preconcurrency open var tables: XCUIElementQuery { fatalError() }
    @preconcurrency open var cells: XCUIElementQuery { fatalError() }
    @preconcurrency open var collectionViews: XCUIElementQuery { fatalError() }
    @preconcurrency open var scrollViews: XCUIElementQuery { fatalError() }
    @preconcurrency open var staticTexts: XCUIElementQuery { fatalError() }
    @preconcurrency open var textFields: XCUIElementQuery { fatalError() }
    @preconcurrency open var secureTextFields: XCUIElementQuery { fatalError() }
    @preconcurrency open var textViews: XCUIElementQuery { fatalError() }
    @preconcurrency open var images: XCUIElementQuery { fatalError() }
    @preconcurrency open var switches: XCUIElementQuery { fatalError() }
    @preconcurrency open var toggles: XCUIElementQuery { fatalError() }
    @preconcurrency open var links: XCUIElementQuery { fatalError() }
    @preconcurrency open var pickers: XCUIElementQuery { fatalError() }
    @preconcurrency open var pickerWheels: XCUIElementQuery { fatalError() }
    @preconcurrency open var datePickers: XCUIElementQuery { fatalError() }
    @preconcurrency open var segmentedControls: XCUIElementQuery { fatalError() }
    @preconcurrency open var sliders: XCUIElementQuery { fatalError() }
    @preconcurrency open var steppers: XCUIElementQuery { fatalError() }
    @preconcurrency open var menus: XCUIElementQuery { fatalError() }
    @preconcurrency open var menuItems: XCUIElementQuery { fatalError() }
    @preconcurrency open var keyboards: XCUIElementQuery { fatalError() }
    @preconcurrency open var keys: XCUIElementQuery { fatalError() }
    @preconcurrency open var otherElements: XCUIElementQuery { fatalError() }
    @preconcurrency @discardableResult open func descendants(matching type: XCUIElement.ElementType) -> XCUIElementQuery { fatalError() }
    @preconcurrency @discardableResult open func children(matching type: XCUIElement.ElementType) -> XCUIElementQuery { fatalError() }
}

@MainActor(unsafe)
open class XCUIApplication: XCUIElement {
    public enum State: UInt, @unchecked Sendable {
        case unknown = 0
        case notRunning = 1
        case runningBackgroundSuspended = 2
        case runningBackground = 3
        case runningForeground = 4
    }

    @preconcurrency public init() { super.init(__harness: ()) }
    @preconcurrency public init(bundleIdentifier: String) { super.init(__harness: ()) }

    @preconcurrency open var launchArguments: [String] { get { [] } set {} }
    @preconcurrency open var launchEnvironment: [String: String] { get { [:] } set {} }
    @preconcurrency open var state: XCUIApplication.State { fatalError() }

    @preconcurrency open func launch() {}
    @preconcurrency open func activate() {}
    @preconcurrency open func terminate() {}
    @preconcurrency @discardableResult open func wait(for state: XCUIApplication.State, timeout: TimeInterval) -> Bool { false }
}
