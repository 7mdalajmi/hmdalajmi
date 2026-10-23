#!/usr/bin/env python3
"""cloudcheck preprocessing: copy Swift sources to a work tree with Linux-only rewrites.

Every rewrite keeps the line count (and, where possible, the columns) so compiler diagnostics map back
to the original file and line unchanged. Nothing here ever touches the original sources.

Two modes. `stub` (default) prepares sources for the stub modules on Linux; `sdk` prepares them for a
real iPhoneOS SDK (check.sh --sdk), where only Apple's closed-source macros need replacing.

Rewrites (both modes):
  @Entry var x: T = v     inside `extension EnvironmentValues` -> the macro's expansion on the same
                          line: a computed property plus a private EnvironmentKey type. (Apple's
                          SwiftUIMacros plugin ships only with Xcode.)
  #Preview ... { ... }    -> blanked (the preview macro and its body are not part of the build).
Rewrites (sdk mode only):
  @State                  -> `@STATE` (same length), a typealias of the State property wrapper declared
                          in Stubs/RealSDKShims.swift: the iOS 27 SDK declares a `State()` macro whose
                          plugin ships only with Xcode, so the property wrapper (the Xcode 26 behaviour,
                          also what the stubs model) is used instead.
Rewrites (stub mode only):
  #selector(              -> ` Selector(` (same length; no Objective-C runtime on Linux, so the method is
                          referenced as a value instead; see Stubs/ObjectiveC).
  override ... func f     inside `extension UI.../NS...` -> `func f__cloudcheck_objc_override` (overriding
                          an @objc method from an extension is legal only with the ObjC runtime; the
                          body is still type-checked).
  #if/#elseif conditions  -> os(iOS) and arch(arm64) become true, other os()/arch() false,
                          targetEnvironment(macCatalyst) false (an iOS device build).

Usage: preprocess.py [--mode stub|sdk] SRC_ROOT OUT_ROOT REL_PATH...   (prints a rewrite log on stdout)
"""
import os
import re
import sys

# Only EnvironmentValues is modelled; @Entry in FocusedValues/Transaction/ContainerValues is reported.
ENTRY_KEYS = {
    "EnvironmentValues": "SwiftUI.EnvironmentKey",
}
ENTRY_UNSUPPORTED = ("FocusedValues", "Transaction", "ContainerValues")

# CLOUDCHECK_ENTRY_NONISOLATED=1 marks the generated key `nonisolated` (to compare both expansions).
ENTRY_NONISOLATED = os.environ.get("CLOUDCHECK_ENTRY_NONISOLATED") == "1"


def blank(text):
    """Replace every character except newlines with a space."""
    return "".join(c if c == "\n" else " " for c in text)


def scan_code(src):
    """Yield (index, char, in_code) skipping strings and comments (approximate, good enough for
    brace matching in ordinary Swift)."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                yield k, src[k], False
            i = j
            continue
        if src.startswith("/*", i):
            depth, k = 1, i + 2
            while k < n and depth:
                if src.startswith("/*", k):
                    depth += 1; k += 2
                elif src.startswith("*/", k):
                    depth -= 1; k += 2
                else:
                    k += 1
            for m in range(i, k):
                yield m, src[m], False
            i = k
            continue
        if src.startswith('"""', i):
            k = src.find('"""', i + 3)
            k = n if k < 0 else k + 3
            for m in range(i, k):
                yield m, src[m], False
            i = k
            continue
        if c == '"':
            k = i + 1
            while k < n and src[k] != '"' and src[k] != "\n":
                k += 2 if src[k] == "\\" else 1
            k = min(k + 1, n)
            for m in range(i, k):
                yield m, src[m], False
            i = k
            continue
        yield i, c, True
        i += 1


def matching_brace(src, open_index):
    depth = 0
    for i, c, code in scan_code(src[open_index:]):
        if not code:
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return open_index + i
    return -1


def strip_previews(src, log, rel):
    out = src
    for m in reversed(list(re.finditer(r"(?m)^[ \t]*#Preview\b", src))):
        start = m.start()
        brace = out.find("{", m.end())
        if brace < 0:
            continue
        end = matching_brace(out, brace)
        if end < 0:
            continue
        line = out.count("\n", 0, start) + 1
        out = out[:start] + blank(out[start:end + 1]) + out[end + 1:]
        log.append(f"{rel}:{line}: #Preview removed")
    return out


ENTRY_RE = re.compile(
    r"^(?P<indent>[ \t]*)@Entry\s+(?P<mods>(?:(?:public|internal|fileprivate|private|package|nonisolated)\s+)*)"
    r"var\s+(?P<name>\w+)\s*:\s*(?P<type>[^=]+?)\s*(?:=\s*(?P<value>.+?))?\s*$")


def expand_entries(src, log, rel):
    lines = src.split("\n")
    container = None  # name of the extended type while inside its extension
    depth = 0
    container_depth = None
    for idx, line in enumerate(lines):
        stripped = line.strip()
        m_ext = re.match(r"^(?:public\s+|internal\s+|private\s+|fileprivate\s+|nonisolated\s+)*extension\s+(?:SwiftUI\.)?(\w+)\b", stripped)
        if m_ext and container is None:
            pending = m_ext.group(1)
        else:
            pending = None
        if "@Entry" in line and container in ENTRY_UNSUPPORTED:
            log.append(f"{rel}:{idx + 1}: HARNESS ERROR: @Entry in {container} is not modelled (only EnvironmentValues)")
        if "@Entry" in line and container in ENTRY_KEYS:
            m = ENTRY_RE.match(line)
            if not m:
                log.append(f"{rel}:{idx + 1}: HARNESS ERROR: @Entry form not understood (needs `@Entry var name: Type = value` on one line)")
            else:
                name, typ = m.group("name"), m.group("type").strip()
                value = m.group("value")
                if value is None:
                    if typ.endswith("?"):
                        value = "nil"
                    else:
                        log.append(f"{rel}:{idx + 1}: HARNESS ERROR: @Entry without a default value")
                        value = "fatalError()"
                mods = m.group("mods")
                key = f"__Key_{name}"
                iso = "nonisolated " if ENTRY_NONISOLATED else ""
                proto = ENTRY_KEYS[container]
                lines[idx] = (f"{m.group('indent')}{mods}var {name}: {typ} {{ get {{ self[{key}.self] }} "
                              f"set {{ self[{key}.self] = newValue }} }}; "
                              f"private {iso}struct {key}: {proto} {{ typealias Value = {typ}; "
                              f"static var defaultValue: Value {{ {value} }} }}")
                log.append(f"{rel}:{idx + 1}: @Entry {name} expanded ({container})")
        # track braces to know when the extension ends
        for _, c, code in scan_code(line + "\n"):
            if not code:
                continue
            if c == "{":
                depth += 1
                if pending is not None and container is None:
                    container, container_depth, pending = pending, depth, None
            elif c == "}":
                if container is not None and depth == container_depth:
                    container, container_depth = None, None
                depth -= 1
    return "\n".join(lines)


OVERRIDE_RE = re.compile(r"^(?P<pre>\s*)override(?P<mid>\s+(?:(?:open|public|internal|fileprivate|private|final|@MainActor|nonisolated)\s+)*)func\s+(?P<name>\w+)")


def neutralize_objc_overrides(src, log, rel):
    """Overriding an Objective-C method from an extension (e.g. `extension UINavigationController {
    override open func viewDidLoad() }`) is legal on Darwin, where the base is @objc, and impossible on
    Linux. Inside extensions of UIKit/Foundation classes (UI*/NS* names), turn such an override into an
    ordinary method with a harness name, so its body (including `super.<name>()`) is still type-checked
    and the rest of the module still reaches the SIL diagnostics."""
    lines = src.split("\n")
    container = None
    depth = 0
    container_depth = None
    for idx, line in enumerate(lines):
        stripped = line.strip()
        pending = None
        m_ext = re.match(r"^(?:public\s+|internal\s+|private\s+|fileprivate\s+|nonisolated\s+)*extension\s+((?:UI|NS)\w+)\b", stripped)
        if m_ext and container is None:
            pending = m_ext.group(1)
        if container is not None:
            m = OVERRIDE_RE.match(line)
            if m:
                mid = re.sub(r"\b(open|public)\b", lambda w: " " * len(w.group(0)), m.group("mid"))
                lines[idx] = (m.group("pre") + " " * len("override") + mid + "func "
                              + m.group("name") + "__cloudcheck_objc_override" + line[m.end():])
                log.append(f"{rel}:{idx + 1}: Objective-C override in extension of {container} renamed (Darwin-only construct)")
        for _, c, code in scan_code(line + "\n"):
            if not code:
                continue
            if c == "{":
                depth += 1
                if pending is not None and container is None:
                    container, container_depth, pending = pending, depth, None
            elif c == "}":
                if container is not None and depth == container_depth:
                    container, container_depth = None, None
                depth -= 1
    return "\n".join(lines)


SELECTOR_RE = re.compile(r"#selector\(")


def rewrite_selectors(src, log, rel):
    out_lines = []
    for idx, line in enumerate(src.split("\n")):
        if "#selector(" in line:
            log.append(f"{rel}:{idx + 1}: #selector rewritten")
            line = SELECTOR_RE.sub(" Selector(", line)
        out_lines.append(line)
    return "\n".join(out_lines)


def rewrite_conditions(src, log, rel):
    out_lines = []
    for idx, line in enumerate(src.split("\n")):
        s = line.lstrip()
        if s.startswith("#if") or s.startswith("#elseif"):
            new = line
            new = re.sub(r"\bos\(\s*iOS\s*\)", "true", new)
            new = re.sub(r"\bos\(\s*\w+\s*\)", "false", new)
            new = re.sub(r"\barch\(\s*arm64\s*\)", "true", new)
            new = re.sub(r"\barch\(\s*\w+\s*\)", "false", new)
            new = re.sub(r"\btargetEnvironment\(\s*macCatalyst\s*\)", "false", new)
            if new != line:
                log.append(f"{rel}:{idx + 1}: platform condition set for an iOS device build")
            line = new
        out_lines.append(line)
    return "\n".join(out_lines)


STATE_RE = re.compile(r"@State\b(?=\s)")


def rewrite_state(src, log, rel):
    out_lines, changed = [], []
    for idx, line in enumerate(src.split("\n")):
        new = line
        if "@State" in line:
            new = "".join(STATE_RE.sub("@STATE", part) if i % 2 == 0 else part
                          for i, part in enumerate(re.split(r'("(?:[^"\\]|\\.)*")', line)))
            if new != line:
                changed.append(idx + 1)
        out_lines.append(new)
    if changed:
        more = f" (also lines {', '.join(map(str, changed[1:]))})" if len(changed) > 1 else ""
        log.append(f"{rel}:{changed[0]}: @State -> @STATE (State property wrapper){more}")
    return "\n".join(out_lines)


def main():
    args = sys.argv[1:]
    mode = "stub"
    if args[:1] == ["--mode"]:
        mode, args = args[1], args[2:]
    if len(args) < 3 or mode not in ("stub", "sdk"):
        print(__doc__)
        sys.exit(2)
    src_root, out_root, rels = args[0], args[1], args[2:]
    log = []
    for rel in rels:
        with open(os.path.join(src_root, rel), encoding="utf-8") as f:
            src = f.read()
        before = src.count("\n")
        src = strip_previews(src, log, rel)
        src = expand_entries(src, log, rel)
        if mode == "sdk":
            src = rewrite_state(src, log, rel)
        else:
            src = rewrite_selectors(src, log, rel)
            src = neutralize_objc_overrides(src, log, rel)
            src = rewrite_conditions(src, log, rel)
        assert src.count("\n") == before, f"line count changed in {rel}"
        dest = os.path.join(out_root, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "w", encoding="utf-8") as f:
            f.write(src)
    for entry in log:
        print(entry)


if __name__ == "__main__":
    main()
