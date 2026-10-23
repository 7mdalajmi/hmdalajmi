#!/usr/bin/env python3
"""cloudcheck report: merge the compiler logs of every target/configuration, map preprocessed paths
back to the real sources, drop exact duplicates, set harness-only diagnostics apart, print a summary.

Usage: report.py WORK_SRC_ROOT REAL_SRC_ROOT STUBS_DIR LOG...    (each LOG is named <target>.<config>.log)
Exit status: 0 = no errors in the app sources, 1 = errors, 2 = the compiler itself failed.
"""
import os
import re
import sys

DIAG_RE = re.compile(r"^(?P<file>[^:\n]+?):(?P<line>\d+):(?P<col>\d+): (?P<sev>error|warning|note|remark): (?P<msg>.*)$")
BARE_RE = re.compile(r"^(?P<file><unknown>|error|warning)(?::\d+)?:?\s*(?P<sev>error|warning)?:?\s*(?P<msg>.*)$")

# Diagnostics that only exist because Linux has no Objective-C runtime or Darwin Foundation.
HARNESS_ONLY = [
    re.compile(r"cannot be overridden from extension"),
    re.compile(r"non-'@objc' .* declared in extension cannot be overridden"),
    re.compile(r"Objective-C interoperability is disabled"),
    re.compile(r"can only be used with the Objective-C runtime"),
]


def parse(path, work_src, real_src, stubs):
    target_config = os.path.basename(path)[:-len(".log")]
    diags = []
    current = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n")
            m = DIAG_RE.match(line)
            if not m:
                if line.startswith("error:") or line.startswith("<unknown>:0: error:"):
                    current = {"where": "<driver>", "sev": "error", "msg": line.split("error:", 1)[1].strip(),
                               "notes": [], "configs": {target_config}, "origin": "driver"}
                    diags.append(current)
                continue
            file = m.group("file")
            origin = "app"
            if file.startswith(work_src + "/"):
                rel = file[len(work_src) + 1:]
                where = f"{rel}:{m.group('line')}:{m.group('col')}"
            elif file.startswith(stubs + "/"):
                rel = file[len(stubs) + 1:]
                where = f"[stub] {rel}:{m.group('line')}:{m.group('col')}"
                origin = "harness" if rel == "DarwinShims.swift" else "stub"
            else:
                where = f"{file}:{m.group('line')}:{m.group('col')}"
                origin = "other"
            entry = {"where": where, "sev": m.group("sev"), "msg": m.group("msg"), "notes": [],
                     "configs": {target_config}, "origin": origin}
            if entry["sev"] in ("note", "remark"):
                if current is not None:
                    current["notes"].append(f"{where}: {entry['sev']}: {entry['msg']}")
                continue
            current = entry
            diags.append(entry)
    return diags


def sort_key(d):
    where = d["where"]
    m = re.match(r"^(?:\[stub\] )?(.*?):(\d+):(\d+)$", where)
    if m:
        return (0 if d["origin"] == "app" else 1, m.group(1), int(m.group(2)), int(m.group(3)), d["msg"])
    return (2, where, 0, 0, d["msg"])


def main():
    work_src, real_src, stubs = sys.argv[1], sys.argv[2], sys.argv[3]
    logs = sys.argv[4:]
    merged = {}
    runs = []
    for log in logs:
        runs.append(os.path.basename(log)[:-len(".log")])
        for d in parse(log, work_src, real_src, stubs):
            key = (d["where"], d["sev"], d["msg"])
            if key in merged:
                merged[key]["configs"] |= d["configs"]
                for n in d["notes"]:
                    if n not in merged[key]["notes"]:
                        merged[key]["notes"].append(n)
            else:
                merged[key] = d
    diags = sorted(merged.values(), key=sort_key)
    harness, real = [], []
    for d in diags:
        if d["origin"] in ("harness", "stub", "driver") or any(p.search(d["msg"]) for p in HARNESS_ONLY):
            harness.append(d)
        else:
            real.append(d)

    def show(d):
        configs = ",".join(sorted(d["configs"], key=runs.index))
        print(f"{d['where']}: {d['sev']}: {d['msg']}   [{configs}]")
        for n in d["notes"]:
            print(f"    {n}")

    print(f"== Diagnostics in {real_src} (paths relative to it)")
    if not real:
        print("   none")
    for d in real:
        show(d)
    if harness:
        print("\n== Harness-only diagnostics (stubs, shims or Linux-only limits; not app findings)")
        for d in harness:
            show(d)
    print("\n== Summary")
    for run in runs:
        e = sum(1 for d in real if run in d["configs"] and d["sev"] == "error")
        w = sum(1 for d in real if run in d["configs"] and d["sev"] == "warning")
        h = sum(1 for d in harness if run in d["configs"])
        print(f"   {run:<22} {e:3d} error(s) {w:3d} warning(s)" + (f"   ({h} harness-only)" if h else ""))
    blocked = [run for run in runs if any(run in d["configs"] and d["sev"] == "error" for d in real + harness)]
    if blocked:
        print("\n   Note: a run with errors stops after type-checking, so its SIL diagnostics (data-race")
        print("   'sending' checks, unreachable code, missing returns...) did not run: " + ", ".join(blocked))
        print("   Fix the errors and run again.")
    if any(d["origin"] == "driver" for d in harness):
        print("\n   The compiler itself failed (see harness-only list): the check is incomplete.")
        sys.exit(2)
    errors = any(d["sev"] == "error" for d in real)
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
