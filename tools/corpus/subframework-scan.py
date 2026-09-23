#!/usr/bin/env python3
"""Size the ownership-filter hole: members whose header lives under SDK/.../SubFrameworks/<X>.framework
while dumping umbrella <F>.framework. surface-diff's parser records a member only when the file path
contains /<F>.framework/, so those members never reach the rows (UICoordinateSpace lives in
SubFrameworks/UIUtilities.framework, reached through UIKit)."""
import re, subprocess, os, collections, sys
# The scratch .m file below must not land inside the charon checkout (it is a git repo; an
# orphaned file there if this script is killed mid-run is a stray untracked file in tracked
# source, not just clutter) or in system /tmp (wiped without warning). corpus/ -- CHARON_CORPUS_ROOT
# addresses it, default coordination/ -- is outside git and durable for the run's lifetime.
CORPUS_ROOT = os.environ.get("CHARON_CORPUS_ROOT") or os.path.join(
    os.path.expanduser("~"), "Git", "projects", "ios", "coordination")
CORPUS = os.path.join(CORPUS_ROOT, "corpus")
if not os.path.isdir(CORPUS):
    sys.exit("subframework-scan.py: no corpus/ data directory found at %s. Set CHARON_CORPUS_ROOT "
              "to the directory that contains corpus/." % CORPUS)
SDK = sorted(__import__("glob").glob("/Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk"),
             key=lambda p: [int(x) for x in re.findall(r"\d+", os.path.basename(p))])[-1]
LINE = re.compile(r"^([| ]*)[|`]-(\w+) 0x[0-9a-f]+ ?(.*)$")
PATH = re.compile(r"(/[^\s:<>,]+\.\w+):\d+:\d+")
FW = sys.argv[1:] or ["Foundation","UIKit","Photos","PhotosUI","AVFoundation","AVKit","CoreGraphics","ImageIO","CoreVideo",
  "CoreImage","CoreMedia","Security","WebKit","GameController","LocalAuthentication","UserNotifications","CoreData",
  "SafariServices","QuartzCore","CoreLocation","CoreText","CloudKit","Contacts","EventKit","MessageUI","StoreKit",
  "AuthenticationServices","BackgroundTasks","CoreMotion","MapKit","AudioToolbox","AVFAudio","Intents","CallKit","NetworkExtension"]
tot = collections.Counter(); who = collections.defaultdict(set)
for fw in FW:
    src = os.path.join(CORPUS, f"sfscan-{os.getpid()}.m")  # scratchpad, not /tmp
    open(src, "w").write(f"#import <{fw}/{fw}.h>\n")
    try:
        cmd = ["xcrun","clang","-x","objective-c","-target","arm64-apple-ios26.0-macabi","-isysroot",SDK,"-w","-fsyntax-only",
               "-Xclang","-ast-dump","-iframework",SDK+"/System/iOSSupport/System/Library/Frameworks",src]
        out = subprocess.run(cmd, capture_output=True, text=True, errors="replace").stdout
    finally:
        os.unlink(src)
    f = None; cur = None; n = 0
    for line in out.splitlines():
        m = LINE.match(line)
        if not m: continue
        depth = len(m.group(1)) // 2; kind = m.group(2); rest = m.group(3)
        for p in PATH.findall(rest): f = p
        if depth == 0 and kind in ("ObjCInterfaceDecl","ObjCProtocolDecl"): cur = rest.split()[-1]
        if depth == 1 and kind in ("ObjCMethodDecl","ObjCPropertyDecl") and f:
            s = re.search(r"/SubFrameworks/(\w+)\.framework/", f)
            if s and ("/%s.framework/" % fw) not in f:
                tot[(fw, s.group(1))] += 1; who[(fw, s.group(1))].add(cur); n += 1
    print(f"{fw}: {n} members under SubFrameworks not owned", flush=True)
print("SUBFRAMEWORK-SCAN-DONE")
for (fw, sub), n in tot.most_common(20):
    print(f"  via {fw:22} -> {sub:18} {n:>4} members; owners: {sorted(who[(fw, sub)])[:6]}")
