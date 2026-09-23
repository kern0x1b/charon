#!/usr/bin/env python3
"""Attribute weak imports to the IMAGE that imports them, and rank what is most likely read unguarded.

Input: a directory with one `nm -m` output per Mach-O (main binary and each dylib/framework), the file
name being the image. A weak import prints as
    (undefined) weak external _SYMBOL (from LIB)
Each image is classified from its own undefined symbols:
    swift      imports Swift runtime/mangled symbols and little C++. The compiler REQUIRES an availability check
               before a newer API is used, so a weak import here is guarded by construction.
    mixed      imports many Swift AND many C++ symbols (a big framework with static C++/ObjC++ libraries linked
               in, e.g. TelegramUIFramework). Image-level attribution cannot separate the two: treat as exposed.
    c++        imports libc++ (`__Z...`) symbols and no Swift: ObjC++/C++ code (WebRTC, tgcalls, TDLib...).
               The compiler only WARNS about an unguarded newer API, so direct reads are possible.
    objc/c     plain Objective-C or C: same as c++ for this purpose.
This is what turns the list of weak symbols into "who reads it", the piece the bare list lacked.

Usage: weak-per-image.py <dir of per-image nm -m outputs> [--any]
  --any  attribute a symbol to every image that imports it, weak OR strong. For a build with a higher
         deployment target (my corpus Telegram targets iOS 11, so most of these are strong there) this
         says which KIND of code references the API, since the same source is behind both builds.
Needs corpus/weak-imports-ranked.tsv (weak-imports.py) for tier, kind and registry state.
Output: corpus/weak-imports-by-image.tsv
"""
import csv, os, re, sys
from collections import defaultdict

# corpus/ is DATA, in the durable location CHARON_CORPUS_ROOT addresses (default coordination/),
# independent of this script's own location. See tools/corpus/README.md.
CORPUS_ROOT = os.environ.get("CHARON_CORPUS_ROOT") or os.path.join(
    os.path.expanduser("~"), "Git", "projects", "ios", "coordination")
CORPUS = os.path.join(CORPUS_ROOT, "corpus")
if not os.path.isdir(CORPUS):
    sys.exit("weak-per-image.py: no corpus/ data directory found at %s. Set CHARON_CORPUS_ROOT to "
              "the directory that contains corpus/." % CORPUS)
WEAK = re.compile(r"\(undefined\) weak external (\S+)")
UNDEF = re.compile(r"\(undefined\) (?:weak )?external (\S+)")
ORDER = {"c++": 0, "mixed": 1, "objc/c": 2, "unknown": 3, "swift": 4}

def classify(undefined):
    swift = sum(1 for s in undefined if s.startswith(("_$s", "_$S", "$s", "$S")) or "swiftCore" in s)
    cpp = sum(1 for s in undefined if s.startswith(("__Z", "_Z")))
    if swift >= 10 and cpp >= 5:
        return "mixed"          # Swift plus statically linked C++/ObjC++: the image alone cannot say which code reads a symbol
    if swift >= 10:
        return "swift"
    if cpp >= 5:
        return "c++"
    return "objc/c" if undefined else "unknown"

def main(d, any_strength=False):
    """d may be flat (one nm file per image) or nested (one directory per MODULE holding the nm output of each
    of its .o files, as the Telegram per-module objects are laid out). Files in the same directory are one
    unit: their weak and undefined symbols are unioned, so a module is classified on all its objects."""
    images = {}
    for root, _dirs, files in os.walk(d):
        for name in sorted(files):
            path = os.path.join(root, name)
            rel = os.path.relpath(root, d)
            unit = re.sub(r"\.txt$", "", name) if rel == "." else rel      # flat: the file is the image; nested: the directory is the module
            e = images.setdefault(unit, {"weak": set(), "undef": set(), "files": 0})
            e["files"] += 1
            for line in open(path, errors="replace"):
                m = UNDEF.search(line)
                if m:
                    e["undef"].add(m.group(1))
                    w = WEAK.search(line)
                    if w or any_strength:
                        e["weak"].add(m.group(1))
    for e in images.values():
        e["class"] = classify(e["undef"])
        e["undef"] = len(e["undef"])
    by_sym = defaultdict(list)
    for img, e in images.items():
        for s in e["weak"]:
            by_sym[s].append(img)
    ranked = list(csv.reader(open(os.path.join(CORPUS, "weak-imports-ranked.tsv")), delimiter="\t"))[1:]
    rows = []
    for tier, sym, kind, fw, intro, reg, apps, strong in ranked:
        imgs = sorted(by_sym.get(sym, []))
        classes = sorted({images[i]["class"] for i in imgs}, key=lambda c: ORDER[c])
        best = classes[0] if classes else "not in these images"
        rows.append((tier, best, sym, kind, fw, intro, reg, apps, imgs, classes))
    rows.sort(key=lambda r: (r[0], ORDER.get(r[1], 4), -int(r[7]), r[2]))
    out = os.path.join(CORPUS, "weak-imports-by-image-any.tsv" if any_strength else "weak-imports-by-image.tsv")
    with open(out, "w") as f:
        f.write("tier\tmost_exposed_image_class\tsymbol\tkind\tframework\tintroduced\tregistry\tcorpus_apps\timages\n")
        for tier, best, sym, kind, fw, intro, reg, apps, imgs, classes in rows:
            f.write(f"{tier}\t{best}\t{sym}\t{kind}\t{fw}\t{intro}\t{reg}\t{apps}\t{'; '.join(imgs[:4])}{' ...' if len(imgs) > 4 else ''}\n")
    print(f"{len(images)} images read; image classes: " + ", ".join(f"{c} {sum(1 for e in images.values() if e['class'] == c)}" for c in ORDER))
    print(f"weak symbols in the ranked list found in these images: {sum(1 for r in rows if r[9])} of {len(rows)} -> {out}")
    cross = defaultdict(lambda: defaultdict(int))
    for tier, best, *_ in rows:
        cross[tier][best] += 1
    for t in sorted(cross):
        print(f"  {t:30} " + ", ".join(f"{k} {v}" for k, v in sorted(cross[t].items(), key=lambda kv: ORDER.get(kv[0], 4))))
    return rows

if __name__ == "__main__":
    main(sys.argv[1], "--any" in sys.argv[2:])
