#!/usr/bin/env python3
"""The two `ForegroundContinuableIntent` rows, read against the framework's own header.

The corpus ledger carries `ForegroundContinuableIntent.requestToContinueInForeground(_:continuation:)`
and `ForegroundContinuableIntent.needsToContinueInForegroundError(_:continuation:)`. This module has an
**empty** `extension ForegroundContinuableIntent` (Remaining.swift:230), so both rows are undeclared,
and this check says so -- and prints the framework's own two declarations, which is what a declaration
here has to match and what the port must not guess at: `requestToContinueInForeground` is generic in a
`ResultValue` and returns it, and `needsToContinueInForegroundError` has a second overload taking
`alwaysConfirm:` and returning `AppIntentError`.

    python3 packages/a/appintents/tests/foreground-continuation-contract.py
"""
import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", ".."))
SOURCE = os.path.join(ROOT, "packages/a/appintents/Sources/AppIntents/Remaining.swift")
SDK = os.path.join(os.path.expanduser("~"), ".xmake/packages/i/iphoneos-sdk/26.2",
                   "*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs",
                   "iPhoneOS26.2.sdk/System/Library/Frameworks/AppIntents.framework/Modules/"
                   "AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface")
ROWS = [("requestToContinueInForeground(_:continuation:)", "requestToContinueInForeground"),
        ("needsToContinueInForegroundError(_:continuation:)", "needsToContinueInForegroundError"),
        # the second overload is not in the ledger, and a subset chosen by which row the ledger
        # happens to carry is a metric rather than a shape -- so the check holds it to the same rule
        ("needsToContinueInForegroundError(_:alwaysConfirm:)", "needsToContinueInForegroundError")]
# what the framework's own declaration carries, and what a declaration here must carry too
NEEDS = {"generic": True, "labels": True, "async": True, "throws": True}


def main():
    found = sorted(glob.glob(os.path.expanduser(SDK)))
    if not found:
        sys.exit("foreground-continuation-contract: %s matches no file; a missing input is a hard error" % SDK)
    interface = "\n".join(open(p, encoding="utf-8", errors="replace").read() for p in found)
    text = open(SOURCE, encoding="utf-8", errors="replace").read()
    # a declaration in this file wraps onto the next line, and the label lives there: match over
    # whitespace-normalised text, not per line
    flat = re.sub(r"\s+", " ", text)
    declared, failures = 0, []
    for row, name in ROWS:
        parts = row.split("(")[1].rstrip(")").split(":")
        want_label = parts[1] if len(parts) > 1 and parts[0] == "_" else parts[0]
        ours = [m.group(0) for m in re.finditer(r"public func %s(?:<[^>]*>)?\(.{0,220}?(?:->|$)" % re.escape(name), flat)]
        theirs = [m.group(0).strip() for m in
                  re.finditer(r"public func %s(?:<[^>]*>)?\(.{0,220}?(?:->|$)" % re.escape(name),
                              re.sub(r"\s+", " ", interface))]
        match = [d for d in ours if re.search(r"\b%s\s*:" % re.escape(want_label), d)]
        print("row   %s" % row)
        for t in sorted(set(theirs)):
            print("  framework: %s" % t[:150])
        if not match:
            failures.append(row)
            print("  declared: **no declaration with that label**")
            continue
        declared = declared + 1
        decl = match[0]
        print("  declared: %s" % decl.strip()[:150])
        twin = next((t for t in theirs if re.search(r"\b%s\s*:" % re.escape(want_label), t)), "")
        for what, needed in (("generic", "<" in twin), ("labels", ":" in twin),
                             ("async", "async" in twin), ("throws", "throws" in twin)):
            have = ("<" in decl) if what == "generic" else (":" in decl) if what == "labels" \
                else (what in decl)
            if needed and not have:
                failures.append("%s: the framework's overload is %s and this declaration is not" % (row, what))
    print("%d of %d rows declared, %d shape failure(s)" % (declared, len(ROWS), len(failures)))
    for f in failures:
        print("FAIL %s" % f)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
