#!/usr/bin/env python3
"""Install a project from the cloud into iCloud Drive/Xcode/<Project>, checking every file's md5 (Mimal, 4 Oct 2026; read-only git files, Durza, 8 Oct 2026).

Run on the bridge (device_bash):
    python3 "$HOME/mnt/Xcode/_tools/xcsync.py" "$HOME/mnt/Xcode/_staging/<Project>-<stamp>" "$HOME/mnt/Xcode/<Project>" [--prune]

The staging folder is made fresh for every transfer (a reused path once delivered an older copy) and holds
<Project>.tar.gz and <Project>.md5 (md5sum lines, paths relative to the project root, .git included).
Steps: extract into <staging>/payload and check every md5 there; copy new and changed files into the target
(nothing is deleted); check every md5 again in the target; list target files the archive no longer has
(with --prune they move to Xcode/_to_delete/<Project>-<stamp>/, never deleted). Exit 1 on any mismatch.
Afterwards the staging folder can move to Xcode/_to_delete as well (deleting needs Hamad's permission).
"""
import hashlib, os, shutil, sys, tarfile, time

# Never pruned: git's own files (locks, FETCH_HEAD), Xcode's workspace and user state, build output.
SKIP_PARTS = {".git", "project.xcworkspace", "xcuserdata", "DerivedData", ".build", ".swiftpm"}
SKIP_NAMES = {".DS_Store"}


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_list(path):
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            digest, name = line.split("  ", 1)
            out[name] = digest
    return out


def check(root, expected):
    bad = []
    for name, digest in expected.items():
        p = os.path.join(root, name)
        if not os.path.isfile(p) or md5(p) != digest:
            bad.append(name)
    return bad


def skipped(rel):
    parts = rel.split(os.sep)
    return any(p in SKIP_PARTS for p in parts) or parts[-1] in SKIP_NAMES or rel.endswith(".xcuserstate")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    prune = "--prune" in sys.argv
    if len(args) != 2:
        print(__doc__)
        sys.exit(2)
    staging, target = (os.path.abspath(a) for a in args)
    project = os.path.basename(target.rstrip("/"))
    archive = os.path.join(staging, project + ".tar.gz")
    expected = read_list(os.path.join(staging, project + ".md5"))
    payload = os.path.join(staging, "payload")
    os.makedirs(payload, exist_ok=True)
    with tarfile.open(archive) as tar:
        tar.extractall(payload, filter="data")
    bad = check(payload, expected)
    if bad:
        print("STAGING MISMATCH", len(bad), bad[:20])
        sys.exit(1)
    os.makedirs(target, exist_ok=True)
    copied = 0
    for name, digest in expected.items():
        src, dst = os.path.join(payload, name), os.path.join(target, name)
        if os.path.isfile(dst) and md5(dst) == digest:
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        try:
            shutil.copy2(src, dst)
        except PermissionError:
            # git keeps some of its files read-only (objects/info/commit-graph): make it writable, once.
            os.chmod(dst, os.stat(dst).st_mode | 0o200)
            shutil.copy2(src, dst)
        copied += 1
    bad = check(target, expected)
    if bad:
        print("TARGET MISMATCH", len(bad), bad[:20])
        sys.exit(1)
    extra = []
    for dirpath, dirnames, filenames in os.walk(target):
        for fn in filenames:
            rel = os.path.relpath(os.path.join(dirpath, fn), target)
            if rel not in expected and not skipped(rel):
                extra.append(rel)
    moved = 0
    if prune and extra:
        bin_root = os.path.join(os.path.dirname(target), "_to_delete", project + "-" + time.strftime("%Y%m%d-%H%M%S"))
        for rel in extra:
            dst = os.path.join(bin_root, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.move(os.path.join(target, rel), dst)
            moved += 1
    pbx = os.path.join(project + ".xcodeproj", "project.pbxproj")
    print(f"ok: {len(expected)} files match md5 in the target; {copied} copied; "
          f"{len(extra)} not in the archive" + (f", {moved} moved to _to_delete" if prune else ""))
    if pbx in expected:
        print("project.pbxproj md5", expected[pbx])
    for rel in extra[:30]:
        print("  extra:", rel)


if __name__ == "__main__":
    main()
