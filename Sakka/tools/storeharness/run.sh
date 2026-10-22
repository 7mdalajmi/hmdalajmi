#!/usr/bin/env bash
# Builds and runs the Sakka store harness on Linux, in one command.
#
#   tools/storeharness/run.sh                   this repository (or the one at $SAKKA_REPO)
#   tools/storeharness/run.sh /path/to/Sakka    another checkout
#   tools/storeharness/run.sh --quiet [repo]    print only failures and the summary
#
# It compiles the app's own files straight from the repo, unchanged: the two stores (Sakka/Baloot/BalootStore.swift,
# Sakka/Hand/HandStore.swift), every file in Sakka/Rules (the rules, Digits, and from build 4 Saves.swift),
# Sakka/App/Settings.swift and Sakka/Design/Palette.swift. The scenarios follow build 4's views and decisions.
# Linux has no SwiftUI, UIKit or AVFoundation, so it adds a thin module named SwiftUI (shims/) and replaces three files
# whole (fakes/): Motion.swift, Speaker.swift and SakkaApp.swift. The scenarios (scenarios/) drive the stores as the views do.
# Exit status: 0 when every check passes, 1 when a check fails, 2 when the build fails.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
QUIET=0
REPO_ARG=""
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    *) REPO_ARG="$arg" ;;
  esac
done
REPO="$(cd "${REPO_ARG:-${SAKKA_REPO:-$HERE/../..}}" && pwd)"
TC="${SWIFT_TOOLCHAIN:-/opt/swift/swift-6.4.0-RELEASE-ubuntu24.04/usr}"
SWIFTC="$TC/bin/swiftc"
BUILD="$HERE/.build"
mkdir -p "$BUILD/shim"

[ -x "$SWIFTC" ] || { echo "No Swift toolchain at $TC (set SWIFT_TOOLCHAIN)"; exit 2; }

APP_FILES=(
  Sakka/Baloot/BalootStore.swift
  Sakka/Hand/HandStore.swift
  Sakka/App/Settings.swift
  Sakka/Design/Palette.swift
)
for f in "${APP_FILES[@]}"; do
  [ -f "$REPO/$f" ] || { echo "Missing $REPO/$f"; exit 2; }
done
# Every file of the rules folder, whatever a build adds there (build 4 added Saves.swift).
while IFS= read -r f; do APP_FILES+=("$f"); done < <(cd "$REPO" && find Sakka/Rules -name '*.swift' | sort)

echo "Sakka store harness"
echo "  repo:   $REPO ($(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo 'not a git checkout'))"
echo "  swift:  $("$SWIFTC" --version 2>&1 | head -1)"
echo "  files:  ${APP_FILES[*]}"

# The three replaced files: say so if they changed since their fakes were written, so the fakes get a look.
while read -r sum path; do
  [ -z "$path" ] && continue
  if [ ! -f "$REPO/$path" ]; then
    echo "  NOTE: $path is gone from the repo; check that its fake in fakes/ is still needed."
  elif [ "$(sha256sum "$REPO/$path" | cut -d' ' -f1)" != "$sum" ]; then
    echo "  NOTE: $path changed since its fake was written; compare it with fakes/$(basename "$path" | sed 's/SakkaApp/AppModel/')."
  fi
done < "$HERE/fakes/REPLACED.sha256"

FLAGS=(-swift-version 6 -default-isolation MainActor
  -enable-upcoming-feature NonisolatedNonsendingByDefault
  -enable-upcoming-feature InferIsolatedConformances
  -enable-upcoming-feature MemberImportVisibility)

# 1. The SwiftUI stand-in module.
"$SWIFTC" -parse-as-library -emit-library -static -emit-module -module-name SwiftUI \
  -emit-module-path "$BUILD/shim/SwiftUI.swiftmodule" -swift-version 6 \
  -o "$BUILD/shim/libSwiftUI.a" "$HERE/shims/SwiftUI/SwiftUI.swift" > "$BUILD/shim.log" 2>&1 \
  || { cat "$BUILD/shim.log"; echo "BUILD FAILED (shim)"; exit 2; }

# 2. The app's files, the fakes and the scenarios, in one module with the app's settings.
SOURCES=()
for f in "${APP_FILES[@]}"; do SOURCES+=("$REPO/$f"); done
SOURCES+=("$HERE"/fakes/*.swift "$HERE"/support/*.swift "$HERE"/scenarios/*.swift)
if ! "$SWIFTC" -module-name SakkaHarness "${FLAGS[@]}" -I "$BUILD/shim" -L "$BUILD/shim" -lSwiftUI \
     "${SOURCES[@]}" -o "$BUILD/sakka-harness" > "$BUILD/build.log" 2>&1; then
  cat "$BUILD/build.log"
  echo "BUILD FAILED"
  exit 2
fi
# Warnings in the app's own files are worth seeing.
grep -E "^$REPO/.*: warning" "$BUILD/build.log" | sed "s#^$REPO/#  warning in #" || true

# 3. Run, with UserDefaults kept in a throwaway home.
RUNHOME="$(mktemp -d)"
trap 'rm -rf "$RUNHOME"' EXIT
set +e
if [ $QUIET = 1 ]; then
  HOME="$RUNHOME" "$BUILD/sakka-harness" --quiet
else
  HOME="$RUNHOME" "$BUILD/sakka-harness"
fi
STATUS=$?
if [ $STATUS -gt 1 ]; then
  echo "  CRASH: the harness stopped with exit $STATUS: a scenario crashed the app's code (see the error above); later scenarios did not run."
  STATUS=1
fi

# 4. Probes that may crash the process run one by one in their own process.
echo
echo "=== Probes (each in its own process, since they may crash)"
for probe in $(HOME="$RUNHOME" "$BUILD/sakka-harness" --list-probes); do
  OUT="$(HOME="$RUNHOME" SWIFT_BACKTRACE=enable=no "$BUILD/sakka-harness" --probe "$probe" 2>&1)"
  CODE=$?
  if [ $CODE -eq 0 ]; then
    echo "  PASS  probe $probe"
  else
    echo "  FAIL  probe $probe (exit $CODE: crashed or returned false)"
    echo "$OUT" | grep -E "^probe:|Fatal error" | sed 's/^/          /'
    STATUS=1
  fi
done
exit $STATUS
