# The CharonMetal objects, which are the port's and not Apple's

Nineteen rows in the registry name a `CharonMetal`-prefixed class: `CharonMetalBlitEncoder`,
`CharonMetalBuffer`, `CharonMetalCommandBuffer`, `CharonMetalComputeEncoder`,
`CharonMetalComputePipeline`, `CharonMetalDepthStencil`, `CharonMetalDevice`, `CharonMetalDrawable`,
`CharonMetalEncoder`, `CharonMetalEventState`, `CharonMetalFunction`, `CharonMetalHeap`,
`CharonMetalLayerState`, `CharonMetalLibrary`, `CharonMetalPipeline`, `CharonMetalQueue`,
`CharonMetalSampler`, `CharonMetalSharedEvent` and `CharonMetalTexture`.

They are this port's own. One page says so for all nineteen because it is one fact about all of them,
and nineteen rows each pointing at a page about something else would be nineteen claims to look
somewhere that does not answer them.

## What they are

Stand-ins for the `MTL` types. The port needs an object to hand back where an application asks Metal
for a device, a buffer or a command queue, and on a release with no GPU to ask, these are what it
hands back. Each is an `@implementation` in `packages/a/apple-backports/Metal/`, and each answers: a
device that reports a registry ID and a name, a buffer with a length, a queue that runs what it is
given.

## Why the ledger says nothing about them

Three separate facts, each checkable:

1. **No SDK header declares any of them.** They are not in `Metal.framework`'s headers, and
   `grep -c CharonMetalDevice coordination/corpus/sdk-26.2-surface.tsv` returns **0**.
2. **The band exports nothing under these names.** They are compiled with hidden visibility -
   `packages/a/apple-backports/xmake.lua:15` sets the package's `-fvisibility=` - so they do not appear
   in the dylib's export list. This is why no row can say `implemented`: that status means the port
   defines the name *and* the band exports it, and a hidden class cannot reach it however many methods
   it defines. `CharonMetalDevice` defines 32 of them, `CharonMetalQueue` 20, `CharonMetalBuffer` 18, and
   the gate still answers "nothing of that name is built" for every one, because it asks the band.
3. **There is no Apple implementation to read.** No dyld cache holds a `CharonMetalDevice`, so there is
   no branch structure, no constant and no return value to port. What these objects answer is the port's
   own model of the GPU-less case, and a row in an SDK ledger has no business claiming to describe it.

So these rows are `ignored`: the ledger records no behaviour for them, and the claim they could have
made - that Metal answers something here - is not a claim anyone can check against Apple.

## Where the real API is

The Metal rows that *are* SDK API are the `MTL`-named ones, and they are adjudicated against what a
held release's body does. The pages for those are the rest of this directory: `Blits.md`,
`Heaps.md`, `ArgumentBindings.md`, `Census.md`, `Absent.md` and the rest. `Census.md` is the count of
what the caches hold; `Absent.md` is what the release does not have.

This page is deliberately NOT one of those. It describes port machinery, and it says so in its title.
