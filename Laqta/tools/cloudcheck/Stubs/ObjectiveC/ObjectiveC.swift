// cloudcheck stub: the piece of the ObjectiveC module that Swift code sees through Foundation/UIKit.
// HARNESS-ONLY: Linux has no Objective-C runtime. preprocess.py rewrites `#selector(` to ` Selector(`
// (same length), so the referenced method is still looked up and type-checked.

public struct Selector: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    private let name: String
    public init(_ str: String) { name = str }
    public init(stringLiteral value: String) { name = value }
    public var description: String { name }

    /// HARNESS-ONLY: target of the `#selector(...)` rewrite. Takes the referenced method as a value.
    public init<Method>(_ method: Method) { name = "\(Method.self)" }
}
