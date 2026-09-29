# Argument bindings: the five objects a kernel's resources are described by

When a kernel's arguments are bound, each resource is described by a *binding*: what it is, how
it is read, and the numbers that describe the memory behind it. Those bindings are plain data.
None of them asks the device anything, which is the whole case for carrying them — a port that
dispatches a device pointer and the three thread identifiers still has to hand these back when a
caller asks what a kernel binds. They are in `Metal/MTLArgumentBinding16.m`, one object, which
`release-split` measures in the **16.0 band**.

## The rows

| protocol | header | the port's class | kind it answers |
| --- | --- | --- | --- |
| `MTLBinding` | `MTLArgument.h:335-343` | `CharonMetalBinding` | the base; buffer |
| `MTLBufferBinding` | `MTLArgument.h:346-352` | `CharonMetalBufferBinding` | `MTLBindingTypeBuffer` (0) |
| `MTLTextureBinding` | `MTLArgument.h:361-366` | `CharonMetalTextureBinding` | `MTLBindingTypeTexture` (2) |
| `MTLThreadgroupBinding` | `MTLArgument.h:355-358` | `CharonMetalThreadgroupBinding` | `MTLBindingTypeThreadgroupMemory` (1) |
| `MTLObjectPayloadBinding` | `MTLArgument.h:369-372` | `CharonMetalObjectPayloadBinding` | the header gives it none of its own, so it rides in the buffer |

`MTLBinding` declares `name`, `type`, `access`, `index`, `used` (`isUsed`) and `argument`
(`isArgument`); the four derive from it and add only their own memory numbers.

## The numbers are the header's, not chosen here

`MTLArgument.h:169-171` gives `MTLBindingTypeBuffer = 0`, `MTLBindingTypeThreadgroupMemory = 1`,
`MTLBindingTypeTexture = 2`, and `:218-220` gives `MTLArgumentAccessReadOnly = 0`,
`ReadWrite = 1`, `WriteOnly = 2`. The case compares the port's values against exactly these.

## Why 16.0, and what that word means

The cache ladder's band for this object is 16.0, and it reports that **no release is held between
12.0 and 16.0**, so 16.0 means **"after 12.0, and by 16.0" — a band, not a measured first
release**. The object's name carries 16 because the family is the 16.0 API. The rows say 16.0
because that is the band the ladder chose.

## What the case measures, and what it cannot

A host comparison **is possible in principle and impossible here**, and the case says so rather
than substituting a round trip of the port's object against itself, which would prove only that
the port agrees with the port. A host `MTLDevice` has no
`newArgumentEncoderWithBufferIndex:error:` — the whole family is behind an argument buffer — so
there is no host binding to compare against. What is measured instead is the header-fixed
constants above, plus each class's own values.

Each row is proved by a mutant that breaks **only that class** and goes red on **that class's own
assertion** and on no other (`tests/backports/host/metal-census/argbinding.m`):

| mutant | red line |
| --- | --- |
| `MTLBinding` `-type` | `FAIL MTLBinding: the base answers the kind it was built as` |
| `MTLBufferBinding` `-type` | `FAIL MTLBufferBinding: its type is MTLBindingTypeBuffer` |
| `MTLTextureBinding` `-type` | `FAIL MTLTextureBinding: its type is MTLBindingTypeTexture` |
| `MTLThreadgroupBinding` `-type` | `FAIL MTLThreadgroupBinding: its type is MTLBindingTypeThreadgroupMemory` |
| `MTLObjectPayloadBinding` `-type` | `FAIL MTLObjectPayloadBinding: it rides in the buffer, the only kind the header gives it` |

The base row needed a case of its own: all four subclasses **override** `-type`, so before it was
asked directly a break in the base's own `-type` reached nothing and no mutant there could ever go
red. `MTLObjectPayloadBinding` needed one for the same reason in reverse — nothing asserted that
it rides in the buffer, so a mutant changing it stayed green until the case said so.

## `MTLArgumentEncoder`: still owed, and what the port answers

The encoder is the other half and is **not** in this object. `MTLArgumentEncoder` is a *protocol*
(`MTLDevice.h:32-354`), and the port vends no class for it. What the port answers, measured
(`tests/backports/host/metal-census/argencoder.m`, a binary linking the binding object and
nothing else from Metal):

- `NSClassFromString(@"MTLArgumentEncoder")` → **nil**. No class, so no object and **no members to
  call** — the same answer a device with no argument buffers gives.
- The port's whole class set in that binary is **exactly its five bindings**, so the nil is the
  port not vending an encoder, not a runtime that cannot be asked.
- `NSProtocolFromString(@"MTLArgumentEncoder")` → **non-nil**, and this does **not** measure the
  port: a binary linking only Foundation already has Apple's protocol names registered
  (`MTLArgumentEncoder` FOUND with 2 conforming classes, `MTLBinding` FOUND with 6, 1277
  protocols in the process). It measures the host's own Metal metadata.

**This overturned a claim in the registry.** The `MTLArgumentEncoder` row's effect read "the
protocol is not there: `NSProtocolFromString` answers nil". That is false on a host and was
replaced with the measurement above. The protocol name resolving is not evidence that the port
vends the protocol; the class query and the port's own class set are what answer for the port.

### The factory is vendored, and it answers nil

The two factories are `-[MTLFunction newArgumentEncoderWithBufferIndex:error:]` and its
reflection-taking twin (`MTLLibrary.h:156-169`), and the port **implements both** at
`Metal/CharonMetalLibrary.m:113` and `:118`, each a `return nil`. That is deliberate and is
recorded in the source: a missing method *raises* on call, while a method that answers nil is a
call that *returns*, so a caller that probes gets a value instead of a crash.

This is a **source fact, not a measurement**, and the case says so rather than implying
otherwise: `CharonMetalFunction` is implemented in the same object as the library, which
references `CharonMetalDevice`, and that object needs EAGL context headers this host case does not
carry — so the call could not be made here without adding a fake to link against, and a fake was
not added.

**Plan, still owed:** the encoder needs an argument-buffer facility first — a buffer of argument
buffers on the device — and only then an encoder that binds a resource at an index into one,
replacing the nil the factories return today. The bindings above are the description such an
encoder would read, which is why they were worth carrying first.
