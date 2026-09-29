# The 14.0 descriptors: twenty classes that describe, and never ask

The largest coherent block of Metal's absent rows is the family that arrived in iOS 14, and it is
one thing: **descriptors**. They are in `Metal/MTLDescriptors14.m`, twenty classes.

| group | classes | what a descriptor holds |
| --- | --- | --- |
| acceleration structure | `MTLAccelerationStructureDescriptor`, `…GeometryDescriptor`, `…BoundingBoxGeometryDescriptor`, `…TriangleGeometryDescriptor`, `MTLPrimitiveAccelerationStructureDescriptor`, `MTLInstanceAccelerationStructureDescriptor` | a usage, offsets, strides, counts, a vertex format, an index type, motion border modes and times |
| ray-tracing function tables | `MTLVisibleFunctionTableDescriptor`, `MTLIntersectionFunctionTableDescriptor` | a function count each |
| counter sampling | `MTLCounterSampleBufferDescriptor`, `MTLComputePassSampleBufferAttachmentDescriptor`, `MTLResourceStatePassSampleBufferAttachmentDescriptor`, `MTLRenderPassSampleBufferAttachmentDescriptor` | a label, a storage mode, a sample count, and the start/end sample indices of each stage |
| the arrays | `…ComputePassSampleBufferAttachmentDescriptorArray`, `…RenderPass…Array`, `…ResourceStatePass…Array` | the two indexed members, over real storage |
| passes and archives | `MTLComputePassDescriptor`, `MTLResourceStatePassDescriptor`, `MTLBinaryArchiveDescriptor` | a dispatch type, a URL |
| linked functions | `MTLLinkedFunctions`, `MTLIntersectionFunctionDescriptor` | four function arrays; **no member of its own** |

**They are all plain data holders, and that is the whole case for carrying them.** A descriptor says
what a pass or an acceleration structure is built from, and none of it asks the device anything. A
port with no ray tracing still has to hand these back when a caller asks what it would build, and
the values a caller reads back are the values it wrote.

## The hierarchy is the header's, and getting it wrong was caught by the compiler

All twenty are `@interface`, **not** `@protocol`, so none carries a conformance list. And
`MTLAccelerationStructureGeometryDescriptor` is a **sibling** of `MTLAccelerationStructureDescriptor`,
not a subclass of it — only the bounding-box and triangle geometry descriptors derive from it. The
first version of the object made the geometry a subclass and synthesized five properties on the base
that belong to the sibling, and `clang` refused it.

## Three members that were invented, and are not there

The compiler did not catch these; reading the headers did, and the compiler would have shipped them.

- `MTLAccelerationStructureUsageInstance` **does not exist**. The cases are `None` 0, `Refit`
  `(1<<0)`, `PreferFastBuild` `(1<<1)`, `ExtendedLimits` (15.0).
- `MTLMotionBorderModeWrap` **does not exist**. The cases are `Clamp` 0, `Vanish` 1.
- `MTLIntersectionFunctionDescriptor` declares **no member of its own** — everything it answers is
  inherited from `MTLFunctionDescriptor`, a different row. The `functionBufferOffset`,
  `functionBufferOffsetAlignment` and `functionStride` this file first carried are in no SDK header
  and are gone.

`MTLAttributeFormatFloat2` is 29 and `MTLIndexTypeUInt16` is 0; `MTLDispatchType` is `Serial` 0 and
`Concurrent` 1. All of them are the header's own values.

## The differential, and the device it never creates

`tests/backports/host/metal-census/descriptors.m` compares the port **property by property against
Apple's own objects**, and **creates no device anywhere**. That is possible because a descriptor is
`[[X alloc] init]` on both sides. `MTLCreateSystemDefaultDevice()` **hangs** on a machine with no
GPU — it was measured hanging and killed — so nothing in this family calls it, and a round trip of
the port against *itself* would prove only that the port agrees with the port.

Fresh **defaults** are compared as well as written values, because a port that invented a default
would pass every written value and still be wrong.

Each mutant breaks one class and must go red on that class's line:

| mutant | red line |
| --- | --- |
| `MTLVisibleFunctionTableDescriptor`'s `-functionCount` dropped | `FAIL MTLVisibleFunctionTableDescriptor.functionCount: the port 0 and Apple's own object 5` |

## What is NOT measured, by name

Every property that holds a **device-made object** is carried and read `nil`, and is not measured:
`primitiveDataBuffer`, `boundingBoxBuffer`, `vertexBuffer`, `indexBuffer`, `transformationMatrixBuffer`,
`instanceDescriptorBuffer`, `motionTransformBuffer`, `geometryDescriptors`,
`instancedAccelerationStructures`, `counterSet`, `sampleBuffer` on all three attachment
descriptors, and `functions` / `binaryFunctions` / `groups` / `privateFunctions` on `MTLLinkedFunctions`.

The reason is the same for every one of them: both sides answer `nil` with no device, and a round
trip with a real one would need a device to make it. The case asserts the `nil` on both sides and
says it is going no further.

## The eleven protocols, and the rule they are bound by

`MTLAccelerationStructure`, `MTLAccelerationStructureCommandEncoder`, `MTLBinaryArchive`,
`MTLCommandBufferEncoderInfo`, `MTLCounter`, `MTLCounterSampleBuffer`, `MTLCounterSet`,
`MTLDynamicLibrary`, `MTLFunctionHandle`, `MTLIntersectionFunctionTable` and
`MTLVisibleFunctionTable` are declared in `CharonMetalProtocols.h`, so a caller resolving one by its
own name finds it — the rule from the stack-20 gate failure.

`tools/transcribe-protocols.py` wrote all eleven, and each arrives as a **forward declaration**: the
SDK this package compiles against already declares them, so the body comes from the umbrella import
and the generator writes only the name. It **refuses** to write anything for the fifteen protocols
already in that header, so the file is a union of runs — this run's eleven were merged into it, and
the header now carries twenty-six.
