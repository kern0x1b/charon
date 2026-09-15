import argparse
import collections
import os
import re
import subprocess
import sys


def sdk_roots(sdk):
    roots = {os.path.abspath(sdk).rstrip("/") + "/", os.path.realpath(sdk).rstrip("/") + "/"}
    return sorted(roots, key=len, reverse=True)


def relative(path, roots):
    path = os.path.normpath(path)
    for root in roots:
        if path.startswith(root):
            return path[len(root):]
    return None


def header_log(path):
    with open(path, errors="replace") as log:
        for line in log:
            line = line.strip()
            if line.startswith("/"):
                yield line


def link_trace(path):
    pattern = re.compile(r"Used (?:indirect )?dynamic library: (.+)$|Used static archive: (.+)$")
    with open(path, errors="replace") as log:
        for line in log:
            match = pattern.search(line.strip())
            if match:
                yield (match.group(1) or match.group(2)).strip()


def ninja_deps(build):
    out = subprocess.run(["ninja", "-C", build, "-t", "deps"],
                         capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("/"):
            yield line


def area(rel):
    parts = rel.split("/")
    if parts[0] == "System" and len(parts) > 3:
        return f"{parts[2]}/{parts[3]}"
    return "/".join(parts[:3]) if parts[0] == "usr" else parts[0]


def main():
    parser = argparse.ArgumentParser(
        description="List the files of an SDK that a build actually read.")
    parser.add_argument("--sdk", required=True)
    parser.add_argument("--headers", nargs="*", default=[],
                        help="logs written by clang with CC_PRINT_HEADERS")
    parser.add_argument("--links", nargs="*", default=[],
                        help="logs written by ld64 with LD_TRACE_DYLIBS and LD_TRACE_ARCHIVES")
    parser.add_argument("--ninja", nargs="*", default=[],
                        help="build directories whose ninja dependency log to read")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    roots = sdk_roots(args.sdk)
    used = set()
    outside = set()
    readers = ([(p, header_log) for p in args.headers] + [(p, link_trace) for p in args.links]
               + [(p, ninja_deps) for p in args.ninja])
    for source, reader in readers:
        if not os.path.exists(source):
            sys.exit(f"missing {source}")
        for path in reader(source):
            rel = relative(path, roots)
            if rel is None:
                outside.add(os.path.dirname(os.path.normpath(path)))
            else:
                used.add(rel)

    real = os.path.realpath(args.sdk)
    every = [os.path.relpath(os.path.join(base, name), real)
             for base, _, names in os.walk(real) for name in names]
    present = sorted(f for f in used if os.path.exists(os.path.join(real, f)))
    with open(args.out, "w") as manifest:
        manifest.write("\n".join(present) + "\n")

    size = lambda files: sum(os.path.getsize(os.path.join(real, f)) for f in files) / 1048576
    used_areas = {area(f) for f in present}
    all_areas = {area(f) for f in every}
    print(f"files read: {len(present)} of {len(every)} ({size(present):.1f} of {size(every):.1f} MB)")
    print(f"tbd stubs read: {sum(f.endswith('.tbd') for f in present)} of {sum(f.endswith('.tbd') for f in every)}")
    for kind in ("Frameworks", "PrivateFrameworks"):
        have = [a for a in all_areas if a.startswith(kind + "/")]
        print(f"{kind}: {sum(a in used_areas for a in have)} of {len(have)}")
    absent = sorted(used - set(present))
    if absent:
        print(f"named but absent from the SDK: {len(absent)}")
    print(f"directories read outside the SDK: {len(outside)}")


main()
