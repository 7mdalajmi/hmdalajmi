// cloudcheck stub: CoreGraphics names used through SwiftUI/UIKit.
// CGFloat, CGPoint, CGSize and CGRect come from Linux Foundation (HARNESS: re-exported here; on Darwin
// they belong to CoreGraphics/CoreFoundation).
@_exported import Foundation

/// iOS SDK: `typedef CF_ENUM(int32_t, CGLineCap)`.
public enum CGLineCap: Int32, @unchecked Sendable {
    case butt = 0
    case round = 1
    case square = 2
}

/// iOS SDK: `typedef CF_ENUM(int32_t, CGLineJoin)`.
public enum CGLineJoin: Int32, @unchecked Sendable {
    case miter = 0
    case round = 1
    case bevel = 2
}

public struct CGVector: Hashable, Sendable {
    public var dx: CGFloat
    public var dy: CGFloat
    public init() { dx = 0; dy = 0 }
    public init(dx: CGFloat, dy: CGFloat) { self.dx = dx; self.dy = dy }
    public static var zero: CGVector { CGVector() }
}

public struct CGAffineTransform: Hashable, Sendable {
    public var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat
    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public static var identity: CGAffineTransform { CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }
    public init(translationX tx: CGFloat, y ty: CGFloat) { self.init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty) }
    public init(scaleX sx: CGFloat, y sy: CGFloat) { self.init(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0) }
    public init(rotationAngle angle: CGFloat) { self.init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }
}
