#!/usr/bin/env bash
# Type-check every Swift file of the app against the real iOS 27 SDK on Linux, without a Mac.
#
# Setup from a fresh cloud machine (once; about 1.5 GB of downloads, all from allowed hosts):
#   1. Swift 6.4 for Ubuntu 24.04 (download.swift.org):
#        mkdir -p /opt/swift && cd /opt/swift
#        curl -sSLO https://download.swift.org/swift-6.4.0-release/ubuntu2404/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE-ubuntu24.04.tar.gz
#        tar xzf swift-6.4.0-RELEASE-ubuntu24.04.tar.gz
#   2. The iOS 27 SDK from the GitHub mirror, only that folder (about 400 MB):
#        git clone --depth 1 --filter=blob:none --no-checkout https://github.com/xybp888/ios-sdks /home/claude/xybp888/ios-sdks
#        cd /home/claude/xybp888/ios-sdks && git sparse-checkout init --cone && git sparse-checkout set iPhoneOS27.0.sdk && git checkout
#
# Usage (from the repository root):  tools/cloudcheck/check.sh            check the app (target Sakka)
#                                     tools/cloudcheck/check.sh --fresh    rebuild the SDK copy and the module cache first
# Environment: SWIFT_TOOLCHAIN (…/usr of the toolchain), IOS_SDK (the iPhoneOS27.0.sdk folder).
#
# What it does, and why:
#   - The mirror has arm64e interfaces only, so the target is arm64e-apple-ios26.0 (the app's deployment target).
#   - Swift's Linux resource folder brings Linux Foundation, CoreFoundation and Dispatch, which would shadow the SDK's,
#     so the check uses a resource folder with only shims, clang and host, and adds the shims to the import path.
#   - In iOS 27 @State is also a macro whose plugin ships only with Xcode. A hard-linked copy of the SDK drops the
#     `macro State` declarations from SwiftUICore, so @State is the property wrapper here. Code must therefore follow
#     both forms: give every @State a value where it is declared (an optional one gets an explicit `= nil`) and never
#     assign `_x = State(…)` in an init. Avoid #Preview, @Entry and @Animatable for the same reason.
#   - The flags match the project: Swift 6, MainActor default isolation, approachable concurrency, member import visibility.
#   - It emits SIL (whole module) instead of only type-checking, so the mandatory SIL passes run too: definite
#     initialisation and the data-race (region isolation) checks that a plain -typecheck never reaches.
#   - Before compiling, a lint holds the code to the @State macro's rules, which the compile itself can't see here.
# It prints the compiler's errors and warnings and exits non-zero if there is any (warnings from the SDK's own C
# headers are filtered out). Planted mistakes it caught on round 10 (8 Oct 2026): a wrong type, a missing SwiftUI
# modifier, and a MainActor call from a nonisolated function; on round 11 (9 Oct 2026): a data race between a
# nonisolated function and a MainActor task, a constant read before it is set (both only in SIL, which -typecheck
# never reaches), and an optional @State without `= nil` (the lint).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TC="${SWIFT_TOOLCHAIN:-/opt/swift/swift-6.4.0-RELEASE-ubuntu24.04/usr}"
SRC_SDK="${IOS_SDK:-/home/claude/xybp888/ios-sdks/iPhoneOS27.0.sdk}"
CACHE="$ROOT/tools/cloudcheck/.cache"
SDK="$CACHE/sdk27"
RDIR="$CACHE/rdir"

[ -x "$TC/bin/swiftc" ] || { echo "No Swift toolchain at $TC (see the top of this file)"; exit 2; }
[ -d "$SRC_SDK/System" ] || { echo "No iOS SDK at $SRC_SDK (see the top of this file)"; exit 2; }

if [ "${1:-}" = "--fresh" ]; then rm -rf "$CACHE"; fi
mkdir -p "$CACHE"

if [ ! -f "$SDK/.ready" ]; then
  rm -rf "$SDK"
  cp -al "$SRC_SDK" "$SDK"
  IFACE="$SDK/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface"
  python3 - "$IFACE" <<'PY'
import os, re, sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
out, i, removed = [], 0, 0
while i < len(lines):
    if re.search(r"public macro State(\(|<)", lines[i]):
        j = i
        while not lines[j].rstrip().endswith(")") or (j == i and lines[j].rstrip().endswith("#externalMacro(")):
            j += 1
        removed += 1
        i = j + 1
        continue
    out.append(lines[i])
    i += 1
os.remove(p)  # break the hard link before writing, so the mirror stays untouched
open(p, "w", encoding="utf-8").write("\n".join(out))
if removed != 3:
    sys.exit(f"expected 3 State macros in SwiftUICore, removed {removed}")
PY
  touch "$SDK/.ready"
fi

if [ ! -d "$RDIR" ]; then
  mkdir -p "$RDIR"
  for d in shims clang host; do ln -s "$TC/lib/swift/$d" "$RDIR/$d"; done
fi

mapfile -t FILES < <(cd "$ROOT" && find Sakka -name '*.swift' | sort)

# What the compile below cannot see, because its SDK copy has no @State macro: the macro's own rules.
# Every @State must get its value where it is declared (an optional too: `= nil`), and no init may write `_x = State(…)`.
# Round 11 (9 Oct 2026) found two optionals in RootView without `= nil` that this check passed and Xcode 27 would not.
STATE_LINT=$(cd "$ROOT" && { grep -rnE '^[[:space:]]*@State\b' Sakka --include='*.swift' | grep -v '=' ;
                              grep -rnE '\b_[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*State\(' Sakka --include='*.swift'; } || true)
if [ -n "$STATE_LINT" ]; then
  echo "$STATE_LINT"
  echo "FAILED: @State without a value where it is declared (Xcode 27's @State macro needs one; an optional needs = nil)"
  exit 1
fi

echo "Checking ${#FILES[@]} files against $(basename "$SRC_SDK") with $("$TC/bin/swiftc" --version 2>&1 | head -1)"

LOG="$CACHE/last.log"
set +e
(cd "$ROOT" && "$TC/bin/swiftc" -emit-sil -wmo -o /dev/null -parse-as-library \
  -module-name Sakka \
  -target arm64e-apple-ios26.0 \
  -sdk "$SDK" -resource-dir "$RDIR" -I "$RDIR/shims" \
  -module-cache-path "$CACHE/modules" \
  -plugin-path "$TC/lib/swift/host/plugins" \
  -swift-version 6 -default-isolation MainActor \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature MemberImportVisibility \
  -Xcc -Wno-nullability-completeness -Xcc -Wno-nullability-inferred-on-nested-type \
  "${FILES[@]}") > "$LOG" 2>&1
STATUS=$?
set -e

# Keep the diagnostics about our files.
grep -E "^Sakka/.*: (error|warning)" "$LOG" | sort -u > "$CACHE/ours.log" || true
if [ -s "$CACHE/ours.log" ]; then
  cat "$CACHE/ours.log"
  echo "FAILED: $(grep -c ': error' "$CACHE/ours.log" || true) errors, $(grep -c ': warning' "$CACHE/ours.log" || true) warnings"
  exit 1
fi
if [ $STATUS -ne 0 ]; then
  grep -E "error" "$LOG" | head -20
  echo "FAILED: the compiler stopped (see $LOG)"
  exit 1
fi
echo "OK: no errors and no warnings"
