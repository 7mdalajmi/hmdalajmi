// A stand-in module named SwiftUI for Linux, where SwiftUI does not exist.
// It declares only the symbols that the compiled app files use (the two stores, Palette.swift and the fake
// Motion.swift), as plain data, so the real store logic runs unchanged. Nothing here draws anything.
//
// Used by: BalootStore.swift (SensoryFeedback, withAnimation), HandStore.swift (withAnimation),
// Palette.swift (Color, ColorScheme, EnvironmentKey, EnvironmentValues, EdgeInsets), fakes/Motion.swift (Animation).
@_exported import Foundation

// MARK: Animation and withAnimation

/// An animation curve, kept as data so a test can read which curve a store asked for.
public struct Animation: Equatable, Sendable, CustomStringConvertible {
    public enum Curve: Equatable, Sendable {
        case timingCurve(Double, Double, Double, Double)
        case easeIn, easeOut, easeInOut, linear, systemDefault
    }

    public var curve: Curve
    public var duration: Double?
    public var delayed: Double = 0

    public init(curve: Curve, duration: Double?, delayed: Double = 0) {
        self.curve = curve
        self.duration = duration
        self.delayed = delayed
    }

    public static func timingCurve(_ c0x: Double, _ c0y: Double, _ c1x: Double, _ c1y: Double, duration: Double = 0.35) -> Animation {
        Animation(curve: .timingCurve(c0x, c0y, c1x, c1y), duration: duration)
    }

    public static let `default` = Animation(curve: .systemDefault, duration: nil)
    public static func easeIn(duration: Double) -> Animation { Animation(curve: .easeIn, duration: duration) }
    public static func easeOut(duration: Double) -> Animation { Animation(curve: .easeOut, duration: duration) }
    public static func easeInOut(duration: Double) -> Animation { Animation(curve: .easeInOut, duration: duration) }
    public static func linear(duration: Double) -> Animation { Animation(curve: .linear, duration: duration) }

    public func delay(_ seconds: Double) -> Animation {
        var a = self
        a.delayed = seconds
        return a
    }

    public var description: String {
        let d = duration.map { String(format: "%.2fs", $0) } ?? "default"
        switch curve {
        case .timingCurve(let a, let b, let c, let e): return "timingCurve(\(a), \(b), \(c), \(e)) \(d)"
        default: return "\(curve) \(d)"
        }
    }
}

/// Every withAnimation call, in order: the harness reads it to check the curve of a step.
@MainActor public enum AnimationLog {
    public static var calls: [Animation?] = []
}

/// Runs the body at once (there is nothing to animate) and records the animation it was given.
@MainActor
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    AnimationLog.calls.append(animation)
    return try body()
}

// MARK: Haptics

public struct SensoryFeedback: Equatable, Sendable, CustomStringConvertible {
    public enum Weight: Equatable, Sendable { case light, medium, heavy }
    public let description: String

    public static let success = SensoryFeedback(description: "success")
    public static let warning = SensoryFeedback(description: "warning")
    public static let error = SensoryFeedback(description: "error")
    public static let selection = SensoryFeedback(description: "selection")
    public static func impact(weight: Weight = .medium, intensity: Double = 1) -> SensoryFeedback {
        SensoryFeedback(description: "impact(\(weight))")
    }
}

// MARK: Colours and environment (for Palette.swift)

public struct Color: Equatable, Hashable, Sendable {
    public enum RGBColorSpace: Equatable, Hashable, Sendable { case sRGB, sRGBLinear, displayP3 }
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
}

public enum ColorScheme: Equatable, Hashable, Sendable, CaseIterable {
    case light, dark
}

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public struct EnvironmentValues {
    private var storage: [ObjectIdentifier: Any] = [:]
    public init() {}

    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get { storage[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
        set { storage[ObjectIdentifier(key)] = newValue }
    }
}

public struct EdgeInsets: Equatable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    public init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}
