# The top of the Metal 4 command chain, and the three measurements that decide how far it goes

Six rows: `MTL4CommandQueueDescriptor` and its two members, `MTL4CommandBufferOptions` and its one,
and `MTL4CommandQueueErrorDomain`. They are plain data holders, they are in
`Metal/MTL4CommandChain26.m`, and every default is Apple's own.

## The commands and their output

```
sh tests/backports/host/metal-census/chain26.sh
```

```
the top of the Metal 4 command chain, against Apple's own objects:
  the port's descriptors are DEFINED in the binary, under their renamed names
  ok   the control: ZZZNoSuchNameCharonR16 is not a class of this framework
  ok   the control: ZZZNoSuchNameCharonR16 is not a symbol of anything loaded
  ok   MTL4CommandQueueErrorDomain resolves to a string
  ok   MTL4CommandQueueErrorDomain -> MTL4CommandQueueErrorDomain
the two descriptors, fresh, on both sides
  ok   queue descriptor: label is nil on both sides
  ok   queue descriptor: feedbackQueue is a member on both sides
  ok   queue descriptor: feedbackQueue is nil on both sides
  ok   queue descriptor: the label is a copy, so changing the caller's string changes neither
  ok   queue descriptor: a copy carries the label each side holds
  ok   buffer options: logState is nil on both sides
  ok   buffer options: APPLE's copy carries the member, which is nil here
  ok   buffer options: the PORT's copy carries it too, which is nil here
AND WHY THE QUEUE IS NOT IN THIS CASE, measured from Apple's side
  ok   this machine has a Metal device
  ok   APPLE's device answers -newMTL4CommandQueue, so a live queue is possible here
  ok   and its fresh label is nil, which is the queue's own measured default
  ok   APPLE's own -newCommandQueueWithDescriptor: RAISES here: -[MTL4CommandQueueDescriptor disableIOFencing]: unrecognized selector sent to instance 0x...
  ok   APPLE's own queue does not implement -beginCommandBufferWithAllocator: here: -[AGXG16XFamilyCommandQueue_mtlnext beginCommandBufferWithAllocator:]: unrecognized selector sent to instance 0x...
14 checks
all checks passed
the control: a mutation that does not compile is RUN FAILED, not red
  ok   RUN FAILED: the broken mutation did not build, and the compiler said why
  ok   and no binary was left to run
the mutations: one per thing the port decides here
  red    queue descriptor: the label is a copy, so changing the caller's string changes neither
  red    queue descriptor: a copy carries the label each side holds
chain26: the differential is green, the control is RUN FAILED, and both mutants are red
```

## RETRACTION: two of the three walls in the first version of this page were my own probe's mistakes

The first version of this page reported three walls that stopped the Metal 4 command chain. **Two of
them were wrong, and they were wrong because the probe asked the wrong objects.** Both are retracted here
and the corrected measurement is in the table below.

**RETRACTED 1: "`-[MTLDevice newCommandQueueWithDescriptor:]` raises, in Apple's own code."** That
selector is **Metal 3's** factory. Metal 4's is `-[MTLDevice newMTL4CommandQueueWithDescriptor:error:]`
(MTLDevice.h:1271), and **it answers with a queue and no error when given a real
`MTL4CommandQueueDescriptor`** - measured:

```
   newMTL4CommandQueueWithDescriptor:error: (a REAL descriptor) -> a queue, error (nil)
```

What raises is Metal 3's `newCommandQueueWithDescriptor:` handed a **Metal 4** descriptor: Apple's Metal 3
queue sends `-disableIOFencing` to it, which the 26.2 descriptor does not have. So the exception was
never Metal 4 refusing anything; it was my probe handing a Metal 4 object to a Metal 3 call.

**RETRACTED 2: "there is no Metal 4 command buffer to compare against on this machine."**
`-beginCommandBufferWithAllocator:` is a method of **`MTL4CommandBuffer`** (MTL4CommandBuffer.h:71), not
of the queue, and the probe sent it to a queue - where it is trivially absent, because it is not that
object's method. The buffer comes from `-[MTLDevice newCommandBuffer]` (MTLDevice.h:1278) and the
allocator from `-[MTLDevice newCommandAllocator]` (MTLDevice.h:1240). Asked properly, **the whole live
chain exists on this machine**, and it is in the table.

What survives is the fourth wall, which was never about Apple's answers at all: the port's own queue and
everything under it are EAGL-backed, and `OpenGLES/EAGL.h` is a device framework, so no **host** case can
build them. That is why the oracle is a captured table and the port's chain is verified on the device.

## The expectations table, and how to regenerate it

`tests/backports/host/metal-census/chain-expectations.txt` is Apple's own output, committed. It is
produced by a script, so a future SDK that changes an answer shows up as a **diff on the table** rather
than as a claim in a commit message:

```
sh tests/backports/host/metal-census/chain-oracle.sh > tests/backports/host/metal-census/chain-expectations.txt
```

The port's chain is checked against that table by a HOST-FREE case on the device or in the emulator, and
every row whose answer depends on the GPU is recorded as a difference rather than asserted - see the
last section.

**THE TABLE REGENERATES BYTE FOR BYTE, and that had to be arranged**: Apple's `-description` carries the
object's ADDRESS, so a table built from it differed on seven lines every run and `git diff` on the
committed table was always dirty - which is the one thing a table in a repository must not be. Every
object in it prints as `<ClassName>` and never as a pointer. Verified by running it twice:

```
$ sh tests/backports/host/metal-census/chain-oracle.sh > /tmp/exp2.txt && \
    diff tests/backports/host/metal-census/chain-expectations.txt /tmp/exp2.txt && echo IDENTICAL
IDENTICAL on a second run
```

### What the live chain answers on this machine

```
the device: Apple M4 Pro
ZZZNoSuchNameCharonR16 -> nil (right)

MTL4CommandQueue, both ways the 26.2 header declares them
   newMTL4CommandQueue -> <AGXG16XFamilyCommandQueue_mtlnext>
   a fresh queue's label              -> (nil)
   its device                         -> <AGXG16SDevice>
   newMTL4CommandQueueWithDescriptor:error: (a REAL descriptor) -> a queue, error (nil)

MTL4CommandAllocator, MTLDevice.h:1240
   newCommandAllocator -> <AGXG16XFamilyCommandAllocator_mtlnext>
   label                              -> (nil)
   device                             -> <AGXG16SDevice>

MTL4CommandBuffer, MTLDevice.h:1278
   newCommandBuffer -> <AGXG16XFamilyCommandBuffer_mtlnext>
   a fresh buffer's label             -> (nil)
   device                             -> <AGXG16SDevice>
   commandQueue                       -> not a member of AGXG16XFamilyCommandBuffer_mtlnext
   status before begin                -> not a member of AGXG16XFamilyCommandBuffer_mtlnext

beginCommandBufferWithAllocator:, MTL4CommandBuffer.h:71
   beginCommandBufferWithAllocator: answered without raising
   status after begin                 -> not a member of AGXG16XFamilyCommandBuffer_mtlnext

the two encoders
   renderCommandEncoderWithDescriptor: -> (nil)
   computeCommandEncoder -> <AGXG16XFamilyComputeContext_mtlnext>
   compute encoder label              -> (nil)
   compute encoder commandBuffer      -> <AGXG16XFamilyCommandBuffer_mtlnext>
   compute pushDebugGroup: answered
   compute popDebugGroup: answered

endEncoding on each encoder that exists, then endCommandBuffer
   compute endEncoding answered
   endCommandBuffer answered
   status at the end                  -> not a member of AGXG16XFamilyCommandBuffer_mtlnext

and the queue's commit, which is NOT ASKED and why
   -[MTL4CommandQueue commit:count:] with an ENDED buffer: Segmentation fault in Apple's
       own framework, measured (exit 139) - so the row is recorded as not answerable
       rather than measured, and the port refuses it instead of calling through
```

Three of those lines are answers a reader would not guess, and two of them are absences:

* **`MTL4CommandBuffer` HAS NO `status` AND NO `commandQueue` MEMBER.** Measured with
  `respondsToSelector:` first, after a `valueForKey:@"status"` raised `NSUnknownKeyException` and killed
  the first run - so the port's buffer must not grow either, and its status is whatever the queue's commit
  leaves rather than a property of its own.
* **`renderCommandEncoderWithDescriptor:` ANSWERS nil for a fresh `MTL4RenderPassDescriptor`** - no
  attachments, no exception. That is the shape the port has to match.
* **`commit:count:` SUCCEEDS, ON BOTH PATHS, IN A PROCESS OF ITS OWN.** This row was wrong twice before
  it was right, and both corrections are the coordinator's.

  **The first mistake: the C array.** `commit:(const id<MTL4CommandBuffer> _Nonnull[_Nonnull])commandBuffers`
  (MTL4CommandQueue.h:231) declares an array of buffers, and `commit:count:` passed ONE buffer where an
  array was expected, so the framework read the object's own memory as the array's first element. The
  Segmentation fault that produced was mine, and the "this row is not answerable" conclusion that came
  with it went with it.

  **The second mistake: `fork()`.** The re-measurement forked a child from a process that already held a
  device, a queue, an allocator and a buffer. **Metal is not fork-safe**, so a signal from such a child
  says something about the fork and nothing about the commit - and the signal was 11, where an assertion
  would have been 6 (SIGABRT).

  **The third thing was worse than either: a fabrication.** That version printed a line beginning
  `Assertion failed:` and naming `IOGPUMetal4CommandQueue.mm, line 360` **from a fixed string, on any
  signal**. Apple's words, typed by me, presented as a capture. It is deleted; `grep -c "Assertion failed"`
  over the case is 0. A printed imitation of a measurement is worse than no answer, because it survives
  review as data.

  **THE MEASUREMENT, in a process EXECed on its own** - `sh tests/backports/host/metal-census/chain-commit.sh`,
  which is the shape `descriptors26-samplebounds.sh` uses for the same reason. Apple's documented sequence
  runs there in one process per form, with the allocator a local that outlives the commit and is read
  after it, and **both of the process's streams and its exit status are recorded as they are**:

  ```
  ===== form ended =====
  | chain-commit: form ended, process 53532
  |   the device: Apple M4 Pro
  |   allocator AGXG16XFamilyCommandAllocator_mtlnext, queue AGXG16XFamilyCommandQueue_mtlnext, buffer AGXG16XFamilyCommandBuffer_mtlnext
  |   beginCommandBufferWithAllocator: answered
  |   endCommandBuffer answered
  |   about to call: id<MTL4CommandBuffer> list[1] = { buffer }; [queue commit:list count:1];
  |   commit:count: returned
  |   the queue has no -waitForCommandBuffers:, so nothing was waited on
  |   the allocator is still alive after the commit: yes
  | chain-commit: form ended reached the end of main
    the process exited 0

  ===== form open =====
  | chain-commit: form open, process 53540
  |   ... the same, with endCommandBuffer DELIBERATELY NOT CALLED ...
  |   commit:count: returned
    the process exited 0
  ```

  So: **a Metal 4 commit returns, on the header's own path and on the un-ended one alike, and the process
  finishes.** Nothing is raised, nothing is asserted, and stderr is empty in both forms.

  **AND THERE IS NO QUEUE-LEVEL WAIT FOR COMMAND BUFFERS**, which the same run shows: the queue has no
  `-waitForCommandBuffers:`, and `MTL4CommandQueue.h` agrees - its only waits are
  `-waitForEvent:value:` (:274) and `-waitForDrawable:` (:308). That is a real fact about Metal 4 and it is
  the reason the port's queue needs no such member.

## The three measurements the first version gave, and what stands of them

The queue, its two device factories and the capture scope over it are **not** in this page, and each of
the three walls is measured rather than assumed. All three are printed by the case above, from Apple's
own side.

**1. A LIVE METAL 4 QUEUE IS POSSIBLE ON THIS MACHINE, so that is not the reason** - this one stands, and
it is now the first row of the table above.

**2. RETRACTED - see the retraction above.** Metal 4's descriptor factory answers with a queue and no
error. What raises is Metal 3's factory handed a Metal 4 descriptor.

**3. RETRACTED - see the retraction above.** The live command buffer, allocator, compute encoder and the
whole path down to `endCommandBuffer` exist and are measured in the table.

**4. AND THE PORT'S OWN QUEUE IS AN EAGL OBJECT, which stands**, which is a different wall and the reason *this* file
holds only the two descriptors: the queue is a wrapper over the port's `CharonMetalQueue`, which holds an
EAGL context over OpenGL ES 2.0, and `OpenGLES/EAGL.h` is a DEVICE framework. That is why
`MTL4CommandChain26.m` does not import `CharonMetal.h` - a host case that `#include`s the file could not
compile it - and why the two descriptors, which hold only values, are measurable while the queue is not.

So the six rows here are the ones whose behaviour can be checked against Apple's own objects, and the
queue with the rest of the chain waits for a decision about how an EAGL-backed object is verified. Each
of the six rows' `effect` says that.

## One harness defect worth naming, because it is the purest form of the control's trap

The control that proves "a mutation that does not compile is RUN FAILED, never red" first named its
scratch file `broken.m.tmp`. **clang does not recognise a `.tmp` extension as a source file**: it
compiled nothing, reported success, and the control passed because no compiler ran. The scratch is
`broken.m` now, and the control also requires an `error:` line in the log - a control that fails because
nothing ran is the same defect as one that fails for the wrong reason.

## Two more, both in the assertions rather than the code

* **A COPY CARRIES WHAT THE DESCRIPTOR HOLDS.** The case first compared a copy against the caller's
  *mutated* string; measured against Apple's own object the copy reads back the label as it stood when it
  was set. The assertion was wrong and the measurement corrected it, and each side's copy is now compared
  to that side's own descriptor.
* **`dlsym` READ THE ADDRESS OF A VARIABLE AS AN OBJECT POINTER.** The error domain's value was first
  fetched with `dlsym` and `[(__bridge id)symbol description]`, which is a Bus error before any output at
  all. It is declared through an asm label now, which reaches the exported variable itself.

## The port's queue, and what is still unverified about it

`Metal/MTL4CommandQueue26.m` carries the Metal 4 queue: the class itself, the device's two factories
and the capture scope over one. It is a **separate file from the two descriptors** because it imports
`CharonMetal.h`, which reaches `OpenGLES/EAGL.h` — so the descriptors are host-measurable and this is
not, and the split is the honest shape of the thing:

```
$ clang -target arm64-apple-macos26.0 ... -fsyntax-only MTL4CommandChain26.m   -> builds on a host
$ clang -target arm64-apple-macos26.0 ... -fsyntax-only MTL4CommandQueue26.m   -> does NOT build on a host, as it must not
```

Both files compile for the device with **0 diagnostics**.

**The queue is the port's own `CharonMetalQueue` under a Metal 4 name.** There is one queue in this port
and it is the one that holds the EAGL context every draw goes through, so a Metal 4 caller asking for a
Metal 4 queue gets the queue that works. `device` answers the port's shared device — the same answer a
Metal 3 caller gets — and `label` is nil on a fresh queue and copied when set.

**`commit:count:` COMMITS rather than refusing**, through to the queue underneath, and the C array is
spelled as MTL4CommandQueue.h:231 declares it. That is the row whose three earlier answers were all
wrong, and the measured answer is that the call returns.

**Every other member of the protocol is refused by name**: the residency sets, the sparse buffer and
texture mappings, and the event and drawable waits and signals. Each names the facility it would need —
a residency set, an `MTLHeap`, an `MTLEvent`, a drawable of the queue's own — and this port has none of
them. **There is no `-waitForCommandBuffers:`**, because Metal 4's queue has none either.

### What is NOT verified, and it is not a small thing

**The device case is WRITTEN AND HAS NOT BEEN RUN.** `tests/backports/device/metalchain-expectations.h`
holds Apple's fourteen measured answers as constants, each naming the header line it came from, and
`tests/backports/device/metalchain.m` holds the port to them — the same shape
`tests/backports/host/metalblit/` records into `tests/backports/device/metalblit-expectations.h`.

It has not been run because **no device is attached** (`idevice_id -l` prints nothing) and I did not
start an emulator run: a gate is using this machine, and an emulator run is a heavy job that goes
through `heavy.sh` and takes a slot from the gate. So the five queue rows carry the honest wording:

> the CHECK against those expectations is the device case `tests/backports/device/metalchain.m` — and that
> case is WRITTEN AND NOT YET RUN, so nothing here claims it green

`Metal/MTL4CommandChain26.m` and `Metal/MTL4CommandQueue26.m` compile clean, the host differential over
the two descriptors is green with its two mutants red, and release-split puts each object in one
release. **What is unverified is the port's queue against the fourteen expectations**, and that is a
device run away.
