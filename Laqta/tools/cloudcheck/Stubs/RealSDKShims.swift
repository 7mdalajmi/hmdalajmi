// cloudcheck HARNESS-ONLY file, compiled into the app and widget modules by `check.sh --sdk` (a real
// iPhoneOS SDK instead of the stubs). Nothing here is an app finding.
//
// The iOS 27 SDK declares `State()` as a macro next to the `State` property wrapper, and Xcode 27 expands
// `@State` with the macro's closed-source plugin (SwiftUIMacros, shipped only with Xcode). preprocess.py
// --mode sdk rewrites `@State` to `@STATE` (same length) so the attribute resolves to the property
// wrapper through this alias: the Xcode 26 behaviour, which is also what the stubs model.
import SwiftUI

typealias STATE<Value> = SwiftUICore.State<Value>
