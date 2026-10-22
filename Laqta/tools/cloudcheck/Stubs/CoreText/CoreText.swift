// cloudcheck stub: the CoreText font-manager calls the apps make, as the iOS 27.0 SDK imports them
// (audited against the interface swift-synthesize-interface prints for CoreText):
//   func CTFontManagerRegisterFontsForURL(_ fontURL: CFURL, _ scope: CTFontManagerScope,
//                                         _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool
// Results of imported C functions are discardable.
@_exported import CoreGraphics
import Foundation

/// HARNESS-ONLY: on Darwin CFURL is a CoreFoundation class toll-free bridged with NSURL, so
/// `url as CFURL` is a valid bridging coercion there. Linux has no CF bridging; aliasing CFURL to URL
/// accepts exactly the `url as CFURL` spelling (a no-op coercion here).
public typealias CFURL = URL

/// Stand-in for the CoreFoundation error class (only used through Unmanaged<CFError>).
public final class CFError: @unchecked Sendable {}

/// iOS SDK: `typedef CF_ENUM(uint32_t, CTFontManagerScope)`.
public enum CTFontManagerScope : UInt32, @unchecked Sendable {
    case none = 0
    case process = 1
    case persistent = 2
    case session = 3
    public static var user: CTFontManagerScope { .persistent }
}

@discardableResult
public func CTFontManagerRegisterFontsForURL(_ fontURL: CFURL, _ scope: CTFontManagerScope,
                                             _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool { true }

@discardableResult
public func CTFontManagerUnregisterFontsForURL(_ fontURL: CFURL, _ scope: CTFontManagerScope,
                                               _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool { true }
