# What the absent rows say, and which of those reasons is a reason

Every `absent` row in this package's Metal and MetalKit registries, grouped by the reason it gives.
Counted from the rows themselves, not from a summary: the command is below, and it names the six
buckets by the words the rows use.

```
python3 - <<'PY'
import json, os, collections
root = "packages/a/apple-backports/registry"
counts = collections.Counter()
for framework in ("Metal", "MetalKit"):
    for name in sorted(os.listdir(os.path.join(root, framework))):
        document = json.load(open(os.path.join(root, framework, name)))
        for entry in document["entries"]:
            if entry["status"] != "absent":
                continue
            reason = (entry.get("reason", "") + " " + entry.get("effect", "")).lower()
            if "no ray tracing" in reason:
                bucket = "hardware: no ray tracing"
            elif "counter heap" in reason:
                bucket = "hardware: no counter heaps"
            elif "arrived in ios" in reason or "arrived with the sdk" in reason:
                bucket = "iOS arrival"
            elif "no sdk header declares" in reason:
                bucket = "port-own name"
            elif "cannot find protocol declaration" in reason:
                bucket = "build error: MTLAllocation"
            elif "not corpus-demanded" in reason:
                bucket = "corpus non-demand"
            else:
                bucket = "other"
            counts[(framework, bucket)] += 1
for key in sorted(counts):
    print(key, counts[key])
PY
```

| reason the row gives | Metal | MetalKit | total |
| --- | ---: | ---: | ---: |
| iOS arrival | 106 | 0 | 106 |
| corpus non-demand | 20 | 18 | 38 |
| port-own name | 19 | 0 | 19 |
| build error: MTLAllocation | 15 | 0 | 15 |
| hardware: no ray tracing | 6 | 0 | 6 |
| hardware: no counter heaps | 2 | 0 | 2 |
| **total** | **168** | **18** | **186** |

## Which of these is an answer, and which is a backlog

**Two of the six are hardware, and they are the only two that answer.** Six rows are ray tracing -
"an acceleration structure is a ray tracing resource, and this device has no ray tracing" - and two
are counter heaps, whose "entry size is a property of the counter hardware". Those eight keep their
absent status, and the answer stays the documented one rather than a missing method.

**The other 178 were not reasons, and this file is the record of that.** A correction, because the
earlier version of this table was wrong in the direction that mattered: it read the 186 rows as
"absent for a hardware reason", and they are not. iOS arrival is not hardware - an API that did not
exist yet is a thing to carry, not a thing to omit, and the port's job is to carry it. Corpus
non-demand is not hardware either; a Tier 2 verdict that nobody asked for is a measure of interest,
not of capability. A port-own name is not hardware at all - it is a class of the port's own under a
name no header declares, and the row is about that name, not about the device. And the fifteen
`MTLAllocation` rows are a build error in the port's own header, quoted at line and column, which is
a thing to fix rather than a thing to be absent about.

So the honest reading of the table is: **eight rows answer as Apple documents, and 178 are work.**
That is the backlog this file exists to name, and it is larger than the work the registry claimed to
have already answered.

## What was done about it

**MetalKit is carried, all 18.** `MTKTextureLoader`'s eleven option and origin constants, the three
classes `MTKMesh` needs - `MTKMeshBuffer`, `MTKMeshBufferAllocator`, `MTKSubmesh` - and the four
single-value model-bridge functions. What each does, and what it deliberately does not claim, is in
`TextureLoader.md` next door; the two places the port says no - a cube layout offered with one image,
and the mipmap levels its descriptor does not build - answer with an `NSError` or with a stated
limit rather than with a silent success.
