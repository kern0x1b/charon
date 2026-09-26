"""inventory.py <scenes-dir> : which of rotation, orientation and eulerAngles each node of Telegram's ten scenes archives
(facts/SceneKit/SCNView.md, "Conventions"), and, for a node with a rotation and no orientation, that rotation beside its
eulerAngles. <scenes-dir> holds the decompressed files of inventory.swift."""
import plistlib, struct, sys

NAMES = ["star2", "coin", "gift2", "badge", "emoji", "tag", "business", "boost", "lightspeed", "swirl"]
for name in NAMES:
    objects = plistlib.load(open("%s/%s.scn" % (sys.argv[1], name), "rb"))["$objects"]
    nodes = [o for o in objects if isinstance(o, dict) and ("childNodes" in o or "camera" in o or "light" in o or "geometry" in o or ("name" in o and "movabilityHint" in o))]
    both = sum(1 for o in nodes if "orientation" in o and "rotation" in o)
    euler_only = sum(1 for o in nodes if "eulerAngles" in o and "orientation" not in o)
    rotation_only = sum(1 for o in nodes if "rotation" in o and "orientation" not in o)
    print(name, "nodes", len(nodes), "rotation and orientation", both, "eulerAngles without orientation", euler_only, "rotation without orientation", rotation_only)
    for o in nodes:
        if "rotation" in o and "orientation" not in o:
            def floats(key):
                value = o.get(key)
                value = objects[value.data] if isinstance(value, plistlib.UID) else value
                return struct.unpack("<%df" % (len(value) // 4), value) if isinstance(value, bytes) else None
            print("   rotation", floats("rotation"), "eulerAngles", floats("eulerAngles"))
