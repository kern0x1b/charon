import argparse
import collections
import glob
import json
import os
import re
import subprocess
import sys
import tempfile

LINE = re.compile(r"^([| ]*)[|`]-(\w+) 0x[0-9a-f]+ ?(.*)$")
PATH = re.compile(r"(/[^\s:<>,]+\.\w+):\d+:\d+")
ATTRIBUTE = re.compile(r"\b(ios|maccatalyst) (\d+(?:\.\d+){0,2}) \d+(?:\.\d+){0,2} \d+(?:\.\d+){0,2}( Unavailable)?")
# The same attribute with all three numbers kept: introduced, deprecated, obsoleted (0 = not set;
# clang prints 100000 for a deprecation with no version, API_TO_BE_DEPRECATED and the like).
AVAILABILITY = re.compile(r"\bios (\d+(?:\.\d+){0,2}) (\d+(?:\.\d+){0,2}) (\d+(?:\.\d+){0,2})( Unavailable)?")
DEPRECATED_NO_VERSION = (100000,)


def newest_sdk():
    found = sorted(glob.glob("/Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk"), key=lambda path: [int(part) for part in re.findall(r"\d+", os.path.basename(path))])
    if not found:
        sys.exit("no macOS SDK found; pass --sdk")
    return found[-1]


def parse_version(text):
    return tuple(int(part) for part in text.split("."))


def show_version(version):
    parts = list(version)
    while len(parts) > 2 and parts[-1] == 0:
        parts.pop()
    return ".".join(str(part) for part in parts)


def member_name(kind, rest):
    match = re.search(r"(?:col:\d+|line:\d+:\d+|[\w/.+-]+:\d+:\d+)\s+(.*)$", rest)
    text = match.group(1) if match else rest
    if kind == "ObjCMethodDecl":
        parts = text.split(" ", 2)
        return parts[0], parts[1]
    return None, text.split(" ", 1)[0]


class Surface:
    """rows: api -> (kind, introduced), what declared() has always returned. details: api -> the
    whole availability of the declaration, filled alongside: introduced, deprecated, obsoleted (a
    version tuple, DEPRECATED_NO_VERSION for a deprecation with no version, or None), unavailable
    (bool) and via ("own", or "container" when introduced came from the enclosing class, protocol,
    category or enum). full=True also walks what declared() leaves out for the callers that only
    match names: enum types and their cases, struct types, inline functions, and it lets a
    category's availability reach its members. A member with no availability of its own takes
    unavailable and obsoleted from its container as well as introduced."""

    def __init__(self, framework, full=False):
        self.framework = framework
        self.full = full
        self.file = None
        self.rows = {}
        self.details = {}
        self.owner = None
        self.container = None
        self.container_version = None
        self.container_detail = None
        self.target = None
        self.target_depth = None
        self.target_attrs = []
        self.enum_open = False

    def own(self, kind, name, api):
        return api

    def record(self, api, kind, version, detail=None):
        if api not in self.rows or (self.rows[api][1] is None and version is not None):
            self.rows[api] = (kind, version)
            self.details[api] = detail

    def resolve(self, kind):
        """The declaration's own attributes folded into one detail, and the container's where the
        declaration has none."""
        introduced = None
        deprecated = None
        obsoleted = None
        unavailable = False
        for found in self.target_attrs:
            if found[0] and found[0] != (0,):
                introduced = found[0] if introduced is None else min(introduced, found[0])
            if found[1] and found[1] != (0,):
                deprecated = found[1] if deprecated is None else min(deprecated, found[1])
            if found[2] and found[2] != (0,):
                obsoleted = found[2] if obsoleted is None else min(obsoleted, found[2])
            unavailable = unavailable or found[3]
        via = "own"
        container = self.container_detail if kind in ("method", "property", "case") else None
        if container is not None:
            if introduced is None:
                introduced = container["introduced"]
                via = "container" if introduced is not None else "own"
            if not self.target_attrs:
                obsoleted = container["obsoleted"]
                unavailable = container["unavailable"]
        return {"introduced": introduced, "deprecated": deprecated, "obsoleted": obsoleted, "unavailable": unavailable, "via": via}

    def finish_target(self):
        if self.target is None:
            return
        api, kind, versions = self.target
        chosen = min(versions) if versions else None
        detail = self.resolve(kind)
        if api is not None:
            self.record(api, "constant" if kind == "case" else kind, chosen if chosen is not None else (self.container_version if kind in ("method", "property", "case") else None), detail)
        if kind in ("class", "protocol"):
            self.container_version = chosen
            self.container_detail = detail
        elif self.full and kind in ("category", "enum"):
            self.container_version = chosen
            self.container_detail = detail
        self.target = None
        self.target_attrs = []

    def feed(self, lines):
        for line in lines:
            match = LINE.match(line)
            if not match:
                continue
            depth = len(match.group(1)) // 2
            kind = match.group(2)
            rest = match.group(3)
            for path in PATH.findall(rest):
                self.file = path
            # SubFrameworks are every framework's in the Catalyst walk, and each its own in the whole-SDK one
            owned = self.file is not None and (("/%s.framework/" % self.framework) in self.file or (not self.full and "/SubFrameworks/" in self.file))
            if kind == "AvailabilityAttr":
                if self.target is not None and depth == self.target_depth + 1:
                    found = ATTRIBUTE.search(rest)
                    if found and found.group(1) == "ios" and not found.group(3):
                        self.target[2].append(parse_version(found.group(2)))
                    elif found and found.group(1) == "ios":
                        self.target[2].append((999,))
                    whole = AVAILABILITY.search(rest)
                    if whole:
                        self.target_attrs.append((parse_version(whole.group(1)), parse_version(whole.group(2)), parse_version(whole.group(3)), bool(whole.group(4))))
                continue
            if kind == "UnavailableAttr" or kind == "DeprecatedAttr":
                # NS_UNAVAILABLE and the plain deprecated attribute: no platform in them, they
                # hold for iOS as they do for every platform.
                if self.full and self.target is not None and depth == self.target_depth + 1:
                    if kind == "UnavailableAttr":
                        self.target_attrs.append((None, None, None, True))
                    else:
                        self.target_attrs.append((None, DEPRECATED_NO_VERSION, None, False))
                continue
            if depth == 0:
                self.finish_target()
                self.owner = None
                self.enum_open = False
                if self.full:
                    self.container_detail = None
                    self.container_version = None
                if not owned:
                    continue
                if kind in ("ObjCInterfaceDecl", "ObjCProtocolDecl"):
                    name = rest.split()[-1]
                    self.owner = name
                    self.container_version = None
                    self.target = (name, "class" if kind == "ObjCInterfaceDecl" else "protocol", [])
                    self.target_depth = 0
                    self.pending_class = True
                elif kind == "ObjCCategoryDecl":
                    self.owner = None
                    self.pending_category = True
                    self.container_version = None
                    self.target = (None, "category", [])
                    self.target_depth = 0
                elif self.full and kind == "EnumDecl":
                    name = rest.split("'")[0].split()[-1]
                    self.enum_open = True
                    self.container_version = None
                    self.target = (None if re.match(r"^(?:col|line):\d+", name) else name, "enum", [])
                    self.target_depth = 0
                elif self.full and kind == "RecordDecl" and " definition" in rest and " struct " in rest:
                    name = rest.split(" definition")[0].split()[-1]
                    self.target = (None if name == "struct" or re.match(r"^(?:col|line):\d+", name) else name, "struct", [])
                    self.target_depth = 0
                elif kind == "VarDecl" and " extern" in rest:
                    name = rest.split("'")[0].split()[-1]
                    self.target = (name, "constant", [])
                    self.target_depth = 0
                elif kind == "FunctionDecl" and ((" static" not in rest or " inline" in rest) if self.full else (" static" not in rest and " inline" not in rest)):
                    name = rest.split("'")[0].split()[-1]
                    self.target = (name + "()", "function", [])
                    self.target_depth = 0
                continue
            if depth == 1 and kind == "ObjCInterface" and getattr(self, "pending_category", False) and self.target and self.target[1] == "category":
                self.owner = rest.split("'")[1]
                self.pending_category = False
                continue
            if self.full and depth == 1 and kind == "EnumConstantDecl" and self.enum_open and owned:
                self.finish_target()
                self.target = (rest.split("'")[0].split()[-1], "case", [])
                self.target_depth = 1
                continue
            if depth == 1 and kind in ("ObjCMethodDecl", "ObjCPropertyDecl") and self.owner and owned:
                self.finish_target()
                if kind == "ObjCMethodDecl" and " implicit " in rest.split("'")[0]:
                    self.target = None
                    continue
                if kind == "ObjCMethodDecl":
                    sign, name = member_name(kind, rest)
                    api = "%s[%s %s]" % (sign, self.owner, name)
                    self.target = (api, "method", [])
                else:
                    _, name = member_name(kind, rest)
                    self.target = ("%s.%s" % (self.owner, name), "property", [])
                self.target_depth = 1
                continue
        self.finish_target()


def cryptex_frameworks(sdk):
    """The overlay an iPhoneOS SDK from iOS 18 on keeps WebKit, SafariServices,
    AuthenticationServices, BrowserKit and JavaScriptCore in, or None."""
    path = os.path.join(sdk, "System", "Cryptexes", "OS", "System", "Library", "Frameworks")
    return path if os.path.isdir(path) else None


def subframeworks(sdk):
    """System/Library/SubFrameworks (UIUtilities: UIGeometry.h, UIDefines.h), or None."""
    path = os.path.join(sdk, "System", "Library", "SubFrameworks")
    return path if os.path.isdir(path) else None


def framework_bases(sdk, target, full=False):
    """The directories a <Framework/...> import can resolve into, in the order clang looks for
    this target: the iOSSupport overlay first for a macabi target, then the SDK's own
    System/Library/Frameworks, then the cryptex overlay, and for the whole-SDK walk (full) the
    SubFrameworks, which are frameworks of their own there."""
    bases = []
    if target.endswith("macabi"):
        bases.append(os.path.join(sdk, "System", "iOSSupport", "System", "Library", "Frameworks"))
    bases.append(os.path.join(sdk, "System", "Library", "Frameworks"))
    if cryptex_frameworks(sdk):
        bases.append(cryptex_frameworks(sdk))
    if full and subframeworks(sdk):
        bases.append(subframeworks(sdk))
    return bases


def framework_headers_dir(sdk, framework, target, full=False):
    """Where framework's own Headers/ live, checked in the same order clang itself would
    resolve <Framework/...> for this target (framework_bases). A framework bundle's Headers is
    sometimes a top-level symlink, sometimes only reachable via Versions/A/Headers (relevant
    when the symlink itself doesn't resolve in this environment); both are checked."""
    for base in framework_bases(sdk, target, full):
        fw = os.path.join(base, framework + ".framework")
        for headers in (os.path.join(fw, "Headers"), os.path.join(fw, "Versions", "A", "Headers")):
            if os.path.isdir(headers):
                return headers
    return None


def sdk_version(sdk):
    """The SDK's own version, from its SDKSettings.json (26.2 for iPhoneOS26.2.sdk)."""
    with open(os.path.join(sdk, "SDKSettings.json")) as stream:
        return json.load(stream)["Version"]


def clang_command(sdk, target, full=False):
    command = ["xcrun", "clang", "-x", "objective-c", "-target", target, "-isysroot", sdk, "-w", "-fsyntax-only", "-Xclang", "-ast-dump"]
    support = os.path.join(sdk, "System", "iOSSupport", "System", "Library", "Frameworks")
    if target.endswith("macabi"):
        command += ["-iframework", support]
    if cryptex_frameworks(sdk):
        command += ["-iframework", cryptex_frameworks(sdk)]
    if full and subframeworks(sdk):
        command += ["-iframework", subframeworks(sdk)]
    return command


def dump_headers(command, imports):
    handle, source = tempfile.mkstemp(suffix=".m")
    with os.fdopen(handle, "w") as stream:
        stream.write(imports)
    try:
        return subprocess.run(command + [source], capture_output=True, text=True, errors="replace")
    finally:
        os.unlink(source)


def declared(sdk, framework, target):
    return declared_surface(sdk, framework, target).rows


def declared_surface(sdk, framework, target, full=False, failed=None):
    """The whole Surface of framework: rows as declared() returns them and the availability
    details. full=True is the walk for an iPhoneOS SDK taken whole: see declared_surface_full."""
    if full:
        return declared_surface_full(sdk, framework, target, failed)
    command = clang_command(sdk, target)
    dump = dump_headers(command, "#import <%s/%s.h>\n" % (framework, framework))
    if not dump.stdout:
        sys.exit("clang produced no AST for %s: %s" % (framework, dump.stderr[:400]))
    # `-fsyntax-only -Xclang -ast-dump` still dumps a non-empty translation unit (builtins,
    # implicit typedefs -- tens of thousands of characters) even after clang reports a FATAL
    # `#import` failure, so `dump.stdout` being non-empty is not evidence the import
    # succeeded. Measured on CoreTelephony: this SDK's own CoreTelephony.framework ships no
    # self-named umbrella header (per-class headers only -- CTCall.h, CTCarrier.h, ... plus
    # CoreTelephonyDefines.h, no CoreTelephony.h), so `#import <CoreTelephony/CoreTelephony.h>`
    # fails with "file not found", yet the check above let it through silently: 18KB of
    # boilerplate stdout, zero real declarations, "CoreTelephony: 0 rows" printed as if the
    # framework had genuinely nothing left to gap-check, no error, no skip. Checking the
    # return code catches exactly this without falsely flagging a framework whose own content
    # legitimately lives elsewhere (MobileCoreServices imports fine, returncode 0, and is
    # correctly empty here because its real content is under CoreServices, scanned
    # separately, not because its own import failed).
    if dump.returncode != 0:
        # A framework with no self-named umbrella header is a normal shape, not an anomaly
        # to special-case by name -- fall back to importing every header actually present in
        # the framework's own Headers/ directory instead of the assumed <Name/Name.h>, once,
        # generically, so the next framework shaped this way needs no new code, only a run.
        headers_dir = framework_headers_dir(sdk, framework, target)
        headers = sorted(f for f in os.listdir(headers_dir) if f.endswith(".h")) if headers_dir else []
        if not headers:
            sys.exit("clang failed to import %s/%s.h for target %s (returncode %d), and no "
                      "fallback headers found (Headers/ dir: %s) -- %s" %
                      (framework, framework, target, dump.returncode, headers_dir, dump.stderr[:400]))
        dump = dump_headers(command, "".join("#import <%s/%s>\n" % (framework, h) for h in headers))
        if not dump.stdout:
            sys.exit("clang produced no AST for %s even importing its %d individual headers: %s"
                      % (framework, len(headers), dump.stderr[:400]))
        if dump.returncode != 0:
            sys.exit("clang still failed for %s after falling back to its %d individual "
                      "headers (returncode %d): %s" %
                      (framework, len(headers), dump.returncode, dump.stderr[:400]))
    surface = Surface(framework)
    surface.feed(dump.stdout.splitlines())
    return surface


def declared_surface_full(sdk, framework, target, failed=None):
    """The walk for an iPhoneOS SDK taken whole (Surface(full=True)): the umbrella header where
    there is one and every other header in the framework's Headers/ together, since an umbrella
    leaves public headers out (CoreImage's CIFilterBuiltins.h: 1063 members the umbrella never
    reaches). When the lot does not parse, each header is read on its own and the ones clang rejects
    are named in `failed` (a list, when the caller passes one) instead of taking the rest down with
    them. A framework with no header at all yields an empty Surface."""
    command = clang_command(sdk, target, full=True)
    headers_dir = framework_headers_dir(sdk, framework, target, full=True)
    headers = sorted(f for f in os.listdir(headers_dir) if f.endswith(".h")) if headers_dir else []
    surface = Surface(framework, full=True)
    if not headers:
        return surface
    imports = [h for h in headers if h != framework + ".h"]
    if framework + ".h" in headers:
        imports.insert(0, framework + ".h")
    dump = dump_headers(command, "".join("#import <%s/%s>\n" % (framework, h) for h in imports))
    if dump.returncode == 0 and dump.stdout:
        surface.feed(dump.stdout.splitlines())
        return surface
    for h in imports:
        single = dump_headers(command, "#import <%s/%s>\n" % (framework, h))
        if single.returncode != 0 or not single.stdout:
            if failed is not None:
                lines = single.stderr.strip().splitlines()
                failed.append("%s/%s: %s" % (framework, h, lines[-1][:200] if lines else "no output"))
            continue
        surface.feed(single.stdout.splitlines())
        surface.file = None
    return surface


def registry_names(root, framework):
    names = {}
    for path in glob.glob(os.path.join(root, framework, "*.json")) + glob.glob(os.path.join(root, framework + ".json")):
        with open(path) as stream:
            data = json.load(stream)
        for entry in data["entries"] if isinstance(data, dict) else data:
            names[entry["api"]] = (entry.get("status", ""), parse_version(entry["introduced"]) if entry.get("introduced") else None)
    return names


class Release:
    def __init__(self, release):
        path = os.path.join(os.path.expanduser("~"), ".charon", "dyld", release, "classes_armv7.json")
        if not os.path.exists(path):
            sys.exit("no class inventory of iOS %s at %s" % (release, path))
        with open(path) as stream:
            self.classes = json.load(stream)["classes"]

    def selectors(self):
        if not hasattr(self, "_selectors"):
            found = set()
            for entry in self.classes.values():
                found.update(entry.get("instance") or [])
                found.update(entry.get("class") or [])
            self._selectors = found
        return self._selectors

    def protocols(self):
        if not hasattr(self, "_protocols"):
            found = set()
            for entry in self.classes.values():
                found.update(entry.get("protocols") or [])
            self._protocols = found
        return self._protocols

    def knows_selector(self, api, kind):
        found = re.match(r"^[-+]\[\w+ (.+)\]$", api)
        if found:
            return found.group(1) in self.selectors()
        if kind == "property":
            name = api.split(".", 1)[1]
            return name in self.selectors()
        return False

    def has(self, api, kind):
        if kind == "class":
            return api in self.classes
        found = re.match(r"^([-+])\[(\w+) (.+)\]$", api)
        if found:
            side = "instance" if found.group(1) == "-" else "class"
            selector, owner = found.group(3), found.group(2)
        elif kind == "property":
            owner, name = api.split(".", 1)
            selectors = [name, "set" + name[0].upper() + name[1:] + ":"]
            side = "instance"
            return self.answers(owner, side, selectors[0])
        else:
            return False
        return self.answers(owner, side, selector)

    def answers(self, owner, side, selector):
        seen = set()
        while owner in self.classes and owner not in seen:
            seen.add(owner)
            entry = self.classes[owner]
            if selector in (entry.get(side) or []):
                return True
            owner = entry.get("superclass")
        return False


def covered(api, kind, version, registry):
    if api in registry:
        return True
    owner = re.match(r"^[-+]\[(\w+) ", api)
    owner = owner.group(1) if owner else (api.split(".")[0] if kind == "property" else None)
    if kind == "property":
        name = api.split(".", 1)[1]
        setter = "set" + name[0].upper() + name[1:] + ":"
        for candidate in ("-[%s %s]" % (owner, name), "-[%s %s]" % (owner, setter)):
            if candidate in registry:
                return True
    entry = registry.get(owner)
    if entry and entry[0] in ("absent", "ignored"):
        return True
    if entry and entry[0] == "implemented" and entry[1] and version and version <= entry[1]:
        return True
    return False


def main():
    parser = argparse.ArgumentParser(description="Diff the API an SDK declares against the registry of the backports. A row is decided when the registry lists it, or its class as absent or ignored, or its class as implemented with the release the row arrived in; a gap is API nobody has decided about, which is absent by default.")
    parser.add_argument("frameworks", nargs="+")
    parser.add_argument("--sdk", default=None, help="a macOS SDK with System/iOSSupport (Mac Catalyst), or an iPhoneOS SDK")
    parser.add_argument("--target", default=None, help="default: iOS 26 Catalyst for a macOS SDK, the SDK's own version for an iPhoneOS one")
    parser.add_argument("--registry", default=os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "..", "packages", "a", "apple-backports", "registry"))
    parser.add_argument("--above", default="6.0", help="only what arrived after this release")
    parser.add_argument("--up-to", default=None, help="only what arrived up to and including this release")
    parser.add_argument("--release", default=None, help="a release whose classes the release itself carries, from ~/.charon/dyld/<release>/classes_armv7.json: what it answers is not a gap")
    parser.add_argument("--list", action="store_true", help="print every gap")
    parser.add_argument("--rows", default=None, help="write every declared row, tab separated, to this file")
    options = parser.parse_args()
    sdk = options.sdk or newest_sdk()
    target = options.target or ("arm64-apple-ios26.0-macabi" if "MacOSX" in os.path.basename(sdk) else "arm64-apple-ios" + sdk_version(sdk))
    above = parse_version(options.above)
    up_to = parse_version(options.up_to) if options.up_to else None
    print("SDK %s, target %s, API that arrived after iOS %s%s" % (os.path.basename(sdk), target, options.above, " up to %s" % options.up_to if up_to else ""))
    inventory = Release(options.release) if options.release else None
    written = open(options.rows, "w") if options.rows else None
    for framework in options.frameworks:
        rows = declared(sdk, framework, target)
        if written:
            for api, (kind, version) in sorted(rows.items()):
                written.write("%s\t%s\t%s\t%s\n" % (framework, kind, api, show_version(version) if version and version != (999,) else ""))
        registry = registry_names(options.registry, framework)
        totals = collections.Counter()
        gaps = collections.Counter()
        carried = collections.Counter()
        listed = []
        unversioned = []
        for api, (kind, version) in sorted(rows.items()):
            if version is None:
                owner = re.match(r"^[-+]\[(\w+) ", api)
                owner = owner.group(1) if owner else api.split(".")[0]
                gone = owner not in inventory.classes and owner not in inventory.protocols() if inventory else False
                if inventory and kind in ("method", "property") and not covered(api, kind, None, registry) and not inventory.knows_selector(api, kind) and gone:
                    unversioned.append((api, kind))
                continue
            if version <= above or version == (999,) or (up_to and version[:2] > up_to + (0,) * (2 - len(up_to)) and version > up_to):
                continue
            release = "%d" % version[0]
            totals[release] += 1
            if not covered(api, kind, version, registry) and inventory and inventory.has(api, kind):
                carried[release] += 1
            elif not covered(api, kind, version, registry):
                gaps[release] += 1
                listed.append((version, api, kind))
        print("\n%s: %d declared after iOS %s, %d not decided%s" % (framework, sum(totals.values()), options.above, sum(gaps.values()),
              ", %d of the rest carried by iOS %s itself" % (sum(carried.values()), options.release) if inventory else ""))
        for release in sorted(totals, key=int):
            print("  iOS %-3s declared %5d   decided %5d%s   gap %5d" % (release, totals[release], totals[release] - gaps[release] - carried[release],
                  "   carried by the release %5d" % carried[release] if inventory else "", gaps[release]))
        if inventory:
            print("  no recorded availability: %d members of a class or protocol iOS %s does not have, that no class of it answers and the registry does not decide" % (len(unversioned), options.release))
        if options.list:
            for version, api, kind in sorted(listed):
                print("    %-6s %-9s %s" % (show_version(version), kind, api))
            for api, kind in unversioned:
                print("    %-6s %-9s %s" % ("?", kind, api))


if __name__ == "__main__":
    main()
