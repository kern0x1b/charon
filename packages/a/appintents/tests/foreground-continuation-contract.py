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
ROWS = ["requestToContinueInForeground(_:continuation:)", "needsToContinueInForegroundError(_:continuation:)"]


def main():
    found = sorted(glob.glob(os.path.expanduser(SDK)))
    if not found:
        sys.exit("foreground-continuation-contract: %s matches no file; a missing input is a hard error" % SDK)
    interface = "\n".join(open(p, encoding="utf-8", errors="replace").read() for p in found)
    text = open(SOURCE, encoding="utf-8", errors="replace").read()
    declared = 0
    for row in ROWS:
        name = row.split("(")[0]
        ours = re.search(r"public func %s[^\n]*" % re.escape(name), text)
        theirs = re.search(r"[^\n]*public func %s[^\n]*" % re.escape(name), interface)
        print("row   %s" % row)
        print("  framework: %s" % (theirs.group(0).strip()[:150] if theirs else "NOT FOUND"))
        if ours:
            declared = declared + 1
            print("  declared: %s" % ours.group(0).strip()[:150])
        else:
            print("  declared: **no** -- this is an empty extension today")
    print("%d of %d rows declared" % (declared, len(ROWS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
