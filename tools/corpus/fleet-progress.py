#!/usr/bin/env python3
"""
fleet-progress.py -- how much of the SDK 26.2 surface the fleet has actually built, counting the
work that is sitting in a band's worktree and not merged yet.

The ledger measures one thing: what a build of main plus the release's own caches contain. Most of
what the bands have built is in their worktrees, so the ledger alone under-reports the fleet by
whatever has not been merged. This adds that third bucket. For every row of
coordination/corpus/sdk-26.2-surface.tsv it says:

  merged on main        the row is implemented in main's own registry -- the checked-in record of
                        what the port carries -- or in a build of main, or the release already ships
                        it. None of it is anybody's outstanding work.
  delivered, built      the row is carried by a band's built libraries or built Swift module and main
                        does not have it. Counted once however many bands carry it.
  delivered, registry only
                        a band's registry records it `implemented` and nothing built carries it, so
                        the claim is a record of intent rather than a delivery.
  decided against       a registry records it absent, inert or ignored: nobody is going to build it.
  still missing         no band and no main: the work nobody has done.

Sources of truth, all read live, nothing taken from a band's report of itself:

  - main:   charon/packages/a/apple-backports/registry/**/*.json, entries with status `implemented`;
            plus the release's own 6.1.3 dyld cache, which the port carries whatever the bands did.
  - a band: charon/.agent-work/worktrees/api-<name>, and eidolon/styx worktrees for Swift modules.
            Its registry the same way; its newest built `lib*Backports.dylib` gate directory through
            tools/corpus/fleet-inventory.lua (the project's own ObjC reader, one run per band);
            its exported symbols with `nm -gU`; and any armv7 binary `.swiftmodule` it has built,
            through `swift-api-digester`, the same reader the ledger's Swift pass uses.

A row is matched to a name by what a source can call it: a property row `C.p` is implemented by a
registry entry for `C.p`, `-[C p]` or `-[C setP:]`, a constant row by `X` or `_X`, a Swift row by any
of the spellings api-ledger.py's Swift pass looks up (the digester prints a member without its
argument labels where the .swiftinterface has them).

Cost: a registry tree is 4.7 MB and 0.04 s to read, a band's 28 libraries 0.2 s. The whole view is
seconds, so it can be run every hour. Per-band inventories are cached under --cache-dir, keyed on
the artifact's own mtime and size and on this file, so a re-run inside the hour is a file read.

Usage:
  python3 fleet-progress.py --surface <tsv> --out <FLEET.md> [--worktrees <workspace root>]
                           [--release-cache <6.1.3 dyld cache>] [--cache-dir <dir>] [--jobs N]
                           [--json <FLEET.json>]
"""
import argparse
import collections
import concurrent.futures
import csv
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
CHARON_ROOT = os.path.realpath(os.path.join(HERE, "..", ".."))
CHARON_ROOT = os.environ.get("CHARON_ROOT", CHARON_ROOT)
BAND_PREFIX = "api-"
IMPLEMENTED = "implemented"
DECIDED_STATUSES = ("absent", "inert", "ignored")


def note(message):
    print(message, file=sys.stderr, flush=True)


def load_ledger_module():
    """api-ledger.py's own name matching, so a row is placed here by the same rules the ledger uses
    rather than by a second spelling of them."""
    spec = importlib.util.spec_from_file_location("api_ledger", os.path.join(HERE, "api-ledger.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ---------------------------------------------------------------------------
# Reading a registry
# ---------------------------------------------------------------------------

def registry_roots(checkout):
    """Every directory named `registry` under a checkout's packages/, which is where each package
    keeps its own: charon's apple-backports has one, its per-band subpackages have their own, and a
    Swift package keeps its own the same way (createml's is packages/c/createml/registry, with the
    same entry shape). Any depth, so a package nested three deep is found without a list to keep."""
    found = []
    packages = os.path.join(checkout, "packages")
    for base, dirs, _ in os.walk(packages) if os.path.isdir(packages) else []:
        if os.path.basename(base) == "registry":
            found.append(base)
            dirs[:] = []
    return sorted(found)


def read_package_registries(checkout):
    """({api: status} over every package's own registry, {package: entries read}) for a checkout."""
    entries, per_package = {}, {}
    for root in registry_roots(checkout):
        read = read_registry(root)
        package = os.path.relpath(os.path.dirname(root), checkout)
        per_package[package] = len(read)
        entries.update(read)
    return entries, per_package


def read_registry_export(path):
    """{api: status} from a carried-registry export: the same rows the registry tree holds, in the
    one file the coordinator's own export writes, so a run against a named main revision does not
    depend on which checkout this worktree has."""
    import csv as _csv
    entries = {}
    with open(path, newline="", encoding="utf-8") as f:
        for row in _csv.DictReader(f, delimiter="\t"):
            if row.get("api"):
                entries[row["api"]] = (row.get("status", ""), row.get("reason", ""))
    return entries


def read_registry(directory):
    """{api: (status, reason)} for every entry in a registry tree. A missing tree is an empty one,
    not an error: a band that has not touched the registry has delivered nothing through it. The
    reason comes along because a decision is only useful with the reason it was taken for."""
    entries = {}
    for base, _, files in os.walk(directory):
        for name in sorted(files):
            if not name.endswith(".json"):
                continue
            try:
                with open(os.path.join(base, name), encoding="utf-8") as f:
                    data = json.load(f)
            except (ValueError, OSError):
                continue
            listed = data.get("entries") if isinstance(data, dict) else data
            for entry in listed or []:
                if entry.get("api"):
                    entries[entry["api"]] = entry.get("status", "")
    return entries


# ---------------------------------------------------------------------------
# Reading a band's built artifacts
# ---------------------------------------------------------------------------

def newest_gate(worktree):
    """The band's newest built gate directory -- the one that says what the band last built, rather
    than every run it has ever done."""
    runs = os.path.join(worktree, ".agent-work", "runs")
    best = None
    if not os.path.isdir(runs):
        return None
    for base, dirs, files in os.walk(runs):
        built = [f for f in files if f.startswith("lib") and f.endswith("Backports.dylib")]
        if not built:
            continue
        stamp = max(os.path.getmtime(os.path.join(base, f)) for f in built)
        if best is None or stamp > best[0]:
            best = (stamp, base)
    return best[1] if best else None


def newest_swiftmodule(worktree):
    """The newest armv7 binary Swift module the tree has built, which is what a port would link:
    a file named `armv7-apple-ios.swiftmodule` inside a `<Module>.swiftmodule` directory. A
    `.swiftinterface` is not one -- that is a reference, which the ledger records separately."""
    best = None
    roots = [os.path.join(worktree, ".agent-work")]
    roots += [os.path.join(worktree, name) for name in ("build", "bridge", "lib")
              if os.path.isdir(os.path.join(worktree, name))]
    for root in roots:
        if not os.path.isdir(root):
            continue
        for base, _, files in os.walk(root):
            if "armv7-apple-ios.swiftmodule" not in files:
                continue
            directory = base
            if not directory.endswith(".swiftmodule"):
                continue
            stamp = os.path.getmtime(os.path.join(base, "armv7-apple-ios.swiftmodule"))
            if best is None or stamp > best[0]:
                best = (stamp, directory)
    return best[1] if best else None


def as_pairs(entries):
    """{name: (instance selectors, class selectors)}. The ledger's own reader hands back a dict per
    class, the lua one hands back two sets; one shape here, so matching has one shape to reason
    about."""
    out = {}
    for name, entry in entries.items():
        if isinstance(entry, dict):
            out[name] = (set(entry.get("instance") or ()), set(entry.get("class") or ()))
        else:
            out[name] = (set(entry[0]), set(entry[1]))
    return out


def inventory_directory(directory, architecture="armv7"):
    """({class: (instance, class)} for the ObjC side, {exported symbols}) for one built tree."""
    classes, protocols, exports = {}, {}, set()
    env = dict(os.environ, CHARON_ROOT=CHARON_ROOT)
    out = subprocess.run(["xmake", "l", os.path.join(HERE, "fleet-inventory.lua"), directory,
                          architecture], cwd=CHARON_ROOT, env=env, capture_output=True, text=True,
                         timeout=1800)
    if out.returncode != 0:
        raise RuntimeError("fleet-inventory.lua failed on %s: %s" % (directory, out.stderr[-2000:]))
    for line in out.stdout.splitlines():
        if line.startswith("#"):
            continue
        parts = line.split("\t")
        if parts[0] == "class" and len(parts) >= 4:
            classes[parts[1]] = (set(p for p in parts[2].split(",") if p),
                                 set(p for p in parts[3].split(",") if p))
        elif parts[0] == "protocol" and len(parts) >= 4:
            protocols[parts[1]] = (set(p for p in parts[2].split(",") if p),
                                   set(p for p in parts[3].split(",") if p))
    # One nm for the whole directory, not one per library: 22 bands x 28 libraries is 616
    # processes, and each costs more than the inventory it serves. nm prints a `path:` header per
    # input when given several, which is a single field and is skipped below.
    dylibs = [os.path.join(directory, name) for name in sorted(os.listdir(directory))
              if name.endswith(".dylib")]
    exports = nm_exports(dylibs) if dylibs else set()
    return classes, protocols, exports


def nm_exports(dylibs):
    if isinstance(dylibs, str):
        dylibs = [dylibs]
    out = subprocess.run(["nm", "-gU"] + list(dylibs), capture_output=True, text=True, timeout=900)
    names = set()
    for line in out.stdout.splitlines():
        fields = line.split()
        if len(fields) >= 3 and re.match(r"^[0-9a-fA-F]+$", fields[0]):
            names.add(fields[2])
        elif len(fields) == 2:
            names.add(fields[1])
    return {n for n in names if n.startswith("_")}


def digester_names(module_dir, digester, sdk, vfs, search_dirs=(), extra_maps=()):
    """{name: kind} for a built armv7 Swift module, through the toolchain's own API digester -- the
    same reader the ledger's Swift pass uses, so a band and the ledger agree on what a module has."""
    module = os.path.basename(module_dir)[:-len(".swiftmodule")]
    handle, out_path = tempfile.mkstemp(suffix="-%s.json" % re.sub(r"\W", "_", module))
    os.close(handle)
    try:
        args = [digester, "-dump-sdk", "-module", module, "-I", module_dir]
        for extra in search_dirs:
            args += ["-I", extra]
        args += ["-target", "armv7-apple-ios6.1.3", "-sdk", sdk, "-Xcc", "-Wno-incompatible-sysroot"]
        for module_map in extra_maps:
            args += ["-Xcc", "-fmodule-map-file=%s" % module_map]
        args += ["-Xcc", "-ivfsoverlay", "-Xcc", vfs, "-o", out_path]
        run = subprocess.run(args, capture_output=True, text=True, errors="replace", timeout=1800)
        if run.returncode != 0:
            return None, "swift-api-digester failed (%d): %s" % (run.returncode,
                                                                  run.stderr.strip()[-200:])
        with open(out_path, encoding="utf-8") as f:
            payload = json.load(f)
    except (ValueError, OSError) as error:
        return None, "the digester's output could not be read: %s" % error
    finally:
        os.unlink(out_path)
    # A member's own printedName is unqualified, so a name is qualified by the types it is declared
    # in; a type is indexed bare and qualified, which is how a surface row names a type.
    types = {"TypeNominal", "TypeDecl", "TypeAlias", "TypeNameAlias"}
    names, stack = {}, [(payload.get("ABIRoot", {}), ())]
    while stack:
        node, path = stack.pop()
        kind, own = node.get("kind"), node.get("printedName") or node.get("name")
        if kind in ("Import", "Root") or not own:
            for child in node.get("children", []):
                stack.append((child, path))
            continue
        here = path + ((kind, own),)
        qualified = ".".join(name for _, name in here)
        for name in ((own, qualified) if kind in types else (qualified,)):
            names.setdefault(name, kind)
        inside = here if kind in types else path
        for child in node.get("children", []):
            stack.append((child, inside))
    return names, None


# ---------------------------------------------------------------------------
# Mapping a source's names onto ledger rows
# ---------------------------------------------------------------------------

PROPERTY_RE = re.compile(r"^([\w]+)\.([\w]+)$")
METHOD_RE = re.compile(r"^([-+])\[([\w]+)(?:\([\w]+\))? (.+)\]$")


def names_a_source_may_call(ledger, row):
    """Every name a registry entry, a built library or a built module could carry for this row."""
    api, kind, lang = row["api"], row["kind"], row["lang"]
    if lang == "swift":
        return ledger.swift_forms(api)
    if kind == "method":
        found = METHOD_RE.match(api)
        return [api, ("-[%s %s]" % (found.group(2), found.group(3)))] if found else [api]
    if kind == "property":
        found = PROPERTY_RE.match(api)
        if not found:
            return [api]
        owner, prop = found.groups()
        return [api, "-[%s %s]" % (owner, prop),
                "-[%s set%s%s:]" % (owner, prop[0].upper(), prop[1:]),
                "+[%s %s]" % (owner, prop)]
    if kind in ("constant", "function"):
        name = api[:-2] if api.endswith("()") else api
        return [api, name, "_" + name]
    return [api]


class Sources:
    """What one source of implementation says it has: a registry's implemented names, a built
    tree's classes and selectors, its exported symbols, and a built module's declaration names."""

    def __init__(self, name, registry=None, classes=None, protocols=None, exports=None, swift=None):
        self.name = name
        self.registry = registry or {}
        self.classes = classes or {}
        self.protocols = protocols or {}
        self.exports = exports or {}
        self.swift = swift or {}

    def implemented_names(self):
        return {api for api, value in self.registry.items()
                if (value[0] if isinstance(value, tuple) else value) == IMPLEMENTED}

    def decisions(self):
        """{api: (status, reason, source)} for the rows a registry has decided against: `absent`,
        `inert` or `ignored` is a decision somebody took, with a reason recorded."""
        found = {}
        for api, value in self.registry.items():
            status, reason = value if isinstance(value, tuple) else (value, "")
            if status in DECIDED_STATUSES:
                found[api] = (status, reason, self.name)
        return found

    def has(self, row, ledger):
        """Whether this source has the row, by the names a source could call it. A property is
        implemented by either accessor; a class property by its class-side getter, which is a class
        selector and never an instance one."""
        api, kind, lang = row["api"], row["kind"], row["lang"]
        if lang == "swift":
            for form in ledger.swift_forms(api):
                if form in self.swift and self.swift[form] in ledger.SWIFT_COMPATIBLE.get(kind, set()):
                    return True
            return False
        if kind in ("class", "protocol"):
            return api in self.classes or api in self.protocols
        if kind in ("method", "property"):
            found = (METHOD_RE.match(api) if kind == "method" else PROPERTY_RE.match(api))
            if not found:
                return False
            if kind == "method":
                owner, selector = found.group(2), "-" + found.group(3)
            else:
                owner, prop = found.groups()
                selector = None
            entry = self.classes.get(owner) or self.protocols.get(owner)
            if not entry:
                return False
            if selector:
                return selector in entry[0] or selector in entry[1]
            getter, setter = "-" + prop, "-set" + prop[0].upper() + prop[1:] + ":"
            for wanted in (getter, setter, "+" + getter):
                if wanted in entry[0] or wanted in entry[1]:
                    return True
            return False
        if kind in ("constant", "function"):
            name = api[:-2] if api.endswith("()") else api
            return ("_" + name) in self.exports
        return api in self.implemented_names()

    def names(self):
        """Every name a row could be matched against this source by: the implemented registry
        entries, each class and protocol by its own name and each of its selectors qualified by its
        owner, each property by its two accessors, the exported symbols, and the module's declared
        names. A method's `+`/`-` is not part of the key, for the reason the ledger gives: apple.objc
        keys a selector with a leading `-` for an instance and a class method alike."""
        index = set(self.implemented_names())
        for owner, (instance, klass) in list(self.classes.items()) + list(self.protocols.items()):
            index.add(owner)
            for selector in instance | klass:
                body = selector[1:] if selector[:1] in "+-" else selector
                index.add("-[%s %s]" % (owner, body))
                index.add("+[%s %s]" % (owner, body))
                if body.startswith("set") and body.endswith(":"):
                    index.add("%s.%s" % (owner, body[3:-1]))
                elif ":" not in body:
                    index.add("%s.%s" % (owner, body))
        for symbol in self.exports:
            index.add(symbol[1:])
        index |= set(self.swift)
        return index


# ---------------------------------------------------------------------------
# Bands
# ---------------------------------------------------------------------------

def discover_bands(worktrees):
    """Every api-* worktree of the charon repository, plus the eidolon and styx worktrees, which are
    where a built Swift module for those ports lives."""
    bands = []
    charon = os.path.join(worktrees, "charon", ".agent-work", "worktrees")
    if os.path.isdir(charon):
        for name in sorted(os.listdir(charon)):
            if name.startswith(BAND_PREFIX) and os.path.isdir(os.path.join(charon, name)):
                bands.append({"name": name, "worktree": os.path.join(charon, name), "kind": "charon"})
    for repo in ("eidolon", "styx"):
        base = os.path.join(worktrees, repo, ".agent-work", "worktrees")
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            path = os.path.join(base, name)
            if os.path.isdir(path):
                bands.append({"name": "%s/%s" % (repo, name), "worktree": path, "kind": repo})
    return bands


def band_sources(band, cache_dir, digester, sdk, vfs, search_dirs, extra_maps, main_names=()):
    """Everything one band has: its registry, its newest built gate directory, and any armv7 Swift
    module it has built. Cached on the artifact's own mtime and size, and on this file, so an
    hourly run inside the same hour is a file read."""
    worktree = band["worktree"]
    # Every package's own registry, not only apple-backports': a Swift package keeps its Swift rows
    # the same way, and a Swift-module row has to count from it.
    registry, packages = read_package_registries(worktree)
    implemented = {api for api, status in registry.items() if status == IMPLEMENTED}
    # What the band holds that main does not: the raw registry count is main's own count plus the
    # band's work, so it says nothing on its own.
    beyond_main = implemented - set(main_names)
    gate = newest_gate(worktree)
    classes = protocols = exports = {}
    if gate:
        key = hashlib.sha256("".join([gate, str(int(os.path.getmtime(gate))), TOOL,
                                      str(int(os.path.getmtime(os.path.join(HERE, "fleet-inventory.lua"))))]
                             ).encode()).hexdigest()[:16]
        cache_file = os.path.join(cache_dir, "band-%s.json" % key)
        if os.path.exists(cache_file):
            with open(cache_file, encoding="utf-8") as f:
                built = json.load(f)
            classes = {k: (set(v[0]), set(v[1])) for k, v in built["classes"].items()}
            protocols = {k: (set(v[0]), set(v[1])) for k, v in built["protocols"].items()}
            exports = set(built["exports"])
        else:
            classes, protocols, exports = inventory_directory(gate)
            with open(cache_file, "w", encoding="utf-8") as f:
                json.dump({"classes": {k: [sorted(v[0]), sorted(v[1])] for k, v in classes.items()},
                           "protocols": {k: [sorted(v[0]), sorted(v[1])]
                                          for k, v in protocols.items()},
                           "exports": sorted(exports)}, f)
    module_dir = newest_swiftmodule(worktree)
    swift = {}
    if module_dir:
        key = hashlib.sha256("".join([module_dir, str(int(os.path.getmtime(module_dir))), TOOL,
                                      str(int(os.path.getmtime(digester)))]).encode()).hexdigest()[:16]
        cache_file = os.path.join(cache_dir, "module-%s.json" % key)
        if os.path.exists(cache_file):
            with open(cache_file, encoding="utf-8") as f:
                swift = json.load(f)
        else:
            found, error = digester_names(module_dir, digester, sdk, vfs, search_dirs, extra_maps)
            if found:
                swift = found
                with open(cache_file, "w", encoding="utf-8") as f:
                    json.dump(swift, f)
            else:
                note("  %s: %s" % (band["name"], error))
    return Sources(band["name"], registry, classes, protocols, exports, swift), {
        "registry-implemented": len(implemented), "beyond-main": len(beyond_main),
        "packages": {k: v for k, v in sorted(packages.items()) if v},
        "gate": gate, "module": module_dir, "classes": len(classes), "exports": len(exports),
        "swift": len(swift)}


TOOL = os.path.realpath(__file__)


def built_tree(gate_dir):
    """The tree a run directory was built from, read from the `tree` file build-gate.lua writes in
    it; a directory without one says so rather than borrowing the worktree's HEAD."""
    record = os.path.join(gate_dir or "", "tree")
    if gate_dir and os.path.exists(record):
        fields = {}
        with open(record, encoding="utf-8", errors="replace") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t", 1)
                if len(parts) == 2:
                    fields[parts[0]] = parts[1]
        if fields.get("revision") and fields["revision"] != "unknown":
            return "%s%s" % (fields["revision"][:12],
                             " (dirty)" if fields.get("dirty") == "yes" else "")
    if not gate_dir:
        return "no --gate given"
    try:
        when = time.strftime("%Y-%m-%d %H:%M", time.localtime(os.path.getmtime(gate_dir)))
    except OSError:
        when = "unknown"
    return "built %s, tree not recorded" % when


def short(path):
    """A path with the home directory written as $HOME, so the file reads the same wherever it is
    read and carries no personal path."""
    return path.replace(os.path.expanduser("~"), "$HOME")


def find_digester():
    root = os.path.expanduser("~/.xmake/packages/s/swift")
    found = []
    for base, _, files in os.walk(root):
        if "swift-api-digester" in files:
            path = os.path.join(base, "swift-api-digester")
            found.append((os.path.getmtime(path), path))
    if not found:
        sys.exit("fleet-progress.py: no swift-api-digester under %s" % root)
    return max(found)[1]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--surface", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--worktrees", default=os.path.expanduser("~/Git/projects/ios"))
    ap.add_argument("--registry", default=None,
                    help="a carried-registry export TSV (framework/api/status/introduced/kind) to "
                         "stand for main's registry, for a main revision this worktree does not "
                         "have. Without it the registry is read from the checkout given")
    ap.add_argument("--gate", default=None,
                    help="a build of main's own libraries (a gate run); part of 'merged on main'. "
                         "Defaults to the coordinator's own build of main, the one the ledger "
                         "measures against, so the two views cannot disagree about what main has")
    ap.add_argument("--release-cache",
                    default=os.path.expanduser("~/.charon/dyld/6.1.3/dyld_shared_cache_armv7"))
    ap.add_argument("--cache-dir", default=None)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--swift-modules", default=None,
                    help="swift-modules.json from api-ledger-swift.py: the armv7 Swift modules the "
                         "port itself links, which are part of main and not of any band. Defaults "
                         "to the ledger's own output beside this file when it is there")
    ap.add_argument("--json", default=None)
    args = ap.parse_args()
    started = time.time()

    ledger = load_ledger_module()
    cache_dir = args.cache_dir or os.path.join(os.path.dirname(args.out), "fleet-cache")
    os.makedirs(cache_dir, exist_ok=True)
    with open(args.surface, newline="", encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f, delimiter="\t")]
    # The rows the ledger reads `not-ios` -- the SDK marks them API_UNAVAILABLE(ios), so they are
    # tvOS's and visionOS's and there is no iOS API in them to build. They are dropped here so both
    # reports in this directory count the same rows, instead of leaving a tvOS-only declaration in
    # `still missing`, a bucket nobody can ever reduce. The list is the ledger's own, read from
    # beside this file; without it every row is counted and the difference is said out loud.
    not_ios = os.path.join(os.path.dirname(args.out), "not-ios.tsv")
    if os.path.exists(not_ios):
        with open(not_ios, newline="", encoding="utf-8") as f:
            dropped = {row["api"] for row in csv.DictReader(f, delimiter="\t")}
        before = len(rows)
        rows = [r for r in rows if r["api"] not in dropped]
        note("%d rows, %d of them not-iOS declarations dropped (the ledger's own list: %s)"
             % (len(rows), before - len(rows), short(not_ios)))
    else:
        note("no %s, so all %d rows are counted; the ledger's not-ios rows are not in this report"
             % (short(not_ios), len(rows)))

    # main: the checked-in registry, a build of main's own libraries, the Swift modules the port
    # itself links, and the release it carries -- whatever the bands did or did not do.
    swift_index = args.swift_modules or os.path.join(os.path.dirname(args.out), "swift-modules.json")
    swift_source = Sources("main-swift")
    if os.path.exists(swift_index):
        with open(swift_index, encoding="utf-8") as f:
            payload = json.load(f)
        for module, declared in payload.get("modules", {}).items():
            for name, kind in declared.items():
                swift_source.swift.setdefault(name, kind)
        note("the port's own Swift modules: %d modules, %d names, from %s"
             % (len(payload.get("modules", {})), len(swift_source.swift), short(swift_index)))
    else:
        note("no swift-modules.json at %s, so main's Swift rows are not counted here; the ledger "
             "writes it beside its own summary" % short(swift_index))
    main_tree = os.path.join(args.worktrees, "charon", "packages", "a", "apple-backports", "registry")
    if args.registry:
        main_source = Sources("main", read_registry_export(args.registry))
        note("main's registry: %d implemented entries, from the export %s"
             % (len(main_source.implemented_names()), short(args.registry)))
    else:
        main_entries, main_packages = read_package_registries(args.worktrees)
        main_source = Sources("main", main_entries)
        note("main's own package registries: %d entries over %s"
             % (len(main_entries), ", ".join("%s %d" % kv for kv in sorted(main_packages.items()))
                or "no package registry"))
    gate = args.gate
    if gate is None:
        candidate = os.path.join(args.worktrees, "charon", ".agent-work", "worktrees", "coord-merge",
                                 ".agent-work", "runs", "nsprog", "gate-6.1.3")
        gate = candidate if os.path.isdir(candidate) else None
    args.gate = gate
    built_source = Sources("main-build")
    if gate and os.path.isdir(gate):
        classes, protocols, exports = inventory_directory(gate)
        built_source = Sources("main-build", {}, classes, protocols, exports)
        note("main's built libraries: %d classes, %d protocols, %d exports from %s -- %s"
             % (len(classes), len(protocols), len(exports), short(args.gate), built_tree(gate)))
    else:
        note("no --gate given, so only main's registry and the release count as merged on main")
    if os.path.exists(args.release_cache):
        classes, protocols = ledger.run_objc_inventory(args.release_cache)
        exports = ledger.run_dump_cache(args.release_cache)
        release_source = Sources("release", {}, as_pairs(classes), as_pairs(protocols), exports)
        note("release cache: %d classes, %d protocols, %d exports"
             % (len(classes), len(protocols), len(exports)))
    else:
        release_source = Sources("release")
        note("release cache %s not there; the release's own rows are not counted" % args.release_cache)

    bands = discover_bands(args.worktrees)
    note("%d bands" % len(bands))
    digester = find_digester()
    sdk = os.path.join(args.worktrees, "charon", ".agent-work", "sdk-26.2", "iPhoneOS26.2.sdk")
    vfs = os.path.join(args.worktrees, "charon", ".agent-work", "runs", "lift-nsuuid", "s8-26.2",
                       "vfs.yaml")
    search_dirs, extra_maps = [], []
    if not os.path.isdir(sdk) or not os.path.exists(vfs):
        note("no SDK or no lift overlay at the usual paths: a band's Swift module is not read")

    band_list, band_detail = {}, {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        main_names = sorted(main_source.implemented_names())

        def one(band):
            return band, band_sources(band, cache_dir, digester, sdk, vfs, search_dirs, extra_maps,
                                      main_names)
        for band, (source, detail) in pool.map(one, bands):
            band_list[band["name"]] = source
            band_detail[band["name"]] = detail
            note("  %-28s registry %5d (+%d beyond main)  gate %s  swift %d"
                 % (band["name"], detail["registry-implemented"], detail["beyond-main"],
                    "yes" if detail["gate"] else "-", detail["swift"]))

    # One pass over the rows against an index of names, not against 37 sources per row: the first
    # shape was 145300 x 37 matches and cost 78 s of this process's own CPU, which is most of a run
    # meant to happen every hour. Here each source contributes a set of names and a row is one
    # lookup per name it could be called by.
    # Two indexes, because "a registry says implemented" and "a build carries it" are different
    # claims and the owner is told about them differently: a row only a registry names has no gate
    # directory behind it, which is not delivered in the sense the report means.
    ordered = [main_source, built_source, swift_source, release_source] + [band_list[n]
                                                                           for n in sorted(band_list)]
    owners = ["main", "main-build", "main-swift", "release"] + sorted(band_list)
    holder_of = collections.defaultdict(set)
    holder_built = collections.defaultdict(set)
    for position, source in enumerate(ordered):
        registry_names = source.implemented_names()
        for name in source.names():
            holder_of[name].add(position)
            if name not in registry_names:
                holder_built[name].add(position)
    decided_by = {}
    for source in ordered:
        decided_by.update(source.decisions())

    bucket = {}
    bands_with = collections.defaultdict(set)
    per_band_rows = collections.Counter()
    for row in rows:
        found = set()
        for name in names_a_source_may_call(ledger, row):
            found.update(holder_of.get(name, ()))
        if found & {0, 1, 2, 3}:
            bucket[row["api"]] = "merged on main"
            continue
        holders = [owners[p] for p in sorted(found)]
        built = [owners[p] for p in sorted(found)
                 if p in holder_built.get(row["api"], set())]
        if holders and built:
            bucket[row["api"]] = "delivered, built"
        elif holders:
            bucket[row["api"]] = "delivered, registry only"
        elif row["api"] in decided_by:
            bucket[row["api"]] = "decided against"
        else:
            bucket[row["api"]] = "still missing"
        for name in holders:
            bands_with[row["api"]].add(name)
            per_band_rows[name] += 1

    # A row api can appear in more than one framework's rows; the buckets are counted per row, and
    # a name held by more than one band is counted once.
    by_framework = collections.defaultdict(collections.Counter)
    for row in rows:
        by_framework[row["framework"]][bucket[row["api"]]] += 1
    totals = collections.Counter(bucket[row["api"]] for row in rows)
    statuses = ["merged on main", "delivered, built", "delivered, registry only", "decided against",
                "still missing"]
    shared = {api: names for api, names in bands_with.items() if len(names) > 1}

    stamp = time.strftime("%Y-%m-%d %H:%M:%S %Z")
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("# Fleet progress -- the SDK 26.2 surface at iOS %s, merged and unmerged\n\n" % "6.1.3")
        f.write("Generated %s by `charon/tools/corpus/fleet-progress.py` in %.1f seconds. "
                "Counts every row of `coordination/corpus/sdk-26.2-surface.tsv` once, from what is "
                "built, never from a band's report of itself.\n\n"
                % (stamp, time.time() - started))
        f.write("| bucket | rows | share |\n| --- | --- | --- |\n")
        for name in ("merged on main", "delivered, built", "delivered, registry only",
                     "decided against", "still missing"):
            f.write("| %s | %d | %.1f%% |\n" % (name, totals[name],
                                                100.0 * totals[name] / max(1, sum(totals.values()))))
        f.write("| **total** | **%d** | |\n\n" % sum(totals.values()))
        # The ledger's own number, so the two files can be reconciled instead of looking like
        # they disagree: it answers a different question (does this work on the release), this one
        # answers whether the fleet has built it anywhere.
        ledger_summary = os.path.join(os.path.dirname(args.out), "SUMMARY.md")
        if os.path.exists(ledger_summary):
            with open(ledger_summary, encoding="utf-8") as summary:
                for line in summary:
                    found = re.match(r"^\| implemented \| (\d+) \|", line)
                    if found:
                        f.write("The ledger's own `implemented` for the same surface is **%s**, which "
                                "is a different question: it asks whether the row *works on the "
                                "release* (a build of main plus the release's caches, with the "
                                "availability lowered), while this view asks whether anyone has "
                                "*built* it. A row can be built and still gated past %s, and a row "
                                "can work without any band having touched it.\n\n"
                                % (found.group(1), "6.1.3"))
                        break
        f.write("- **merged on main** -- implemented in main's own registry%s, or in a build of "
                "main's own libraries%s, or in the armv7 "
                "Swift modules the port itself links, or the release's own %s cache already ships it. "
                "Not anybody's outstanding work.\n"
                % ((" (`%s`)" % short(args.registry)) if args.registry else
                   " (`charon/packages/a/apple-backports/registry`)",
                   (" (`%s`)" % short(args.gate)) if args.gate else "",
                   os.path.basename(short(args.release_cache))))
        f.write("- **delivered, built** -- a band's built libraries or built Swift module carry the "
                "row and main does not: %d rows.\n" % totals["delivered, built"])
        f.write("- **delivered, registry only** -- a band's registry records the row `implemented` "
                "and nothing built carries it, so the claim is a record of intent with no library "
                "behind it: %d rows. This is the bucket the owner should not read as delivered.\n"
                % totals["delivered, registry only"])
        f.write("- **decided against** -- a registry records the row `absent`, `inert` or `ignored`, "
                "with its reason in that registry's entry. Nobody is going to build it and it should "
                "not sit in a to-do list: %d rows.\n" % totals["decided against"])
        f.write("- Both delivered buckets are counted once however many bands have the row; %d are "
                "held by more than one band.\n" % len(shared))
        f.write("- **still missing** -- no band and no main: the work nobody has done.\n")
        f.write("- Rows the SDK marks `API_UNAVAILABLE(ios)` are tvOS's and visionOS's, not iOS's, "
                "and are **not counted here**: the ledger reads them `not-ios` and writes the list "
                "to `not-ios.tsv` beside this file, which this report drops so both reports in this "
                "directory count the same rows. Without that file every row is counted and this "
                "sentence is the difference.\n")
        f.write("- The %d bands' sources: %s\n\n"
                % (len(bands), ", ".join(sorted(band_list)) or "none found"))
        # The columns come from `statuses`, the list the totals table uses. This table used to ask
        # the bucket that used to be called "delivered, not merged", after it was split into
        # "delivered, built" and "delivered, registry only", so the column was structurally zero.
        f.write("## By framework\n\n| framework | rows | %s |\n| --- | --- | %s |\n"
                % (" | ".join(statuses), " | ".join("---" for _ in statuses)))
        for framework in sorted(by_framework):
            t = by_framework[framework]
            f.write("| %s | %d | %s |\n" % (framework, sum(t.values()),
                                             " | ".join(str(t.get(st, 0)) for st in statuses)))
        f.write("\n## By band\n\nA band's own count, and what it built that main does not have. The "
                "per-band numbers overlap; the total above does not.\n\n")
        f.write("| band | registry entries beyond main | built libraries | built Swift module | "
                "ledger rows it holds |\n| --- | --- | --- | --- | --- |\n")
        for name in sorted(band_detail):
            d = band_detail[name]
            gate = d["gate"].replace(os.path.expanduser("~"), "$HOME") if d["gate"] else "-"
            module = d["module"].replace(os.path.expanduser("~"), "$HOME") if d["module"] else "-"
            f.write("| %s | %d | %s | %s | %d |\n" % (name, d["beyond-main"], gate, module,
                                                     per_band_rows[name]))
        if shared:
            f.write("\n## Rows more than one band holds\n\n%d rows are in more than one band's work, "
                    "which is what deduplication is for:\n\n" % len(shared))
            for api, names in sorted(shared.items(), key=lambda kv: (-len(kv[1]), kv[0]))[:25]:
                f.write("- `%s` -- %s\n" % (api, ", ".join(sorted(names))))
        f.write("\n## What this does not measure\n\n")
        f.write("- A band with no built gate directory and no built Swift module contributes its "
                "registry only. %d of the %d bands are in that state, and their built work -- if any "
                "-- is not in these numbers.\n"
                % (sum(1 for d in band_detail.values() if not d["gate"] and not d["swift"]),
                   len(band_detail)))
        f.write("- A band that built, but whose newest gate run is older than work it has since "
                "written, is counted at the state of that run; the run's path is in its row above.\n")
        f.write("- Swift rows are matched by name and kind, with the argument labels of the "
                "declaration normalised away, not by signature; a band whose module spells a "
                "declaration in a way neither form covers leaves the row unplaced rather than "
                "guessed at.\n")
    note("wrote %s in %.1f seconds" % (args.out, time.time() - started))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump({"generated": stamp, "totals": dict(totals),
                       "by-framework": {k: dict(v) for k, v in by_framework.items()},
                       "by-band": {k: dict(v, rows=per_band_rows[k]) for k, v in band_detail.items()},
                       "shared": {k: sorted(v) for k, v in shared.items()}}, f, indent=1, sort_keys=True)
        note("wrote %s" % args.json)
    # Every bucket, from `statuses`, and under the name the bucket has: this line had three %d and two
    # values, so a run that got here raised a TypeError at the last statement, after writing its
    # reports -- and the stale "delivered not merged" named a bucket this tool no longer has.
    note("; ".join("%s %d" % (status, totals[status]) for status in statuses))


if __name__ == "__main__":
    main()
