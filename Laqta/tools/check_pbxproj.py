#!/usr/bin/env python3
"""Checks an Xcode project.pbxproj without Xcode: it must parse as an OpenStep plist, every
object id it points to must exist, ids must be unique, and every target must have what Xcode
expects. Run: python3 tools/check_pbxproj.py [path/to/project.pbxproj]
Exit code 0 means no problems found.
"""
import re
import sys

SAFE = re.compile(r"[A-Za-z0-9_$/:.\-]")


class Parser:
    def __init__(self, text):
        self.s = text
        self.i = 0
        self.keys_seen = []

    def error(self, msg):
        line = self.s.count("\n", 0, self.i) + 1
        raise SyntaxError(f"line {line}: {msg}")

    def skip(self):
        s = self.s
        while self.i < len(s):
            c = s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif s.startswith("/*", self.i):
                j = s.find("*/", self.i + 2)
                if j < 0:
                    self.error("unclosed comment")
                self.i = j + 2
            elif s.startswith("//", self.i):
                j = s.find("\n", self.i)
                self.i = len(s) if j < 0 else j + 1
            else:
                break

    def value(self):
        self.skip()
        c = self.s[self.i] if self.i < len(self.s) else ""
        if c == "{":
            return self.dict()
        if c == "(":
            return self.array()
        if c == '"':
            return self.quoted()
        return self.bare()

    def quoted(self):
        self.i += 1
        out = []
        while True:
            if self.i >= len(self.s):
                self.error("unclosed string")
            c = self.s[self.i]
            if c == "\\":
                out.append(self.s[self.i:self.i + 2])
                self.i += 2
            elif c == '"':
                self.i += 1
                return "".join(out)
            else:
                out.append(c)
                self.i += 1

    def bare(self):
        j = self.i
        while j < len(self.s) and SAFE.match(self.s[j]):
            j += 1
        if j == self.i:
            ch = self.s[self.i:self.i + 1]
            self.error(f"unexpected {ch!r} (a value with characters outside A-Z a-z 0-9 _$/:.- needs quotes)")
        v = self.s[self.i:j]
        self.i = j
        return v

    def dict(self):
        self.i += 1
        d = {}
        while True:
            self.skip()
            if self.s[self.i] == "}":
                self.i += 1
                return d
            k = self.quoted() if self.s[self.i] == '"' else self.bare()
            self.skip()
            if self.s[self.i] != "=":
                self.error(f"expected '=' after {k}")
            self.i += 1
            v = self.value()
            self.skip()
            if self.s[self.i] != ";":
                self.error(f"expected ';' after the value of {k}")
            self.i += 1
            if k in d:
                self.error(f"duplicate key {k}")
            d[k] = v

    def array(self):
        self.i += 1
        a = []
        while True:
            self.skip()
            if self.s[self.i] == ")":
                self.i += 1
                return a
            a.append(self.value())
            self.skip()
            if self.s[self.i] == ",":
                self.i += 1
            elif self.s[self.i] != ")":
                self.error("expected ',' or ')' in a list")


ID = re.compile(r"^[0-9A-F]{24}$")


def refs(v):
    if isinstance(v, dict):
        for x in v.values():
            yield from refs(x)
    elif isinstance(v, list):
        for x in v:
            yield from refs(x)
    elif isinstance(v, str) and ID.match(v):
        yield v


def check(path):
    text = open(path, encoding="utf-8").read()
    problems = []
    if not text.startswith("// !$*UTF8*$!"):
        problems.append("first line is not // !$*UTF8*$!")
    p = Parser(text[text.index("{"):])
    root = p.value()
    objects = root.get("objects", {})
    ids = list(re.findall(r"^\t\t([0-9A-F]{24}) ", text, re.M))
    dup = {x for x in ids if ids.count(x) > 1}
    if dup:
        problems.append(f"ids defined twice: {sorted(dup)}")
    for oid, obj in objects.items():
        if not isinstance(obj, dict) or "isa" not in obj:
            problems.append(f"{oid} has no isa")
            continue
        for r in refs({k: v for k, v in obj.items() if k not in ("remoteGlobalIDString",)}):
            if r not in objects:
                problems.append(f"{oid} ({obj['isa']}) points to missing {r}")
    if root.get("rootObject") not in objects:
        problems.append("rootObject missing")
    for oid, obj in objects.items():
        if obj.get("isa") == "PBXContainerItemProxy" and obj.get("remoteGlobalIDString") not in objects:
            problems.append(f"proxy {oid} points to missing target")
        if obj.get("isa") == "PBXNativeTarget":
            name = obj.get("name")
            for key in ("buildConfigurationList", "productReference", "productType", "buildPhases"):
                if key not in obj:
                    problems.append(f"target {name} has no {key}")
            phases = [objects[x]["isa"] for x in obj.get("buildPhases", []) if x in objects]
            if "PBXSourcesBuildPhase" not in phases:
                problems.append(f"target {name} has no Sources phase")
    used = {r for o in objects.values() for r in refs(o)} | {root.get("rootObject")}
    for oid, obj in objects.items():
        if oid not in used:
            problems.append(f"{oid} ({obj.get('isa')}) is never referenced")
    return problems, objects


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "Zakati.xcodeproj/project.pbxproj"
    try:
        problems, objects = check(path)
    except SyntaxError as e:
        print(f"{path}: does not parse: {e}")
        sys.exit(1)
    kinds = {}
    for o in objects.values():
        kinds[o["isa"]] = kinds.get(o["isa"], 0) + 1
    print(f"{path}: {len(objects)} objects, " + ", ".join(f"{v} {k}" for k, v in sorted(kinds.items())))
    for t in (o for o in objects.values() if o["isa"] == "PBXNativeTarget"):
        groups = [objects[g]["path"] for g in t.get("fileSystemSynchronizedGroups", [])]
        print(f"  target {t['name']}: {t['productType']} · folders {', '.join(groups)}")
    if problems:
        print("problems:")
        for x in problems:
            print("  -", x)
        sys.exit(1)
    print("no problems")


if __name__ == "__main__":
    main()
