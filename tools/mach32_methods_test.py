#!/usr/bin/env python3
"""The controls for tools/mach32_methods.py, against one 32-bit image in a shared cache.

Each control is a way a reading of a release's classes goes wrong without saying so, and each was
arrived at by being wrong here first:

- the class count, so a walk that stops early or steps wrong is caught rather than reported as an image
  that has fewer classes;
- `valueForProperty:` found in `MPMediaEntity`'s **own** instance list. It is the positive control and
  it is the one that failed twice: first because the reading looked only at `MPMediaItem` and its
  concrete subclasses, and then because the method names were masked, which read every odd-addressed
  selector two bytes into the middle of it and made the method look absent. A control that has caught two
  real faults earns its place.
- a nonsense selector absent, so a reader that answers yes to everything cannot pass.
- the metaclass list read from a different structure to the instance list, as counts: a selector may
  legitimately appear in both, so the check is where the lists come from and not that they are disjoint.

    python3 tools/mach32_methods_test.py <cache> <image-address>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mach32_methods import Cache, Image, categories, classes   # noqa: E402

DEFAULT_CACHE = os.path.expanduser("~/.charon/dyld/6.1.3/dyld_shared_cache_armv7")
MEDIAPLAYER_6_1_3 = 0x31fe3000
EXPECTED_CLASSES = 236
POSITIVE = "valueForProperty:"
POSITIVE_OWNER = "MPMediaEntity"
NEGATIVE = "aSelectorNoFrameworkHas"


def main(argv):
    cache_path = argv[1] if len(argv) > 1 else DEFAULT_CACHE
    address = int(argv[2], 0) if len(argv) > 2 else MEDIAPLAYER_6_1_3
    if not os.path.exists(cache_path):
        sys.stderr.write("not run: the cache %s is not here, so the controls cannot run\n" % cache_path)
        return 2
    image = Image(Cache(cache_path), address)
    read = classes(image)
    found = []
    own = {}
    for entry in read:
        own[entry["name"]] = entry["instance"]["selectors"]
    if len(read) != EXPECTED_CLASSES:
        found.append("the image has %d classes in __objc_classlist, not %d" % (len(read), EXPECTED_CLASSES))
    if POSITIVE not in own.get(POSITIVE_OWNER, []):
        found.append("%s is not in %s's own instance list, so every name this reader reports is suspect"
                     % (POSITIVE, POSITIVE_OWNER))
    for selectors in own.values():
        if NEGATIVE in selectors:
            found.append("a nonsense selector was reported as declared")
            break
    item = [e for e in read if e["name"] == "MPMediaItem"]
    if not item:
        found.append("MPMediaItem is not in __objc_classlist")
    else:
        instance, own_class = len(item[0]["instance"]["selectors"]), len(item[0]["class"]["selectors"])
        if instance == own_class or not instance:
            found.append("MPMediaItem's instance and class lists do not read as two structures: %d and %d"
                         % (instance, own_class))
        else:
            print("MPMediaItem: %d own instance methods, %d own class methods" % (instance, own_class))
    print("categories in __objc_catlist: %d" % len(categories(image)))
    for line in found:
        sys.stderr.write("FAIL: %s\n" % line)
    if found:
        return 1
    print("mach32_methods_test: OK (0 failures)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
