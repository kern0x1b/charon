# PHASEObject

Carried in `libAVFAudioBackports.dylib` (the `avfaudio` config), in `PHASEObject15.m`: a 3D object in
the engine, organised into a hierarchy with relative transforms. Fourteen registry entries.

`AVAudioEnvironmentNode`'s `rootObject` and `PHASEEngine`'s both answer one of these, so it is carried
here rather than the property being `absent`: the SDK declares `@property(readonly, strong)
PHASEObject *rootObject`, and the declared type is what an application sees. The host's concrete class
is a `PHASERootObject` — a framework-internal subclass with no row in the corpus — which is an
implementation detail and not the declared surface.

## The identity is a literal, and the gate is why

`PHASEObject`'s transform is a `simd_float4x4` and both transforms start at the identity, which the
header's own note requires — *"The transform must have orthogonal basis vectors and uniform scale"* — and
which a zeroed allocation is not.

It is written out as a **literal**, not taken from the SDK's `matrix_identity_float4x4`, because the
6.1.3 gate names that as a weak import the release does not export:

```
libAVFAudioBackports.dylib weakly imports 1 symbol the armv7 release it is
checked against does not export, each of which is NULL there and must be
called only behind a check for it: _matrix_identity_float4x4
```

A weak import of a symbol the release lacks is a call through NULL, so the object depends on no symbol
to stand at one.

## The hierarchy

- `initWithEngine:` is the header's `NS_DESIGNATED_INITIALIZER`; `-init` and `+new` are
  `NS_UNAVAILABLE`, and both rows are `absent` with that reason.
- **`addChild:error:` refuses a child that already has a parent**, which is what the header says it
  does: *"Returns an error if the child already has a parent."* An object already in the hierarchy
  cannot be added here without the hierarchy becoming a graph.
- `removeChild:` and `removeChildren` clear the link from both sides, and a child's world transform is
  recomputed.
- **`worldTransform` is the object's own transform composed with every ancestor's** — one matrix
  product, and the whole of what a hierarchy of relative transforms is. A parent's move moves the
  subtree, because the subtree's world transform is derived from it.
- `right`, `up` and `forward` are the class properties the header declares, and the right-handed frame
  it names: right along +x, up along +y, forward along −z.
- `NSCopying`, which the header declares: a copy takes the transform and starts with no children of its
  own, because two objects sharing a children array would both claim the same children.

## The host differential

`tests/backports/host/phase/run.sh` compares the **declared behaviour** and not the class name: that
the port's root is a `PHASEObject`, that it has no parent and no children, and that its transform is
the identity — and that the host agrees about the two of those that are declared behaviour.

## The open item: the harness answers `rootObject` through a class that is not only the port's

The engine's `rootObject` is made, kept, and answered — and the harness still reports it as nil. What is
established, and what is not, so the next reader does not repeat the three measurements:

**Not the rename.** The answering method is the port's own, found by the coordinator's method
(`class_getMethodImplementation` on the object's own class, then `dladdr`):

```
stage asked charon_host_PHASEEngine, imp 0x1023ac108,
    symbol -[charon_host_PHASEEngine rootObject]
```

so it is neither a category elsewhere nor the SDK's, and the port's and Apple's classes are two
distinct classes in the one binary. The breakpoint on it hits.

**Not a weak or unsafe ivar, and not the wrong initializer.** The engine declares the ivar
`PHASEObject *_charon_rootObject;` with no ownership qualifier, and assigns it in
`-initWithUpdateMode:`, which is its only initializer. `@synthesize rootObject = _charon_rootObject;`
binds the property to that ivar and is required by the build's
`-Werror=objc-missing-property-synthesis`; it did not change the harness's answer.

**What the class's ivars say.** Reading the runtime's own ivar list and every slot:

```
stage ivar _charon_unitsPerSecond      at   8  slot 0x3ff0000000000000   <- 1.0, the header's
stage ivar _charon_defaultReverbPreset  at  32  slot 0x724e6f6e             <- 'rNon', the header's
stage ivar _charon_rootObject          at  72  slot 0x755cd20e00           <- a live root
stage ivar _lastRenderTime             at  80  type AVAudioTime
```

Every ivar this port declares is at the offset it should be, holding the value the header documents, and
**the root's slot holds a live object** while the message returns nil. And there is a tenth ivar,
`_lastRenderTime`, typed `AVAudioTime`, which `grep -rn` finds **nowhere** in
`packages/a/apple-backports/`. It is a property of Apple's own 26.0 `PHASEEngine`, whose declared type is
`AVAudioTime`.

`nm` finds exactly one definition of the class, in `PHASEEngine15.m.o`, and the harness binary contains
**no AVFAudio symbol at all**. So the class the runtime answers through carries the port's ivars *and* an
ivar from Apple's `PHASEEngine`. The only mechanism I know that produces that is the port's object and
the framework's agreeing on one class name once the harness renames it — which is a **harness**
defect, not a port one, and is the thing to chase next.

`checks=37 failures=1` until then. No mutant is added for it, because a mutant that presumes the
cause is the mistake this delivery has already made once.
