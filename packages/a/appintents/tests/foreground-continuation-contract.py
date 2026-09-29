#!/usr/bin/env python3
"""The two `ForegroundContinuableIntent` rows plus the second overload, against the framework's header.

The corpus ledger carries `ForegroundContinuableIntent.requestToContinueInForeground(_:continuation:)`
and `ForegroundContinuableIntent.needsToContinueInForegroundError(_:continuation:)`. The interface
declares a **third** shape, `needsToContinueInForegroundError(_:alwaysConfirm:)`, and it is here too:
a subset chosen by which row the ledger happens to carry is a metric, not a shape.

**Existence on each side, never a first match.** The row's labels come from the row's own spelling,
every declaration of that name is collected per side as a list of label lists, and the row is green iff
the row's labels are in **both**. The port side is read from its own
`extension ForegroundContinuableIntent` block, because `Remaining.swift` declares plenty of other
things and a first match there compares a stranger's declaration.

The `@MainActor`, `async`, `throws` and generic facts are compared from the same per-side lists.

    python3 packages/a/appintents/tests/foreground-continuation-contract.py
    python3 packages/a/appintents/tests/foreground-continuation-contract.py --mutate
"""
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
sys.path.insert(0, HERE)
from paramlabels import external_labels, declaration_at  # noqa: E402

SOURCE_REL = "packages/a/appintents/Sources/AppIntents/Remaining.swift"
SOURCE = os.environ.get("FOREGROUND_CONTRACT_SOURCE") or SOURCE_REL
SDK = os.path.join(os.path.expanduser("~"), ".xmake/packages/i/iphoneos-sdk/26.2",
                   "*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs",
                   "iPhoneOS26.2.sdk/System/Library/Frameworks/AppIntents.framework/Modules/"
                   "AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface")
# (row, function name); the row's labels are read off its spelling, not parsed out of Swift
ROWS = [("requestToContinueInForeground(_:continuation:)", "requestToContinueInForeground"),
        ("needsToContinueInForegroundError(_:continuation:)", "needsToContinueInForegroundError"),
        ("needsToContinueInForegroundError(_:alwaysConfirm:)", "needsToContinueInForegroundError")]


def one_interface():
    found = sorted(glob.glob(os.path.join(ROOT, SDK)))
    if not found:
        sys.exit("foreground-continuation-contract: %s matches no file; a missing input is a hard error" % SDK)
    return "\n".join(open(p, encoding="utf-8", errors="replace").read() for p in found)


def row_labels(row):
    parts = row.split("(")[1].rstrip(")").split(":")
    while parts and not parts[-1]:
        parts.pop()
    return parts


def _port_block(text):
    start = re.search(r"extension ForegroundContinuableIntent \{", text)
    if not start:
        return ""
    rest = text[start.end():]
    end = rest.find("\n}\n")
    return rest[:end] if end > 0 else rest


def _decls(block, name):
    """Every declaration of `name`, each matched by balanced parentheses, not by a `->` window."""
    out, at = [], 0
    while True:
        found = declaration_at(block, name, at)
        if not found:
            return out
        out.append(found)
        at = block.find("func " + name, block.find(found, at) + 1)


def main():
    interface = re.sub(r"[ \t]+", " ", one_interface())
    port = re.sub(r"[ \t]+", " ",
                  open(SOURCE if os.path.isabs(SOURCE) else os.path.join(ROOT, SOURCE),
                       encoding="utf-8", errors="replace").read())
    block = _port_block(port)
    if not block:
        sys.exit("foreground-continuation-contract: %s has no extension ForegroundContinuableIntent" % SOURCE_REL)
    failures, declared = [], 0
    for row, name in ROWS:
        want = row_labels(row)
        theirs = _decls(interface, name)
        ours = _decls(block, name)
        their_labels = [external_labels(d) for d in theirs]
        our_labels = [external_labels(d) for d in ours]
        red = want not in their_labels or want not in our_labels
        print("row   %s  labels=%s" % (row, want))
        print("  framework: %s" % their_labels)
        print("  this port: %s" % our_labels)
        if not red:
            declared += 1
            print("  ok: the row's labels are declared on both sides")
        else:
            failures.append("%s: the row's labels %s are not declared on both sides" % (row, want))
            print("  RED: the row's labels are missing on %s" % ("this port" if want not in our_labels
                                                                 else "the framework"))
        for what, test in (("generic", lambda d: bool(re.search(r"func\s+\w+\s*<", d))),
                           ("async", lambda d: "async" in d), ("throws", lambda d: "throws" in d),
                           ("@MainActor", lambda d: "@MainActor" in d)):
            if any(test(d) for d in theirs) and not any(test(d) for d in ours):
                failures.append("%s: the framework's declaration is %s and this one is not" % (row, what))
    print("%d of %d rows declared, %d shape failure(s)" % (declared, len(ROWS), len(failures)))
    for f in failures:
        print("FAIL %s" % f)
    return 1 if failures else 0


def mutate():
    """A mutation of the port's own external label, and one of its internal name."""
    import shutil
    scratch = os.path.join(ROOT, ".agent-work/runs/foreground-mutation")
    os.makedirs(scratch, exist_ok=True)
    target = os.path.join(scratch, "Remaining.swift")
    real = os.path.join(ROOT, SOURCE_REL)
    original = open(real, encoding="utf-8").read()
    declaration = "public func needsToContinueInForegroundError(_ dialog: IntentDialog? = nil,"
    bad = 0
    try:
        for name, before, after, want_failure in (
                ("A: internal name only",
                 "public func requestToContinueInForeground<ResultValue>(_ dialog: IntentDialog? = nil",
                 "public func requestToContinueInForeground<ResultValue>(_ dialog2: IntentDialog? = nil", False),
                ("B: external label",
                 # the *continuation:* overload's head: the two overloads share `_ dialog:`, so the
                 # pattern names the one that carries `continuation:` and nothing else
                 re.compile(r"needsToContinueInForegroundError\(\s*_ dialog:[^)]*continuation:"),
                 "needsToContinueInForegroundError(dialog: IntentDialog? = nil,\n                                                 continuation:", True)):
            if hasattr(before, "subn"):
                found, n = before.subn(after.replace("\\", "\\\\"), original, count=1)
                if n != 1:
                    sys.exit("foreground-mutation: the pattern matched %d times; it must match once" % n)
            else:
                if original.count(before) != 1:
                    sys.exit("foreground-mutation: `%s` occurs %d times; it must occur exactly once"
                             % (before, original.count(before)))
                found = original.replace(before, after, 1)
            open(target, "w", encoding="utf-8").write(found)
            env = dict(os.environ, FOREGROUND_CONTRACT_SOURCE=target)
            run = subprocess.run([sys.executable, os.path.join(HERE, os.path.basename(__file__))],
                                 capture_output=True, text=True, cwd=ROOT, env=env)
            red = run.returncode != 0
            print("=== mutation %s on %s" % (name, os.path.relpath(target, ROOT)))
            for line in run.stdout.splitlines():
                if "labels=" in line or "this port:" in line or line.startswith("FAIL") \
                        or "rows declared" in line:
                    print("    " + line.strip()[:140])
            print("    check exit %d -> %s" % (run.returncode, "red" if red else "green"))
            if red != want_failure:
                bad += 1
                print("    WRONG")
            open(real, "w", encoding="utf-8").write(
                subprocess.run(["git", "show", "HEAD:" + SOURCE_REL], capture_output=True, text=True,
                               cwd=ROOT).stdout)
            if open(real, encoding="utf-8").read() != original:
                sys.exit("foreground-mutation: the restore from git did not put %s back" % SOURCE_REL)
        print("%d of 2 mutations behaved wrongly" % bad)
        return 1 if bad else 0
    finally:
        open(real, "w", encoding="utf-8").write(
            subprocess.run(["git", "show", "HEAD:" + SOURCE_REL], capture_output=True, text=True,
                           cwd=ROOT).stdout)


if __name__ == "__main__":
    sys.exit(mutate() if "--mutate" in sys.argv else main())
