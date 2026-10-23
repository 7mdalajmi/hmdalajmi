#!/usr/bin/env python3
"""cloudcheck compare: the diagnostics of the stub run against those of the real-SDK run (check.sh
--compare), to show where the stubs are not faithful. The two work trees have the same relative paths and
the same line numbers, so a diagnostic is matched by file, line, column, severity and message.

The stubs cannot spell an iOS-versioned deprecation the way the SDK does (`@available(iOS, deprecated:
18.0)` is mapped to `@available(*, deprecated, message: "deprecated in iOS 18.0")`, see Stubs/SwiftUI's
header), so deprecation and unavailability messages are compared without the platform and version.
Notes are shown but not compared (their locations point into different modules).

Usage: compare.py SRC STUBS_DIR STUB_WORK STUB_LOG_DIR SDK_WORK SDK_LOG_DIR LOGNAME...
       (each LOGNAME is <target>.<config>.log and exists in both log directories)
Exit status: 0 = the two runs agree, 1 = they differ, 2 = the compiler itself failed in either run.
"""
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import report  # noqa: E402

GROUP_RE = re.compile(r"\s+\[#\w+\]$")
STUB_DEPRECATED_RE = re.compile(r"^(?P<d>.*?) is deprecated: deprecated in iOS [0-9.]+(?P<rest>(?:: .*)?)$")
SDK_DEPRECATED_RE = re.compile(r"^(?P<d>.*?) (?:is|was) deprecated in iOS(?: [0-9.]+)?(?P<rest>(?:: .*)?)$")
SDK_UNAVAILABLE_RE = re.compile(r"^(?P<d>.*?) is unavailable in iOS(?P<rest>(?:: .*)?)$")
SDK_OBSOLETED_RE = re.compile(r"^(?P<d>.*?) was obsoleted in iOS [0-9.]+$")


def normalize(msg):
    msg = GROUP_RE.sub("", msg)
    for rx, fmt in ((STUB_DEPRECATED_RE, "{d} is deprecated{rest}"),
                    (SDK_DEPRECATED_RE, "{d} is deprecated{rest}"),
                    (SDK_UNAVAILABLE_RE, "{d} is unavailable{rest}"),
                    (SDK_OBSOLETED_RE, "{d} is unavailable{rest}")):
        m = rx.match(msg)
        if m:
            return fmt.format(d=m.group("d"), rest=m.groupdict().get("rest") or "")
    return msg


def is_harness(d):
    return d["origin"] in ("harness", "stub", "driver") or any(p.search(d["msg"]) for p in report.HARNESS_ONLY)


def collect(work, log_dir, src, stubs, lognames):
    """{key: diag} with configs merged; key = (where, severity, normalized message)."""
    found, harness = {}, {}
    for name in lognames:
        path = os.path.join(log_dir, name)
        if not os.path.exists(path):
            harness[("<driver>", "error", f"missing log {path}")] = {
                "where": "<driver>", "sev": "error", "msg": f"missing log {path}", "notes": [],
                "configs": {name[:-len(".log")]}, "origin": "driver"}
            continue
        for d in report.parse(path, work, src, stubs):
            key = (d["where"], d["sev"], normalize(d["msg"]))
            bucket = harness if is_harness(d) else found
            if key in bucket:
                bucket[key]["configs"] |= d["configs"]
                for n in d["notes"]:
                    if n not in bucket[key]["notes"]:
                        bucket[key]["notes"].append(n)
            else:
                bucket[key] = d
    return found, harness


def main():
    if len(sys.argv) < 8:
        print(__doc__)
        sys.exit(2)
    src, stubs, stub_work, stub_logs, sdk_work, sdk_logs = sys.argv[1:7]
    lognames = sys.argv[7:]
    runs = [n[:-len(".log")] for n in lognames]
    stub, stub_h = collect(stub_work, stub_logs, src, stubs, lognames)
    sdk, sdk_h = collect(sdk_work, sdk_logs, src, stubs, lognames)

    def order(d):
        return report.sort_key(d)

    def show(d, configs=None):
        configs = configs if configs is not None else d["configs"]
        print(f"   {d['where']}: {d['sev']}: {d['msg']}   [{','.join(sorted(configs, key=runs.index))}]")
        for n in d["notes"]:
            print(f"       {n}")

    both, only_sdk, only_stub = [], [], []
    for key in set(stub) | set(sdk):
        a, b = stub.get(key), sdk.get(key)
        if a and b:
            common = a["configs"] & b["configs"]
            if common:
                both.append((b, common))
            if b["configs"] - common:
                only_sdk.append((b, b["configs"] - common))
            if a["configs"] - common:
                only_stub.append((a, a["configs"] - common))
        elif b:
            only_sdk.append((b, b["configs"]))
        else:
            only_stub.append((a, a["configs"]))

    print(f"== Stubs vs SDK, {src} (paths relative to it)")
    print(f"   {len(both)} diagnostic(s) in both runs, {len(only_sdk)} only with the SDK, "
          f"{len(only_stub)} only with the stubs")
    sections = (("Only with the SDK (the stubs miss these: a stub is too permissive)", only_sdk),
                ("Only with the stubs (the SDK does not report these: a stub is too strict or wrong)", only_stub),
                ("In both runs (diagnostics in the sources)", both))
    for title, items in sections:
        if items:
            print(f"\n== {title}")
            for d, configs in sorted(items, key=lambda x: order(x[0])):
                show(d, configs)
    for label, h in (("stub run", stub_h), ("SDK run", sdk_h)):
        if h:
            print(f"\n== Harness-only diagnostics, {label} (not compared)")
            for d in sorted(h.values(), key=order):
                show(d)

    print("\n== Summary              stubs (errors/warnings)   SDK (errors/warnings)   differences")
    blocked = []
    for run in runs:
        counts = []
        for found in (stub, sdk):
            e = sum(1 for d in found.values() if run in d["configs"] and d["sev"] == "error")
            w = sum(1 for d in found.values() if run in d["configs"] and d["sev"] == "warning")
            counts.append(f"{e:3d} / {w:<3d}")
            if e:
                blocked.append(run)
        diff = sum(1 for _, c in only_sdk + only_stub if run in c)
        print(f"   {run:<22} {counts[0]:<25} {counts[1]:<23} {diff}")
    if blocked:
        print("\n   Note: a run with errors stops after type-checking, so its SIL diagnostics did not run;")
        print("   differences in those runs may only reflect that: " + ", ".join(sorted(set(blocked), key=runs.index)))
    if any(d["origin"] == "driver" for d in list(stub_h.values()) + list(sdk_h.values())):
        print("\n   The compiler itself failed in a run (see the harness-only lists): the comparison is incomplete.")
        sys.exit(2)
    sys.exit(1 if only_sdk or only_stub else 0)


if __name__ == "__main__":
    main()
