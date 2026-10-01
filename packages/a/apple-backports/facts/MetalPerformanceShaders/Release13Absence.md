# The release-13 rows of `registry/MetalPerformanceShaders/absent_MetalPerformanceShaders.json`

55 rows — **52 `class`, 2 `protocol`, 1 `method`** — sat at `absent` with the SDK's own declaration as
their only `source`, which is an assertion and not a measurement. This page holds the measurement,
the commands that reproduce it and their output, so a reviewer can settle any row here without a
second tool.

**The claim, in one line:** no held release below 16.0 carries any of the 55 names, so `absent` is
the correct verdict for all 55 and the gate's `held` check (`backports.lua:1904`) cannot fire on
any of them.

## Which releases can decide a 13.x row, and why these four

`check_registry` decides `held` at `backports.lua:1904`:

```lua
local natively = deployment and entry.introduced and dyld.compare_versions(deployment, entry.introduced) >= 0
if (entry.status == "absent" or entry.status == "owed") and in_range(entry, deployment) and not natively and carried_by_release(entry, inventory) then
```

`not natively` means the row is only ever in question at a `deployment` **below its `introduced`**,
so a 13.0/13.4 row can only be tested by a band that runs below 13.0. `band_plan`
(`backports.lua:2578`) then checks such a band against the first and last release of its range.
Four releases were read directly, and they are the four that matter:

| release | architecture | why it is here |
|---|---|---|
| **4.3** | armv7 | the oldest release the package deploys on |
| **6.1.3** | armv7 | the other one, and the default of `cache-census.lua` |
| **12.0** | arm64 | the newest held rung below 13.0, where a 13.0 API would most plausibly have leaked in |
| **16.0** | arm64e | **the control** — see the hole below |

### The hole, which is why the control is 16.0 and not 13.0

The held ladder (`~/.charon/dyld`) has **no 13.0, 14.0 or 15.0**. `ls ~/.charon/dyld` runs 3.0, 3.1.3,
3.2, 4.0, 4.3, 4.3.5, 5.0, 5.1.1, 6.0, 6.0.2, 6.1, 6.1.3, 6.1.4, 6.1.6, 7.0 … 9.3.6, 10.0.1 …
10.3.4, 11.0, **12.0, 16.0**, 18.0 — 53 release directories, of which `dyld.held_ladder` uses the 50
that have an armv7/arm64 cache (it skips the armv6-only 1.1.4, 2.2.1 and 4.2.1). So a name the SDK
declares at 13.0 has **no held rung between 12.0 and 16.0**, and its oldest held carrier is 16.0.
That is why 16.0 is the control here rather than another absence: it is the rung that proves the
reader finds these names when they are there.

## The whole ladder, from the index

```
python3 tools/cache-index/first-rung.py < .agent-work/runs/w01-mps-r13/names.txt
```

Output — all 55 names:

```
weightsLayout	16.0
MPSCNNConvolutionTransposeGradient	16.0
… 54 more, every one 16.0 …
MPSTemporaryNDArray	16.0
```

`first-rung` answers **the OLDEST held release that carries the name** (its own docstring: "The
answer is the OLDEST held release that carries the name, because that is the release a port of it
must support"). So a first rung of 16.0 is not merely "it is in 16.0" — it is **no held release
older than 16.0 carries it**, which covers every rung between 4.3 and 12.0 that was not read
directly. That is the claim this page rests on.

### Four controls, and what each one rules out

```
$ printf 'MPSImageIntegral\nMPSImageGaussianBlur\nMPSImageBox\nMPSNDArrayAbs\n' | python3 tools/cache-index/first-rung.py
MPSImageIntegral	9.0
MPSImageGaussianBlur	9.0
MPSImageBox	9.0
MPSNDArrayAbs	NONE
$ printf 'NSString\nUIView\nNotARealClassNameXyz\n' | python3 tools/cache-index/first-rung.py
NSString	3.0
UIView	3.0
NotARealClassNameXyz	NONE
```

- `MPSImageIntegral`, `MPSImageGaussianBlur`, `MPSImageBox` → 9.0. The index resolves a Metal
  Performance Shaders **class name** and gives it a real MPS rung, so a `16.0` on this family is a
  rung and not a spelling the index failed to match. (A class's symbol is not `_MPSImageIntegral`:
  that spelling reads `NONE`, because the bare class name is the right one here.)
- `MPSNDArrayAbs` → NONE. A name from the right family, spelled like a real member, that no release
  has — so `NONE` is an answer the tool does give, and a `16.0` is not its way of saying "not found".
- `NSString` → 3.0, `UIView` → 3.0, `NotARealClassNameXyz` → NONE. The ladder is being walked and a
  made-up name reads nothing.

## The four caches, class-scoped, with the control in the same run

```
CHARON_ROOT=$PWD xmake l tools/corpus/cache-census.lua MPS 4.3 6.1.3 12.0 16.0
```

```
4.3       ~/.charon/dyld/4.3/dyld_shared_cache_armv7
         images 354, of which naming MPS 0
         classes 7187, of which MPS* 6 (MPServerObject MPServerObjectProxy MPShuffledItemGroup MPSwipableView MPSwipeGestureRecognizer MPSystemNowPlayingController)
         protocols 564, of which MPS* 1 (MPSwipableViewDelegate)
6.1.3     ~/.charon/dyld/6.1.3/dyld_shared_cache_armv7
         images 524, of which naming MPS 0
         classes 11378, of which MPS* 21 (MPSSLookupResponseTransformContext MPScrollingTitlesView MPServerObject … MPSwipableView MPSwipeGestureRecognizer MPSystemNowPlayingController)
         protocols 1171, of which MPS* 1 (MPSwipableViewDelegate)
12.0      ~/.charon/dyld/12.0/dyld_shared_cache_arm64
         images 1368, of which naming MPS 5
         classes 63192, of which MPS* 459 (MPSAccelerationStructure MPSAccelerationStructureGroup MPSBinaryImageKernel MPSCNNAdd … MPSNNPadding MPSNNTrainableNode)
         protocols 11426, of which MPS* 21 (MPSCNNBatchNormalizationDataSource MPSCNNConvolutionDataSource … MPSwipableViewDelegate)
16.0      ~/.charon/dyld/16.0/dyld_shared_cache_arm64e
         images 2664, of which naming MPS 7
         classes 143137, of which MPS* 961 (MPSANEWeightFileManager … MPSCNNGroupNormalization MPSCNNGroupNormalizationGradient MPSNDArray … MPSSVGFDenoiser MPSTemporalAA)
         protocols 25549, of which MPS* 34 (MPSCNNBatchNormalizationDataSource MPSCNNConvolutionDataSource MPSCNNGroupNormalizationDataSource … MPSNDArrayAllocator MPSSVGFTextureAllocator …)
control: 1504 name(s) beginning MPS found in this run, so a zero on another rung is the release's and not the reader's
```

**The 4.3 and 6.1.3 zeros are not MPS zeros.** Both caches carry `MPS*` names — 6 and 21 — and every
one of them is a different thing: `MPServerObject`, `MPStoreOfferArtworkImageCache`,
`MPShuffledItemGroup`, `MPSwipableView`, `MPSwipeGestureRecognizer`,
`MPSystemNowPlayingController`. They are MailStore, the shuffle controller and the system Now
Playing controller, and they share three letters with the framework and nothing else. **Zero images
in either cache name `MPS` at all**: Metal Performance Shaders does not exist below iOS 9, so on
the two releases this package deploys on there is no substrate for any of these rows — which is the
`reason` these rows already carried, now measured instead of asserted.

### The exact, name-by-name answer

The census prints a truncated list, so the per-name answer comes from the dump `carried_by_release`
itself reads:

```
CHARON_ROOT=$PWD xmake l tools/corpus/objc-inventory.lua ~/.charon/dyld/4.3/dyld_shared_cache_armv7    > inv-4.3.tsv
CHARON_ROOT=$PWD xmake l tools/corpus/objc-inventory.lua ~/.charon/dyld/6.1.3/dyld_shared_cache_armv7  > inv-6.1.3.tsv
CHARON_ROOT=$PWD xmake l tools/corpus/objc-inventory.lua ~/.charon/dyld/12.0/dyld_shared_cache_arm64  | grep -E '^(class|protocol)	MPS' > inv-12.0-mps.tsv
CHARON_ROOT=$PWD xmake l tools/corpus/objc-inventory.lua ~/.charon/dyld/16.0/dyld_shared_cache_arm64e | grep -E '^(class|protocol)	MPS' > inv-16.0-mps.tsv
```

One TSV line per class, `class<TAB>name<TAB>superclass<TAB>image<TAB>instance selectors<TAB>class
selectors<TAB>protocols`, and one per protocol. The selector columns carry a `-` prefix, which is
what `carried_by_release` (`backports.lua:1612`) expects. Lines read: 7751 at 4.3, 12549 at 6.1.3,
480 MPS lines at 12.0, 995 at 16.0.

**Two independent tools agree on every release** — 4.3: 7187 + 564 = 7751, 6.1.3: 11378 + 1171 =
12549, 12.0: 459 + 21 = 480, 16.0: 961 + 34 = 995. The census's counts and the inventory's line
counts are the same numbers, so the two readers are reading the same cache.

| release | of the 54 class/protocol names |
|---|---|
| 4.3 | **0 / 54** carried |
| 6.1.3 | **0 / 54** carried |
| 12.0 | **0 / 54** carried |
| 16.0 | **54 / 54** carried |

### Six class controls, and the question they make real

A zero at 4.3 and 6.1.3 is only worth reading if the same reader finds MPS where MPS is. Six classes
the tree **already carries rows for**, run through the same three dumps:

```
MPSImageIntegral           4.3=-  6.1.3=-  12.0=Y  16.0=Y
MPSImageGaussianBlur       4.3=-  6.1.3=-  12.0=Y  16.0=Y
MPSImageBox                4.3=-  6.1.3=-  12.0=Y  16.0=Y
MPSCNNConvolution          4.3=-  6.1.3=-  12.0=Y  16.0=Y
MPSCNNBatchNormalization   4.3=-  6.1.3=-  12.0=Y  16.0=Y
MPSMatrixSum               4.3=-  6.1.3=-  12.0=Y  16.0=Y
```

6/6 absent where the framework is absent, 6/6 present where it is present. And 12.0 is not a lazy
control: it carries **459** MPS classes, among them the immediate neighbours of these rows —
`MPSCNNConvolutionTranspose`, `MPSCNNConvolutionTransposeNode`, `MPSCNNFullyConnected`,
`MPSCNNFullyConnectedGradient` — so the 0/54 at 12.0 is "the neighbourhood is there and these are
not", not "the reader was looking for the wrong family".

## The method row, and the trap that makes it its own question

`-[MPSCNNConvolutionDataSource weightsLayout]` is the one member in the slice, and
**a selector's rung says nothing about its owner**: at 16.0 six classes carry `-weightsLayout`
(`MPSCNNConvolutionDataSource`, `MPSCNNConvolution`, `MPSCNNConvolutionGradient`,
`MPSCNNConvolutionWeightsAndBiasesState`, `MPSGraphConvolution2DOpDescriptor`,
`MPSGraphDepthwiseConvolution2DOpDescriptor`), so a bare-selector first-rung answer could not say
whose member this is. The owner settles it:

| release | is `MPSCNNConvolutionDataSource` declared? | does it carry `-weightsLayout`? |
|---|---|---|
| 4.3 | no — no such owner exists | 0 classes anywhere on the release carry the selector |
| 6.1.3 | no — no such owner exists | 0 classes anywhere on the release carry the selector |
| 12.0 | **yes**, a protocol with 13 selectors | **no** — and `-kernelWeightsDataType` is not one either |
| 16.0 | **yes**, a protocol with 15 selectors | **yes** — and `-kernelWeightsDataType` is one |

12.0 is the answer that matters. Its protocol arrives in 11.3, so it is there to be asked, it has
thirteen selectors to choose from, and `-weightsLayout` is not among them: the two members added at
13.0 and 14.0 are exactly the two missing from 12.0's thirteen. At 16.0 the same protocol lists
fifteen and both are present, so the spelling of the selector is right and the reader finds it where
it exists. That is a real question asked of a real owner, not a formality.

## The registry's own source agrees, name for name

```
python3 -c '
import sys, collections
names=[l.strip() for l in open("names.txt") if l.strip()]
rows=[l.rstrip("\n").split("\t") for l in open(sys.argv[1])]
hit=[f for f in rows[1:] if f[3] in names or any(f[3].endswith(" "+n+"]") for n in names)]
print("surface rows matched:", len(hit), "of", len(names))
print("introduced:", dict(collections.Counter(f[4] for f in hit)))
print("registry column:", dict(collections.Counter(f[9] for f in hit)))
' $HOME/Git/projects/ios/coordination/corpus/sdk-26.2-surface.tsv
```

```
surface rows matched: 55 of 55
introduced: {'13': 7, '13.0': 47, '13.4': 1}
registry column: {'absent': 55}
```

145301 rows, indexed on `api` (column 4) — column 0 is `framework` and reading that one is a
mistake that reports every name absent, which is how this table was first read here. All 55 are
present, all under `framework=MetalPerformanceShaders`, all with `registry=absent`, and every
`introduced` matching the registry row it backs: **13.0 for 47** (46 classes/protocols plus the one
member), `13` for 7, **13.4 for 1** (`MPSImageEDLines`). The member is present under its own
spelling `-[MPSCNNConvolutionDataSource weightsLayout]`, `introduced=13.0`; the same table has 14
rows naming `weightsLayout`, and the other 13 belong to MetalPerformanceShadersGraph's convolution
descriptors at 14.0 and 16.3, which is another slice's business.

**No row of the 55 disagrees with the SDK.** Unlike the UIKit 16.0 batch, which found two rows whose
`introduced` the cache does not corroborate, nothing here needed correcting — 16.0 is the oldest
held rung above the hole, so it cannot contradict a 13.0 declaration, only be consistent with it.

## The port side: it exports none of them either

```
grep -rIln --include='*.m' --include='*.h' --include='*.c' --include='*.mm' \
    -E "$(paste -sd'|' names.txt)" packages/a/apple-backports/
```

**0 files.** No header in the package declares any of the 55 and no object defines one, so
`implemented` is not true of any of them today and `answered` (`backports.lua:1871-1895`, "listed
as absent, but what is built answers it") cannot fire either.

## Why this band is the absence and not an object

The rulebook allows an audit to be half a band "UNLESS IT PROVES THE ABSENCE", and then: *if the
rows are blocked on substrate no band end carries, proving the absence at both ends with a
certified control IS the band*. Measured, that is the situation here, and there is a second reason
besides the substrate:

- **No band end carries any of these names to compare against.** `absent` is settled; but `implemented`
  is a different claim, and it needs an oracle.
- **The host cannot be one.** This machine's MPS does not run: 15 rows of this very file record that
  its AGX family lacks `computeCommandEncoderWithDispatchType:` and that the release's own kernel
  dies encoding with `'[AGXG16XFamilyCommandBuffer mtlnext computeCommandEncoderWithDispatchType:]`,
  unrecognized selector`. Every `implemented` MPS row in the tree says the same thing about its own
  numbers — "no number on this row is a measurement of Apple's code".
- **So the reference would have to come from the header, and these headers do not give one.** This is
  the line that separates this slice from the MPS 9.0 rows that *are* implemented:
  `MPSImageIntegral.h:19-20` states its rectangle exactly — `sumRect.origin =
  MPSUnaryImageKernel.offset`, `sumRect.size = dest_position - clipRect.origin` — which is a formula
  a plain C reference can be written from, and `MPSImageIntegral` is `implemented` against it.
  `MPSNDArray.h`, `MPSNDArrayDescriptor.h`, the `MPSNDArrayGradientKernels.h` family,
  `MPSNNGramMatrixCalculation.h`, `MPSSVGF.h` and `MPSImageEdge.h` describe **compute kernels and
  their buffers**, not the arithmetic a value must have. Writing a class that satisfies the name and
  guessing the contents would be a crutch under §9, and a registry row asserting it would be worse
  than an honest `absent`.

Three of these families are not merely undocumented but structurally GPU-shaped, and a CPU class
could not answer them at all: `MPSPolygonBuffer`, `MPSPolygonAccelerationStructure` and
`MPSQuadrilateralAccelerationStructure` exist to build and read **ray-tracing acceleration
structures** on the device, and `MPSSVGF`/`MPSTemporalAA` are temporal filters whose inputs are a
motion vector and a history buffer the release produces.

## What a caller gets

- **A class row** (`MPSNDArray`, `MPSSVGF`, `MPSPolygonBuffer`, …): the class is not in the release
  and the port exports none, so `NSClassFromString(@"MPSNDArray")` answers nil, and a caller that
  built against a compile-time reference gets nothing to send to.
- **A protocol row** (`MPSCNNGroupNormalizationDataSource`, `MPSSVGFTextureAllocator`): the protocol
  is not declared, so `NSProtocolFromString` answers nil and a conformer cannot be declared against
  a header the port installs.
- **The method row**: a caller can still write `-weightsLayout` in its own `MPSCNNConvolutionDataSource`
  conformer — nothing rejects that — and nothing will ever call it, because the framework that would
  call it is absent from every release the port runs on and the port does not supply one.

## What a reader should take from this

Every row of the file at release 13 says `absent`, and that is now a measurement rather than a queue
entry: **0/54 carried at 4.3, 0/54 at 6.1.3, 0/54 at 12.0, 54/54 at 16.0; the owner of the one
member row declares it in 16.0 and not in 12.0; 6/6 class controls and 1504 MPS names in the same
run; 0 files in the package name any of the 55.** No status here is wrong, and none of these rows
should be read as work not started — the substrate is absent at every band end, and the oracle that
an `implemented` row would need does not exist on this machine or in any cache the port holds.