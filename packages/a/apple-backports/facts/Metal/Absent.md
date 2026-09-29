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

### update 2026-09-29: the fifteen protocol rows, re-derived from what the port carries

The rows this file counted as "a build error: MTLAllocation, 15" were **stale**, and the correction
is the point of this entry. Each of the fifteen carried the reason:

> `CharonMetalProtocols.h:51:35: error: cannot find protocol declaration for 'MTLAllocation'`

Two things about that are no longer true. **`CharonMetalProtocols.h` does not name `MTLAllocation`
at all** — `grep -c MTLAllocation` on the file is 0 — and **line 51 is a bare forward declaration**,
not that diagnostic. The header compiles with the library's own flags and no `-I`, run from
`packages/a/apple-backports`, and the quoted `file:line:column` no longer resolves to anything.

So the fifteen were re-derived from what the port actually carries, and the evidence is a compiled
one. **`-Wprotocol` was silenced in every Metal class's own source** by a `#pragma clang diagnostic
ignored` at the top of the file, and a *suppressed* warning cannot be promoted to an error — so
`-Werror=protocol` had never been able to fire on any of them. Removing the two lines and compiling
with `-Werror=protocol -Werror=incomplete-implementation` names the missing required members, exactly:

```
Metal/CharonMetalBuffer.m:4:17: error: method 'newTextureWithDescriptor:offset:bytesPerRow:' in protocol 'MTLBuffer' not implemented
Metal/CharonMetalBuffer.m:4:17: error: method 'addDebugMarker:range:' in protocol 'MTLBuffer' not implemented
Metal/CharonMetalBuffer.m:4:17: error: method 'removeAllDebugMarkers' in protocol 'MTLBuffer' not implemented
```

| protocol | the port's class | missing required members, measured |
| --- | --- | --- |
| MTLDevice | `CharonMetalDevice` | debug markers, the offset texture constructor |
| MTLResource | `CharonMetalBuffer`, `CharonMetalTexture` **by inheritance** | the debug markers `MTLResource` declares |
| MTLBuffer | `CharonMetalBuffer` | debug markers, the offset texture constructor |
| MTLTexture | `CharonMetalTexture` | debug markers |
| MTLSamplerState | `CharonMetalSampler` (CharonMetal.h:186) | none |
| MTLFunction | `CharonMetalFunction` | none |
| MTLLibrary | `CharonMetalLibrary` | function constants, `-newFunctionWithConstantValues:` |
| MTLRenderPipelineState | `CharonMetalPipeline` | the binary, the stage-input accessors |
| MTLCommandQueue | `CharonMetalQueue` | `-insertDebugBoundary:`, the handler members |
| MTLCommandBuffer | `CharonMetalCommandBuffer` | none |
| MTLCommandEncoder | `CharonMetalEncoder`, `CharonMetalComputeEncoder` **by inheritance** | none |
| MTLRenderCommandEncoder | `CharonMetalEncoder` | `-setViewport`, debug marking |
| MTLDrawable | `CharonMetalDrawable` **by inheritance** through `CAMetalDrawable` | none — the stripped compile is CLEAN |
| MTLDepthStencilState | `CharonMetalDepthStencil` | none — the stripped compile is CLEAN |
| MTLCaptureScope | `CharonMTLCaptureScope` | none |

**Three of them needed no class at all**, because 16.4's own headers make the conformance by
inheritance: `MTLBuffer.h:32` declares `@protocol MTLBuffer <MTLResource>` and `MTLTexture.h:264` the
same, `MTLRenderCommandEncoder.h:131` and `MTLComputeCommandEncoder.h:41` both declare
`<MTLCommandEncoder>`, and `CAMetalDrawable` is `<MTLDrawable>`. A class conforming to a protocol
conforms to everything it inherits.

**The pragmas are half removed, and the half that stays is measured.** Ten classes are fully
conformant and their pragmas are gone; thirteen are not, and their stripped compile says so in as many
words, so their pragmas stay — a build failure that says nothing is worse than a warning that names the
gap. **The remaining partial conformances are work owed, and this file now names every one of them.**

**The file floors do not move.** Every row in `ios8render.json` and `ios11capturemanager.json` is
`minimum: 6.0`, which is where the port's Metal starts, so flipping a protocol row to `implemented`
adds it to `bands[introduced]` (backports.lua:664) without raising any file's floor. `MTLCaptureScope`
is `introduced: 11.0`, so it lands in that band; every other one is `introduced: 8.0`.

### update 2026-09-29: r2 — ten of the fifteen are inert, not implemented, and the citations are corrected

A review of `metal-alloc` found the fifteen flipped to unqualified `implemented` while their classes
demonstrably miss required members, and it is right: `backports.lua:664` turns a protocol row with
`status == "implemented"` into a **band floor** through `bands[introduced]`, so claiming a conformance
that is not callable claims a floor this port cannot support. A missing required protocol method is a
callable gap — owed, not carried.

**The rule now applied: `implemented` only where the stripped compile is clean.** Ten rows are
`inert` — the class is carried and the members it does implement are callable, but these are not, and
each row names them:

| row | the port's class | the exact selectors owed |
| --- | --- | --- |
| MTLDevice | `CharonMetalDevice` | `heapBufferSizeAndAlignWithLength:options:`, `heapTextureSizeAndAlignWithDescriptor:`, `minimumLinearTextureAlignmentForPixelFormat:`, `minimumTextureBufferAlignmentForPixelFormat:`, `newBufferWithBytesNoCopy:length:options:deallocator:`, `newComputePipelineStateWithDescriptor:options:completionHandler:` and 13 more |
| MTLResource | `CharonMetalBuffer`, `CharonMetalTexture` | `isAliasable`, `makeAliasable`, and the debug markers `MTLResource` declares |
| MTLBuffer | `CharonMetalBuffer` | `addDebugMarker:range:`, `removeAllDebugMarkers`, `newTextureWithDescriptor:offset:bytesPerRow:`, the `MTLResource` pair |
| MTLTexture | `CharonMetalTexture` | `getBytes:bytesPerRow:bytesPerImage:fromRegion:mipmapLevel:slice:`, `newTextureViewWithPixelFormat:`, `newTextureViewWithPixelFormat:textureType:levels:slices:`, `newSharedTextureHandle`, the `MTLResource` pair |
| MTLFunction | `CharonMetalLibrary` | `newArgumentEncoderWithBufferIndex:`, `newArgumentEncoderWithBufferIndex:reflection:` |
| MTLLibrary | `CharonMetalLibrary` | `newFunctionWithDescriptor:error:` and the intersection-function and completion-handler forms |
| MTLRenderPipelineState | `CharonMetalPipeline` | `imageblockMemoryLengthForDimensions:`, `functionHandleWithFunction:stage:`, `newIntersectionFunctionTableWithDescriptor:stage:`, `newVisibleFunctionTableWithDescriptor:stage:` |
| MTLCommandQueue | `CharonMetalQueue` | `commandBufferWithDescriptor:` |
| MTLCommandBuffer | `CharonMetalCommandBuffer` | `blitCommandEncoderWithDescriptor:`, `computeCommandEncoderWithDescriptor:`, `computeCommandEncoderWithDispatchType:`, `accelerationStructureCommandEncoder`, `encodeSignalEvent:value:`, `encodeWaitForEvent:value:` and more |
| MTLCommandEncoder, MTLRenderCommandEncoder | `CharonMetalEncoder`, `CharonMetalComputeEncoder` | `setVertexBufferOffset:atIndex:`, `setFragmentBufferOffset:atIndex:`, `setScissorRects:count:`, `setDepthClipMode:`, and on the compute side `setBufferOffset:atIndex:` and more |

**Four stay `implemented`, because the stripped compile is clean for their classes:**
`MTLSamplerState` (`CharonMetalSampler`), `MTLDepthStencilState` (`CharonMetalDepthStencil`),
`MTLDrawable` (`CharonMetalDrawable`) and `MTLCaptureScope` (`CharonMTLCaptureScope`).

**The floors, computed from the registry as it now stands.** `protocol_sources` (backports.lua:656)
reads every `implemented` protocol row and raises `floors_of[introduced]` to the row's `minimum`:

| file | implemented protocol rows | their `introduced` | floor raised |
| --- | --- | --- | --- |
| `ios8render.json` | `MTLSamplerState`, `MTLDrawable`, `MTLDepthStencilState` | 8.0 | **6.0** |
| `ios11capturemanager.json` | `MTLCaptureScope` | 11.0 | **6.0** |

Every row in both files is `minimum: 6.0`, and 6.0 is where the port's Metal starts, so **no floor
moves**: the ten `inert` rows contribute none, and the four that do would not raise a floor even if
they were higher.

**Three citations corrected, each verified by `grep -n` against the 16.4 SDK rather than recalled.**
`MTLResource` is forward-declared at **`MTLBuffer.h:17`**, and it is the base of `MTLBuffer` at
**`MTLBuffer.h:32`**. `MTLDrawable` is declared at **`MTLDrawable.h:26`** and forward-declared at
**`MTLCommandBuffer.h:20`**; `CharonMetalDrawable` conforms to `CAMetalDrawable`, whose inheritance
from `MTLDrawable` is in **`QuartzCore/…/CAMetalLayer.h:28`** — QuartzCore, not a Metal header, which
is what the earlier entry implied by citing the Metal headers for it. `MTLCommandEncoder` is the base
of **`MTLRenderCommandEncoder.h:131`** and **`MTLComputeCommandEncoder.h:41`**.

**And the count was wrong: TWELVE classes keep the pragma, not thirteen.** Ten had it removed, and
twelve keep theirs — `CharonMetalBuffer`, `CharonMetalDevice`, `CharonMetalEncoder`,
`CharonMetalLibrary`, `CharonMetalPipeline`, `CharonMetalQueue`, `CharonMetalTexture`,
`MTLBlitCommandEncoder8`, `MTLComputeCommandEncoder8`, `MTLComputePipeline8`, `MTLHeap10` and
`MTLSharedEvent12`. A reviewer's independent run measured the same twelve refusing with
`-Wprotocol` naming a member in each, and the control — the same tree with the pragmas in place —
compiles clean.

### update 2026-09-29: r3 — the acceptance test is BOTH diagnostics, and two rows are now honest

A review measured the stripped compile **with `-Wobjc-protocol-property-synthesis` as well as
`-Wprotocol`** and found two rows I had left `implemented` that are not: a protocol property nobody
implements is auto-synthesized to nothing and **raises unrecognized-selector when read**, so it is a
callable gap exactly as a missing method is. My r1 run checked `-Wprotocol` only, and the claim that
four rows were conformant was false for two of them.

**The two are now honest, by implementing rather than by demoting:**

- **`MTLFunction`** — the two argument encoders answer `nil`, because an argument encoder is a Metal 3
  *argument buffer* and this port dispatches a device pointer plus the three thread identifiers;
  `functionConstantsDictionary` is `@{}` because the plist carries no constants; `options` is
  `MTLFunctionOptionNone`, the enumeration's own zero and "Default usage" per
  `MTLFunctionDescriptor.h:17`; `patchType` is `MTLPatchTypeNone`, which `MTLLibrary.h:127` names for
  "not a post tessellation function"; `patchControlPointCount` is `-1`, the header's own value for a
  shader that specified none; and `vertexAttributes` and `stageInputAttributes` are the kernel's
  **real** argument list from the plist, each attribute built by the reader's own `MTLVertexAttribute`
  through one helper so the two cannot drift apart.
- **`MTLSamplerState`** — `gpuResourceID` answers a typed zero, because it is a "Handle of the GPU
  resource suitable for storing in an Argument Buffer" (`MTLTexture.h:424`) and this device is the
  port's own over OpenGL ES 2.0 with no GPU resource handle to hand out.

**The remaining six selectors on `MTLLibrary`** — `newFunctionWithDescriptor:error:`, its
completion-handler form, and the two intersection-function pairs — are iOS 14.0 function-descriptor
forms the port does not carry, and the `MTLLibrary` row stays `inert` naming them.

**And the citation corrected once more:** `MTLTexture.h` does not declare `<MTLResource>` at all — it
imports `MTLResource.h` at `MTLTexture.h:10` and `MTLTexture.h:32` reads `MTLTextureType3D = 7,`. The
base declaration is `MTLResource` in **`MTLResource.h`**, reached from `MTLTexture.h:10`'s import.
