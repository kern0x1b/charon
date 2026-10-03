# The Metal 4 descriptors, and the tile pipeline's colour attachments

120 rows: the seventeen classes of Metal 4 that say what a pipeline is built FROM, and the two classes
of iOS 11 that say what a tile pipeline's colour attachments are. They are all plain data holders. The
case for carrying them is the same case the 16.0 and 14.0 families make and no other: a descriptor asks
the device nothing, so an application that fills one gets an object it can read, copy and reset, and the
half that is not there is named below and in each row's `effect`.

## The commands and their output

```
sh tests/backports/host/metal-census/descriptors26.sh
```

```
the differential, against Apple's own objects, with no device created:
  the DEVICE objects define all of them under Apple's own names (MTL4PipelineOptions and 16 more)
  ok   the control: ZZZNoSuchNameCharonR16 is not a class of this framework
  ok   fresh: shaderValidation: the port 0 and Apple's own object 0
  ok   copy of a changed one: shaderReflection: the port 2 and Apple's own object 2
  ok   fresh: maxCallStackDepth, and it is Apple's own 1 and not a zero: the port 1 and Apple's own object 1
  ok   fresh: writeMask, and it is MTLColorWriteMaskAll: the port 15 and Apple's own object 15
  ok   fresh: sourceRGBBlendFactor, and it is One: the port 1 and Apple's own object 1
  ok   a write copies: the slot holds a copy on both sides, not the object handed in
  ok   a nil empties the slot: the format is the default on both sides
  ok   fresh: options is nil on both sides, and NOT a fresh MTL4PipelineOptions
  ok   fresh: rasterSampleCount, and it is Apple's own 1: the port 1 and Apple's own object 1
  ok   fresh: vertexDescriptor IS an object on both sides
  ok   fresh: maxVertexAmplificationCount, and it is Apple's own 1: the port 1 and Apple's own object 1
  ok   fresh: isRasterizationEnabled is YES on both sides
  ok   fresh: vertexStaticLinkingDescriptor is an object on both sides
  ok   tile colour attachment 7: both sides answer a descriptor
  ok   fresh MTL4FunctionDescriptor is an object, and it has no members to compare
136 checks, each one against Apple's own object
all checks passed
the control: a mutation that does not compile is RUN FAILED, not red
  ok   RUN FAILED: the broken mutation did not build, and no binary was left to run
the mutations: one per thing the port decides that a header does not state
  red  the attachment's fresh write mask:   fresh: writeMask, and it is MTLColorWriteMaskAll: the port 2 and Apple's own object 15
  red  the options' copy carrying shaderReflection:   copy of a changed one: shaderReflection: the port 0 and Apple's own object 2
  red  the render pipeline's fresh rasterSampleCount:   fresh: rasterSampleCount, and it is Apple's own 1: the port 0 and Apple's own object 1
  red  the array's copy semantics on a write:   a write copies: the slot holds a copy on both sides, not the object handed in
  red  the stage's fresh maxCallStackDepth:   fresh: maxCallStackDepth, and it is Apple's own 1 and not a zero: the port 0 and Apple's own object 1
  red  the render pipeline's fresh vertex descriptor:   fresh: vertexDescriptor IS an object on both sides
  red  the tile array's getter:   tile colour attachment 0: both sides answer a descriptor
descriptors26: the differential is green, the control is RUN FAILED, and all seven mutants are red
```

**The seam, in one line.** The port's seventeen 26.0 classes and its two 11.0 classes are compiled under
other names, together, in one translation unit the script writes, and both copies are in one binary with
Apple's own; the case asks each side by its own name. The rename is a `#define` inside that unit and not
a `-D` on the command line: the same file with the same flags and the same `-D` produced an object
carrying Apple's name in one invocation and the port's in another, from one command line
(`facts/Metal/DeviceOnThisMachine.md` and `mdltexture.sh` are where that is written down). The binary is
asked for the renamed symbols and the run stops if they are absent, because a case that read Apple's
class and called it the port's would agree with itself.

**No device is created, and the reason is that a descriptor asks for none** - both sides are
`[[X alloc] init]`. That is measured, on a machine that HAS one, in
`facts/Metal/DeviceOnThisMachine.md`; the old reason (`MTLCreateSystemDefaultDevice()` hangs without a
GPU) was false and is gone.

## The values, and which of them a header does not give

Every default in the port is Apple's own, measured against a fresh object of Apple's class. The ones a
header states are stated there and measured anyway; the ones it does not are the ones worth having:

| what | Apple's own fresh value | where |
|---|---|---|
| `MTL4PipelineDescriptor.options` | **nil** | the header does not say, and an implementer would guess a fresh options |
| `MTL4RenderPipelineDescriptor.vertexDescriptor` | **an object**, a fresh `MTLVertexDescriptor` | ditto, and the opposite guess |
| the `null_resettable` static linking descriptors | **objects** on a fresh descriptor | `null_resettable` says the getter may hand one back; the port makes one on first use and the compute and tile descriptors make one in `-init` |
| `rasterSampleCount`, `maxVertexAmplificationCount` | **1** | not 0 |
| `isRasterizationEnabled` | **YES** | not NO |
| `MTL4PipelineStageDynamicLinkingDescriptor.maxCallStackDepth` | **1** | not 0 |
| the colour attachment's write mask | **15**, `MTLColorWriteMaskAll` | |
| its source factors / destination factors / operations | **One / Zero / Add** | the header says so, and it is measured |
| its pixel format | **0**, `MTLPixelFormatInvalid` | |
| the colour attachment array | **eight slots** | the header declares two members and no bound; indices 0 to 7 answer a descriptor and index 8 fails Apple's own assertion |
| the tile colour attachment array | **eight slots** | the same measurement, out of process |
| `requiredThreadsPerThreadgroup` and the mesh ones | **0 x 0 x 0** | not 1 x 1 x 1 |

**The two eight-slot bounds are measured OUT OF PROCESS, one index per invocation**, because index 8
triggers an assertion that STOPS the process: a case that asked 0 to 8 in one run would die at 8 having
compared nothing after it. That is the same shape as the four-slot measurement
`facts/Metal/Descriptors16.md` records for the 14.0 family, and the same reason.

## The three things a mutation had to be spent on, and what two of them were first

The seven mutations are one per thing the port decides that a header does not state. Three of them were
**wrong on the first attempt** and the harness said so, which is the reason to keep the mutations:

* **M1** was the attachment's write mask and is red. **M2** was the base's `options` SETTER, and it came
  back GREEN - nothing in the case ever sets `options` to nil, so nothing observed it. It is now the
  options' `-copyWithZone:` dropping `shaderReflection`, and the case was strengthened to copy a
  descriptor a caller has CHANGED, because two copies of two fresh objects agree whatever the copy does.
* **M4** was the array's reset of a nil, and it came back GREEN: the getter makes a descriptor when the
  slot is empty, so emptying a slot and resetting it are the same thing through the only way in. A reset
  nothing can observe is not proved by a green run. The port keeps the reset because the header asks for
  it (`MTL4RenderPipeline.h`: "You can safely set the color attachment at any legal index to nil. This
  has the effect of resetting that attachment descriptor's state to its default values"), and M4 is now
  the copy semantics of a write, which the case does compare. What a nil shows is named in the case:
  the slot is empty again, so the getter answers a fresh descriptor and the format is the default on
  both sides.

## What none of these objects is for, and which rows say so

**Nothing in this port reads a descriptor made here.** There is no `MTL4CommandQueue`, no
`MTL4CommandBuffer` and no pipeline state this port builds from any of these, so an application that
fills one gets an object it can read, copy and reset - and no object to hand it to.

The mesh pipeline is the sharpest case, and it is the same argument `facts/Metal/Metal16Absence.md`
makes for the 16.0 mesh descriptor: its three `MTL4FunctionDescriptor` members ARE the pipeline's
object, mesh and fragment stages rather than values this port can hold, and this port's rendering path
is Metal over OpenGL ES 2.0 (`facts/Metal/RenderPath.md`), which has no mesh stage and no geometry or
tessellation stage either.

Each row's `effect` says exactly that, because `implemented` owes a reader the measured behaviour
INCLUDING the part that is not there.

## What is not measured here

**What a pipeline built from any of these would DO.** That needs a Metal 4 command queue and a pipeline
state, and neither is in this port - which is a statement about the port and not about the host, and it
is the same absence the 16.0 family records. Every member of these classes IS measured, against Apple's
own object, on the member the header names.