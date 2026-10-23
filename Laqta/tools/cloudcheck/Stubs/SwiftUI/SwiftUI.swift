// cloudcheck stub: SwiftUI (+ SwiftUICore) as seen through `import SwiftUI` with the iOS 27.0 SDK, for the
// APIs the apps use.
//
// Provenance: every declaration that has a counterpart in the SDK's SwiftUI/SwiftUICore .swiftinterface
// files carries the SDK's own header (attributes, isolation, @preconcurrency, @_disfavoredOverload,
// parameter attributes such as @_inheritActorContext / @isolated(any) / sending, ~Sendable, @frozen),
// copied by the stub audit; the result builders and the View/Toolbar/Tab/Scene/Widget protocols are written
// from the interfaces by hand (the "verbatim" regions). The module is compiled in Swift 5 mode with the
// SDK's upcoming features, as Apple compiles it (check.sh).
//
// Availability: the stubs are compiled for the Linux host, where iOS availability is inert. iOS
// deprecations at or before the iOS 26.0 deployment target are therefore spelled `@available(*,
// deprecated, message: "deprecated in iOS N: ...")`; later and future (100000) deprecations, and APIs
// introduced after iOS 26.0, are left out or unannotated (use `check.sh --sdk` for those).
//
// Not modelled: Xcode 27 expands `@State` with the closed-source SwiftUIMacros.StateMacro; this stub keeps
// the `State` property wrapper (the Xcode 26 behaviour). The SDK's @inlinable modifier bodies (padding,
// frame...) are not reproduced, so their results are opaque here.
//
// Re-exports what a plain `import SwiftUI` makes visible on iOS (the SwiftUI/SwiftUICore Clang modules
// re-export UIKit, Foundation, CoreGraphics and CoreText; Darwin Foundation re-exports Observation).
// Bodies are placeholders: this module is only ever used for type-checking.
@_exported import Foundation
@_exported import CoreGraphics
@_exported import CoreText
@_exported import UIKit
@_exported import Observation

@usableFromInline func _stub<T>() -> T { fatalError("cloudcheck stub") }

// cloudcheck:verbatim-begin (written from the iOS 27 SDK interface by hand; the stub audit leaves it alone)
// MARK: - View and the view builder
// iOS 27 SDK: `ContentBuilder` is a typealias of `ViewBuilder`, whose single-element, `buildIf` and
// `buildEither` functions are unconstrained, and which also builds toolbar content (see the toolbar
// section). The iOS 27-only `buildBlock(...) -> TupleContent` overload is left out: it is unavailable at
// the iOS 26.0 deployment target, so the compiler picks the TupleView overload there.

@preconcurrency @MainActor public protocol View {
    associatedtype Body: View
    @ContentBuilder @MainActor @preconcurrency var body: Self.Body { get }
}

extension View where Self.Body == Never {
    public var body: Never { fatalError("primitive view") }
}

extension Never: View {
    public typealias Body = Never
    /// One `body` for every protocol Never conforms to (View, Scene, ToolbarContent, TabContent, WidgetConfiguration).
    public var body: Never { fatalError() }
}

public typealias ContentBuilder = ViewBuilder
public typealias EmptyContent = EmptyView

@resultBuilder public struct ViewBuilder {
    public static func buildBlock() -> EmptyContent { EmptyView() }
    public static func buildBlock<Content>(_ content: Content) -> Content { content }
    @_disfavoredOverload public static func buildBlock<each Content>(_ content: repeat each Content) -> TupleView<(repeat each Content)> where repeat each Content: View {
        TupleView((repeat each content))
    }
}
extension ViewBuilder: Sendable {}
extension ViewBuilder {
    public static func buildIf<Content>(_ content: Content?) -> Content? { content }
    public static func buildEither<TrueContent, FalseContent>(first: TrueContent) -> _ConditionalContent<TrueContent, FalseContent> {
        _ConditionalContent(storage: .trueContent(first))
    }
    public static func buildEither<TrueContent, FalseContent>(second: FalseContent) -> _ConditionalContent<TrueContent, FalseContent> {
        _ConditionalContent(storage: .falseContent(second))
    }
}
extension ViewBuilder {
    public static func buildLimitedAvailability<Content>(_ content: Content) -> AnyView where Content: View { AnyView(content) }
}

@frozen nonisolated public struct TupleView<T>: View, ~Sendable {
    public var value: T
    nonisolated public init(_ value: T) { self.value = value }
    public typealias Body = Never
}

@frozen public struct _ConditionalContent<TrueContent, FalseContent>: ~Sendable {
    @frozen public enum Storage: ~Sendable {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }
    public let storage: _ConditionalContent<TrueContent, FalseContent>.Storage
    public init(storage: _ConditionalContent<TrueContent, FalseContent>.Storage) { self.storage = storage }   // internal in the SDK
}
extension _ConditionalContent: View where TrueContent: View, FalseContent: View { public typealias Body = Never }

extension Optional: View where Wrapped: View { public typealias Body = Never }

@frozen nonisolated public struct EmptyView: View {
    nonisolated public init() {}
    public typealias Body = Never
}
extension EmptyView: Sendable {}

@frozen nonisolated public struct AnyView: View, ~Sendable {
    nonisolated public init<V>(_ view: V) where V: View {}
    nonisolated public init<V>(erasing view: V) where V: View {}
    public typealias Body = Never
}

// cloudcheck:verbatim-end

// MARK: - Modifiers

@frozen
public struct ModifiedContent<Content, Modifier> {
    public var content: Content
    public var modifier: Modifier
    nonisolated public init (content: Content, modifier: Modifier) {
        self.content = content
        self.modifier = modifier
    }
}
extension ModifiedContent: View where Content: View, Modifier: ViewModifier { public typealias Body = Never }

@preconcurrency @MainActor public protocol ViewModifier {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func body(content: Self.Content) -> Self.Body
    typealias Content = _ViewModifier_Content<Self>
}

@frozen
public struct _ViewModifier_Content<Modifier: ViewModifier> {}
extension _ViewModifier_Content: View { public typealias Body = Never }

@frozen nonisolated public struct EmptyModifier : ViewModifier {
    public static let identity: EmptyModifier = EmptyModifier()
    nonisolated public init () {}
    public func body(content: Content) -> Content { content }
}

nonisolated public struct AccessibilityAttachmentModifier : ViewModifier, ~Sendable {
    public func body(content: Content) -> Content { content }
}

extension View {
    nonisolated public func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        ModifiedContent(content: self, modifier: modifier)
    }
}

// MARK: - Dynamic properties, state, bindings

public protocol DynamicProperty {
    mutating func update()
}
extension DynamicProperty {
    public mutating func update() {}
}

@frozen public struct Transaction : ~Sendable {
    public init () {}
    public init (animation: Animation?) {}
    public var animation: Animation?
    public var disablesAnimations: Bool = false
}

@frozen @propertyWrapper public struct State<Value> : DynamicProperty {
    public init (wrappedValue value: Value) {}
    public init (initialValue value: Value) {}
    public var wrappedValue: Value {
        get { _stub() }
        nonmutating set {}
    }
    public var projectedValue: Binding<Value> { _stub() }
}
extension State where Value: ExpressibleByNilLiteral {
    public init () {}
}

@frozen @propertyWrapper @dynamicMemberLookup
public struct Binding<Value> {
    public var transaction: Transaction {
        get { _stub() }
        set {}
    }
    @preconcurrency public init (@_inheritActorContext get: @escaping @isolated(any) @Sendable () -> Value, @_inheritActorContext set: @escaping @isolated(any) @Sendable (Value) -> Void) {}
    @preconcurrency public init (@_inheritActorContext get: @escaping @isolated(any) @Sendable () -> Value, @_inheritActorContext set: @escaping @isolated(any) @Sendable (Value, Transaction) -> Void) {}
    public static func constant(_ value: Value) -> Binding<Value> { _stub() }
    public var wrappedValue: Value {
        get { _stub() }
        nonmutating set {}
    }
    public var projectedValue: Binding<Value> { self }
    public init (projectedValue: Binding<Value>) {}
    public subscript <Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> { _stub() }
}
extension Binding {
    public init <V>(_ base: Binding<V>) where Value == V? {}
    public init ?(_ base: Binding<Value?>) {}
    public init <V>(_ base: Binding<V>) where Value == AnyHashable, V : Hashable {}
    public func transaction(_ transaction: Transaction) -> Binding<Value> { self }
    public func animation(_ animation: Animation? = .default) -> Binding<Value> { self }
}
extension Binding: Identifiable where Value: Identifiable {
    public var id: Value.ID { _stub() }
}
extension Binding: DynamicProperty {}

@frozen @propertyWrapper public struct FocusState<Value> : DynamicProperty, ~Sendable where Value : Hashable {
    @frozen @propertyWrapper public struct Binding : ~Sendable {
        @usableFromInline let _location: Int
        public var wrappedValue: Value {
            get { _stub() }
            nonmutating set {}
        }
        public var projectedValue: FocusState<Value>.Binding { self }
    }
    public var wrappedValue: Value {
        get { _stub() }
        nonmutating set {}
    }
    public var projectedValue: FocusState<Value>.Binding { _stub() }
    public init () where Value == Bool {}
    public init <T>() where Value == T?, T : Hashable {}
}

@dynamicMemberLookup @propertyWrapper
public struct Bindable<Value> {
    public var wrappedValue: Value
    public var projectedValue: Bindable<Value> { self }
    @available(*, unavailable, message: "The wrapped value must be an object that conforms to Observable") public init (wrappedValue: Value) { self.wrappedValue = wrappedValue }
    @available(*, unavailable, message: "The wrapped value must be an object that conforms to Observable") public init (projectedValue: Bindable<Value>) { self.wrappedValue = projectedValue.wrappedValue }
}
extension Bindable where Value: AnyObject, Value: Observable {
    public subscript <Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject> { _stub() }
    public init (wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public init (_ wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public init (projectedValue: Bindable<Value>) { self.wrappedValue = projectedValue.wrappedValue }
}
extension Bindable: Identifiable where Value: Identifiable {
    public var id: Value.ID { wrappedValue.id }
}
extension Bindable: DynamicProperty {}
extension Bindable: Sendable where Value: Sendable {}

// MARK: - Environment

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

public struct EnvironmentValues : CustomStringConvertible, ~Sendable {
    public init () {}
    public subscript <K>(key: K.Type) -> K.Value where K : EnvironmentKey {
        get { _stub() }
        set {}
    }
    public var description: String { "" }
}

@frozen @propertyWrapper public struct Environment<Value> : DynamicProperty {
    public init (_ keyPath: KeyPath<EnvironmentValues, Value>) {}
    public var wrappedValue: Value { _stub() }
}
extension Environment {
    public init (_ objectType: Value.Type) where Value : AnyObject, Value : Observable {}
    public init <T>(_ objectType: T.Type) where Value == T?, T : AnyObject, T : Observable {}
}

public enum ColorScheme : CaseIterable, Sendable {
    case light
    case dark
}

public enum ColorSchemeContrast : CaseIterable, Sendable {
    case standard
    case increased
}

public enum ScenePhase : Comparable {
    case background
    case inactive
    case active
}

public enum LayoutDirection : Hashable, CaseIterable, Sendable {
    case leftToRight
    case rightToLeft
}

public enum UserInterfaceSizeClass : Sendable {
    case compact
    case regular
}

public enum DynamicTypeSize : Hashable, Comparable, CaseIterable, Sendable {
    case xSmall
    case small
    case medium
    case large
    case xLarge
    case xxLarge
    case xxxLarge
    case accessibility1
    case accessibility2
    case accessibility3
    case accessibility4
    case accessibility5
    public var isAccessibilitySize: Bool { self >= .accessibility1 }
}

@preconcurrency @MainActor public struct DismissAction {
    @MainActor @preconcurrency public func callAsFunction() {}
}

@preconcurrency @MainActor public struct OpenURLAction {
    public struct Result : Sendable {
        public static let handled: OpenURLAction.Result = Result()
        public static let discarded: OpenURLAction.Result = Result()
        public static let systemAction: OpenURLAction.Result = Result()
        public static func systemAction(_ url: URL) -> OpenURLAction.Result { Result() }
    }
    @preconcurrency @MainActor public init (handler: @escaping (URL) -> OpenURLAction.Result) {}
    @MainActor @preconcurrency public func callAsFunction(_ url: URL) {}
    @MainActor @preconcurrency public func callAsFunction(_ url: URL, completion: @escaping (_ accepted: Bool) -> Void) {}
}

extension EnvironmentValues {
    public var colorScheme: ColorScheme { get { _stub() } set {} }
    public var colorSchemeContrast: ColorSchemeContrast { _stub() }
    public var scenePhase: ScenePhase { get { _stub() } set {} }
    public var layoutDirection: LayoutDirection { get { _stub() } set {} }
    public var locale: Locale { get { _stub() } set {} }
    public var calendar: Calendar { get { _stub() } set {} }
    public var timeZone: TimeZone { get { _stub() } set {} }
    public var dynamicTypeSize: DynamicTypeSize { get { _stub() } set {} }
    public var horizontalSizeClass: UserInterfaceSizeClass? { get { _stub() } set {} }
    public var verticalSizeClass: UserInterfaceSizeClass? { get { _stub() } set {} }
    public var displayScale: CGFloat { get { _stub() } set {} }
    public var isEnabled: Bool { get { _stub() } set {} }
    public var font: Font? { get { _stub() } set {} }
    public var accessibilityReduceMotion: Bool { _stub() }
    public var accessibilityReduceTransparency: Bool { _stub() }
    public var accessibilityDifferentiateWithoutColor: Bool { _stub() }
    public var accessibilityVoiceOverEnabled: Bool { _stub() }
    public var isPresented: Bool { _stub() }
    public var dismiss: DismissAction { _stub() }
    @preconcurrency @MainActor public var openURL: OpenURLAction { get { _stub() } set {} }
}

// MARK: - Observation hooks

extension View {
    nonisolated public func environment<T>(_ object: T?) -> some View where T : AnyObject, T : Observable { self }
    nonisolated public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View { self }
}

// MARK: - Localized strings

public protocol _FormatSpecifiable: Equatable {
    associatedtype _Arg: CVarArg
    var _arg: Self._Arg { get }
    var _specifier: String { get }
}
extension Int: _FormatSpecifiable { public var _arg: Int { self }; public var _specifier: String { "%lld" } }
extension Int8: _FormatSpecifiable { public var _arg: Int32 { Int32(self) }; public var _specifier: String { "%d" } }
extension Int16: _FormatSpecifiable { public var _arg: Int32 { Int32(self) }; public var _specifier: String { "%d" } }
extension Int32: _FormatSpecifiable { public var _arg: Int32 { self }; public var _specifier: String { "%d" } }
extension Int64: _FormatSpecifiable { public var _arg: Int64 { self }; public var _specifier: String { "%lld" } }
extension UInt: _FormatSpecifiable { public var _arg: UInt { self }; public var _specifier: String { "%llu" } }
extension UInt8: _FormatSpecifiable { public var _arg: UInt32 { UInt32(self) }; public var _specifier: String { "%u" } }
extension UInt16: _FormatSpecifiable { public var _arg: UInt32 { UInt32(self) }; public var _specifier: String { "%u" } }
extension UInt32: _FormatSpecifiable { public var _arg: UInt32 { self }; public var _specifier: String { "%u" } }
extension UInt64: _FormatSpecifiable { public var _arg: UInt64 { self }; public var _specifier: String { "%llu" } }
extension Float: _FormatSpecifiable { public var _arg: Float { self }; public var _specifier: String { "%f" } }
extension Double: _FormatSpecifiable { public var _arg: Double { self }; public var _specifier: String { "%lf" } }
extension CGFloat: _FormatSpecifiable { public var _arg: Double { Double(self) }; public var _specifier: String { "%lf" } }

@frozen public struct LocalizedStringKey : Equatable, ExpressibleByStringInterpolation, ~Sendable {
    public init (_ value: String) {}
    public init (stringLiteral value: String) {}
    public init (stringInterpolation: LocalizedStringKey.StringInterpolation) {}

    public struct StringInterpolation : StringInterpolationProtocol, ~Sendable {
        public init (literalCapacity: Int, interpolationCount: Int) {}
        public mutating func appendLiteral(_ literal: String) {}
        public mutating func appendInterpolation(_ string: String) {}
        public mutating func appendInterpolation<Subject>(_ subject: Subject, formatter: Formatter? = nil) where Subject : ReferenceConvertible {}
        public mutating func appendInterpolation<Subject>(_ subject: Subject, formatter: Formatter? = nil) where Subject : NSObject {}
        public mutating func appendInterpolation<F>(_ input: F.FormatInput, format: F) where F: FormatStyle, F.FormatInput: Equatable, F.FormatOutput == String {} // cloudcheck: as in the SDK
        public mutating func appendInterpolation<F>(_ input: F.FormatInput, format: F) where F: FormatStyle, F.FormatInput: Equatable, F.FormatOutput == AttributedString {} // cloudcheck: as in the SDK
        public mutating func appendInterpolation<T>(_ value: T) where T : _FormatSpecifiable {}
        public mutating func appendInterpolation<T>(_ value: T, specifier: String) where T : _FormatSpecifiable {}
        public mutating func appendInterpolation(_ text: Text) {}
        public mutating func appendInterpolation(_ attributedString: AttributedString) {}
        public mutating func appendInterpolation(_ image: Image) {}
        public mutating func appendInterpolation(_ date: Date, style: Text.DateStyle) {}
    }
}

// MARK: - Text

@frozen public struct Text : Equatable, Sendable {
    public init (verbatim content: String) {}
    @_disfavoredOverload public init <S>(_ content: S) where S : StringProtocol {}
    public init (_ key: LocalizedStringKey, tableName: String? = nil, bundle: Bundle? = nil, comment: StaticString? = nil) {}
    @_disfavoredOverload public init (_ attributedContent: AttributedString) {}
    public init (_ date: Date, style: Text.DateStyle) {}
    public init (_ image: Image) {}
    public init <F>(_ input: F.FormatInput, format: F) where F : FormatStyle, F.FormatInput : Equatable, F.FormatOutput == String {}

    public static func == (a: Text, b: Text) -> Bool { true }

    public struct DateStyle : Sendable {
        public static let time: Text.DateStyle = DateStyle()
        public static let date: Text.DateStyle = DateStyle()
        public static let relative: Text.DateStyle = DateStyle()
        public static let offset: Text.DateStyle = DateStyle()
        public static let timer: Text.DateStyle = DateStyle()
    }

    public struct LineStyle : Hashable, Sendable {
        public enum Pattern: Sendable {
            case solid, dot, dash, dashDot, dashDotDot
        }
        public init (pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) {}
        public static let single: Text.LineStyle = LineStyle()
    }

    public enum TruncationMode : Sendable {
        case head, tail, middle
    }

    public enum Case : Sendable {
        case uppercase, lowercase
    }

    public struct Scale : Sendable, Hashable {
        public static let `default`: Text.Scale = Scale()
        public static let secondary: Text.Scale = Scale()
    }
}
extension Text: View { public typealias Body = Never }

extension Text {
    nonisolated public func font(_ font: Font?) -> Text { self }
    nonisolated public func fontWeight(_ weight: Font.Weight?) -> Text { self }
    nonisolated public func fontDesign(_ design: Font.Design?) -> Text { self }
    nonisolated public func fontWidth(_ width: Font.Width?) -> Text { self }
    nonisolated public func foregroundColor(_ color: Color?) -> Text { self }
    nonisolated public func foregroundStyle<S>(_ style: S) -> Text where S : ShapeStyle { self }
    nonisolated public func bold() -> Text { self }
    nonisolated public func bold(_ isActive: Bool) -> Text { self }
    nonisolated public func italic() -> Text { self }
    nonisolated public func italic(_ isActive: Bool) -> Text { self }
    nonisolated public func monospaced(_ isActive: Bool = true) -> Text { self }
    nonisolated public func monospacedDigit() -> Text { self }
    nonisolated public func strikethrough(_ isActive: Bool = true, color: Color? = nil) -> Text { self }
    nonisolated public func strikethrough(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern, color: Color? = nil) -> Text { self }
    nonisolated public func underline(_ isActive: Bool = true, color: Color? = nil) -> Text { self }
    nonisolated public func underline(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern, color: Color? = nil) -> Text { self }
    nonisolated public func kerning(_ kerning: CGFloat) -> Text { self }
    nonisolated public func tracking(_ tracking: CGFloat) -> Text { self }
    nonisolated public func baselineOffset(_ baselineOffset: CGFloat) -> Text { self }
    public func textScale(_ scale: Text.Scale, isEnabled: Bool = true) -> Text { self }
    @available(*, deprecated, message: "deprecated in iOS 26.0: Use string interpolation on `Text` instead: `Text(\"Hello \\(name)\")`") public static func + (lhs: Text, rhs: Text) -> Text { lhs }
}

// MARK: - Fonts

@frozen public struct Font : Hashable, Sendable {
    public enum TextStyle : CaseIterable, Sendable {
        case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2
    }

    @frozen public struct Weight : Hashable {
        public static let ultraLight: Font.Weight = Weight()
        public static let thin: Font.Weight = Weight()
        public static let light: Font.Weight = Weight()
        public static let regular: Font.Weight = Weight()
        public static let medium: Font.Weight = Weight()
        public static let semibold: Font.Weight = Weight()
        public static let bold: Font.Weight = Weight()
        public static let heavy: Font.Weight = Weight()
        public static let black: Font.Weight = Weight()
    }

    public enum Design : Hashable, Sendable {
        case `default`, serif, rounded, monospaced
    }

    public struct Width : Hashable, Sendable {
        public var value: CGFloat
        public init (_ value: CGFloat) { self.value = value }
        public static let compressed: Font.Width = Width(0)
        public static let condensed: Font.Width = Width(0)
        public static let standard: Font.Width = Width(0)
        public static let expanded: Font.Width = Width(0)
    }

    public static let largeTitle: Font = Font()
    public static let title: Font = Font()
    public static let title2: Font = Font()
    public static let title3: Font = Font()
    public static let headline: Font = Font()
    public static let subheadline: Font = Font()
    public static let body = Font()
    public static let callout: Font = Font()
    public static let footnote: Font = Font()
    public static let caption: Font = Font()
    public static let caption2: Font = Font()

    @_disfavoredOverload public static func system(_ style: Font.TextStyle, design: Font.Design = .default) -> Font { Font() }
    /// iOS 16 overloads with optional parameters; disfavoured so existing calls keep resolving (as in the SDK).
    public static func system(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> Font { Font() }
    @_disfavoredOverload public static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font { Font() }
    public static func system(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font { Font() }
    public static func custom(_ name: String, size: CGFloat) -> Font { Font() }
    public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font { Font() }
    public static func custom(_ name: String, fixedSize: CGFloat) -> Font { Font() }

    public func weight(_ weight: Font.Weight) -> Font { self }
    public func width(_ width: Font.Width) -> Font { self }
    public func bold() -> Font { self }
    public func italic() -> Font { self }
    public func monospaced() -> Font { self }
    public func monospacedDigit() -> Font { self }
    public func smallCaps() -> Font { self }
    public func leading(_ leading: Font.Leading) -> Font { self }

    public enum Leading : Sendable {
        case standard, tight, loose
    }
}

// MARK: - Colours, shape styles, gradients

public protocol ShapeStyle : Sendable {}

@frozen public struct ForegroundStyle : ShapeStyle {
    public init () {}
}
extension ShapeStyle where Self == ForegroundStyle {
    public static var foreground: ForegroundStyle { ForegroundStyle() }
}

@frozen public struct HierarchicalShapeStyle : ShapeStyle {
    public static let primary: HierarchicalShapeStyle = HierarchicalShapeStyle()
    public static let secondary: HierarchicalShapeStyle = HierarchicalShapeStyle()
    public static let tertiary: HierarchicalShapeStyle = HierarchicalShapeStyle()
    public static let quaternary: HierarchicalShapeStyle = HierarchicalShapeStyle()
}
extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var primary: HierarchicalShapeStyle { .primary }
    public static var secondary: HierarchicalShapeStyle { .secondary }
    public static var tertiary: HierarchicalShapeStyle { .tertiary }
    public static var quaternary: HierarchicalShapeStyle { .quaternary }
}

@frozen public struct AnyShapeStyle : ShapeStyle {
    public init <S>(_ style: S) where S : ShapeStyle {}
}

public struct Material : Sendable {
    public static let ultraThin: Material = Material()
    public static let thin: Material = Material()
    public static let regular: Material = Material()
    public static let thick: Material = Material()
    public static let ultraThick: Material = Material()
    public static let bar: Material = Material()
}
extension ShapeStyle where Self == Material {
    public static var ultraThinMaterial: Material { .ultraThin }
    public static var thinMaterial: Material { .thin }
    public static var regularMaterial: Material { .regular }
    public static var thickMaterial: Material { .thick }
    public static var ultraThickMaterial: Material { .ultraThick }
    public static var bar: Material { .bar }
}

public struct _OpacityShapeStyle<Base: ShapeStyle>: ShapeStyle {}

extension ShapeStyle {
    @_disfavoredOverload public func opacity(_ opacity: Double) -> some ShapeStyle { _OpacityShapeStyle<Self>() }
}

@frozen public struct Color : Hashable, CustomStringConvertible, Sendable {
    public enum RGBColorSpace : Sendable {
        case sRGB, sRGBLinear, displayP3
    }

    public init (_ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {}
    public init (_ colorSpace: Color.RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) {}
    public init (hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) {}
    public init (_ name: String, bundle: Bundle? = nil) {}
    public init (uiColor: UIColor) {}
    @_disfavoredOverload public init (_ color: UIColor) {}

    public func opacity(_ opacity: Double) -> Color { self }
    public var description: String { "" }

    public static let clear: Color = Color(white: 0, opacity: 0)
    public static let black: Color = Color(white: 0)
    public static let white: Color = Color(white: 1)
    public static let gray: Color = Color(white: 0.5)
    public static let red: Color = Color(red: 1, green: 0, blue: 0)
    public static let green: Color = Color(red: 0, green: 1, blue: 0)
    public static let blue: Color = Color(red: 0, green: 0, blue: 1)
    public static let orange: Color = Color(red: 1, green: 0.5, blue: 0)
    public static let yellow: Color = Color(red: 1, green: 1, blue: 0)
    public static let pink: Color = Color(red: 1, green: 0.5, blue: 0.5)
    public static let purple: Color = Color(red: 0.5, green: 0, blue: 0.5)
    public static let mint: Color = Color(red: 0, green: 1, blue: 0.8)
    public static let teal: Color = Color(red: 0, green: 0.5, blue: 0.5)
    public static let cyan: Color = Color(red: 0, green: 1, blue: 1)
    public static let indigo: Color = Color(red: 0.3, green: 0, blue: 0.5)
    public static let brown: Color = Color(red: 0.6, green: 0.4, blue: 0.2)
    public static let primary: Color = Color(white: 0)
    public static let secondary: Color = Color(white: 0.5)
    public static var accentColor: Color { Color(white: 0) }
}
extension Color: ShapeStyle {}
extension Color: View { public typealias Body = Never }

extension ShapeStyle where Self == Color {
    public static var clear: Color { Color.clear }
    public static var black: Color { Color.black }
    public static var white: Color { Color.white }
    public static var gray: Color { Color.gray }
    public static var red: Color { Color.red }
    public static var green: Color { Color.green }
    public static var blue: Color { Color.blue }
    public static var orange: Color { Color.orange }
    public static var yellow: Color { Color.yellow }
    public static var pink: Color { Color.pink }
    public static var purple: Color { Color.purple }
    public static var mint: Color { Color.mint }
    public static var teal: Color { Color.teal }
    public static var cyan: Color { Color.cyan }
    public static var indigo: Color { Color.indigo }
    public static var brown: Color { Color.brown }
}

extension UIColor {
    convenience public init (_ color: Color) { self.init(white: 0, alpha: 0) }
}

@frozen public struct Gradient : Equatable {
    @frozen public struct Stop : Equatable {
        public var color: Color
        public var location: CGFloat
        public init (color: Color, location: CGFloat) {
            self.color = color
            self.location = location
        }
    }
    public var stops: [Gradient.Stop]
    public init (stops: [Gradient.Stop]) { self.stops = stops }
    public init (colors: [Color]) { self.stops = [] }
}

@frozen nonisolated public struct LinearGradient : ShapeStyle, View, Sendable {
    nonisolated public init (gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {}
    nonisolated public init (colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {}
    nonisolated public init (stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {}
}
extension LinearGradient { public typealias Body = Never }

@frozen nonisolated public struct RadialGradient : ShapeStyle, View, Sendable {
    nonisolated public init (gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {}
    nonisolated public init (colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {}
    nonisolated public init (stops: [Gradient.Stop], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {}
}
extension RadialGradient { public typealias Body = Never }

@frozen nonisolated public struct EllipticalGradient : ShapeStyle, View, Sendable {
    nonisolated public init (gradient: Gradient, center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {}
    nonisolated public init (colors: [Color], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {}
    nonisolated public init (stops: [Gradient.Stop], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {}
}
extension EllipticalGradient { public typealias Body = Never }

@frozen nonisolated public struct AngularGradient : ShapeStyle, View, Sendable {
    nonisolated public init (gradient: Gradient, center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .zero) {}
    nonisolated public init (colors: [Color], center: UnitPoint, startAngle: Angle, endAngle: Angle) {}
    nonisolated public init (stops: [Gradient.Stop], center: UnitPoint, startAngle: Angle, endAngle: Angle) {}
}
extension AngularGradient { public typealias Body = Never }

// MARK: - Geometry and layout values

@frozen public struct UnitPoint : Hashable {
    public var x: CGFloat
    public var y: CGFloat
    public init () { x = 0; y = 0 }
    public init (x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
    public static let zero: UnitPoint = UnitPoint(x: 0, y: 0)
    public static let center: UnitPoint = UnitPoint(x: 0.5, y: 0.5)
    public static let leading: UnitPoint = UnitPoint(x: 0, y: 0.5)
    public static let trailing: UnitPoint = UnitPoint(x: 1, y: 0.5)
    public static let top: UnitPoint = UnitPoint(x: 0.5, y: 0)
    public static let bottom: UnitPoint = UnitPoint(x: 0.5, y: 1)
    public static let topLeading: UnitPoint = UnitPoint(x: 0, y: 0)
    public static let topTrailing: UnitPoint = UnitPoint(x: 1, y: 0)
    public static let bottomLeading: UnitPoint = UnitPoint(x: 0, y: 1)
    public static let bottomTrailing: UnitPoint = UnitPoint(x: 1, y: 1)
}

@frozen public struct Angle {
    public var radians: Double
    public var degrees: Double { get { radians * 180 / .pi } set { radians = newValue * .pi / 180 } }
    public init () { radians = 0 }
    public init (radians: Double) { self.radians = radians }
    public init (degrees: Double) { self.radians = degrees * .pi / 180 }
    public static func radians(_ radians: Double) -> Angle { Angle(radians: radians) }
    public static func degrees(_ degrees: Double) -> Angle { Angle(degrees: degrees) }
    public static var zero: Angle { Angle() }
    public static func < (lhs: Angle, rhs: Angle) -> Bool { lhs.radians < rhs.radians }
}

@frozen public struct HorizontalAlignment : Equatable {
    public static let leading: HorizontalAlignment = HorizontalAlignment()
    public static let center: HorizontalAlignment = HorizontalAlignment()
    public static let trailing: HorizontalAlignment = HorizontalAlignment()
}

@frozen public struct VerticalAlignment : Equatable {
    public static let top: VerticalAlignment = VerticalAlignment()
    public static let center: VerticalAlignment = VerticalAlignment()
    public static let bottom: VerticalAlignment = VerticalAlignment()
    public static let firstTextBaseline: VerticalAlignment = VerticalAlignment()
    public static let lastTextBaseline: VerticalAlignment = VerticalAlignment()
}

@frozen public struct Alignment : Equatable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment
    public init (horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
    public static let center: Alignment = Alignment(horizontal: .center, vertical: .center)
    public static let leading: Alignment = Alignment(horizontal: .leading, vertical: .center)
    public static let trailing: Alignment = Alignment(horizontal: .trailing, vertical: .center)
    public static let top: Alignment = Alignment(horizontal: .center, vertical: .top)
    public static let bottom: Alignment = Alignment(horizontal: .center, vertical: .bottom)
    public static let topLeading: Alignment = Alignment(horizontal: .leading, vertical: .top)
    public static let topTrailing: Alignment = Alignment(horizontal: .trailing, vertical: .top)
    public static let bottomLeading: Alignment = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottomTrailing: Alignment = Alignment(horizontal: .trailing, vertical: .bottom)
    public static var centerFirstTextBaseline: Alignment { Alignment(horizontal: .center, vertical: .firstTextBaseline) }
    public static var leadingFirstTextBaseline: Alignment { Alignment(horizontal: .leading, vertical: .firstTextBaseline) }
    public static var trailingFirstTextBaseline: Alignment { Alignment(horizontal: .trailing, vertical: .firstTextBaseline) }
}

@frozen public enum Edge : Int8, CaseIterable {
    case top, leading, bottom, trailing

    @frozen public struct Set : OptionSet {
        public typealias Element = Edge.Set
        public let rawValue: Int8
        public init (rawValue: Int8) { self.rawValue = rawValue }
        public init (_ e: Edge) { self.rawValue = 1 << e.rawValue }
        public static let top: Edge.Set = Edge.Set(.top)
        public static let leading: Edge.Set = Edge.Set(.leading)
        public static let bottom: Edge.Set = Edge.Set(.bottom)
        public static let trailing: Edge.Set = Edge.Set(.trailing)
        public static let all: Edge.Set = [.top, .leading, .bottom, .trailing]
        public static let horizontal: Edge.Set = [.leading, .trailing]
        public static let vertical: Edge.Set = [.top, .bottom]
    }
}

@frozen public enum VerticalEdge : Int8, CaseIterable, Codable {
    case top, bottom
}

@frozen public enum HorizontalEdge : Int8, CaseIterable, Codable {
    case leading, trailing
}

@frozen public struct EdgeInsets : Equatable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat
    public init (top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
    public init () { self.init(top: 0, leading: 0, bottom: 0, trailing: 0) }
}

@frozen public enum Axis : Int8, CaseIterable {
    case horizontal, vertical

    @frozen public struct Set : OptionSet {
        public typealias Element = Axis.Set
        public let rawValue: Int8
        public init (rawValue: Int8) { self.rawValue = rawValue }
        public static let horizontal: Axis.Set = Axis.Set(rawValue: 1)
        public static let vertical: Axis.Set = Axis.Set(rawValue: 2)
    }
}

@frozen public enum Visibility : Hashable, CaseIterable {
    case automatic, visible, hidden
}

@frozen public enum TextAlignment : Hashable, CaseIterable {
    case leading, center, trailing
}

public enum BlendMode : Sendable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight
    case difference, exclusion, hue, saturation, color, luminosity, sourceAtop, destinationOver
    case destinationOut, plusDarker, plusLighter
}

public enum ControlSize : CaseIterable, Sendable {
    case mini, small, regular, large, extraLarge
}

public enum RoundedCornerStyle : Sendable {
    case circular, continuous
}

@frozen public struct FillStyle : Equatable {
    public var isEOFilled: Bool
    public var isAntialiased: Bool
    public init (eoFill: Bool = false, antialiased: Bool = true) {
        isEOFilled = eoFill
        isAntialiased = antialiased
    }
}

@frozen public struct StrokeStyle : Equatable {
    public var lineWidth: CGFloat
    public var lineCap: CGLineCap
    public var lineJoin: CGLineJoin
    public var miterLimit: CGFloat
    public var dash: [CGFloat]
    public var dashPhase: CGFloat
    public init (lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter, miterLimit: CGFloat = 10, dash: [CGFloat] = [CGFloat](), dashPhase: CGFloat = 0) {
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.dash = dash
        self.dashPhase = dashPhase
    }
}

@frozen public struct SafeAreaRegions : OptionSet {
    public let rawValue: UInt
    public init (rawValue: UInt) { self.rawValue = rawValue }
    public static let container: SafeAreaRegions = SafeAreaRegions(rawValue: 1)
    public static let keyboard: SafeAreaRegions = SafeAreaRegions(rawValue: 2)
    public static let all: SafeAreaRegions = [.container, .keyboard]
}

public struct ContentShapeKinds : OptionSet, Sendable {
    public var rawValue: Int
    public init (rawValue: Int) { self.rawValue = rawValue }
    public static let interaction: ContentShapeKinds = ContentShapeKinds(rawValue: 1)
    public static let dragPreview: ContentShapeKinds = ContentShapeKinds(rawValue: 2)
    public static let contextMenuPreview: ContentShapeKinds = ContentShapeKinds(rawValue: 4)
    public static let hoverEffect: ContentShapeKinds = ContentShapeKinds(rawValue: 8)
    public static let accessibility: ContentShapeKinds = ContentShapeKinds(rawValue: 16)
}

public struct PinnedScrollableViews : OptionSet, Sendable {
    public let rawValue: UInt32
    public init (rawValue: UInt32) { self.rawValue = rawValue }
    public static let sectionHeaders: PinnedScrollableViews = PinnedScrollableViews(rawValue: 1)
    public static let sectionFooters: PinnedScrollableViews = PinnedScrollableViews(rawValue: 2)
}

// MARK: - Accessibility values

public struct AccessibilityTraits : SetAlgebra, Sendable {
    public typealias Element = AccessibilityTraits
    @usableFromInline var bits: UInt64
    @usableFromInline init(bits: UInt64) { self.bits = bits }
    public init () { bits = 0 }
    public func contains(_ member: AccessibilityTraits) -> Bool { bits & member.bits == member.bits }
    public func union(_ other: AccessibilityTraits) -> AccessibilityTraits { .init(bits: bits | other.bits) }
    public func intersection(_ other: AccessibilityTraits) -> AccessibilityTraits { .init(bits: bits & other.bits) }
    public func symmetricDifference(_ other: AccessibilityTraits) -> AccessibilityTraits { .init(bits: bits ^ other.bits) }
    public mutating func insert(_ newMember: AccessibilityTraits) -> (inserted: Bool, memberAfterInsert: AccessibilityTraits) {
        let had = contains(newMember)
        bits |= newMember.bits
        return (!had, newMember)
    }
    public mutating func remove(_ member: AccessibilityTraits) -> AccessibilityTraits? {
        let had = contains(member)
        bits &= ~member.bits
        return had ? member : nil
    }
    public mutating func update(with newMember: AccessibilityTraits) -> AccessibilityTraits? {
        let had = contains(newMember)
        bits |= newMember.bits
        return had ? newMember : nil
    }
    public mutating func formUnion(_ other: AccessibilityTraits) { bits |= other.bits }
    public mutating func formIntersection(_ other: AccessibilityTraits) { bits &= other.bits }
    public mutating func formSymmetricDifference(_ other: AccessibilityTraits) { bits ^= other.bits }

    public static let isButton: AccessibilityTraits = AccessibilityTraits(bits: 1 << 0)
    public static let isHeader: AccessibilityTraits = AccessibilityTraits(bits: 1 << 1)
    public static let isSelected: AccessibilityTraits = AccessibilityTraits(bits: 1 << 2)
    public static let isLink: AccessibilityTraits = AccessibilityTraits(bits: 1 << 3)
    public static let isSearchField: AccessibilityTraits = AccessibilityTraits(bits: 1 << 4)
    public static let isImage: AccessibilityTraits = AccessibilityTraits(bits: 1 << 5)
    public static let playsSound: AccessibilityTraits = AccessibilityTraits(bits: 1 << 6)
    public static let isKeyboardKey: AccessibilityTraits = AccessibilityTraits(bits: 1 << 7)
    public static let isStaticText: AccessibilityTraits = AccessibilityTraits(bits: 1 << 8)
    public static let isSummaryElement: AccessibilityTraits = AccessibilityTraits(bits: 1 << 9)
    public static let updatesFrequently: AccessibilityTraits = AccessibilityTraits(bits: 1 << 10)
    public static let startsMediaSession: AccessibilityTraits = AccessibilityTraits(bits: 1 << 11)
    public static let allowsDirectInteraction: AccessibilityTraits = AccessibilityTraits(bits: 1 << 12)
    public static let causesPageTurn: AccessibilityTraits = AccessibilityTraits(bits: 1 << 13)
    public static let isModal: AccessibilityTraits = AccessibilityTraits(bits: 1 << 14)
    public static let isToggle: AccessibilityTraits = AccessibilityTraits(bits: 1 << 15)
    public static let isTabBar: AccessibilityTraits = AccessibilityTraits(bits: 1 << 16)
}

public struct AccessibilityChildBehavior : Hashable, ~Sendable {
    public static let ignore: AccessibilityChildBehavior = AccessibilityChildBehavior(kind: 0)
    public static let contain: AccessibilityChildBehavior = AccessibilityChildBehavior(kind: 1)
    public static let combine: AccessibilityChildBehavior = AccessibilityChildBehavior(kind: 2)
    private let kind: Int
    private init(kind: Int) { self.kind = kind }
}

// MARK: - Animation and transitions

@frozen public struct Animation : Equatable, Sendable {
    public static let `default`: Animation = Animation()
    public static var easeInOut: Animation { Animation() }
    public static var easeIn: Animation { Animation() }
    public static var easeOut: Animation { Animation() }
    public static var linear: Animation { Animation() }
    public static var spring: Animation { Animation() }
    public static var smooth: Animation { Animation() }
    public static var snappy: Animation { Animation() }
    public static var bouncy: Animation { Animation() }
    public static func easeInOut(duration: TimeInterval) -> Animation { Animation() }
    public static func easeIn(duration: TimeInterval) -> Animation { Animation() }
    public static func easeOut(duration: TimeInterval) -> Animation { Animation() }
    public static func linear(duration: TimeInterval) -> Animation { Animation() }
    @_disfavoredOverload public static func spring(response: Double = 0.5, dampingFraction: Double = 0.825, blendDuration: TimeInterval = 0) -> Animation { Animation() }
    public static func spring(duration: TimeInterval = 0.5, bounce: Double = 0.0, blendDuration: Double = 0) -> Animation { Animation() }
    public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation { Animation() }
    public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation { Animation() }
    public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation { Animation() }
    public func delay(_ delay: TimeInterval) -> Animation { self }
    public func speed(_ speed: Double) -> Animation { self }
    public func repeatForever(autoreverses: Bool = true) -> Animation { self }
    public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation { self }
}

@frozen public struct AnyTransition : ~Sendable {
    nonisolated(unsafe) public static var opacity: AnyTransition { AnyTransition() }
    public static var identity: AnyTransition { AnyTransition() }
    public static var slide: AnyTransition { AnyTransition() }
    public static var scale: AnyTransition { AnyTransition() }
    public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition { AnyTransition() }
    public static func move(edge: Edge) -> AnyTransition { AnyTransition() }
    public static func push(from edge: Edge) -> AnyTransition { AnyTransition() }
    public static func offset(_ offset: CGSize) -> AnyTransition { AnyTransition() }
    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition { AnyTransition() }
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition { AnyTransition() }
    public func combined(with other: AnyTransition) -> AnyTransition { self }
    public func animation(_ animation: Animation?) -> AnyTransition { self }
}

/// HARNESS: requirements omitted (the apps only use the built-in transitions).
@preconcurrency @MainActor public protocol Transition {}

nonisolated public struct OpacityTransition : Transition, ~Sendable {
    nonisolated public init () {}
}
extension Transition where Self == OpacityTransition {
    @MainActor @preconcurrency public static var opacity: OpacityTransition { OpacityTransition() }
}

// MARK: - Shapes

public protocol Animatable {}

@frozen public struct Path : Equatable, @unchecked Sendable {
    public init () {}
    public init (_ rect: CGRect) {}
    public init (roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {}
    public init (ellipseIn rect: CGRect) {}
    public init (_ callback: (inout Path) -> ()) {}
    public mutating func move(to end: CGPoint) {}
    public mutating func addLine(to end: CGPoint) {}
    public mutating func addRect(_ rect: CGRect) {}
    public mutating func addEllipse(in rect: CGRect) {}
    public mutating func closeSubpath() {}
}

nonisolated public protocol Shape : Sendable, Animatable, View {
    nonisolated func path(in rect: CGRect) -> Path
}

public protocol InsettableShape : Shape {
    associatedtype InsetShape: InsettableShape
    nonisolated func inset(by amount: CGFloat) -> Self.InsetShape
}

@frozen
public struct _ShapeView<Content: Shape, Style: ShapeStyle> {}
extension _ShapeView: View { public typealias Body = Never }

@frozen nonisolated public struct StrokeShapeView<Content, Style, Background> : ~Sendable where Content : Shape, Style : ShapeStyle, Background : View {}
extension StrokeShapeView: View { public typealias Body = Never }

@frozen nonisolated public struct StrokeBorderShapeView<Content, Style, Background> : ~Sendable where Content : InsettableShape, Style : ShapeStyle, Background : View {}
extension StrokeBorderShapeView: View { public typealias Body = Never }

extension Shape {
    public var body: _ShapeView<Self, ForegroundStyle> { _ShapeView() }
}

/// A shape value produced by the shape modifiers (`trim`, `stroke(style:)`, `rotation`...).
@frozen
public struct _ModifiedShape<Base: Shape>: Sendable {}
extension _ModifiedShape: Shape {
    nonisolated public func path(in rect: CGRect) -> Path { Path() }
}
@frozen public struct OffsetShape<Content> : Shape where Content : Shape {
    nonisolated public func path(in rect: CGRect) -> Path { Path() }
}
@frozen public struct ScaledShape<Content> : Shape where Content : Shape {
    nonisolated public func path(in rect: CGRect) -> Path { Path() }
}
@frozen public struct RotatedShape<Content> : Shape where Content : Shape {
    nonisolated public func path(in rect: CGRect) -> Path { Path() }
}

extension Shape {
    nonisolated public func fill<S>(_ content: S = .foreground, style: FillStyle = FillStyle()) -> _ShapeView<Self, S> where S : ShapeStyle { _ShapeView() }
    @_disfavoredOverload nonisolated public func fill(style: FillStyle = FillStyle()) -> some View { _ShapeView<Self, ForegroundStyle>() }
    nonisolated public func stroke<S>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> StrokeShapeView<Self, S, EmptyView> where S : ShapeStyle { StrokeShapeView() }
    nonisolated public func stroke<S>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> StrokeShapeView<Self, S, EmptyView> where S : ShapeStyle { StrokeShapeView() }
    nonisolated public func stroke(style: StrokeStyle) -> some Shape { _ModifiedShape<Self>() }
    nonisolated public func stroke(lineWidth: CGFloat = 1) -> some Shape { _ModifiedShape<Self>() }
    nonisolated public func trim(from startFraction: CGFloat = 0, to endFraction: CGFloat = 1) -> some Shape { _ModifiedShape<Self>() }
    nonisolated public func rotation(_ angle: Angle, anchor: UnitPoint = .center) -> RotatedShape<Self> { RotatedShape() }
    nonisolated public func offset(x: CGFloat = 0, y: CGFloat = 0) -> OffsetShape<Self> { OffsetShape() }
    nonisolated public func scale(_ scale: CGFloat, anchor: UnitPoint = .center) -> ScaledShape<Self> { ScaledShape() }
}

extension InsettableShape {
    nonisolated public func strokeBorder<S>(_ content: S = .foreground, style: StrokeStyle, antialiased: Bool = true) -> StrokeBorderShapeView<Self, S, EmptyView> where S : ShapeStyle { StrokeBorderShapeView() }
    nonisolated public func strokeBorder<S>(_ content: S = .foreground, lineWidth: CGFloat = 1, antialiased: Bool = true) -> StrokeBorderShapeView<Self, S, EmptyView> where S : ShapeStyle { StrokeBorderShapeView() }
}

@frozen public struct Circle : Shape {
    public init () {}
}
extension Circle: InsettableShape {
    nonisolated public func path(in rect: CGRect) -> Path { Path() }
    nonisolated public func inset(by amount: CGFloat) -> some InsettableShape { self }
}

@frozen public struct Capsule : Shape {
    public var style: RoundedCornerStyle
    public init (style: RoundedCornerStyle = .continuous) { self.style = style }
}
extension Capsule: InsettableShape {
    nonisolated public func path(in r: CGRect) -> Path { Path() }
    nonisolated public func inset(by amount: CGFloat) -> some InsettableShape { self }
}

@frozen public struct Rectangle : Shape {
    public init () {}
}
extension Rectangle: InsettableShape {
    nonisolated public func path(in rect: CGRect) -> Path { Path() }
    nonisolated public func inset(by amount: CGFloat) -> some InsettableShape { self }
}

@frozen public struct RoundedRectangle : Shape {
    public var cornerSize: CGSize
    public var style: RoundedCornerStyle
    public init (cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
        self.cornerSize = cornerSize
        self.style = style
    }
    public init (cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.cornerSize = CGSize(width: cornerRadius, height: cornerRadius)
        self.style = style
    }
}
extension RoundedRectangle: InsettableShape {
    nonisolated public func path(in rect: CGRect) -> Path { Path() }
    nonisolated public func inset(by amount: CGFloat) -> some InsettableShape { self }
}

extension Shape where Self == Rectangle {
    public static var rect: Rectangle { Rectangle() }
}
extension Shape where Self == Circle {
    public static var circle: Circle { Circle() }
}
extension Shape where Self == Capsule {
    public static var capsule: Capsule { Capsule() }
}
extension Shape where Self == RoundedRectangle {
    public static func rect(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) -> Self {
        RoundedRectangle(cornerRadius: cornerRadius, style: style)
    }
}

@frozen public struct Ellipse : Shape {
    public init () {}
}
extension Ellipse: InsettableShape {
    nonisolated public func path(in rect: CGRect) -> Path { Path() }
    nonisolated public func inset(by amount: CGFloat) -> some InsettableShape { self }
}

// MARK: - Images

@frozen public struct Image : Equatable, Sendable {
    public enum ResizingMode : Sendable { case tile, stretch }
    public enum TemplateRenderingMode : Sendable { case template, original }
    public enum Scale : Hashable, Sendable { case small, medium, large }
    public enum Interpolation : Sendable { case none, low, medium, high }

    public init (_ name: String, bundle: Bundle? = nil) {}
    public init (_ name: String, bundle: Bundle? = nil, label: Text) {}
    public init (decorative name: String, bundle: Bundle? = nil) {}
    public init (systemName: String) {}
    public init (systemName: String, variableValue: Double?) {}
    public init (uiImage: UIImage) {}

    public static func == (a: Image, b: Image) -> Bool { true }

    public func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: Image.ResizingMode = .stretch) -> Image { self }
    public func renderingMode(_ renderingMode: Image.TemplateRenderingMode?) -> Image { self }
    public func interpolation(_ interpolation: Image.Interpolation) -> Image { self }
    public func antialiased(_ isAntialiased: Bool) -> Image { self }
}
extension Image: View { public typealias Body = Never }

// MARK: - Containers and controls

@frozen nonisolated public struct VStack<Content> : View, ~Sendable where Content : View {
    nonisolated public init (alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ContentBuilder content: () -> Content) {}
    public typealias Body = Never
}

@frozen nonisolated public struct HStack<Content> : View, ~Sendable where Content : View {
    nonisolated public init (alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ContentBuilder content: () -> Content) {}
    public typealias Body = Never
}

@frozen nonisolated public struct ZStack<Content> : View, ~Sendable where Content : View {
    nonisolated public init (alignment: Alignment = .center, @ContentBuilder content: () -> Content) {}
    public typealias Body = Never
}

public struct GridItem : Sendable {
    public enum Size : Sendable {
        case fixed(CGFloat)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }
    public var size: GridItem.Size
    public var spacing: CGFloat?
    public var alignment: Alignment?
    public init (_ size: GridItem.Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}

nonisolated public struct LazyVGrid<Content> : View, ~Sendable where Content : View {
    nonisolated public init (columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ContentBuilder content: () -> Content) {}
    public typealias Body = Never
}

nonisolated public struct LazyHGrid<Content> : View, ~Sendable where Content : View {
    nonisolated public init (rows: [GridItem], alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ContentBuilder content: () -> Content) {}
    public typealias Body = Never
}

nonisolated public struct LazyVStack<Content> : View, ~Sendable where Content : View {
    nonisolated public init (alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ContentBuilder content: () -> Content) {}
    public typealias Body = Never
}

nonisolated public struct LazyHStack<Content> : View, ~Sendable where Content : View {
    nonisolated public init (alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ContentBuilder content: () -> Content) {}
    public typealias Body = Never
}

nonisolated public struct ScrollView<Content> : View, ~Sendable where Content : View {
    nonisolated public init (_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ContentBuilder content: () -> Content) {}
    public typealias Body = Never
}

@frozen public struct Spacer {
    public var minLength: CGFloat?
    public init (minLength: CGFloat? = nil) { self.minLength = minLength }
    public typealias Body = Never
}

nonisolated public struct Divider : View, ~Sendable {
    nonisolated public init () {}
    public typealias Body = Never
}

// cloudcheck:verbatim-begin
@frozen public struct Group<Content>: ~Sendable {
    public typealias Body = Never
}
extension Group {
    nonisolated public init(@ContentBuilder content: () -> Content) {}
}
extension Group: View where Content: View {}
extension Group: Scene where Content: Scene {
    @_disfavoredOverload nonisolated public init(@SceneBuilder content: () -> Content) {}
}
extension Group: ToolbarContent where Content: ToolbarContent {}
// cloudcheck:verbatim-end

public struct ForEach<Data, ID, Content> : ~Sendable where Data : RandomAccessCollection, ID : Hashable {
    public var data: Data
    public var content: (Data.Element) -> Content
}
extension ForEach: View where Content: View { public typealias Body = Never }
extension ForEach where ID == Data.Element.ID, Content: View, Data.Element: Identifiable {
    public init (_ data: Data, @ContentBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }
}
extension ForEach where Content: View {
    public init (_ data: Data, id: KeyPath<Data.Element, ID>, @ContentBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }
}
extension ForEach where Data == Range<Int>, ID == Int, Content: View {
    public init (_ data: Range<Int>, @ContentBuilder content: @escaping (Int) -> Content) {
        self.data = data
        self.content = content
    }
}

public struct GeometryProxy : ~Sendable {
    public var size: CGSize { _stub() }
    public var safeAreaInsets: EdgeInsets { _stub() }
    @_disfavoredOverload public func frame(in coordinateSpace: CoordinateSpace) -> CGRect { _stub() }
}

public enum CoordinateSpace : ~Sendable {
    case global
    case local
    case named(AnyHashable)
}

@frozen nonisolated public struct GeometryReader<Content> : View, ~Sendable where Content : View {
    public var content: (GeometryProxy) -> Content
    nonisolated public init (@ContentBuilder content: @escaping (GeometryProxy) -> Content) { self.content = content }
    public typealias Body = Never
}

public struct ButtonRole : Equatable, Sendable {
    public static let destructive: ButtonRole = ButtonRole(kind: 0)
    public static let cancel: ButtonRole = ButtonRole(kind: 1)
    private let kind: Int
    private init(kind: Int) { self.kind = kind }
}

nonisolated public struct Button<Label> : View, ~Sendable where Label : View {
    @preconcurrency nonisolated public init (action: @escaping @MainActor () -> Void, @ContentBuilder label: () -> Label) {}
    @preconcurrency nonisolated public init (role: ButtonRole?, action: @escaping @MainActor () -> Void, @ContentBuilder label: () -> Label) {}
    public typealias Body = Never
}
extension Button where Label == Text {
    @preconcurrency nonisolated public init (_ titleKey: LocalizedStringKey, action: @escaping @MainActor () -> Void) {}
    @preconcurrency @_disfavoredOverload nonisolated public init <S>(_ title: S, action: @escaping @MainActor () -> Void) where S : StringProtocol {}
    @preconcurrency nonisolated public init (_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping @MainActor () -> Void) {}
    @preconcurrency @_disfavoredOverload nonisolated public init <S>(_ title: S, role: ButtonRole?, action: @escaping @MainActor () -> Void) where S : StringProtocol {}
}
extension Button where Label == SwiftUI.Label<Text, Image> {
    nonisolated public init (_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping @MainActor () -> Void) {}
    @_disfavoredOverload nonisolated public init <S>(_ title: S, systemImage: String, action: @escaping @MainActor () -> Void) where S : StringProtocol {}
    nonisolated public init (_ titleKey: LocalizedStringKey, systemImage: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {}
}

nonisolated public struct Label<Title, Icon> : View, ~Sendable where Title : View, Icon : View {
    nonisolated public init (@ContentBuilder title: () -> Title, @ContentBuilder icon: () -> Icon) {}
    public typealias Body = Never
}
extension Label where Title == Text, Icon == Image {
    nonisolated public init (_ titleKey: LocalizedStringKey, systemImage name: String) {}
    @_disfavoredOverload nonisolated public init <S>(_ title: S, systemImage name: String) where S : StringProtocol {}
    nonisolated public init (_ titleKey: LocalizedStringKey, image name: String) {}
    @_disfavoredOverload nonisolated public init <S>(_ title: S, image name: String) where S : StringProtocol {}
}

nonisolated public struct Toggle<Label> : View, ~Sendable where Label : View {
    nonisolated public init (isOn: Binding<Bool>, @ContentBuilder label: () -> Label) {}
    public typealias Body = Never
}
extension Toggle where Label == Text {
    nonisolated public init (_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) {}
    @_disfavoredOverload nonisolated public init <S>(_ title: S, isOn: Binding<Bool>) where S : StringProtocol {}
}

nonisolated public struct TextField<Label> : View, ~Sendable where Label : View {
    nonisolated public init (text: Binding<String>, prompt: Text? = nil, @ContentBuilder label: () -> Label) {}
    nonisolated public init (text: Binding<String>, prompt: Text? = nil, axis: Axis, @ContentBuilder label: () -> Label) {}
    public typealias Body = Never
}
extension TextField where Label == Text {
    nonisolated public init (_ titleKey: LocalizedStringKey, text: Binding<String>) {}
    @_disfavoredOverload nonisolated public init <S>(_ title: S, text: Binding<String>) where S : StringProtocol {}
    nonisolated public init (_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) {}
    @_disfavoredOverload nonisolated public init <S>(_ title: S, text: Binding<String>, prompt: Text?) where S : StringProtocol {}
    nonisolated public init (_ titleKey: LocalizedStringKey, text: Binding<String>, axis: Axis) {}
    @_disfavoredOverload nonisolated public init <S>(_ title: S, text: Binding<String>, axis: Axis) where S : StringProtocol {}
    nonisolated public init (_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?, axis: Axis) {}
    @_disfavoredOverload nonisolated public init <S>(_ title: S, text: Binding<String>, prompt: Text?, axis: Axis) where S : StringProtocol {}
}

nonisolated public struct SecureField<Label> : View, ~Sendable where Label : View {
    public typealias Body = Never
}
extension SecureField where Label == Text {
    nonisolated public init (_ titleKey: LocalizedStringKey, text: Binding<String>) {}
    @_disfavoredOverload nonisolated public init <S>(_ title: S, text: Binding<String>) where S : StringProtocol {}
}

public struct DatePickerComponents : OptionSet, Sendable {
    public let rawValue: UInt
    public init (rawValue: UInt) { self.rawValue = rawValue }
    public static let hourAndMinute: DatePickerComponents = DatePickerComponents(rawValue: 1)
    public static let date: DatePickerComponents = DatePickerComponents(rawValue: 2)
}

nonisolated public struct DatePicker<Label> : View, ~Sendable where Label : View {
    public typealias Components = DatePickerComponents
    nonisolated public init (selection: Binding<Date>, displayedComponents: DatePicker<Label>.Components = [.hourAndMinute, .date], @ContentBuilder label: () -> Label) {}
    nonisolated public init (selection: Binding<Date>, in range: ClosedRange<Date>, displayedComponents: DatePicker<Label>.Components = [.hourAndMinute, .date], @ContentBuilder label: () -> Label) {}
    nonisolated public init (selection: Binding<Date>, in range: PartialRangeFrom<Date>, displayedComponents: DatePicker<Label>.Components = [.hourAndMinute, .date], @ContentBuilder label: () -> Label) {}
    nonisolated public init (selection: Binding<Date>, in range: PartialRangeThrough<Date>, displayedComponents: DatePicker<Label>.Components = [.hourAndMinute, .date], @ContentBuilder label: () -> Label) {}
    public typealias Body = Never
}
extension DatePicker where Label == Text {
    nonisolated public init (_ titleKey: LocalizedStringKey, selection: Binding<Date>, displayedComponents: DatePicker<Label>.Components = [.hourAndMinute, .date]) {}
    nonisolated public init (_ titleKey: LocalizedStringKey, selection: Binding<Date>, in range: ClosedRange<Date>, displayedComponents: DatePicker<Label>.Components = [.hourAndMinute, .date]) {}
    nonisolated public init (_ titleKey: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeFrom<Date>, displayedComponents: DatePicker<Label>.Components = [.hourAndMinute, .date]) {}
    nonisolated public init (_ titleKey: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeThrough<Date>, displayedComponents: DatePicker<Label>.Components = [.hourAndMinute, .date]) {}
    @_disfavoredOverload nonisolated public init <S>(_ title: S, selection: Binding<Date>, displayedComponents: DatePicker<Label>.Components = [.hourAndMinute, .date]) where S : StringProtocol {}
    @_disfavoredOverload nonisolated public init <S>(_ title: S, selection: Binding<Date>, in range: ClosedRange<Date>, displayedComponents: DatePicker<Label>.Components = [.hourAndMinute, .date]) where S : StringProtocol {}
}

nonisolated public struct Picker<Label, SelectionValue, Content> : View, ~Sendable where Label : View, SelectionValue : Hashable, Content : View {
    nonisolated public init (selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content, @ContentBuilder label: () -> Label) {}
    public typealias Body = Never
}
extension Picker where Label == Text {
    nonisolated public init (_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content) {}
    @_disfavoredOverload nonisolated public init <S>(_ title: S, selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content) where S : StringProtocol {}
}

nonisolated public struct ProgressView<Label, CurrentValueLabel> : View, ~Sendable where Label : View, CurrentValueLabel : View {
    public typealias Body = Never
}
extension ProgressView where Label == EmptyView, CurrentValueLabel == EmptyView {
    nonisolated public init () where Label == EmptyView {}
    nonisolated public init <V>(value: V?, total: V = 1.0) where Label == EmptyView, CurrentValueLabel == EmptyView, V : BinaryFloatingPoint {}
}
extension ProgressView where CurrentValueLabel == EmptyView {
    nonisolated public init (@ContentBuilder label: () -> Label) {}
}
extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
    nonisolated public init (_ titleKey: LocalizedStringKey) where Label == Text {}
    @_disfavoredOverload nonisolated public init <S>(_ title: S) where Label == Text, S : StringProtocol {}
}

// MARK: - Lists, forms, menus

nonisolated public struct List<SelectionValue, Content> : View, ~Sendable where SelectionValue : Hashable, Content : View {
    public typealias Body = Never
}
extension List where SelectionValue == Never {
    nonisolated public init (@ContentBuilder content: () -> Content) {}
    nonisolated public init <Data, RowContent>(_ data: Data, @ContentBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable {}
    nonisolated public init <Data, ID, RowContent>(_ data: Data, id: KeyPath<Data.Element, ID>, @ContentBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, ID, RowContent>, Data : RandomAccessCollection, ID : Hashable, RowContent : View {}
}

public struct Section<Parent, Content, Footer> : ~Sendable {}
extension Section: View where Parent: View, Content: View, Footer: View {
    public typealias Body = Never
    public init (@ContentBuilder content: () -> Content, @ContentBuilder header: () -> Parent, @ContentBuilder footer: () -> Footer) {}
}
extension Section where Parent == EmptyView, Content: View, Footer == EmptyView {
    public init (@ContentBuilder content: () -> Content) {}
}
extension Section where Parent: View, Content: View, Footer == EmptyView {
    public init (@ContentBuilder content: () -> Content, @ContentBuilder header: () -> Parent) {}
}
extension Section where Parent == EmptyView, Content: View, Footer: View {
    public init (@ContentBuilder content: () -> Content, @ContentBuilder footer: () -> Footer) {}
}
extension Section where Parent == Text, Content: View, Footer == EmptyView {
    public init (_ titleKey: LocalizedStringKey, @ContentBuilder content: () -> Content) {}
    @_disfavoredOverload public init <S>(_ title: S, @ContentBuilder content: () -> Content) where S : StringProtocol {}
}

nonisolated public struct Form<Content> : View, ~Sendable where Content : View {
    nonisolated public init (@ContentBuilder content: () -> Content) {}
    public typealias Body = Never
}

nonisolated public struct Menu<Label, Content> : View, ~Sendable where Label : View, Content : View {
    nonisolated public init (@ContentBuilder content: () -> Content, @ContentBuilder label: () -> Label) {}
    public typealias Body = Never
}
extension Menu where Label == Text {
    nonisolated public init (_ titleKey: LocalizedStringKey, @ContentBuilder content: () -> Content) where Label == Text {}
    @_disfavoredOverload nonisolated public init <S>(_ title: S, @ContentBuilder content: () -> Content) where Label == Text, S : StringProtocol {}
}

/// HARNESS: requirements omitted (the apps only use the built-in list styles).
public protocol ListStyle {}
public struct PlainListStyle : ListStyle, ~Sendable { public init() {} }
public struct GroupedListStyle : ListStyle, ~Sendable { public init() {} }
public struct InsetListStyle : ListStyle, ~Sendable { public init() {} }
public struct InsetGroupedListStyle : ListStyle, ~Sendable { public init() {} }
public struct SidebarListStyle : ListStyle, ~Sendable { public init() {} }
public struct DefaultListStyle : ListStyle, ~Sendable { public init() {} }
extension ListStyle where Self == PlainListStyle { public static var plain: PlainListStyle { PlainListStyle() } }
extension ListStyle where Self == GroupedListStyle { public static var grouped: GroupedListStyle { GroupedListStyle() } }
extension ListStyle where Self == InsetListStyle { public static var inset: InsetListStyle { InsetListStyle() } }
extension ListStyle where Self == InsetGroupedListStyle { public static var insetGrouped: InsetGroupedListStyle { InsetGroupedListStyle() } }
extension ListStyle where Self == SidebarListStyle { public static var sidebar: SidebarListStyle { SidebarListStyle() } }
extension ListStyle where Self == DefaultListStyle { public static var automatic: DefaultListStyle { DefaultListStyle() } }

public enum NavigationBarItem {
    public enum TitleDisplayMode : Sendable {
        case automatic, inline, large
    }
}

extension View {
    nonisolated public func navigationTitle(_ title: Text) -> some View { self }
    nonisolated public func navigationTitle(_ titleKey: LocalizedStringKey) -> some View { self }
    @_disfavoredOverload nonisolated public func navigationTitle<S>(_ title: S) -> some View where S : StringProtocol { self }
    nonisolated public func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View { self }
    nonisolated public func listStyle<S>(_ style: S) -> some View where S : ListStyle { self }
    nonisolated public func alert<A>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ContentBuilder actions: () -> A) -> some View where A : View { self }
    nonisolated public func alert<A, M>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ContentBuilder actions: () -> A, @ContentBuilder message: () -> M) -> some View where A : View, M : View { self }
    @_disfavoredOverload nonisolated public func alert<S, A>(_ title: S, isPresented: Binding<Bool>, @ContentBuilder actions: () -> A) -> some View where S : StringProtocol, A : View { self }
    @_disfavoredOverload nonisolated public func alert<S, A, M>(_ title: S, isPresented: Binding<Bool>, @ContentBuilder actions: () -> A, @ContentBuilder message: () -> M) -> some View where S : StringProtocol, A : View, M : View { self }
    nonisolated public func confirmationDialog<A>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ContentBuilder actions: () -> A) -> some View where A : View { self }
    nonisolated public func confirmationDialog<A, M>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ContentBuilder actions: () -> A, @ContentBuilder message: () -> M) -> some View where A : View, M : View { self }
}

// MARK: - Navigation

public struct NavigationPath : ~Sendable {
    public init () {}
    public var count: Int { 0 }
    public var isEmpty: Bool { true }
    public mutating func append<V>(_ value: V) where V : Hashable {}
    public mutating func removeLast(_ k: Int = 1) {}
    public static func == (a: NavigationPath, b: NavigationPath) -> Bool { true }
}

nonisolated public struct NavigationStack<Data, Root> : View, ~Sendable where Root : View {
    public typealias Body = Never
}
extension NavigationStack where Data == NavigationPath {
    nonisolated public init (@ContentBuilder root: () -> Root) where Data == NavigationPath {}
    nonisolated public init (path: Binding<NavigationPath>, @ContentBuilder root: () -> Root) where Data == NavigationPath {}
}
extension NavigationStack where Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection, Data.Element: Hashable {
    nonisolated public init (path: Binding<Data>, @ContentBuilder root: () -> Root) where Data : MutableCollection, Data : RandomAccessCollection, Data : RangeReplaceableCollection, Data.Element : Hashable {}
}

nonisolated public struct NavigationLink<Label, Destination> : View, ~Sendable where Label : View, Destination : View {
    nonisolated public init (@ContentBuilder destination: () -> Destination, @ContentBuilder label: () -> Label) {}
    public typealias Body = Never
}
extension NavigationLink where Destination == Never {
    nonisolated public init <P>(value: P?, @ContentBuilder label: () -> Label) where P : Hashable {}
}
extension NavigationLink where Label == Text, Destination == Never {
    nonisolated public init <P>(_ titleKey: LocalizedStringKey, value: P?) where Label == Text, P : Hashable {}
    @_disfavoredOverload nonisolated public init <S, P>(_ title: S, value: P?) where Label == Text, S : StringProtocol, P : Hashable {}
}

public struct ToolbarPlacement : ~Sendable {
    private init() {}
    public static var automatic: ToolbarPlacement { ToolbarPlacement() }
    public static var bottomBar: ToolbarPlacement { ToolbarPlacement() }
    public static var navigationBar: ToolbarPlacement { ToolbarPlacement() }
    public static var tabBar: ToolbarPlacement { ToolbarPlacement() }
}

public struct ToolbarItemPlacement : ~Sendable {
    private init() {}
    public static let automatic: ToolbarItemPlacement = ToolbarItemPlacement()
    public static let principal: ToolbarItemPlacement = ToolbarItemPlacement()
    public static let navigation: ToolbarItemPlacement = ToolbarItemPlacement()
    public static let primaryAction: ToolbarItemPlacement = ToolbarItemPlacement()
    public static let secondaryAction: ToolbarItemPlacement = ToolbarItemPlacement()
    public static let status: ToolbarItemPlacement = ToolbarItemPlacement()
    public static let confirmationAction: ToolbarItemPlacement = ToolbarItemPlacement()
    public static let cancellationAction: ToolbarItemPlacement = ToolbarItemPlacement()
    public static let destructiveAction: ToolbarItemPlacement = ToolbarItemPlacement()
    public static let keyboard: ToolbarItemPlacement = ToolbarItemPlacement()
    public static var topBarLeading: ToolbarItemPlacement { ToolbarItemPlacement() }
    public static var topBarTrailing: ToolbarItemPlacement { ToolbarItemPlacement() }
    public static let bottomBar: ToolbarItemPlacement = ToolbarItemPlacement()
}

// cloudcheck:verbatim-begin (written from the iOS 27 SDK interface by hand; the stub audit leaves it alone)
@preconcurrency @MainActor public protocol ToolbarContent {
    associatedtype Body: ToolbarContent
    @ContentBuilder @MainActor @preconcurrency var body: Self.Body { get }
}
public protocol CustomizableToolbarContent: ToolbarContent where Self.Body: CustomizableToolbarContent {}
extension ToolbarContent where Self.Body == Never {
    public var body: Never { fatalError("primitive toolbar content") }
}
extension Never: ToolbarContent, CustomizableToolbarContent {}
extension Optional: ToolbarContent where Wrapped: ToolbarContent {}
extension _ConditionalContent: ToolbarContent where TrueContent: ToolbarContent, FalseContent: ToolbarContent {}

// Internal in the SDK as well; the builders return `some ToolbarContent`.
nonisolated struct TupleToolbarContent<T>: ToolbarContent, CustomizableToolbarContent, ~Sendable {
    typealias Body = Never
    init(_ value: T) {}
}

// SDK 27: toolbar(content:) and ToolbarContent.body use ContentBuilder (ViewBuilder), extended in SwiftUI:
extension ViewBuilder {
    @_disfavoredOverload public static func buildLimitedAvailability(_ content: any ToolbarContent) -> some ToolbarContent { TupleToolbarContent(()) }
    @_disfavoredOverload public static func buildLimitedAvailability(_ content: any CustomizableToolbarContent) -> some CustomizableToolbarContent { TupleToolbarContent(()) }
    @_disfavoredOverload public static func buildBlock<each Content>(_ content: repeat each Content) -> some ToolbarContent where repeat each Content: ToolbarContent {
        TupleToolbarContent((repeat each content))
    }
    @_disfavoredOverload public static func buildBlock<each Content>(_ content: repeat each Content) -> some CustomizableToolbarContent where repeat each Content: CustomizableToolbarContent {
        TupleToolbarContent((repeat each content))
    }
}

// Still in the SDK (with fixed-arity buildBlock overloads for 2...10 elements, modelled here by one pack).
@resultBuilder public struct ToolbarContentBuilder: ~Sendable {
    public static func buildExpression<Content>(_ content: Content) -> Content where Content: ToolbarContent { content }
    public static func buildBlock<Content>(_ content: Content) -> some ToolbarContent where Content: ToolbarContent { content }
    public static func buildBlock<each Content>(_ content: repeat each Content) -> some ToolbarContent where repeat each Content: ToolbarContent {
        TupleToolbarContent((repeat each content))
    }
}
extension ToolbarContentBuilder {
    public static func buildIf<Content>(_ content: Content?) -> Content? where Content: ToolbarContent { content }
    public static func buildEither<TrueContent, FalseContent>(first: TrueContent) -> _ConditionalContent<TrueContent, FalseContent> where TrueContent: ToolbarContent, FalseContent: ToolbarContent {
        _ConditionalContent(storage: .trueContent(first))
    }
    public static func buildEither<TrueContent, FalseContent>(second: FalseContent) -> _ConditionalContent<TrueContent, FalseContent> where TrueContent: ToolbarContent, FalseContent: ToolbarContent {
        _ConditionalContent(storage: .falseContent(second))
    }
}

nonisolated public struct ToolbarItemGroup<Content>: ToolbarContent, ~Sendable where Content: View {
    nonisolated public init(placement: ToolbarItemPlacement = .automatic, @ContentBuilder content: () -> Content) {}
    public typealias Body = Never
}

nonisolated public struct ToolbarItem<ID, Content>: ToolbarContent, ~Sendable where Content: View {
    public typealias Body = Never
}
extension ToolbarItem where ID == () {
    nonisolated public init(placement: ToolbarItemPlacement = .automatic, @ContentBuilder content: () -> Content) {}
}
extension ToolbarItem: CustomizableToolbarContent where ID == String {
    nonisolated public init(id: String, placement: ToolbarItemPlacement = .automatic, @ContentBuilder content: () -> Content) {}
}
extension ToolbarItem: Identifiable where ID: Hashable {
    nonisolated public var id: ID { fatalError() }
}

// cloudcheck:verbatim-end

// cloudcheck:verbatim-begin (written from the iOS 27 SDK interface by hand; the stub audit leaves it alone)
// MARK: - Tabs (iOS 18 TabContent API)

@preconcurrency @MainActor public protocol TabContent<TabValue> {
    associatedtype TabValue: Hashable where Self.TabValue == Self.Body.TabValue
    associatedtype Body: TabContent
    @TabContentBuilder<Self.TabValue> @MainActor @preconcurrency var body: Self.Body { get }
}
extension Never: TabContent {
    public typealias TabValue = Never
}
extension _ConditionalContent: TabContent where TrueContent: TabContent, FalseContent: TabContent, TrueContent.TabValue == FalseContent.TabValue {
    public typealias TabValue = TrueContent.TabValue
    @MainActor @preconcurrency public var body: _ConditionalContent<TrueContent, FalseContent> { return self }
}
extension Optional: TabContent where Wrapped: TabContent {
    public typealias TabValue = Wrapped.TabValue
    @MainActor @preconcurrency public var body: Optional<Wrapped> { return self }
}

nonisolated public struct DefaultTabLabel: View, ~Sendable {
    public typealias Body = Never
}

public struct Tab<Value, Content, Label>: ~Sendable {}
extension Tab: TabContent where Value: Hashable, Content: View, Label: View {
    public typealias TabValue = Value
    @_disfavoredOverload nonisolated public init<S>(_ title: S, image: String, value: Value, @ContentBuilder content: () -> Content) where Label == DefaultTabLabel, S: StringProtocol {}
    nonisolated public init(_ titleKey: LocalizedStringKey, image: String, value: Value, @ContentBuilder content: () -> Content) where Label == DefaultTabLabel {}
    @_disfavoredOverload nonisolated public init<S>(_ title: S, systemImage: String, value: Value, @ContentBuilder content: () -> Content) where Label == DefaultTabLabel, S: StringProtocol {}
    @_disfavoredOverload nonisolated public init<S, T>(_ title: S, systemImage: String, value: T, @ContentBuilder content: () -> Content) where Value == T?, Label == DefaultTabLabel, S: StringProtocol, T: Hashable {}
    nonisolated public init(_ titleKey: LocalizedStringKey, systemImage: String, value: Value, @ContentBuilder content: () -> Content) where Label == DefaultTabLabel {}
    nonisolated public init<T>(_ titleKey: LocalizedStringKey, systemImage: String, value: T, @ContentBuilder content: () -> Content) where Value == T?, Label == DefaultTabLabel, T: Hashable {}
    nonisolated public init(value: Value, @ContentBuilder content: () -> Content) where Label == EmptyView {}
    nonisolated public init(value: Value, @ContentBuilder content: () -> Content, @ContentBuilder label: () -> Label) {}
    public typealias Body = Tab<Value, Content, Label>
    @MainActor @preconcurrency public var body: Tab<Value, Content, Label> { return self }
}
extension Tab where Value == Never, Content: View, Label: View {
    @_disfavoredOverload public init<S>(_ title: S, systemImage: String, @ContentBuilder content: () -> Content) where Label == DefaultTabLabel, S: StringProtocol {}
    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ContentBuilder content: () -> Content) where Label == DefaultTabLabel {}
}

/// Harness-only value for the builders' `some TabContent<TabValue>` results (internal in the SDK).
struct _HarnessTabContent<V: Hashable>: TabContent {
    typealias TabValue = V
    var body: _HarnessTabContent<V> { return self }
}

@resultBuilder public struct TabContentBuilder<TabValue>: ~Sendable where TabValue: Hashable {
    nonisolated public struct Content<C>: View, ~Sendable where C: TabContent {
        public typealias Body = Never
    }
    public static func buildExpression(_ content: some TabContent<TabValue>) -> some TabContent<TabValue> { content }
    public static func buildBlock(_ content: some TabContent<TabValue>) -> some TabContent<TabValue> { content }
    public static func buildIf(_ content: (some TabContent<TabValue>)?) -> (some TabContent<TabValue>)? { content }
    public static func buildEither<T, F>(first: T) -> _ConditionalContent<T, F> where TabValue == T.TabValue, T: TabContent, F: TabContent, T.TabValue == F.TabValue {
        _ConditionalContent(storage: .trueContent(first))
    }
    public static func buildEither<T, F>(second: F) -> _ConditionalContent<T, F> where TabValue == T.TabValue, T: TabContent, F: TabContent, T.TabValue == F.TabValue {
        _ConditionalContent(storage: .falseContent(second))
    }
}
extension TabContentBuilder {
    public static func buildBlock<C0, C1>(_ c0: C0, _ c1: C1) -> some TabContent<TabValue> where TabValue == C0.TabValue, C0: TabContent, C1: TabContent, C0.TabValue == C1.TabValue { _HarnessTabContent<TabValue>() }
    public static func buildBlock<C0, C1, C2>(_ c0: C0, _ c1: C1, _ c2: C2) -> some TabContent<TabValue> where TabValue == C0.TabValue, C0: TabContent, C1: TabContent, C2: TabContent, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue { _HarnessTabContent<TabValue>() }
    public static func buildBlock<C0, C1, C2, C3>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> some TabContent<TabValue> where TabValue == C0.TabValue, C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue, C2.TabValue == C3.TabValue { _HarnessTabContent<TabValue>() }
    public static func buildBlock<C0, C1, C2, C3, C4>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> some TabContent<TabValue> where TabValue == C0.TabValue, C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue, C2.TabValue == C3.TabValue, C3.TabValue == C4.TabValue { _HarnessTabContent<TabValue>() }
    public static func buildBlock<C0, C1, C2, C3, C4, C5>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> some TabContent<TabValue> where TabValue == C0.TabValue, C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent, C5: TabContent, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue, C2.TabValue == C3.TabValue, C3.TabValue == C4.TabValue, C4.TabValue == C5.TabValue { _HarnessTabContent<TabValue>() }
    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> some TabContent<TabValue> where TabValue == C0.TabValue, C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent, C5: TabContent, C6: TabContent, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue, C2.TabValue == C3.TabValue, C3.TabValue == C4.TabValue, C4.TabValue == C5.TabValue, C5.TabValue == C6.TabValue { _HarnessTabContent<TabValue>() }
    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> some TabContent<TabValue> where TabValue == C0.TabValue, C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent, C5: TabContent, C6: TabContent, C7: TabContent, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue, C2.TabValue == C3.TabValue, C3.TabValue == C4.TabValue, C4.TabValue == C5.TabValue, C5.TabValue == C6.TabValue, C6.TabValue == C7.TabValue { _HarnessTabContent<TabValue>() }
    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> some TabContent<TabValue> where TabValue == C0.TabValue, C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent, C5: TabContent, C6: TabContent, C7: TabContent, C8: TabContent, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue, C2.TabValue == C3.TabValue, C3.TabValue == C4.TabValue, C4.TabValue == C5.TabValue, C5.TabValue == C6.TabValue, C6.TabValue == C7.TabValue, C7.TabValue == C8.TabValue { _HarnessTabContent<TabValue>() }
    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8, C9>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> some TabContent<TabValue> where TabValue == C0.TabValue, C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent, C5: TabContent, C6: TabContent, C7: TabContent, C8: TabContent, C9: TabContent, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue, C2.TabValue == C3.TabValue, C3.TabValue == C4.TabValue, C4.TabValue == C5.TabValue, C5.TabValue == C6.TabValue, C6.TabValue == C7.TabValue, C7.TabValue == C8.TabValue, C8.TabValue == C9.TabValue { _HarnessTabContent<TabValue>() }
}

nonisolated public struct TabView<SelectionValue, Content>: View, ~Sendable where SelectionValue: Hashable, Content: View {
    nonisolated public init(selection: Binding<SelectionValue>?, @ContentBuilder content: () -> Content) {}
    nonisolated public init<C>(selection: Binding<SelectionValue>, @TabContentBuilder<SelectionValue> content: () -> C) where Content == TabContentBuilder<SelectionValue>.Content<C>, C: TabContent {}
    public typealias Body = Never
}
extension TabView where SelectionValue == Int {
    nonisolated public init(@ContentBuilder content: () -> Content) {}
}
extension TabView {
    nonisolated public init<C>(@TabContentBuilder<Never> content: () -> C) where SelectionValue == Never, Content == TabContentBuilder<Never>.Content<C>, C: TabContent {}
}

// cloudcheck:verbatim-end

// MARK: - Sheets

public struct PresentationDetent : Hashable, Sendable {
    private let id: Int
    private init(id: Int) { self.id = id }
    public static let medium: PresentationDetent = PresentationDetent(id: 0)
    public static let large: PresentationDetent = PresentationDetent(id: 1)
    public static func fraction(_ fraction: CGFloat) -> PresentationDetent { PresentationDetent(id: 2) }
    public static func height(_ height: CGFloat) -> PresentationDetent { PresentationDetent(id: 3) }
}

// MARK: - Styles

public struct PrimitiveButtonStyleConfiguration : ~Sendable {
    @MainActor @preconcurrency public struct Label : View, ~Sendable { public typealias Body = Never }
    public let role: ButtonRole?
    public let label: PrimitiveButtonStyleConfiguration.Label
    public func trigger() {}
}

@preconcurrency @MainActor public protocol PrimitiveButtonStyle {
    associatedtype Body: View
    @ContentBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = PrimitiveButtonStyleConfiguration
}

public struct ButtonStyleConfiguration : ~Sendable {
    @MainActor @preconcurrency public struct Label : View, ~Sendable { public typealias Body = Never }
    public let role: ButtonRole?
    public let label: ButtonStyleConfiguration.Label
    public let isPressed: Bool
}

@preconcurrency @MainActor public protocol ButtonStyle {
    associatedtype Body: View
    @ContentBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ButtonStyleConfiguration
}

nonisolated public struct PlainButtonStyle : PrimitiveButtonStyle, ~Sendable {
    nonisolated public init () {}
    nonisolated public func makeBody(configuration: PlainButtonStyle.Configuration) -> some View { configuration.label }
}
nonisolated public struct BorderlessButtonStyle : PrimitiveButtonStyle, ~Sendable {
    nonisolated public init () {}
    nonisolated public func makeBody(configuration: BorderlessButtonStyle.Configuration) -> some View { configuration.label }
}
nonisolated public struct BorderedButtonStyle : PrimitiveButtonStyle, ~Sendable {
    nonisolated public init () {}
    nonisolated public func makeBody(configuration: BorderedButtonStyle.Configuration) -> some View { configuration.label }
}
nonisolated public struct BorderedProminentButtonStyle : PrimitiveButtonStyle, ~Sendable {
    nonisolated public init () {}
    nonisolated public func makeBody(configuration: BorderedProminentButtonStyle.Configuration) -> some View { configuration.label }
}
nonisolated public struct DefaultButtonStyle : PrimitiveButtonStyle, ~Sendable {
    nonisolated public init () {}
    nonisolated public func makeBody(configuration: DefaultButtonStyle.Configuration) -> some View { configuration.label }
}
extension PrimitiveButtonStyle where Self == PlainButtonStyle {
    @MainActor @preconcurrency public static var plain: PlainButtonStyle { PlainButtonStyle() }
}
extension PrimitiveButtonStyle where Self == BorderlessButtonStyle {
    nonisolated public static var borderless: BorderlessButtonStyle { BorderlessButtonStyle() }
}
extension PrimitiveButtonStyle where Self == BorderedButtonStyle {
    nonisolated public static var bordered: BorderedButtonStyle { BorderedButtonStyle() }
}
extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle {
    nonisolated public static var borderedProminent: BorderedProminentButtonStyle { BorderedProminentButtonStyle() }
}
extension PrimitiveButtonStyle where Self == DefaultButtonStyle {
    nonisolated public static var automatic: DefaultButtonStyle { DefaultButtonStyle() }
}

/// HARNESS: requirements omitted (the apps only use the built-in picker styles).
public protocol PickerStyle {}
public struct MenuPickerStyle : PickerStyle, ~Sendable { public init() {} }
public struct SegmentedPickerStyle : PickerStyle, ~Sendable { public init() {} }
public struct WheelPickerStyle : PickerStyle, ~Sendable { public init() {} }
public struct InlinePickerStyle : PickerStyle, ~Sendable { public init() {} }
public struct NavigationLinkPickerStyle : PickerStyle, ~Sendable { public init() {} }
public struct DefaultPickerStyle : PickerStyle, ~Sendable { public init() {} }
extension PickerStyle where Self == MenuPickerStyle { public static var menu: MenuPickerStyle { MenuPickerStyle() } }
extension PickerStyle where Self == SegmentedPickerStyle { public static var segmented: SegmentedPickerStyle { SegmentedPickerStyle() } }
extension PickerStyle where Self == WheelPickerStyle { public static var wheel: WheelPickerStyle { WheelPickerStyle() } }
extension PickerStyle where Self == InlinePickerStyle { public static var inline: InlinePickerStyle { InlinePickerStyle() } }
extension PickerStyle where Self == NavigationLinkPickerStyle { public static var navigationLink: NavigationLinkPickerStyle { NavigationLinkPickerStyle() } }
extension PickerStyle where Self == DefaultPickerStyle { public static var automatic: DefaultPickerStyle { DefaultPickerStyle() } }

public struct ScrollIndicatorVisibility : ~Sendable {
    private let id: Int
    private init(id: Int) { self.id = id }
    public static var automatic: ScrollIndicatorVisibility { ScrollIndicatorVisibility(id: 0) }
    public static var visible: ScrollIndicatorVisibility { ScrollIndicatorVisibility(id: 1) }
    public static var hidden: ScrollIndicatorVisibility { ScrollIndicatorVisibility(id: 2) }
    public static var never: ScrollIndicatorVisibility { ScrollIndicatorVisibility(id: 3) }
}

public struct ScrollDismissesKeyboardMode : Sendable {
    private init() {}
    public static var automatic: ScrollDismissesKeyboardMode { ScrollDismissesKeyboardMode() }
    public static var immediately: ScrollDismissesKeyboardMode { ScrollDismissesKeyboardMode() }
    public static var interactively: ScrollDismissesKeyboardMode { ScrollDismissesKeyboardMode() }
    public static var never: ScrollDismissesKeyboardMode { ScrollDismissesKeyboardMode() }
}

public struct SubmitLabel : Sendable {
    private init() {}
    public static var done: SubmitLabel { SubmitLabel() }
    public static var go: SubmitLabel { SubmitLabel() }
    public static var send: SubmitLabel { SubmitLabel() }
    public static var join: SubmitLabel { SubmitLabel() }
    public static var route: SubmitLabel { SubmitLabel() }
    public static var search: SubmitLabel { SubmitLabel() }
    public static var `return`: SubmitLabel { SubmitLabel() }
    public static var next: SubmitLabel { SubmitLabel() }
    public static var `continue`: SubmitLabel { SubmitLabel() }
}

public struct SubmitTriggers : OptionSet, Sendable {
    public typealias RawValue = Int
    public let rawValue: SubmitTriggers.RawValue
    public init (rawValue: SubmitTriggers.RawValue) { self.rawValue = rawValue }
    public static let text: SubmitTriggers = SubmitTriggers(rawValue: 1)
    public static let search: SubmitTriggers = SubmitTriggers(rawValue: 2)
}

public struct TextInputAutocapitalization : Sendable {
    private init() {}
    public static var never: TextInputAutocapitalization { TextInputAutocapitalization() }
    public static var words: TextInputAutocapitalization { TextInputAutocapitalization() }
    public static var sentences: TextInputAutocapitalization { TextInputAutocapitalization() }
    public static var characters: TextInputAutocapitalization { TextInputAutocapitalization() }
}

public struct ContainerBackgroundPlacement : Sendable, Hashable {
    @usableFromInline let id: Int
    /// HARNESS-ONLY: lets the WidgetKit stub declare `.widget` (the real initializer is SPI).
    public init(__harnessID id: Int) { self.id = id }
    public static let navigation = ContainerBackgroundPlacement(__harnessID: 1)
}

// MARK: - View modifiers

extension View {
    // Text and appearance
    nonisolated public func font(_ font: Font?) -> some View { self }
    nonisolated public func fontWeight(_ weight: Font.Weight?) -> some View { self }
    nonisolated public func fontDesign(_ design: Font.Design?) -> some View { self }
    nonisolated public func foregroundStyle<S>(_ style: S) -> some View where S : ShapeStyle { self }
    nonisolated public func foregroundStyle<S1, S2>(_ primary: S1, _ secondary: S2) -> some View where S1 : ShapeStyle, S2 : ShapeStyle { self }
    nonisolated public func foregroundColor(_ color: Color?) -> some View { self }
    nonisolated public func strikethrough(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) -> some View { self }
    nonisolated public func underline(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) -> some View { self }
    nonisolated public func bold(_ isActive: Bool = true) -> some View { self }
    nonisolated public func italic(_ isActive: Bool = true) -> some View { self }
    nonisolated public func monospacedDigit() -> some View { self }
    nonisolated public func lineLimit(_ number: Int?) -> some View { self }
    nonisolated public func lineLimit(_ limit: Int, reservesSpace: Bool) -> some View { self }
    nonisolated public func lineLimit(_ limit: PartialRangeFrom<Int>) -> some View { self }
    nonisolated public func lineLimit(_ limit: PartialRangeThrough<Int>) -> some View { self }
    nonisolated public func lineLimit(_ limit: ClosedRange<Int>) -> some View { self }
    nonisolated public func lineSpacing(_ lineSpacing: CGFloat) -> some View { self }
    nonisolated public func minimumScaleFactor(_ factor: CGFloat) -> some View { self }
    nonisolated public func multilineTextAlignment(_ alignment: TextAlignment) -> some View { self }
    nonisolated public func truncationMode(_ mode: Text.TruncationMode) -> some View { self }
    nonisolated public func textCase(_ textCase: Text.Case?) -> some View { self }
    nonisolated public func imageScale(_ scale: Image.Scale) -> some View { self }
    nonisolated public func tint<S>(_ tint: S?) -> some View where S : ShapeStyle { self }
    @_disfavoredOverload nonisolated public func tint(_ tint: Color?) -> some View { self }
    nonisolated public func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View { self }
    nonisolated public func dynamicTypeSize(_ size: DynamicTypeSize) -> some View { self }
    nonisolated public func dynamicTypeSize<T>(_ range: T) -> some View where T : RangeExpression, T.Bound == DynamicTypeSize { self }
    nonisolated public func blendMode(_ blendMode: BlendMode) -> some View { self }
    nonisolated public func opacity(_ opacity: Double) -> some View { self }
    nonisolated public func controlSize(_ controlSize: ControlSize) -> some View { self }
    nonisolated public func labelsHidden() -> some View { self }
    nonisolated public func hidden() -> some View { self }
    nonisolated public func disabled(_ disabled: Bool) -> some View { self }
    nonisolated public func id<ID>(_ id: ID) -> some View where ID : Hashable { self }
    nonisolated public func tag<V>(_ tag: V, includeOptional: Bool = true) -> some View where V : Hashable { self }
    nonisolated public func zIndex(_ value: Double) -> some View { self }
    nonisolated public func allowsHitTesting(_ enabled: Bool) -> some View { self }
    nonisolated public func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View { self }

    // Layout
    nonisolated public func padding(_ insets: EdgeInsets) -> some View { self }
    nonisolated public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View { self }
    nonisolated public func padding(_ length: CGFloat) -> some View { self }
    nonisolated public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View { self }
    nonisolated public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
                                  minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil,
                                  alignment: Alignment = .center) -> some View { self }
    @available(*, deprecated, message: "Please pass one or more parameters.")
    nonisolated public func frame() -> some View { self }
    nonisolated public func fixedSize() -> some View { self }
    nonisolated public func fixedSize(horizontal: Bool, vertical: Bool) -> some View { self }
    nonisolated public func layoutPriority(_ value: Double) -> some View { self }
    nonisolated public func offset(_ offset: CGSize) -> some View { self }
    nonisolated public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View { self }
    nonisolated public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View { self }
    nonisolated public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> some View { self }
    nonisolated public func scaleEffect(_ scale: CGSize, anchor: UnitPoint = .center) -> some View { self }
    nonisolated public func scaleEffect(x: CGFloat = 1.0, y: CGFloat = 1.0, anchor: UnitPoint = .center) -> some View { self }
    nonisolated public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View { self }
    nonisolated public func safeAreaInset<V>(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ContentBuilder content: () -> V) -> some View where V : View { self }
    nonisolated public func safeAreaInset<V>(edge: HorizontalEdge, alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ContentBuilder content: () -> V) -> some View where V : View { self }
    nonisolated public func contentShape<S>(_ shape: S, eoFill: Bool = false) -> some View where S : Shape { self }
    nonisolated public func contentShape<S>(_ kind: ContentShapeKinds, _ shape: S, eoFill: Bool = false) -> some View where S : Shape { self }
    nonisolated public func clipShape<S>(_ shape: S, style: FillStyle = FillStyle()) -> some View where S : Shape { self }
    nonisolated public func clipped(antialiased: Bool = false) -> some View { self }
    nonisolated public func cornerRadius(_ radius: CGFloat, antialiased: Bool = true) -> some View { self }

    // Background and overlay
    @_disfavoredOverload nonisolated public func background<Background>(_ background: Background, alignment: Alignment = .center) -> some View where Background : View { self }
    nonisolated public func background<V>(alignment: Alignment = .center, @ContentBuilder content: () -> V) -> some View where V : View { self }
    nonisolated public func background(ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View { self }
    nonisolated public func background<S>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View where S : ShapeStyle { self }
    nonisolated public func background<S, T>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View where S : ShapeStyle, T : Shape { self }
    nonisolated public func background<S>(in shape: S, fillStyle: FillStyle = FillStyle()) -> some View where S : Shape { self }
    @_disfavoredOverload nonisolated public func overlay<Overlay>(_ overlay: Overlay, alignment: Alignment = .center) -> some View where Overlay : View { self }
    nonisolated public func overlay<V>(alignment: Alignment = .center, @ContentBuilder content: () -> V) -> some View where V : View { self }
    nonisolated public func overlay<S>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View where S : ShapeStyle { self }
    nonisolated public func overlay<S, T>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View where S : ShapeStyle, T : Shape { self }
    nonisolated public func containerBackground<S>(_ style: S, for container: ContainerBackgroundPlacement) -> some View where S : ShapeStyle { self }
    nonisolated public func containerBackground<V>(for container: ContainerBackgroundPlacement, alignment: Alignment = .center, @ContentBuilder content: () -> V) -> some View where V : View { self }

    // Accessibility
    nonisolated public func accessibilityLabel(_ label: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { .init(content: self, modifier: .init()) }
    nonisolated public func accessibilityLabel(_ labelKey: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { .init(content: self, modifier: .init()) }
    @_disfavoredOverload nonisolated public func accessibilityLabel<S>(_ label: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S : StringProtocol { .init(content: self, modifier: .init()) }
    nonisolated public func accessibilityHint(_ hint: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { .init(content: self, modifier: .init()) }
    nonisolated public func accessibilityHint(_ hintKey: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { .init(content: self, modifier: .init()) }
    @_disfavoredOverload nonisolated public func accessibilityHint<S>(_ hint: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S : StringProtocol { .init(content: self, modifier: .init()) }
    nonisolated public func accessibilityValue(_ valueDescription: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { .init(content: self, modifier: .init()) }
    nonisolated public func accessibilityValue(_ valueKey: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { .init(content: self, modifier: .init()) }
    @_disfavoredOverload nonisolated public func accessibilityValue<S>(_ value: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S : StringProtocol { .init(content: self, modifier: .init()) }
    nonisolated public func accessibilityIdentifier(_ identifier: String) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { .init(content: self, modifier: .init()) }
    nonisolated public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { .init(content: self, modifier: .init()) }
    nonisolated public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { .init(content: self, modifier: .init()) }
    nonisolated public func accessibilityHidden(_ hidden: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { .init(content: self, modifier: .init()) }
    nonisolated public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View { self }
    nonisolated public func accessibilitySortPriority(_ sortPriority: Double) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { .init(content: self, modifier: .init()) }

    // Navigation, toolbars, presentation
    nonisolated public func navigationDestination<D, C>(for data: D.Type, @ContentBuilder destination: @escaping (D) -> C) -> some View where D : Hashable, C : View { self }
    nonisolated public func navigationBarBackButtonHidden(_ hidesBackButton: Bool = true) -> some View { self }
    nonisolated public func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View { self }
    @_disfavoredOverload nonisolated public func toolbar<Content>(@ContentBuilder content: () -> Content) -> some View where Content : View { self }
    nonisolated public func toolbar<Content>(@ContentBuilder content: () -> Content) -> some View where Content : ToolbarContent { self }
    nonisolated public func sheet<Item, Content>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ContentBuilder content: @escaping (Item) -> Content) -> some View where Item : Identifiable, Content : View { self }
    nonisolated public func sheet<Content>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ContentBuilder content: @escaping () -> Content) -> some View where Content : View { self }
    nonisolated public func fullScreenCover<Item, Content>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ContentBuilder content: @escaping (Item) -> Content) -> some View where Item : Identifiable, Content : View { self }
    nonisolated public func fullScreenCover<Content>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ContentBuilder content: @escaping () -> Content) -> some View where Content : View { self }
    nonisolated public func presentationDetents(_ detents: Set<PresentationDetent>) -> some View { self }
    nonisolated public func presentationDetents(_ detents: Set<PresentationDetent>, selection: Binding<PresentationDetent>) -> some View { self }
    nonisolated public func presentationDragIndicator(_ visibility: Visibility) -> some View { self }
    nonisolated public func presentationBackground<S>(_ style: S) -> some View where S : ShapeStyle { self }
    nonisolated public func presentationBackground<V>(alignment: Alignment = .center, @ContentBuilder content: () -> V) -> some View where V : View { self }
    nonisolated public func presentationCornerRadius(_ cornerRadius: CGFloat?) -> some View { self }
    nonisolated public func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View { self }
    nonisolated public func contextMenu<MenuItems>(@ContentBuilder menuItems: () -> MenuItems) -> some View where MenuItems : View { self }

    // Input
    nonisolated public func focused(_ condition: FocusState<Bool>.Binding) -> some View { self }
    nonisolated public func focused<Value>(_ binding: FocusState<Value>.Binding, equals value: Value) -> some View where Value : Hashable { self }
    nonisolated public func keyboardType(_ type: UIKeyboardType) -> some View { self }
    nonisolated public func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View { self }
    nonisolated public func autocorrectionDisabled(_ disable: Bool = true) -> some View { self }
    nonisolated public func submitLabel(_ submitLabel: SubmitLabel) -> some View { self }
    nonisolated public func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping () -> Void) -> some View { self }
    nonisolated public func scrollIndicators(_ visibility: ScrollIndicatorVisibility, axes: Axis.Set = [.vertical, .horizontal]) -> some View { self }
    nonisolated public func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardMode) -> some View { self }
    nonisolated public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View { self }

    // Styles
    nonisolated public func buttonStyle<S>(_ style: S) -> some View where S : PrimitiveButtonStyle { self }
    nonisolated public func buttonStyle<S>(_ style: S) -> some View where S : ButtonStyle { self }
    nonisolated public func pickerStyle<S>(_ style: S) -> some View where S : PickerStyle { self }

    // Life cycle
    nonisolated public func onAppear(perform action: (() -> Void)? = nil) -> some View { self }
    nonisolated public func onDisappear(perform action: (() -> Void)? = nil) -> some View { self }
    nonisolated public func onChange<V>(of value: V, initial: Bool = false, _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void) -> some View where V : Equatable { self }
    nonisolated public func onChange<V>(of value: V, initial: Bool = false, _ action: @escaping () -> Void) -> some View where V : Equatable { self }
    @available(*, deprecated, message: "deprecated in iOS 17.0: Use `onChange` with a two or zero parameter action closure instead.") nonisolated public func onChange<V>(of value: V, perform action: @escaping (_ newValue: V) -> Void) -> some View where V : Equatable { self }
    // iOS 26: the task modifiers take a task name and the caller's file/line; the iOS 15 `task(priority:_:)`
    // forms are internal in the iOS 27 SDK.
    nonisolated public func task(name: String? = nil, priority: TaskPriority = .userInitiated, file: String = #fileID, line: Int = #line,
                                 @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void) -> some View { self }
    nonisolated public func task<T>(id: T, name: String? = nil, priority: TaskPriority = .userInitiated, file: String = #fileID, line: Int = #line, @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void) -> some View where T : Equatable { self }

    // Animation
    nonisolated public func animation<V>(_ animation: Animation?, value: V) -> some View where V : Equatable { self }
    @available(*, deprecated, message: "deprecated in iOS 15.0: Use withAnimation or animation(_:value:) instead.") @_disfavoredOverload nonisolated public func animation(_ animation: Animation?) -> some View { self }
    @_disfavoredOverload nonisolated public func transition(_ t: AnyTransition) -> some View { self }
    nonisolated public func transition<T>(_ transition: T) -> some View where T : Transition { self }
}

extension View where Self: Equatable {
    nonisolated public func animation(_ animation: Animation?) -> some View { self }
}

// MARK: - Previews (the `#Preview` macro is removed by preprocess.py)

@preconcurrency @MainActor public protocol PreviewProvider {
    associatedtype Previews: View
    @ContentBuilder @preconcurrency @MainActor static var previews: Self.Previews { get }
}

// cloudcheck:verbatim-begin (written from the iOS 27 SDK interface by hand; the stub audit leaves it alone)
// MARK: - App and scenes

@preconcurrency @MainActor public protocol App {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }
    @MainActor @preconcurrency init()
}
extension App {
    @MainActor @preconcurrency public static func main() {}
}

@preconcurrency @MainActor public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }
}
extension Scene where Self.Body == Never {
    public var body: Never { fatalError("primitive scene") }
}
extension Never: Scene {}

/// Harness-only value for SceneBuilder's `some Scene` results (internal in the SDK).
struct _HarnessScene: Scene {
    typealias Body = Never
}

@resultBuilder public struct SceneBuilder: ~Sendable {
    public static func buildExpression<Content>(_ content: Content) -> Content where Content: Scene { content }
    @available(*, unavailable, message: "Provide at leas one scene")
    public static func buildBlock() -> some Scene { _HarnessScene() }
    public static func buildBlock<Content>(_ content: Content) -> Content where Content: Scene { content }
    @_disfavoredOverload public static func buildBlock<each Content>(_ content: repeat each Content) -> some Scene where repeat each Content: Scene { _HarnessScene() }
}
extension SceneBuilder {
    @available(*, unavailable, message: "if statements in a SceneBuilder can only be used with #available clauses")
    public static func buildOptional<S>(_ scene: S?) where S: Scene {}
}

nonisolated public struct WindowGroup<Content>: Scene, ~Sendable where Content: View {
    @available(*, deprecated, renamed: "init(id:makeContent:)", message: "deprecated in iOS 18.0: Use the initializer which takes an escaping content builder instead.")
    nonisolated public init(id: String, @ContentBuilder content: () -> Content) {}
    @available(*, deprecated, renamed: "init(makeContent:)", message: "deprecated in iOS 18.0: Use the initializer which takes an escaping content builder instead.")
    nonisolated public init(@ContentBuilder content: () -> Content) {}
    public typealias Body = Never
}
extension WindowGroup {
    nonisolated public init(id: String, @ContentBuilder makeContent: @escaping () -> Content) {}
    nonisolated public init(@ContentBuilder makeContent: @escaping () -> Content) {}
}

// MARK: - Widget protocols (declared in SwiftUI; WidgetKit adds the configurations)

@preconcurrency @MainActor public protocol WidgetConfiguration {
    associatedtype Body: WidgetConfiguration
    @MainActor @preconcurrency var body: Self.Body { get }
}
extension WidgetConfiguration where Self.Body == Never {
    public var body: Never { fatalError("primitive widget configuration") }
}
extension Never: WidgetConfiguration {}

@frozen nonisolated public struct EmptyWidgetConfiguration: WidgetConfiguration {
    nonisolated public init() {}
    public typealias Body = Never
}
extension EmptyWidgetConfiguration: Sendable {}

@preconcurrency @MainActor public protocol Widget {
    associatedtype Body: WidgetConfiguration
    @MainActor @preconcurrency init()
    @MainActor @preconcurrency var body: Self.Body { get }
}
extension Widget {
    @MainActor @preconcurrency public static func main() {}
}

@preconcurrency @MainActor public protocol WidgetBundle {
    associatedtype Body: Widget
    @MainActor @preconcurrency init()
    @WidgetBundleBuilder @MainActor @preconcurrency var body: Self.Body { get }
}
extension WidgetBundle {
    @MainActor @preconcurrency public static func main() {}
}

/// Harness-only value for WidgetBundleBuilder's `some Widget` results (internal in the SDK).
struct _HarnessWidget: Widget {
    init() {}
    var body: EmptyWidgetConfiguration { EmptyWidgetConfiguration() }
}

@resultBuilder public struct WidgetBundleBuilder: ~Sendable {
    public static func buildExpression<Content>(_ content: Content) -> Content where Content: Widget { content }
    public static func buildBlock() -> some Widget { _HarnessWidget() }
    public static func buildBlock<Content>(_ content: Content) -> some Widget where Content: Widget { content }
    @_disfavoredOverload public static func buildBlock<each C>(_ c: repeat each C) -> some Widget where repeat each C: Widget { _HarnessWidget() }
}

// cloudcheck:verbatim-end

// MARK: - AttributedString scope

extension AttributeScopes {
    public var swiftUI: AttributeScopes.SwiftUIAttributes.Type { AttributeScopes.SwiftUIAttributes.self }

    public struct SwiftUIAttributes : AttributeScope, ~Sendable {
        public let font: AttributeScopes.SwiftUIAttributes.FontAttribute
        public let foregroundColor: AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
        public let backgroundColor: AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
        public let strikethroughStyle: AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute
        public let underlineStyle: AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute
        public let kern: AttributeScopes.SwiftUIAttributes.KerningAttribute
        public let tracking: AttributeScopes.SwiftUIAttributes.TrackingAttribute
        public let baselineOffset: AttributeScopes.SwiftUIAttributes.BaselineOffsetAttribute
        public let foundation: AttributeScopes.FoundationAttributes
    }
}

extension AttributeScopes.SwiftUIAttributes {
    @frozen public enum FontAttribute : AttributedStringKey {
        public typealias Value = Font
        public static let name: String = "SwiftUI.Font"
    }
    @frozen public enum ForegroundColorAttribute : AttributedStringKey {
        public typealias Value = Color
        public static let name: String = "SwiftUI.ForegroundColor"
    }
    @frozen public enum BackgroundColorAttribute : AttributedStringKey {
        public typealias Value = Color
        public static let name: String = "SwiftUI.BackgroundColor"
    }
    @frozen public enum StrikethroughStyleAttribute : AttributedStringKey {
        public typealias Value = Text.LineStyle
        public static let name: String = "SwiftUI.StrikethroughStyle"
    }
    @frozen public enum UnderlineStyleAttribute : AttributedStringKey {
        public typealias Value = Text.LineStyle
        public static let name: String = "SwiftUI.UnderlineStyle"
    }
    @frozen public enum KerningAttribute {
        public typealias Value = CGFloat
        public static let name: String = "SwiftUI.Kern"
    }
    @frozen public enum TrackingAttribute {
        public typealias Value = CGFloat
        public static let name: String = "SwiftUI.Tracking"
    }
    @frozen public enum BaselineOffsetAttribute {
        public typealias Value = CGFloat
        public static let name: String = "SwiftUI.BaselineOffset"
    }
}

extension AttributeDynamicLookup {
    public subscript <T>(dynamicMember keyPath: KeyPath<AttributeScopes.SwiftUIAttributes, T>) -> T where T : AttributedStringKey {
        self[T.self]
    }
}


// MARK: - Conformances the SDK declares in extensions (generated by the stub audit)
extension Alignment: Sendable {}
extension Angle: Comparable {}
extension Angle: Hashable {}
extension Angle: Sendable {}
extension Animation: Hashable {}
extension AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute: Sendable {}
extension AttributeScopes.SwiftUIAttributes.BaselineOffsetAttribute: Sendable {}
extension AttributeScopes.SwiftUIAttributes.FontAttribute: Sendable {}
extension AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute: Sendable {}
extension AttributeScopes.SwiftUIAttributes.KerningAttribute: Sendable {}
extension AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute: Sendable {}
extension AttributeScopes.SwiftUIAttributes.TrackingAttribute: Sendable {}
extension AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute: Sendable {}
extension Axis.Set: Sendable {}
extension Axis: Equatable {}
extension Axis: Hashable {}
extension Axis: Sendable {}
extension Binding: Sendable where Value : Sendable {}
extension BlendMode: Equatable {}
extension BlendMode: Hashable {}
extension Color.RGBColorSpace: Equatable {}
extension Color.RGBColorSpace: Hashable {}
extension ColorScheme: Equatable {}
extension ColorScheme: Hashable {}
extension ColorSchemeContrast: Equatable {}
extension ColorSchemeContrast: Hashable {}
extension ControlSize: Hashable {}
extension CoordinateSpace: Equatable {}
extension CoordinateSpace: Hashable {}
extension DismissAction: Sendable {}
extension Edge.Set: Sendable {}
extension Edge: Equatable {}
extension Edge: Hashable {}
extension Edge: Sendable {}
extension EdgeInsets: Sendable {}
extension EmptyModifier: Sendable {}
extension Environment: Sendable where Value : Sendable {}
extension FillStyle: Sendable {}
extension Font.Leading: Equatable {}
extension Font.Leading: Hashable {}
extension Font.TextStyle: Equatable {}
extension Font.TextStyle: Hashable {}
extension Font.Weight: Sendable {}
extension Gradient.Stop: Hashable {}
extension Gradient.Stop: Sendable {}
extension Gradient: Hashable {}
extension GridItem.Size: Equatable {}
extension GridItem: Equatable {}
extension HorizontalAlignment: Sendable {}
extension HorizontalEdge: Equatable {}
extension HorizontalEdge: Hashable {}
extension HorizontalEdge: Sendable {}
extension Image.Interpolation: Equatable {}
extension Image.Interpolation: Hashable {}
extension Image.ResizingMode: Equatable {}
extension Image.ResizingMode: Hashable {}
extension Image.TemplateRenderingMode: Equatable {}
extension Image.TemplateRenderingMode: Hashable {}
extension Material: ShapeStyle {}
extension ModifiedContent: Equatable where Content : Equatable, Modifier : Equatable {}
extension ModifiedContent: Sendable where Content : Sendable, Modifier : Sendable {}
extension NavigationBarItem.TitleDisplayMode: Equatable {}
extension NavigationBarItem.TitleDisplayMode: Hashable {}
extension NavigationPath: Equatable {}
extension OpenURLAction: Sendable {}
extension RoundedCornerStyle: Equatable {}
extension RoundedCornerStyle: Hashable {}
extension SafeAreaRegions: Sendable {}
extension ScenePhase: Hashable {}
extension ScenePhase: Sendable {}
extension ScrollDismissesKeyboardMode: Equatable {}
extension ScrollDismissesKeyboardMode: Hashable {}
extension ScrollIndicatorVisibility: Equatable {}
extension Spacer: Sendable {}
extension Spacer: View {}
extension State: Sendable where Value : Sendable {}
extension StrokeStyle: Sendable {}
extension Text.Case: Equatable {}
extension Text.Case: Hashable {}
extension Text.DateStyle: Equatable {}
extension Text.TruncationMode: Equatable {}
extension Text.TruncationMode: Hashable {}
extension TextAlignment: Sendable {}
extension UnitPoint: Sendable {}
extension UserInterfaceSizeClass: Equatable {}
extension UserInterfaceSizeClass: Hashable {}
extension VerticalAlignment: Sendable {}
extension VerticalEdge: Equatable {}
extension VerticalEdge: Hashable {}
extension VerticalEdge: Sendable {}
extension Visibility: Sendable {}