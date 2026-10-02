# The ModelIO surface the 26.2 headers declare

## Where every number here comes from

Clang's own JSON AST of the 26.2 headers, read two ways:

- `tools/corpus/surface-diff-latest.py --rows` for the class, method and property lists with the ios
  availability on each node;
- a direct `xcrun clang -ast-dump=json -ast-dump-filter=MDL` for the property accessor shape, because
  `--rows` flattens a property to `Class.name` and drops both `readwrite` and `getter=`.

No header is parsed by regex. The first attempt did, and it invented selectors from macros, attributed
159 members to macOS through a 400-character lookahead that swallowed the next declaration's availability,
and found 114 methods where the headers declare 283.

## The classes and methods

66 classes and 276 methods across five objects, one per release band, so that release-split never sees a
file whose members first appear in more than one release. `MDIO150` was written and had zero
implementations in it; the generator now writes no file for a band with nothing in it.

**The member list is the AST's `ObjCMethodDecl` list, not `nm` on the generated objects.** Building it
from `nm` measures the compiler, not the framework: it offered to carry `-[MDLMesh .cxx_destruct]` and
`-[MDLObject allocator]`, and a body for `.cxx_destruct` would have overridden the ARC helper clang
emits for a C++ class. Seven methods are dropped by an NSObject-basics rule and every rule prints its count,
so a rule matching nothing is visible.

Every emitted selector was checked byte-for-byte against the AST's own selector string: **283 methods, 0
mismatches**. That check is what a comparison against my own output cannot do.

## The accessors

405 rows: **259 getters** and **146 setters**, from 259 properties of which 146 are `readwrite`. The
`readwrite` flag is read from the node, not guessed, because guessing produces a row for a setter clang
never synthesises. `getter=` appears on none of ModelIO's properties, so every getter is the property name.

## Reconciled against the ledger, and a retraction

313 of the ledger's 314 methods are declared in the headers, and the AST adds ten the ledger does not
list — `MDLVertexDescriptor`, `MDLVertexBufferLayout` and `MDLVertexAttribute`, all 9.0 — which are
carried because the headers declare them.

**I reported once that 39 methods disagreed with the ledger on their band. There are no such
disagreements**: 274 shared names, 274 agreeing, 0 differing. The 39 came from comparing against a
larger earlier parse and were miscounted as band conflicts. Nothing was routed, and there is nothing to
route.

## What these rows answer, and what they do not

The answers are the honest empties — nil, NO, 0 — for a machine with no GPU, no asset library and no
provider. `MDLAsset` and `MDLMesh` are built for real on the CPU in the commit after this one; nothing in
these 747 rows claims to be a loaded asset or a computed mesh.

## Seven of these rows name protocols, not classes

A 6.1.3 band link refused with `Undefined symbols for architecture armv7` for
`_OBJC_CLASS_$_MDLAssetResolver` and `_OBJC_CLASS_$_MDLLightProbeIrradianceDataSource`, each
"referenced from" a category in MDIO110.o and MDIO90.o. A category adds methods to a class and never
creates one, so the two questions are what the names are and whether they can be carried.

**Neither is a class; both are protocols the 16.4 SDK declares with a body.**

| name | where 16.4 declares it | what it is |
| --- | --- | --- |
| `MDLAssetResolver` | `MDLAssetResolver.h:14` | `@protocol MDLAssetResolver <NSObject>` |
| `MDLLightProbeIrradianceDataSource` | `MDLAsset.h:298` | `@protocol MDLLightProbeIrradianceDataSource <NSObject>` |
| `MDLMeshBuffer` | `MDLMeshBuffer.h:61` | `@protocol MDLMeshBuffer <NSObject, NSCopying>` |
| `MDLMeshBufferAllocator` | `MDLMeshBuffer.h:181` | `@protocol MDLMeshBufferAllocator <NSObject>` |
| `MDLObjectContainerComponent` | `MDLTypes.h:82` | `@protocol MDLObjectContainerComponent <MDLComponent, NSFastEnumeration>` |
| `MDLTransformComponent` | `MDLTransform.h:27` | `@protocol MDLTransformComponent <MDLComponent>` |
| `MDLTransformOp` | `MDLTransformStack.h:26` | `@protocol MDLTransformOp` |

`grep -rn "@interface MDLAssetResolver"` over the SDK's System/Library/Frameworks returns nothing and
`grep -rn "@class MDLAssetResolver"` over the same tree returns nothing, every framework and not
only ModelIO; the same holds for `MDLLightProbeIrradianceDataSource`, whose only
two hits in the whole SDK are the `@protocol` at MDLAsset.h:298 and the consumer at MDLAsset.h:332.
Every consumer in the SDK takes the name protocol-qualified - `id<MDLAssetResolver>` at MDLAsset.h:229,
MDLMaterial.h:385, MDLMaterial.h:393 and MDLTexture.h:86, and
`id<MDLLightProbeIrradianceDataSource>` at MDLAsset.h:332 - so no caller is ever given an instance of
either and there is nothing to instantiate. The tree's own host probe had it right already:
`tests/backports/host/modelio/port-support.m:57` restates `@protocol MDLAssetResolver <NSObject>` with
both methods, and `MDLAsset9.m:24` declares `@property (nonatomic, retain) id<MDLAssetResolver> resolver;`.

The generator's header map is why they were ever mistaken for classes: `tools/corpus/hdr-map.json`
records only `@interface` declarations, and it holds the three concrete resolvers
(`MDLRelativeAssetResolver`, `MDLPathAssetResolver`, `MDLBundleAssetResolver`) and neither protocol.
`CharonModelIO.h` then declared each missing name as `@interface X : NSObject` so a category had
something to attach to, and that is the whole of the failure: **seven** categories on seven such
names emitted seven `_OBJC_CLASS_$_` references and no object in the library defined any of them. The
band link printed two of the seven.

The ios version on each protocol row is clang's, not the generator's: compiled at
`-target armv7-apple-ios6.1.3` with `-Wunguarded-availability`, which names iOS 11.0 for
`MDLAssetResolver` and `MDLTransformOp`, iOS 9.0 for `MDLMeshBuffer`, `MDLMeshBufferAllocator`,
`MDLObjectContainerComponent` and `MDLTransformComponent`, and **nothing at all** for
`MDLLightProbeIrradianceDataSource`, which the SDK annotates with no version - so its row's 9.0 is the
version of the surface it belongs to, `MDLLightProbe` at MDLLight.h:142 being
`API_AVAILABLE(macos(10.11), ios(9.0), tvos(9.0))`.

**Twenty of the twenty-one rows a protocol owns are implemented by a concrete class that conforms to
it**, and one is not: nothing in the 16.4 SDK and nothing in this port conforms to
`MDLLightProbeIrradianceDataSource`, so `sphericalHarmonicsCoefficientsAtPosition:` is adjudicated
`absent` with that reason. Measured by reading every `@implementation` block of this directory and
matching each row's selector against the classes the SDK declares as conforming:
`MDLMeshBufferData` (2 of 2), `MDLMeshBufferDataAllocator` (6 of 6), `MDLObjectContainer` (3 of 3),
`MDLTransform` (4 of 4), `MDLTransformStack` (3 of 3), the eight `MDLTransform*Op` classes (3 of 3),
and `MDLRelativeAssetResolver`, `MDLPathAssetResolver`, `MDLBundleAssetResolver` (2 of 2 each).

The protocols themselves are carried the way `modules/apple/backports.lua`'s `protocol_sources()`
carries every other one: a `kind: protocol`, `status: implemented` row, from which the build writes
`ModelIOBackportsProtocols<release>.m` and clang emits `__OBJC_PROTOCOL_$_<name>` into it.
`CharonModelIOProtocols.h` is the header those generated sources import, and holds forward
declarations only, because every one of the seven is declared with a body by the SDK the package
compiles against and the umbrella import beside them brings the bodies in.

## Owed, and not verified here

The gate's two lists — built without a row, row without a build — have **not** been computed. An earlier
attempt used `nm`, which is wrong: Objective-C methods are not `nm` symbols, only classes are, so it found
10 of 276 and reported 39 rows as unbuilt that are in fact present. A second attempt parsed `otool -ov`,
whose output my pattern matched not at all, so it printed `BUILT WITHOUT A ROW: 0` over a comparison that
had examined nothing. Neither number means anything and neither is claimed. The coordinator's gate closes
the rest in one round.
