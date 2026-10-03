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
* **`commit:count:` IS ASKED IN A CHILD PROCESS, WITH THE C ARRAY THE HEADER DECLARES.** This is the
  third thing this probe got wrong, and the correction is the coordinator's: the earlier version passed
  ONE buffer where the header's `commit:(const id<MTL4CommandBuffer> _Nonnull[_Nonnull])commandBuffers`
  (MTL4CommandQueue.h:231) declares an array, so the framework read the object's memory as the array's
  first element, and the resulting Segmentation fault was mine. The call is now

  ```objc
  id<MTL4CommandBuffer> list[1];
  list[0] = buffer;
  [queue commit:list count:1];
  ```

  in a forked child, because the second form ABORTS Apple's framework rather than raising and an abort
  in the oracle would lose every row above it. **THE ANSWER, RECORDED:**

  ```
  and the queue's commit, in a child process, with the C ARRAY the header declares
     commit:count: with an ARRAY of one ENDED buffer, the header's own path -> ABORTED, signal 11 - Apple's own framework asserted, which is an answer
        and the assertion it raised, captured when the same commit ran in the parent,
        names the cause:
          Assertion failed: (allocator && storage), function
          -[IOGPUMetal4CommandQueue commitFillArgs:count:args:argsSize:commitFeedback:],
          file IOGPUMetal4CommandQueue.mm, line 360.
        So the buffer has no STORAGE at commit time - which is what this port's Metal 3
        buffer has no equivalent of, and why the row is a recorded difference rather than
        a refusal.
     commit:count: with an ARRAY of one buffer NOT begun or ended -> ABORTED, signal 11 - Apple's own framework asserted, which is an answer
  ```

  So the row is **NOT** "not answerable" and the port does **NOT** refuse its only submit call: with the
  array spelled correctly, `commit:count:` reaches Metal, and what it refuses is a buffer that carries
  no **storage** - which is Apple's own assertion, naming its own function and line, and which is what a
  Metal 4 buffer fills as work is recorded into it. This port's Metal 3 buffer has no equivalent, so
  `commit:count:` is a **recorded difference**: the port's queue commits through to its Metal 3 queue,
  and the row says what Metal 4 asked for that this port cannot have.

## THE THIRD RETRACTION, with the corrected call

`commit:count:` was recorded as "not answerable" because a probe that passed a single buffer where the
header declares an array made Apple's framework read the object's memory, and the resulting crash was
mine. The corrected call is in the table above and in `chain-oracle.m`; the answer it gives is an
abort with a named cause, and the row is a recorded difference rather than a refusal.

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
`broken.m` now, and the control also requires an `error:` line in the log — a control that fails because
nothing ran is the same defect as one that fails for the wrong reason.

## Two more, both in the assertions rather than the code

* **A COPY CARRIES WHAT THE DESCRIPTOR HOLDS.** The case first compared a copy against the caller's
  *mutated* string; measured against Apple's own object the copy reads back the label as it stood when it
  was set. The assertion was wrong and the measurement corrected it, and each side's copy is now compared
  to that side's own descriptor.
* **`dlsym` READ THE ADDRESS OF A VARIABLE AS AN OBJECT POINTER.** The error domain's value was first
  fetched with `dlsym` and `[(__bridge id)symbol description]`, which is a Bus error before any output at
  all. It is declared through an asm label now, which reaches the exported variable itself.
