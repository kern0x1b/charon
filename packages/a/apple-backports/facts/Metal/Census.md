# What the 26.2 Metal headers declare, and what a registry row covers

`python3 tools/metal-uncovered.py` from the repository root. `--framework Metal|MetalKit|MetalFX`
narrows it, `--verbose` lists the members with no row, `--no-ast` skips the control that compiles
twice. Every number below comes from that one command.

## The counts, and the union they are over

| framework | headers | members declared | with a row | no row | names declared | with a row | no row |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Metal | 96 | 6694 | 84 | 6610 | 8682 | 177 | 8505 |
| MetalKit | 5 | 17962 | 0 | 17962 | 19090 | 23 | 19067 |
| MetalFX | 10 | 7097 | 0 | 7097 | 12718 | 0 | 12718 |

The declared side is a union, and the two halves are asked different questions of a registry row.
A **member** is an interface, protocol or category member; a **name** is a class, a protocol, a file
scope function, a constant or an enumeration constant. A row whose api is `-[Class sel]` or
`Class.sel` is a member row and is covered by its owner's members; a row whose api is bare - the
class `MTKMesh`, the function `MTKMetalVertexDescriptorFromModelIO()` - is a name row and is covered
by the declared names.

That distinction is not a detail. Mapping a bare api to `(api, api)` made it a member row that no
selector can equal, and all 29 MetalKit rows then read as uncovered. The true answer is 23 covered
and 6 the headers do not declare. The same mistake on the declared side sent file scope functions
through `selector_of()` and invented `setMTKMetalVertexDescriptorFromModelIO():`, a member no header
declares and no row can be asking about.

**These are framework totals, not per-header, and they include more than the framework.** One
translation unit of the umbrella pulls in every header the framework's own headers import, so
MetalKit's five headers count QuartzCore and UIKit with them.

## Five controls, and each has already caught a bug

```
  member in a header MTLDevice   newBufferWithLength:options: found
  member in a header MTLBuffer   getBytes:                    found
  a name in no Metal header is found zero times          True  ('aNameNoHeaderDeclares:')
  a known implemented row is counted as covered        True  (MTLBlitCommandEncoder.copyFromBuffer:...)
  and with that row removed, it moves back               True  (scratch-registry: 16 row(s) for MTLBlitCommandEncoder, was 17)
  one declaration removed from a scratch copy            True  (MTLDevice.h newSharedEventWithHandle:: 6694 declared -> 6693, moved by 1)
```

- The two member controls name the header as well as the member, because `newBufferWithLength:
  options:` was checked as an `MTLBuffer` member when it is an `MTLDevice` method in `MTLDevice.h`,
  and the control failed for a reason of its own making.
- The count came out at 6959 declared and 0 covered against 119 implemented rows until the method
  kind was measured: over `MTLDevice.h`'s top level the histogram is 4555 `ObjCMethodDecl`, 1597
  `ObjCPropertyDecl`, 127 `ObjCIvarDecl` and **not one** `ObjCInstanceMethodDecl`, the kind the tool
  was filtering on. Every method in the framework was being dropped. Selectors come from
  `ObjCMethodDecl.mangledName`, the whole `-[Owner selector:]`, because a method's own `name` is a
  selector piece.
- The match control writes a scratch copy of the registry and reads it by argument. Its first version
  overwrote the checkout's registry and put it back, so it could not fail.
- The fifth control copies the headers to `.agent-work/runs/uncovered/scratch-sdk`, laid out as the
  SDK is, and reads the same listing against that root. It once reported the count moving by 11379:
  it had never read the copy at all, because it wrote absolute paths and `headers()` matched listing
  lines by the SDK directory in front of them, so every line was dropped and 0 was compared against
  11379. Now `6694 -> 6693`.

## Why there is no per-header table

The table the census is asked for - per header, declared / with a row / no row - is not delivered,
and the reason is measured rather than guessed.

**clang's JSON AST does not attribute a definition to the header that declares it.** Over
`MTKView.h` the AST holds 2941 interfaces and protocols, of which **1995 have no `loc.file` at all**,
and `MTKView` is among them. The text AST dump is no better: the same declaration prints
`<line:24:1, line:237:2> line:24:12 MTKView`, a line number with no file.

**A difference against a Foundation-only translation unit does not substitute for a location.** Each
header's transitive imports are counted with it, and a header is not its imports:

| header | "own" members | "own" names |
| --- | ---: | ---: |
| MTKModel.h | 10620 | 6930 |
| MTKTextureLoader.h | 933 | 6946 |
| MTKView.h | 21099 | 12152 |

`MTKView.h` pulls 1178 other headers - UIKit, QuartzCore, simd - and Foundation does not have them,
so they all read as its own. The baseline has to be include complete for that header, and the
include closure is the thing being measured, so the method is circular. Two stronger baselines were
tried and are both worse in a different way: all the framework's other headers with no umbrella gives
**0** for every header, because the others re-import it; and the header's own transitive closure does
not compile, because those headers are imported by bare name across every framework -
`'CAAnimation.h' file not found`.

**libclang's C API would give the location, and its cursor children cannot be walked on this
machine.** `python3 tests/backports/host/metal-census/libclang-probe/probe.py` reproduces this from
the tree, and it is the evidence for the claim rather than an assertion about it. It builds the C
probe on demand into `.agent-work/runs/metal-census/`; nothing is written outside `.agent-work`.

The translation unit is real, and the probe proves that rather than asserting it. `decl.m` is an
`@interface` with one method plus a file scope function, so a parse that quietly produced nothing
would show as zero tokens rather than as zero children:

```
libclang    /Library/Developer/CommandLineTools/usr/lib/libclang.dylib
version     Apple clang version 21.0.0 (clang-2100.3.34.2)
CXCursor    32 bytes, kind at 0, xdata at 4, data at 8 (ctypes)
ctypes      diagnostics 0  tokens 17  children 0
sizeof(CXCursor) 32  offsetof kind 0 xdata 4 data 8 (C)
C          diagnostics 0  tokens 17  children 0
```

**The likeliest explanation is ruled out, not assumed away.** A visitor that never fires through
`ctypes` on arm64 is commonly a `CXCursor` whose layout does not match `clang-c/Index.h`, since the
struct is 32 bytes and is passed by value. It matches: 32 bytes, `kind` at 0, `xdata` at 4, `data` at
8, printed from both sides, and the children are still zero. The block-based entry point
`clang_visitChildrenWithBlock`, whose disassembly does contain an indirect call where
`clang_visitChildren` has none, was also tried through a hand-built `BlockLiteral` and likewise
returned 0 children.

Two ctypes details cost real time and are recorded so they are not paid again: reading any count
after `clang_disposeTokens` aborts the process with no message, so the token array is not disposed;
and a visitor that calls back into libclang from inside the callback, or that closes over a local,
also aborts. Both aborts are why the probe counts in the callback and inspects afterwards.

So the per-header table waits on a libclang that walks, or on an AST that carries a file for a
definition. Neither exists here today, and the aggregate counts above are the most this census can
stand behind.

## The harnesses in `metal-census/`, and the one thing owed about them

`stitch.sh`, `reflection.sh`, `argbinding.sh`, `pre-export.sh` and `check-split-control.sh` are the
census's host harnesses. Each is 100755, each guards its scratch with `work-guard.sh` and removes it
at the end, and each is run BY HAND from `packages/a/apple-backports` — the exception being
`run.sh`, which `tools/matter-host-diff.lua` and `tools/matter-pure-diff.lua` really do drive. There is no test list,
Makefile target or lua suite that drives this directory, and **nothing outside this directory drives
one** — the four files outside it that mention them at all are facts files, which is to say
documentation. Measured, and recounted by `check-harness-invokers.sh` below, which fails if a
mention outside the directory is anything other than a facts file. `run.sh` in the same directory is
MetalKit's own differential, not a harness runner.

**Within** the directory the harnesses are not independent: `check-split-control.sh` INVOKES
`pre-export.sh` at its line 48 and its line 78, and it is that pair which makes check 2's control
runnable at all. `argbinding.sh` and `reflection.m` each NAME another harness in their header — the
how-to line each copies its compile command from — which is a reference and not an invocation. The
list below is generated, and an earlier revision of this file instead said each harness was "named
only by itself and by the facts file", which was false for three of the five.

**Owed:** a runner that drives all of them, so a green run is something the machine records rather
than something a band remembers. It is not done here because no such runner exists to add one to,
and inventing a second entry point for harnesses that already have one would be the duplication
this workspace forbids. The honest statement is the property itself: until a runner exists, these
harnesses are run on demand, and a change to one of them is only exercised by whoever runs it.

<!-- invokers: generated by check-harness-invokers.sh, do not edit by hand -->
```
argbinding.sh            packages/a/apple-backports/facts/Metal/ArgumentBindings.md packages/a/apple-backports/facts/Metal/Census.md
check-harness-invokers.sh packages/a/apple-backports/facts/Metal/Census.md
check-protocol-rows.sh   packages/a/apple-backports/facts/Metal/Census.md
check-split-control.sh   packages/a/apple-backports/facts/Metal/Census.md packages/a/apple-backports/facts/Metal/FunctionStitching.md
descriptors.sh           packages/a/apple-backports/facts/Metal/Census.md
pre-export.sh            packages/a/apple-backports/facts/Metal/Census.md packages/a/apple-backports/facts/Metal/FunctionStitching.md tests/backports/host/metal-census/check-split-control.sh
reflection.sh            packages/a/apple-backports/facts/Metal/Census.md packages/a/apple-backports/facts/Metal/TypeTree.md tests/backports/host/metal-census/reflection.m
run.sh                   packages/a/apple-backports/ARKit/CharonARTracker.m packages/a/apple-backports/facts/ARKit/TrackerDifferential.md packages/a/apple-backports/facts/AVFAudio/AVAudioEngineManualRendering.md packages/a/apple-backports/facts/Accelerate/SparseBLAS.md packages/a/apple-backports/facts/Accelerate/vDSPBiquad6.md packages/a/apple-backports/facts/Accessibility/Accessibility.md packages/a/apple-backports/facts/AuthenticationServices/ASAuthorizationRequest.md packages/a/apple-backports/facts/Contacts/Fetching.md packages/a/apple-backports/facts/CoreImage/ContextOwner.md packages/a/apple-backports/facts/CoreImage/Differences.md packages/a/apple-backports/facts/CoreMedia/CMTimeMultiplyByRatio.md packages/a/apple-backports/facts/HealthKit/HealthKit.md packages/a/apple-backports/facts/MLCompute/Values.md packages/a/apple-backports/facts/Metal/Census.md packages/a/apple-backports/facts/Metal/Heaps.md packages/a/apple-backports/facts/SceneKit/SCNView.md packages/s/styx/facts/Combine/CombineKit.md tests/backports/README.md tests/backports/device/below6/run.sh tests/backports/device/below6/xmake.lua tests/backports/device/callkit-cases.m tests/backports/device/display-probe/xmake.lua tests/backports/device/healthkit/run.sh tests/backports/emulate/calls/run.sh tests/backports/host/accessibilitychart/cases.m tests/backports/host/accessibilitychart/mutants.sh tests/backports/host/arkit/run.sh tests/backports/host/authservices/run.sh tests/backports/host/authservices/values.sh tests/backports/host/bundlerequest/differential.m tests/backports/host/bundlerequest/measure/README.md tests/backports/host/bundlerequest/run.sh tests/backports/host/cachereader/run.sh tests/backports/host/callkit/run.sh tests/backports/host/certificatepresentation/mutate.py tests/backports/host/certificatepresentation/run.sh tests/backports/host/ciimage/pixel/probe.m tests/backports/host/collectionmovement/run.sh tests/backports/host/collectiontransition/run.sh tests/backports/host/combine/README.md tests/backports/host/constants/run.sh tests/backports/host/contacts/compare.py tests/backports/host/contacts/expectations.py tests/backports/host/contacts/run.sh tests/backports/host/coordspace/run.sh tests/backports/host/coredata/run.sh tests/backports/host/coremedia7/cmtaginlines.m tests/backports/host/coremedia7/constants.m tests/backports/host/coreml/record.m tests/backports/host/coreml/run.sh tests/backports/host/createml/differential.swift tests/backports/host/createml/suite-counts.py tests/backports/host/createml/tabularframe.swift tests/backports/host/custompresentation/run.sh tests/backports/host/customtransition/run.sh tests/backports/host/datecomponents/run.sh tests/backports/host/diffable/run.sh tests/backports/host/documentmenu/run.sh tests/backports/host/dragdroprouting/run.sh tests/backports/host/dragdroprouting/xmake.lua tests/backports/host/dynamics/fields_test.m tests/backports/host/dynamics/run.sh tests/backports/host/errorprovider/run.sh tests/backports/host/exclusion/run.sh tests/backports/host/fitting/run.sh tests/backports/host/flowauto/run.sh tests/backports/host/fontdesc/run.sh tests/backports/host/fontkeys/run.sh tests/backports/host/foundation-constants/probe.m tests/backports/host/foundation-constants/run.sh tests/backports/host/foundation14/run.sh tests/backports/host/foundation8b/run.sh tests/backports/host/foundationbatch/run.sh tests/backports/host/fuzz/run.sh tests/backports/host/graphics/run.sh tests/backports/host/hapcrypto/bignum.c tests/backports/host/hapcrypto/run-bignum.sh tests/backports/host/hapcrypto/run.sh tests/backports/host/healthkit/differential.m tests/backports/host/healthkit/run.sh tests/backports/host/homeindicator/run.sh tests/backports/host/homekit/run.sh tests/backports/host/imageio/run.sh tests/backports/host/imagetraits/run.sh tests/backports/host/inputview/run.sh tests/backports/host/insetref/run.sh tests/backports/host/invalidation/run.sh tests/backports/host/itemprovider/run.sh tests/backports/host/jscontext/checks.m tests/backports/host/json1/differential.m tests/backports/host/layoutguide/run.sh tests/backports/host/layoutsupport/run.sh tests/backports/host/mapkit-geojson/runner.m tests/backports/host/mediaplayeritem/README.md tests/backports/host/mediaplayeritem/run.sh tests/backports/host/metal-census/mesh-differential.m tests/backports/host/metalblit/run.sh tests/backports/host/metricvalue/run.sh tests/backports/host/mlcompute/layer-cases.m tests/backports/host/mlcompute/run.sh tests/backports/host/modelio/probe.m tests/backports/host/network-connection/differential.m tests/backports/host/network-objects/differential.m tests/backports/host/network-proxy/differential.m tests/backports/host/orderedcollections/run.sh tests/backports/host/pasteboard10/run.sh tests/backports/host/personname/run.sh tests/backports/host/phase/values.m tests/backports/host/photosettings/oracle.m tests/backports/host/popover/run.sh tests/backports/host/presentation/run.sh tests/backports/host/presentationintent/run.sh tests/backports/host/presses/run.sh tests/backports/host/previewaction/run.sh tests/backports/host/previewing/run.sh tests/backports/host/progress/run.sh tests/backports/host/realityfoundation/run.sh tests/backports/host/registry/run.sh tests/backports/host/relativedatetime/run.sh tests/backports/host/renames/run.sh tests/backports/host/resolvedphoto/oracle.m tests/backports/host/run-all.sh tests/backports/host/safeguide/run.sh tests/backports/host/scrollguide/run.sh tests/backports/host/searchcontroller/run.sh tests/backports/host/security/README.md tests/backports/host/sensorkit/run.sh tests/backports/host/sheet/run.sh tests/backports/host/sheethandover/record.m tests/backports/host/sheethandover/run.sh tests/backports/host/sheetmetrics/run.sh tests/backports/host/sheetshadow/run.sh tests/backports/host/show/run.sh tests/backports/host/signpost/run.sh tests/backports/host/smallapis2/run.sh tests/backports/host/sparsecomplex/run.sh tests/backports/host/spotlightstore/run.sh tests/backports/host/spotlightstore/search.m tests/backports/host/spotlightstore/store.m tests/backports/host/streammetrics/run.sh tests/backports/host/streammetrics/test.m tests/backports/host/stringdrawing/run.sh tests/backports/host/swiftregistry/run.sh tests/backports/host/tableestimates/run.sh tests/backports/host/tail1/run.sh tests/backports/host/tail2/run.sh tests/backports/host/tail3/run.sh tests/backports/host/template/run.sh tests/backports/host/termofaddress/run.sh tests/backports/host/textalign/run.sh tests/backports/host/textattr/run.sh tests/backports/host/textdragdrop/run.sh tests/backports/host/textdragdrop/xmake.lua tests/backports/host/textdragweak/run.sh tests/backports/host/textdragweak/xmake.lua tests/backports/host/textkit7/run.sh tests/backports/host/textsystem7/run.sh tests/backports/host/timing/run.sh tests/backports/host/touchtypes/run.sh tests/backports/host/traits11/run.sh tests/backports/host/uikit2/.frozen-run.sh tests/backports/host/uikit2/run.sh tests/backports/host/uikitadditions/run.sh tests/backports/host/uikitconst/run.sh tests/backports/host/uikitnames/run.sh tests/backports/host/uikitscroll/run.sh tests/backports/host/uiviewinteractions/run.sh tests/backports/host/underlying/run.sh tests/backports/host/unitformat/differential.m tests/backports/host/units/shift-and-run.sh tests/backports/host/usernotifications/mutants.sh tests/backports/host/usernotifications/run.sh tests/backports/host/videotoolbox/run.sh tests/backports/host/vision/run.sh tests/backports/host/vtclass/mutants-expected.txt tests/backports/host/vtclass/run.sh tests/backports/host/webkit/run.sh tests/backports/source/selector-synthesize/check.py tools/matter-pure-diff.lua
stitch.sh                packages/a/apple-backports/facts/Metal/Census.md packages/a/apple-backports/facts/Metal/FunctionStitching.md tests/backports/host/foundation-constants/run.sh tests/backports/host/metal-census/argbinding.sh
```
<!-- invokers: end -->

**Owed, restated because it is the part that is true and still not done:** a runner that drives all
of these, so a green run is something the machine records rather than something a band remembers.
It is not done here because no such runner exists to add one to, and inventing a second entry point
for harnesses that already have one would be the duplication this workspace forbids. Until a runner
exists these harnesses are run on demand, and a change to one is only exercised by whoever runs it.
`check-harness-invokers.sh` keeps the generated list above honest; it does not make anything run.
