#!/usr/bin/env python3
"""Dump SDK-declared API -> (kind, introduced) per framework by reusing surface-diff.declared()
(clang -ast-dump over the Mac Catalyst SDK). Output: corpus/sdk-introduced.json

Two things this does beyond a bare re-export of declared():

- A member with no @available of its own falls back to its containing class's or protocol's own
  resolved version, inside surface-diff.declared() itself (Surface.container_version) - this was
  already there, not added here. What was broken was reaching it at all: the generator's own
  import pointed at a worktree (.claude/worktrees/priceless-kepler-a7622c) that no longer exists,
  so every run needed SURFACE_DIFF set by hand or it did not run - and when sdk-introduced.json
  goes missing, crash-demand.py loses ~700 rows to `continue` with no count, silently, because a
  KeyError deep in ver() looks nothing like "the generator never ran". Fixed by preferring a
  local, already-current copy (surface-diff-latest.py, right beside this script) over the dead
  worktree, with SURFACE_DIFF still the first choice for whoever wants to point it elsewhere.

- A member that still has no version after that fallback - neither its own nor its container's -
  is checked against a real iPhoneOS SDK's declared() for the same framework, and named in
  corpus/sdk-introduced-unverified.tsv when absent there, rather than dropped outright.
  Measured against -[UINavigationBarDelegate navigationBarNSToolbarSection:], the concrete
  example this fallback was asked to filter as Catalyst-only ("NSToolbar is not in iOS at all"):
  it IS real iOS API, since iOS 16, per the iPhoneOS 16.4 SDK's own header text - just
  unannotated in both SDKs, the same as an old pre-@available method like
  -[NSURLConnectionDelegate connection:didFailWithError:] (iOS 2.0). "Absent from the one local
  iPhoneOS SDK" does not distinguish those from a real, genuinely Catalyst-only member (an
  AppKit-shaped extra the macabi target parses because Catalyst hosts it and real iOS never
  does) - it also matches ordinary newer API the local SDK, capped at 16.4, simply predates.
  Checked directly: -[CBCentralManagerDelegate
  centralManager:didDisconnectPeripheral:timestamp:isReconnecting:error:], a real iOS 17
  CoreBluetooth addition, is unannotated in the Catalyst dump AND absent from the 16.4 SDK - the
  same shape as the Catalyst-only case, with no way to tell them apart from this AST alone. An
  automatic drop on that signal would have silently discarded real API exactly the way this whole
  effort exists to stop; the two categories are named to the file above for a human decision, not
  merged into one guess.
"""
import glob
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# corpus/ is DATA, in the durable location CHARON_CORPUS_ROOT addresses (default coordination/),
# independent of this script's own location. surface-diff-latest.py is a NEIGHBOR SCRIPT, found
# beside this file (HERE, already correct above). See tools/corpus/README.md.
CORPUS_ROOT = os.environ.get("CHARON_CORPUS_ROOT") or os.path.join(
    os.path.expanduser("~"), "Git", "projects", "ios", "coordination")
CORPUS = os.path.join(CORPUS_ROOT, "corpus")
if not os.path.isdir(CORPUS):
    sys.exit("sdk-introduced.py: no corpus/ data directory found at %s. Set CHARON_CORPUS_ROOT to "
              "the directory that contains corpus/." % CORPUS)


def load_surface_diff():
    candidates = [
        os.environ.get("SURFACE_DIFF"),
        os.path.join(HERE, "surface-diff-latest.py"),
        os.path.join(os.path.expanduser("~"), "Git", "projects", "ios", "charon", "tests", "backports", "tools", "surface-diff.py"),
    ]
    for path in candidates:
        if path and os.path.isfile(path):
            spec = importlib.util.spec_from_file_location("sd", path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            print("surface-diff: %s" % path, flush=True)
            return module
    sys.exit("no surface-diff.py found: tried %s - set SURFACE_DIFF, or refresh %s" %
              (", ".join(p for p in candidates if p), os.path.join(HERE, "surface-diff-latest.py")))


def newest_iphoneos_sdk():
    found = sorted(glob.glob(os.path.join(os.path.expanduser("~"), ".xmake", "packages", "i", "iphoneos-sdk", "*", "*", "*.sdk")))
    return found[-1] if found else None


sd = load_surface_diff()
sdk = sd.newest_sdk()
IOS_SDK = newest_iphoneos_sdk()
IOS_TARGET = "arm64-apple-ios16.4"
if IOS_SDK:
    print("real iPhoneOS SDK for the Catalyst-only check: %s" % IOS_SDK, flush=True)
else:
    print("no real iPhoneOS SDK found - the Catalyst-only check is skipped, nothing is dropped by it", flush=True)

FRAMEWORKS = ["Foundation","UIKit","Photos","PhotosUI","AVFoundation","AVKit","CoreGraphics","ImageIO",
 "CoreVideo","CoreImage","CoreMedia","Security","CoreServices","MobileCoreServices","WebKit",
 "GameController","CoreTelephony","LocalAuthentication","UserNotifications","CoreData",
 "SafariServices","QuartzCore","CoreLocation","CoreText","CloudKit","Contacts","EventKit",
 "MessageUI","StoreKit","AuthenticationServices","BackgroundTasks","CoreMotion","MapKit",
 "AudioToolbox","Accelerate","VideoToolbox","AVFAudio","Intents","CallKit","PushKit",
 "NetworkExtension","SystemConfiguration","CoreBluetooth","Vision","CoreML","NaturalLanguage",
 # FileProvider was never in this list at all -- not a parsing/macro issue, just absent, found by
 # tracing one crash-demand row (`documentStorageURL`) that could only ever collide with a UIKit
 # entry because its real second owner (NSFileProviderExtension, NSFileProviderManager) had no
 # entry to collide against. Confirmed with declared() directly: both are real, both are in the
 # local SDK header (NSFileProviderExtension.h:99, NSFileProviderManager.h:169), neither needed
 # anything beyond being named here. 69 more real classes across ~20 other frameworks show the
 # same shape (ARKit, CoreHaptics, CoreSpotlight, JavaScriptCore, MediaPlayer, PassKit, ReplayKit,
 # SceneKit, Speech, WatchConnectivity, Messages, Social, MetricKit, ModelIO, OSLog, Metal-family)
 # -- named to the coordinator, not added here without being asked.
 "FileProvider",
 # The other ~20 real frameworks that shared FileProvider's exact shape: present in the local
 # SDK's own headers, simply never named here. Added on the coordinator's explicit instruction
 # after FileProvider's fix, including Metal -- excluded from RANKING via A5_UNREACHABLE
 # (iPhone 4S/iPad 2 lack the hardware), but that is a ranking-time decision, not a reason to
 # keep it invisible to the INDEX: Metal classes remain possible second owners of a colliding
 # selector name, and the index has to be complete for collision resolution regardless of what
 # ranking later does with the result.
 "Metal","MetalKit","MetalPerformanceShaders","SceneKit","CoreHaptics","MediaPlayer","PassKit",
 "Speech","JavaScriptCore","OSLog","CoreSpotlight","Messages","ReplayKit","ARKit","MetricKit",
 "ModelIO","WatchConnectivity","Social",
 # Found by the coverage check itself, on the run right after re-ingesting 8 apps from real
 # binaries (2026-09-23): PDFView (PDFKit) and the two MetalFX descriptor classes -- real demand
 # that only became visible once the corpus held current, real binaries instead of the stale
 # store.json this session started from. Exactly the deviation-from-clean-run signal the check
 # exists to produce.
 "PDFKit","MetalFX"]
out = {}
unverified = []  # (api, kind, framework): no version even after the container fallback, and not
                 # found in the local iPhoneOS SDK either - Catalyst-only or merely newer than
                 # that SDK, indistinguishable from this AST alone; named for a human, not guessed.
for fw in FRAMEWORKS:
    try:
        rows = sd.declared(sdk, fw, "arm64-apple-ios26.0-macabi")
    except SystemExit as e:
        # Truncated to 60 chars before today only showed "clang failed to import CoreTelephony/C"
        # -- readable enough to look like a normal skip line, not enough to show the actual
        # reason. 240 keeps the log line short but leaves the return code and the fatal-error
        # text intact.
        print(f"{fw}: skipped ({str(e)[:240]})", flush=True); continue
    except Exception as e:
        print(f"{fw}: error {e}", flush=True); continue
    real_ios = None
    if IOS_SDK:
        try:
            real_ios = sd.declared(IOS_SDK, fw, IOS_TARGET)
        except Exception as e:
            print(f"{fw}: iPhoneOS cross-check skipped ({str(e)[:60]})", flush=True)
    for api, (kind, ver) in rows.items():
        if ver is None and real_ios is not None and api not in real_ios:
            unverified.append((fw, kind, api))
        v = ".".join(map(str, ver)) if ver else None
        cur = out.get(api)
        # A forward declaration (@class CNContact;) in an earlier framework's header records the class with
        # no version and would win over the real definition dumped later; prefer the row that has a version.
        if cur is None or (cur[1] is None and v is not None):
            out[api] = [kind, v, fw]
    print(f"{fw}: {len(rows)} rows", flush=True)
json.dump(out, open(os.path.join(CORPUS, "sdk-introduced.json"), "w"))

# FRAMEWORKS is a hand-maintained list and it already drifted silently once (FileProvider was
# simply never added; found only by tracing one crash-demand row by hand, half a session later).
# A hardcoded list that can go stale without anything saying so is the wrong shape by itself, per
# the coordinator: derive coverage from what the corpus actually needs, not from memory. Full
# derivation isn't done here (store.json's own framework label is unreliable for this --
# NSFileProviderExtension is attributed to "UIKit" there despite needing FileProvider's header,
# so a label-driven auto-list would have propagated the same undercount) -- this is the mandated
# minimum instead: after every run, name every real class the corpus holds that ISN'T in `out`
# and isn't a known non-SDK name, loudly, so the next gap surfaces on its own first run rather
# than through another half-session of manual tracing.
KNOWN_NON_SDK = {
    # Swift runtime internals -- synthesized by the compiler, no ObjC header exists to dump.
    "SwiftNativeNSObject", "_TtCs12_SwiftObject",
    # libdispatch/os_log C-level objects (OS_OBJECT_DECL macro) -- no @interface, nothing for
    # declared()'s ObjCInterfaceDecl/ObjCMethodDecl walk to find even if the framework is scanned.
    "OS_dispatch_group", "OS_dispatch_queue", "OS_dispatch_source", "OS_os_log",
    # This repo's OWN backport-side classes, not Apple's -- e.g. NSConstantDoubleNumber is
    # `implemented` in the registry at 13.0; there is no Apple header to have declared it.
    "NSConstantArray", "NSConstantDictionary", "NSConstantDoubleNumber", "NSConstantIntegerNumber",
    # Genuinely private Apple class: exported at the link level (present in Messages.framework's
    # own .tbd) but declared in no public header anywhere under Messages.framework -- checked
    # directly, `grep` across every .h in the framework finds nothing. declared() can only ever
    # find header-declared API by construction (it works by #import, not by reading .tbd exports),
    # so this is a structural blind spot of the method itself, not a missing framework and not a
    # broken import -- Messages itself scans fine (102 rows).
    "_MSStickerPackCollectionViewDataSource",
}
_store_candidates = [p for p in [
    os.environ.get("CHARON_TOOLS_DIR") and os.path.join(os.environ["CHARON_TOOLS_DIR"], "store.json"),
    os.path.join(CORPUS, "store.json"),
] if p]
_store_path = next((p for p in _store_candidates if os.path.isfile(p)), None)
if _store_path is None:
    print("FRAMEWORKS coverage check: no store.json found (looked in %s) -- cannot check the "
          "index against real corpus demand this run. Not fatal to sdk-introduced.json itself, "
          "but this safety net did not run." % ", ".join(_store_candidates), flush=True)
else:
    _store = json.load(open(_store_path))
    _corpus_classes = set()
    for _app, _d in _store["apps"].items():
        for _e in _d["demand"]:
            if _e.get("kind") == "class":
                _corpus_classes.add(_e["name"])
    _uncovered = sorted(c for c in _corpus_classes if c not in out and c not in KNOWN_NON_SDK)
    if _uncovered:
        print("FRAMEWORKS COVERAGE GAP: %d real corpus class(es) are absent from "
              "sdk-introduced.json and not in the known-non-SDK allowlist -- FRAMEWORKS is "
              "probably missing a real framework (the FileProvider shape) or that framework's "
              "import is silently failing (the CoreTelephony shape). Not dropped, not guessed at:"
              % len(_uncovered), flush=True)
        for c in _uncovered:
            print("  %s" % c, flush=True)
    else:
        print("FRAMEWORKS coverage check: every one of %d corpus classes is either indexed or "
              "a known non-SDK name (%d allowlisted). No gap found this run."
              % (len(_corpus_classes), len(KNOWN_NON_SDK)), flush=True)
with open(os.path.join(CORPUS, "sdk-introduced-unverified.tsv"), "w") as stream:
    stream.write("framework\tkind\tapi\treason\n")
    for fw, kind, api in sorted(unverified):
        stream.write("%s\t%s\t%s\tno version of its own or its container's, and not declared in the local iPhoneOS SDK either - Catalyst-only or newer than that SDK, not distinguished here\n" % (fw, kind, api))
print("SDK-DONE total", len(out), "unversioned-and-unverified", len(unverified), "(listed, not dropped - see corpus/sdk-introduced-unverified.tsv)", flush=True)
