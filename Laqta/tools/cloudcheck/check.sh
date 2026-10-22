#!/usr/bin/env bash
# cloudcheck: type-check the Zakati iOS targets on Linux, before they reach a Mac.
#
# Default (stub) mode: builds stub Apple SDK modules (Stubs/<Module>/<Module>.swift, whose declarations are
# copied from the iOS 27.0 SDK interfaces; XCTest's from Apple's documentation, as XCTest is not in the
# SDK), copies the sources to a work tree with line-preserving rewrites
# (preprocess.py: @Entry expansion, #Preview removal, Linux-only Objective-C constructs), compiles each
# target through the SIL diagnostic passes with the Xcode project's Swift settings, and prints every error
# and warning mapped back to the real file and line (report.py), with harness-only diagnostics apart.
#
# --sdk mode: the same, against a real iPhoneOS SDK directory (a copy of Xcode's
# Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk, or ~250 MB of the github.com/xybp888/iOS-SDKs
# mirror: git clone --depth 1 --filter=blob:none --no-checkout https://github.com/xybp888/iOS-SDKs.git &&
# cd iOS-SDKs && git sparse-checkout set --no-cone '/iPhoneOS27.0.sdk/*' \
# '!/iPhoneOS27.0.sdk/System/Library/PrivateFrameworks/*' && git checkout): the real SwiftUI/UIKit/... interfaces and
# headers, with availability, deprecation and app-extension checks. Only XCTest (a platform framework, not
# in the SDK) stays a stub, built against that SDK. Apple's closed-source macros are still replaced
# (@Entry expanded; @State -> the State property wrapper, see Stubs/RealSDKShims.swift).
# --compare mode: runs both and prints the diagnostics on which they disagree (a stub fidelity check).
#
# Usage:  tools/cloudcheck/check.sh [SOURCE_ROOT] [-t app,widget,tour] [-c Debug,Release] [-k]
#                                   [--sdk SDK_DIR | --compare SDK_DIR]
#         tools/cloudcheck/check.sh --selftest [--sdk SDK_DIR]
#   SOURCE_ROOT  checkout to check (default: the repository that contains this script)
#   -t           targets (default: app,widget,tour)
#   -c           configurations (default: Debug,Release; Debug = -Onone -D DEBUG, Release = -O)
#   -k           keep the work directory and print where it is
#   --sdk        check against the iPhoneOS SDK in SDK_DIR instead of the stubs
#   --compare    check against the stubs and against SDK_DIR; report only where the two differ
#   --selftest   compile selftest/KnownGood.swift (idioms the real SDK accepts without diagnostics) with the
#                app settings; any diagnostic there is a stub (or harness) bug
# Env:    SWIFT_BIN  toolchain bin directory (default: the Swift 6.4 toolchain under /home/claude/toolchain,
#                    else swiftc on PATH)
#         CLOUDCHECK_ENTRY_NONISOLATED=1  expand @Entry with a `nonisolated` key type (to compare)
# Exit:   0 no errors (with --compare: no differences), 1 errors in the sources (differences), 2 harness
#         failure.
# Runs from any directory. The first --sdk run builds the SDK's Swift modules from their interfaces into
# ~/.cache/cloudcheck (about two minutes on two cores); later runs reuse them.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/../.." && pwd)"
TARGETS="app,share"
CONFIGS="Debug,Release"
KEEP=0
SELFTEST=0
MODE=stub
SDK=""
DEPLOYMENT_TARGET=27.0   # IPHONEOS_DEPLOYMENT_TARGET in Laqta.xcodeproj

die() { echo "cloudcheck: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in -t|-c|--sdk|--compare) [ $# -ge 2 ] || die "$1 needs a value" ;; esac
    case "$1" in
        -t) TARGETS="$2"; shift 2 ;;
        -c) CONFIGS="$2"; shift 2 ;;
        -k) KEEP=1; shift ;;
        --selftest) SELFTEST=1; shift ;;
        --sdk) MODE=sdk; SDK="$2"; shift 2 ;;
        --compare) MODE=compare; SDK="$2"; shift 2 ;;
        -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
        -*) die "unknown option $1" ;;
        *) SRC="$(cd "$1" && pwd)"; shift ;;
    esac
done

DEFAULT_BIN=/home/claude/toolchain/swift-6.4.0-RELEASE-ubuntu24.04/usr/bin
SWIFT_BIN="${SWIFT_BIN:-$DEFAULT_BIN}"
if [ -x "$SWIFT_BIN/swiftc" ]; then SWIFTC="$SWIFT_BIN/swiftc"; else SWIFTC="$(command -v swiftc || true)"; fi
[ -n "$SWIFTC" ] || die "swiftc not found (set SWIFT_BIN)"
SWIFT_VERSION_LINE="$("$SWIFTC" --version 2>&1 | head -1)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cloudcheck.XXXXXX")"
if [ "$KEEP" = 1 ]; then echo "work directory: $WORK"; else trap 'rm -rf "$WORK"' EXIT; fi
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/cloudcheck"

# ---- 1. Stub modules (cached by content) --------------------------------------------------------------
# Built the way Apple builds the SDK modules: their .swiftinterface files say `-language-mode 5` plus a
# few upcoming features (listed per module below). Swift 6 mode would change what clients see: a
# `@MainActor () -> Void` parameter would become implicitly @Sendable (SE-0434), protocols would inherit
# isolation from the protocols they refine, and the module would count as concurrency-checked (which
# turns @preconcurrency-suppressed diagnostics into warnings).
MODULES="ObjectiveC CoreGraphics CoreText UIKit UserNotifications SwiftUI WidgetKit XCTest"
stub_flags() {
    case "$1" in
        SwiftUI) echo "-enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility" ;;
        WidgetKit) echo "-enable-upcoming-feature MemberImportVisibility" ;;
        *) echo "" ;;
    esac
}
HASH="$( (cat "$HERE"/Stubs/*/*.swift "$HERE"/Stubs/*.swift "$0"; echo "$SWIFT_VERSION_LINE") | sha1sum | cut -c1-16)"
CACHE="$CACHE_ROOT/modules-$HASH"
build_stubs() {
    [ -f "$CACHE/.complete" ] && return 0
    local tmp="$CACHE_ROOT/building-$$"
    rm -rf "$tmp"; mkdir -p "$tmp"
    for m in $MODULES; do
        # shellcheck disable=SC2046
        if ! "$SWIFTC" -emit-module -parse-as-library -module-name "$m" -swift-version 5 $(stub_flags "$m") \
                -enable-library-evolution -suppress-warnings -I "$tmp" \
                -emit-module-path "$tmp/$m.swiftmodule" "$HERE/Stubs/$m/$m.swift" \
                -diagnostic-style llvm > "$WORK/stub-$m.log" 2>&1; then
            echo "cloudcheck: stub module $m failed to build:" >&2
            cat "$WORK/stub-$m.log" >&2
            rm -rf "$tmp"
            exit 2
        fi
    done
    touch "$tmp/.complete"
    # Publish atomically; drop module sets built from older stub sources.
    [ -f "$CACHE/.complete" ] || rm -rf "$CACHE"
    if mv -T "$tmp" "$CACHE" 2>/dev/null; then
        find "$CACHE_ROOT" -maxdepth 1 -name 'modules-*' ! -name "modules-$HASH" -mmin +60 -exec rm -rf {} + 2>/dev/null || true
    else
        rm -rf "$tmp"   # another run published the same set first
    fi
}

# ---- 1b. A real iPhoneOS SDK (--sdk / --compare) ------------------------------------------------------
# The Linux toolchain can type-check for an iOS target once the SDK's Swift modules are built from their
# .swiftinterface files. Two adjustments: SwiftShims is exposed through a resource directory whose top-level
# module map points at the SDK's shims (recent SDKs turn off Clang's sub-directory module map search), and
# XCTest, which the SDK does not contain, is the stub module built for the iOS target.
setup_sdk() {
    [ -n "$SDK" ] || die "--sdk/--compare need an SDK directory"
    SDK="$(cd "$SDK" && pwd)" || die "no SDK at $SDK"
    [ -d "$SDK/System/Library/Frameworks/SwiftUI.framework" ] || die "$SDK is not an iPhoneOS SDK (no SwiftUI.framework)"
    if [ -f "$SDK/usr/lib/swift/Swift.swiftmodule/arm64-apple-ios.swiftinterface" ]; then ARCH=arm64; else ARCH=arm64e; fi
    SDK_TARGET="$ARCH-apple-ios$DEPLOYMENT_TARGET"
    # The SDK's modules (built from its interfaces, ~250 MB) depend only on the SDK and the compiler.
    SDKC="$CACHE_ROOT/sdk-$(echo "$SDK|$SWIFT_VERSION_LINE" | sha1sum | cut -c1-16)"
    RES="$SDKC/resource"
    MCACHE="$SDKC/module-cache"
    if [ ! -f "$RES/module.modulemap" ]; then
        rm -rf "$RES"; mkdir -p "$RES" "$MCACHE"
        local toolres; toolres="$(cd "$(dirname "$SWIFTC")/../lib/swift" && pwd)"
        for d in clang host apinotes; do ln -s "$toolres/$d" "$RES/$d"; done
        local shims="$SDK/usr/lib/swift/shims"; [ -f "$shims/module.modulemap" ] || shims="$toolres/shims"
        ln -s "$shims" "$RES/shims"
        sed -n 's/^module \([A-Za-z_]*\).*/extern module \1 "shims\/module.modulemap"/p' "$shims/module.modulemap" > "$RES/module.modulemap.tmp"
        mv "$RES/module.modulemap.tmp" "$RES/module.modulemap"
    fi
    # The XCTest stub, built for the iOS target against this SDK.
    XSTUBS="$SDKC/xctest-$(sha1sum < "$HERE/Stubs/XCTest/XCTest.swift" | cut -c1-16)"
    if [ ! -f "$XSTUBS/XCTest.swiftmodule" ]; then
        local tmp="$SDKC/building-$$"
        rm -rf "$tmp"; mkdir -p "$tmp"
        if ! "$SWIFTC" -emit-module -parse-as-library -module-name XCTest -swift-version 5 -enable-library-evolution \
                -suppress-warnings -target "$SDK_TARGET" -sdk "$SDK" -resource-dir "$RES" -module-cache-path "$MCACHE" \
                -emit-module-path "$tmp/XCTest.swiftmodule" "$HERE/Stubs/XCTest/XCTest.swift" \
                -diagnostic-style llvm > "$WORK/sdk-xctest.log" 2>&1; then
            echo "cloudcheck: the XCTest stub failed to build against $SDK:" >&2
            cat "$WORK/sdk-xctest.log" >&2
            rm -rf "$tmp"
            exit 2
        fi
        rm -rf "$SDKC"/xctest-*
        mv -T "$tmp" "$XSTUBS" 2>/dev/null || rm -rf "$tmp"
    fi
}

# ---- 2. Targets (from Laqta.xcodeproj) ------------------------------------------------------------------
# Project-wide: SWIFT_VERSION 6.0, SWIFT_APPROACHABLE_CONCURRENCY=YES on every target
# (NonisolatedNonsendingByDefault + InferIsolatedConformances), DEBUG in Debug only, deployment target 26.0.
# app/widget: SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor, SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY=YES;
# the widget is an app extension.
# `core`: the files that do not depend on SwiftData's @Model types, so they can be
# checked on Linux where Apple's SwiftDataMacros plugin does not exist.
target_find() {   # target dir   (run from the tree root)
    if [ "$1" = core ] && [ -f "$HERE/core-files.txt" ]; then
        find "$2" -name '*.swift' | sort | grep -Fxf "$HERE/core-files.txt" || true
    else
        find "$2" -name '*.swift' | sort
    fi
}
target_dirs() {
    case "$1" in
        app) echo "Laqta Shared" ;;
        core) echo "Laqta Shared LaqtaShare" ;;
        share) echo "LaqtaShare Shared" ;;
        *) die "unknown target $1" ;;
    esac
}
target_module() {
    case "$1" in app) echo Laqta ;; share) echo LaqtaShare ;; core) echo LaqtaCore ;; selftest) echo SelfTest ;; esac
}
target_flags() {
    case "$1" in
        app|core|selftest) echo "-default-isolation MainActor -enable-upcoming-feature MemberImportVisibility" ;;
        share) echo "-default-isolation MainActor -enable-upcoming-feature MemberImportVisibility -application-extension" ;;
    esac
}
COMMON=(-swift-version 6 -enable-upcoming-feature NonisolatedNonsendingByDefault
        -enable-upcoming-feature InferIsolatedConformances -parse-as-library -wmo
        -diagnostic-style llvm -no-color-diagnostics)

# compile KIND TARGET CONFIG LOG FILE...   (KIND: stub or sdk)
compile() {
    local kind="$1" t="$2" c="$3" log="$4"; shift 4
    local opt
    case "$c" in
        Debug) opt=(-Onone -D DEBUG) ;;
        Release) opt=(-O) ;;
        *) die "unknown configuration $c" ;;
    esac
    local env_flags extra=()
    if [ "$kind" = stub ]; then
        env_flags=(-I "$CACHE")
        extra=("$HERE/Stubs/DarwinShims.swift")
    else
        env_flags=(-target "$SDK_TARGET" -sdk "$SDK" -resource-dir "$RES" -module-cache-path "$MCACHE" -I "$XSTUBS")
        [ "$t" = tour ] || extra=("$HERE/Stubs/RealSDKShims.swift")
    fi
    # shellcheck disable=SC2046
    "$SWIFTC" -emit-sil -o /dev/null -module-name "$(target_module "$t")" "${opt[@]}" "${COMMON[@]}" "${env_flags[@]}" \
        $(target_flags "$t") "$@" "${extra[@]}" > "$log" 2>&1 || true
}

if [ "$MODE" = compare ] && [ "$SELFTEST" = 1 ]; then die "--selftest takes --sdk, not --compare"; fi
if [ "$MODE" != sdk ]; then build_stubs; fi
if [ "$MODE" != stub ]; then setup_sdk; fi

if [ "$SELFTEST" = 1 ]; then
    kind=stub; [ "$MODE" = sdk ] && kind=sdk
    python3 "$HERE/preprocess.py" --mode "$kind" "$HERE" "$WORK/selftest-src" selftest/KnownGood.swift > /dev/null \
        || die "preprocessing failed"
    compile "$kind" selftest Debug "$WORK/selftest.log" "$WORK/selftest-src/selftest/KnownGood.swift"
    if grep -E '(error|warning):' "$WORK/selftest.log"; then
        echo "cloudcheck selftest ($kind): FAILED (the diagnostics above are harness bugs)"; exit 1
    fi
    echo "cloudcheck selftest ($kind): OK"; exit 0
fi

# ---- 3. Preprocess every file once per mode ------------------------------------------------------------
ALL_FILES=()
for t in ${TARGETS//,/ }; do
    for d in $(target_dirs "$t"); do
        [ -d "$SRC/$d" ] || continue
        while IFS= read -r f; do ALL_FILES+=("$f"); done < <(cd "$SRC" && target_find "$t" "$d")
    done
done
[ ${#ALL_FILES[@]} -gt 0 ] || die "no Swift sources under $SRC for targets $TARGETS"
mapfile -t ALL_FILES < <(printf '%s\n' "${ALL_FILES[@]}" | sort -u)
KINDS="stub"; [ "$MODE" = sdk ] && KINDS="sdk"; [ "$MODE" = compare ] && KINDS="stub sdk"
for k in $KINDS; do
    python3 "$HERE/preprocess.py" --mode "$k" "$SRC" "$WORK/$k" "${ALL_FILES[@]}" > "$WORK/rewrites-$k.txt" \
        || die "preprocessing failed"
done

# ---- 4. Compile ---------------------------------------------------------------------------------------------
for k in $KINDS; do
    mkdir -p "$WORK/logs-$k"
    for t in ${TARGETS//,/ }; do
        FILES=()
        for d in $(target_dirs "$t"); do
            [ -d "$WORK/$k/$d" ] || continue
            while IFS= read -r f; do FILES+=("$WORK/$k/$f"); done < <(cd "$WORK/$k" && target_find "$t" "$d")
        done
        [ ${#FILES[@]} -gt 0 ] || die "target $t: no Swift sources under $SRC/{$(target_dirs "$t" | tr ' ' ',')}"
        for c in ${CONFIGS//,/ }; do
            compile "$k" "$t" "$c" "$WORK/logs-$k/$t.$c.log" "${FILES[@]}"
        done
    done
done

# ---- 5. Report ------------------------------------------------------------------------------------------------
case "$MODE" in
    stub) echo "cloudcheck: $SRC  (stubs; swiftc: $SWIFT_VERSION_LINE)" ;;
    sdk) echo "cloudcheck: $SRC  (SDK $SDK, $SDK_TARGET; XCTest stubbed; swiftc: $SWIFT_VERSION_LINE)" ;;
    compare) echo "cloudcheck: $SRC  (stubs vs SDK $SDK, $SDK_TARGET; swiftc: $SWIFT_VERSION_LINE)" ;;
esac
for k in $KINDS; do
    if [ -s "$WORK/rewrites-$k.txt" ]; then
        echo "== Line-preserving rewrites applied to the $k work copy"
        sed 's/^/   /' "$WORK/rewrites-$k.txt"
        echo
    fi
done
LOGS=()
for t in ${TARGETS//,/ }; do for c in ${CONFIGS//,/ }; do LOGS+=("$t.$c.log"); done; done
set +e
if [ "$MODE" = compare ]; then
    python3 "$HERE/compare.py" "$SRC" "$HERE/Stubs" "$WORK/stub" "$WORK/logs-stub" "$WORK/sdk" "$WORK/logs-sdk" "${LOGS[@]}"
    STATUS=$?
else
    k=$KINDS
    python3 "$HERE/report.py" "$WORK/$k" "$SRC" "$HERE/Stubs" "${LOGS[@]/#/$WORK/logs-$k/}"
    STATUS=$?
fi
set -e
exit $STATUS
