#!/usr/bin/env python3
"""Write what the canon's 6.1.3 band exports to aggregate.BUILT_EXPORTS, for gen-report.py's LAUNCH-BLOCK.

usage: built-exports.py <canon-run>

<canon-run> is the output directory of coordination/canon-build.lua (workspace skill canon-install):
it holds one org.charon.apple-backports_*.deb and build/stage. The list is every name `nm -gUj`
gives over the stage's bands/6.1.3/*.dylib, under a first line naming the deb's Version, so a
list older than the canon it is read against says so in the report."""
import glob, importlib.util, os, subprocess, sys

HERE = os.path.dirname(os.path.realpath(__file__))
spec = importlib.util.spec_from_file_location("agg", os.path.join(HERE, "aggregate.py"))
agg = importlib.util.module_from_spec(spec); spec.loader.exec_module(agg)
BAND = "build/stage/usr/lib/charon/org.charon.apple-backports/bands/6.1.3"

def main():
    if len(sys.argv) != 2:
        sys.exit("usage: built-exports.py <canon-run>")
    run = sys.argv[1]
    debs = glob.glob(os.path.join(run, "org.charon.apple-backports_*.deb"))
    if len(debs) != 1:
        sys.exit("built-exports.py: %s holds %d canon packages, not one" % (run, len(debs)))
    version = subprocess.run(["dpkg-deb", "-f", debs[0], "Version"], capture_output=True, text=True, check=True).stdout.strip()
    dylibs = sorted(glob.glob(os.path.join(run, BAND, "*.dylib")))
    if not dylibs:
        sys.exit("built-exports.py: no dylib under %s" % os.path.join(run, BAND))
    names = set()
    for dylib in dylibs:
        out = subprocess.run(["nm", "-gUj", dylib], capture_output=True, text=True, check=True).stdout
        names.update(line.strip() for line in out.splitlines() if line.strip())
    with open(agg.BUILT_EXPORTS, "w") as f:
        f.write(agg.BUILT_EXPORTS_HEADER + version + "\n")
        for name in sorted(names):
            f.write(name + "\n")
    print("built-exports.py: %d names of %d libraries of canon %s -> %s" % (len(names), len(dylibs), version, agg.BUILT_EXPORTS))

main()
