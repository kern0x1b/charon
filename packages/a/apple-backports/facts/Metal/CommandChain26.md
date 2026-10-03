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

## The three measurements that decide how far the chain goes

The queue, its two device factories and the capture scope over it are **not** in this page, and each of
the three walls is measured rather than assumed. All three are printed by the case above, from Apple's
own side.

**1. A LIVE METAL 4 QUEUE IS POSSIBLE ON THIS MACHINE, so that is not the reason.** The host device
answers `-newMTL4CommandQueue` and the queue's fresh label is nil - both checks in the run above. Saying
this first is what makes the other two visible as what they are.

**2. `-[MTLDevice newCommandQueueWithDescriptor:]` RAISES, IN APPLE'S OWN CODE.**

```
-[MTL4CommandQueueDescriptor disableIOFencing]: unrecognized selector sent to instance 0x...
```

Apple's own queue sends `-disableIOFencing` to the descriptor, and the SDK's own
`MTL4CommandQueueDescriptor` does not implement it, so the framework refuses itself. The descriptor
path has no Apple behaviour to copy even on a device, and this port's `+newMTL4CommandQueueWithDescriptor:`
therefore takes the label and nothing else.

**3. THERE IS NO METAL 4 COMMAND BUFFER TO COMPARE AGAINST ON THIS MACHINE.**

```
-[AGXG16XFamilyCommandQueue_mtlnext beginCommandBufferWithAllocator:]: unrecognized selector sent to instance 0x...
```

The selector is not implemented on Apple's own queue here, so there is no live command buffer, and
therefore none for the encoder, the render encoder or the compute encoder either. **113 rows of the
chain have no host oracle on this machine**, and a port object whose behaviour has no oracle is what the
last three reviews caught.

**4. AND THE PORT'S OWN QUEUE IS AN EAGL OBJECT**, which is a different wall and the reason *this* file
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
