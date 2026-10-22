#!/usr/bin/env python3
"""Check Sakka.xcodeproj without Xcode.

Usage (from the repository root):  python3 tools/check_pbxproj.py [path/to/project.pbxproj]

It parses project.pbxproj (the OpenStep format Xcode writes) and fails on what would stop Xcode from opening or
building it, or would quietly change the app:
  - a syntax error, a duplicate object id, an unquoted value that is not plain ASCII (Xcode cannot read those);
  - an object without isa, an id that points nowhere or to the wrong kind of object, an object nothing uses;
  - a synchronized folder, group file, Info.plist or xcconfig that is missing on disk;
  - a target that sets MARKETING_VERSION or CURRENT_PROJECT_VERSION itself (they belong to Config/Sakka.xcconfig);
  - a shared scheme naming a target id that is not in the project.
Planted faults it caught on round 10 (8 Oct 2026): a deleted object, a broken reference, an unquoted «صكة».
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

KNOWN = {
    "PBXProject", "PBXGroup", "PBXFileReference", "PBXFileSystemSynchronizedRootGroup",
    "PBXFileSystemSynchronizedBuildFileExceptionSet", "PBXNativeTarget", "PBXSourcesBuildPhase",
    "PBXFrameworksBuildPhase", "PBXResourcesBuildPhase", "PBXCopyFilesBuildPhase", "PBXShellScriptBuildPhase",
    "PBXBuildFile", "PBXTargetDependency", "PBXContainerItemProxy", "XCBuildConfiguration", "XCConfigurationList",
    "PBXVariantGroup", "XCRemoteSwiftPackageReference", "XCSwiftPackageProductDependency",
}

# field -> the kinds it may point to
REFS = {
    ("PBXProject", "mainGroup"): {"PBXGroup"},
    ("PBXProject", "productRefGroup"): {"PBXGroup"},
    ("PBXProject", "buildConfigurationList"): {"XCConfigurationList"},
    ("PBXProject", "targets"): {"PBXNativeTarget"},
    ("PBXGroup", "children"): {"PBXGroup", "PBXFileReference", "PBXFileSystemSynchronizedRootGroup", "PBXVariantGroup"},
    ("PBXNativeTarget", "buildConfigurationList"): {"XCConfigurationList"},
    ("PBXNativeTarget", "buildPhases"): {"PBXSourcesBuildPhase", "PBXFrameworksBuildPhase", "PBXResourcesBuildPhase",
                                         "PBXCopyFilesBuildPhase", "PBXShellScriptBuildPhase"},
    ("PBXNativeTarget", "dependencies"): {"PBXTargetDependency"},
    ("PBXNativeTarget", "fileSystemSynchronizedGroups"): {"PBXFileSystemSynchronizedRootGroup"},
    ("PBXNativeTarget", "productReference"): {"PBXFileReference"},
    ("PBXTargetDependency", "target"): {"PBXNativeTarget"},
    ("PBXTargetDependency", "targetProxy"): {"PBXContainerItemProxy"},
    ("PBXContainerItemProxy", "containerPortal"): {"PBXProject"},
    ("PBXContainerItemProxy", "remoteGlobalIDString"): {"PBXNativeTarget"},
    ("XCConfigurationList", "buildConfigurations"): {"XCBuildConfiguration"},
    ("XCBuildConfiguration", "baseConfigurationReference"): {"PBXFileReference"},
    ("PBXFileSystemSynchronizedRootGroup", "exceptions"): {"PBXFileSystemSynchronizedBuildFileExceptionSet"},
}


class ParseError(Exception):
    pass


def tokenize(text):
    i, n, toks = 0, len(text), []
    while i < n:
        ch = text[i]
        if ch.isspace():
            i += 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j + 1
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            if j < 0:
                raise ParseError("unclosed comment")
            i = j + 2
        elif ch in "{}()=;,":
            toks.append((ch, None, i))
            i += 1
        elif ch == '"':
            j, buf = i + 1, []
            while j < n and text[j] != '"':
                if text[j] == "\\" and j + 1 < n:
                    buf.append({"n": "\n", "t": "\t"}.get(text[j + 1], text[j + 1]))
                    j += 2
                else:
                    buf.append(text[j])
                    j += 1
            if j >= n:
                raise ParseError(f"unclosed string at {i}")
            toks.append(("str", "".join(buf), i))
            i = j + 1
        else:
            m = re.match(r"[A-Za-z0-9_$./:\-]+", text[i:])
            if not m:
                raise ParseError(f"unexpected {text[i:i + 20]!r} at {i}: a value with other characters must be quoted")
            toks.append(("str", m.group(0), i))
            i += len(m.group(0))
    return toks


def parse(text):
    toks = tokenize(text)
    pos = 0

    def value():
        nonlocal pos
        kind, val, at = toks[pos]
        if kind == "{":
            pos += 1
            d = {}
            while toks[pos][0] != "}":
                k = toks[pos]
                if k[0] != "str":
                    raise ParseError(f"expected a key at {k[2]}")
                pos += 1
                if toks[pos][0] != "=":
                    raise ParseError(f"expected = at {toks[pos][2]}")
                pos += 1
                v = value()
                if toks[pos][0] != ";":
                    raise ParseError(f"expected ; at {toks[pos][2]}")
                pos += 1
                if k[1] in d:
                    raise ParseError(f"duplicate key {k[1]}")
                d[k[1]] = v
            pos += 1
            return d
        if kind == "(":
            pos += 1
            arr = []
            while toks[pos][0] != ")":
                arr.append(value())
                if toks[pos][0] == ",":
                    pos += 1
                elif toks[pos][0] != ")":
                    raise ParseError(f"expected , or ) at {toks[pos][2]}")
            pos += 1
            return arr
        if kind == "str":
            pos += 1
            return val
        raise ParseError(f"unexpected {kind} at {at}")

    result = value()
    if pos != len(toks):
        raise ParseError("text after the end")
    return result


def check(path):
    errors = []
    text = open(path, encoding="utf-8").read()
    if not text.startswith("// !$*UTF8*$!"):
        errors.append("missing the // !$*UTF8*$! header")
    try:
        top = parse(text[text.find("{"):])
    except ParseError as e:
        return [f"syntax: {e}"]
    objects = top.get("objects", {})
    root = top.get("rootObject")
    if root not in objects or objects[root].get("isa") != "PBXProject":
        errors.append("rootObject is not a PBXProject")
    for oid, obj in objects.items():
        if not re.fullmatch(r"[0-9A-F]{24}", oid):
            errors.append(f"{oid}: not a 24-hex id")
        isa = obj.get("isa")
        if not isa:
            errors.append(f"{oid}: no isa")
        elif isa not in KNOWN:
            errors.append(f"{oid}: unknown isa {isa}")
    used = {root}
    for oid, obj in objects.items():
        isa = obj.get("isa")
        for (kind, field), allowed in REFS.items():
            if kind != isa or field not in obj:
                continue
            refs = obj[field] if isinstance(obj[field], list) else [obj[field]]
            for r in refs:
                used.add(r)
                if r not in objects:
                    errors.append(f"{oid} ({isa}).{field} points to {r}, which is not in the project")
                elif objects[r].get("isa") not in allowed:
                    errors.append(f"{oid} ({isa}).{field} points to a {objects[r].get('isa')}")
        if isa == "PBXProject":
            for tid, attrs in obj.get("attributes", {}).get("TargetAttributes", {}).items():
                if tid not in objects:
                    errors.append(f"TargetAttributes names {tid}, which is not in the project")
                if isinstance(attrs, dict) and attrs.get("TestTargetID") and attrs["TestTargetID"] not in objects:
                    errors.append(f"TestTargetID {attrs['TestTargetID']} is not in the project")
    for oid in objects:
        if oid not in used:
            errors.append(f"{oid} ({objects[oid].get('isa')}) is not used by anything")

    # Files on disk, resolved through the groups.
    base = os.path.dirname(os.path.dirname(path))

    def walk(gid, folder):
        g = objects.get(gid, {})
        for cid in g.get("children", []):
            c = objects.get(cid, {})
            p = c.get("path")
            if c.get("isa") == "PBXGroup":
                walk(cid, os.path.join(folder, p) if p else folder)
            elif c.get("isa") in ("PBXFileReference", "PBXFileSystemSynchronizedRootGroup") and c.get("sourceTree") == "<group>":
                full = os.path.join(folder, p or "")
                if not os.path.exists(full):
                    errors.append(f"{os.path.relpath(full, base)} ({c.get('isa')}) is missing on disk")
                file_paths[cid] = full

    file_paths = {}
    if root in objects:
        walk(objects[root].get("mainGroup"), base)
    for oid, obj in objects.items():
        if obj.get("isa") != "XCBuildConfiguration":
            continue
        s = obj.get("buildSettings", {})
        ref = obj.get("baseConfigurationReference")
        owner_is_target = any(
            o.get("isa") == "XCConfigurationList" and oid in o.get("buildConfigurations", [])
            and any(t.get("buildConfigurationList") == lid and t.get("isa") == "PBXNativeTarget" for t in objects.values())
            for lid, o in objects.items())
        if owner_is_target:
            for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
                if key in s:
                    errors.append(f"{oid} ({obj.get('name')}) sets {key}: it belongs to the xcconfig")
            if ref is None:
                errors.append(f"{oid} ({obj.get('name')}) has no baseConfigurationReference to the xcconfig")
        if ref and ref in file_paths:
            xc = open(file_paths[ref], encoding="utf-8").read()
            for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
                if not re.search(rf"^{key}\s*=\s*\S+", xc, re.M):
                    errors.append(f"{os.path.basename(file_paths[ref])} does not set {key}")
        plist = s.get("INFOPLIST_FILE")
        if plist and not os.path.exists(os.path.join(base, plist)):
            errors.append(f"INFOPLIST_FILE {plist} is missing")

    # Shared schemes.
    scheme_dir = os.path.join(os.path.dirname(path), "xcshareddata", "xcschemes")
    if os.path.isdir(scheme_dir):
        for name in os.listdir(scheme_dir):
            body = open(os.path.join(scheme_dir, name), encoding="utf-8").read()
            for bid in re.findall(r'BlueprintIdentifier = "([0-9A-F]{24})"', body):
                if bid not in objects:
                    errors.append(f"scheme {name} names {bid}, which is not in the project")
    return errors


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "Sakka.xcodeproj", "project.pbxproj")
    errors = check(path)
    if errors:
        for e in errors:
            print("ERROR:", e)
        sys.exit(1)
    print("OK:", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
