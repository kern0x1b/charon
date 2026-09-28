# The ARSCNView family: what carries, what is a dependency, and what each piece is blocked on

Measured 2026-09-28 in the `api-reality` worktree, for the ARKit series on `cfde59f06`.

## The shape, per band

| band | `SCNView` carried | the family |
| --- | --- | --- |
| 4.3 | no — the row's minimum is 6.0 | dependency |
| 6.1.3 | yes — the port implements the SDK's own class | **writable**, except the two gaps below |
| 8.0+ | native | the same rows |

The port implements the SDK's declared classes rather than declaring its own: `CharonSCN.h:1` is
`#import <SceneKit/SceneKit.h>`, and `SCNView.m` is `@implementation SCNView` carrying
`_OBJC_CLASS_$_SCNView`. So `ARSCNView` compiled against the SDK's SceneKit header subclasses exactly
the port's class, and `ARKitBackports` now names `SceneKitBackports` in its `libraries`.

## The 42 rows

| piece | rows | state |
| --- | --- | --- |
| `ARSCNView` | 1 class + 5 methods + 4 properties | written; **two build defects below** |
| `ARSCNViewDelegate` | 1 protocol + 5 `renderer:` methods | declaration, per `kind=protocol` |
| `ARSCNPlaneGeometry` | 1 class + 2 methods | **blocked** on a SceneKit row that is not implemented |
| `ARSCNFaceGeometry` | 1 class + 3 methods | class and constructors carry; `updateFromFaceGeometry:` is absent by sensor |
| `ARSCNDebugOptionShowWorldOrigin`, `…ShowFeaturePoints` | 2 constants | writable; SceneKit's `SCNDebugOptions` values |
| `ARSKView`, `ARSKViewDelegate` | 9 rows | **dependency** — SpriteKit is not carried |

## The two build defects in `ARSCNView.m`

Both measured, both with a known fix, neither committed:

1. **`@synthesize` is not allowed in a category's implementation**, even on the non-fragile ABI armv7
   has, so the anchor a node stands for cannot be a category ivar on the SDK's `SCNNode`. The fix that
   uses only public API is for the view to hold the pairing itself — an `NSMapTable` from node to
   anchor — and for `anchorForNode:` to walk the parents looking each up, and `nodeForAnchor:` to walk
   the scene the other way. No category, no associated object, no ivar on a class the port does not
   declare.
2. **`-unprojectPoint:ontoPlaneWithTransform:` is `API_AVAILABLE(ios(12.0))`**, so at a 6.1.3 target the
   SDK's declaration is invisible and the selector does not resolve. `ARSCNView` is an 11.0 class with a
   12.0 method on it, so that method belongs in a **12.0 object** beside the other 12.0 API, and
   `ARSCNView`'s 11.0 object declares the class and the 11.0 members. That is the release split, and it
   is the same rule the ARKit objects already follow.

The draft is in `.agent-work/ARSCNView-draft.m`.

## The gap in `ARSCNPlaneGeometry`, settled by the SDK

`SCNGeometry.h:121` and `:135`:

```objc
@property(nonatomic, readonly) NSArray<SCNGeometrySource *> *geometrySources API_AVAILABLE(macos(10.10));
@property(nonatomic, readonly) NSArray<SCNGeometryElement *> *geometryElements API_AVAILABLE(macos(10.10));
```

**Both are readonly, and the only public way to put data into a geometry is
`+geometryWithSources:elements:`, which returns a new object.** So `-updateFromPlaneGeometry:` — an
instance method, which by its name has to update the receiver in place — cannot repopulate a geometry
from ARKit's file: the storage is the SDK's and is not visible there. Apple's own design has the
update living inside SceneKit, where those ivars are.

So this is a SceneKit change and not a SceneKit *row*, and the two ways it can be made are both in
SceneKit's gift: the properties readwrite, or a method that takes a geometry and repopulates it. Either
one is new API on a class the tree implements, so it is the SceneKit band's to add and to measure
against the host's SceneKit — which has these properties writable, since on macOS
`+geometryWithSources:elements:` is the documented way to build one and a caller that mutates in place
does so through SceneKit's own storage.

What is *not* needed any more is the constructor work. All the constructors were the ones the SDK has
declared since 8.0, and the port implements the two ARSCNPlaneGeometry needs:

| constructor | port | registry |
| --- | --- | --- |
| `+geometrySourceWithData:semantic:…:dataStride:` | `SCNGeometrySource.m` | **added** (commit `1f8a5812e`) |
| `+geometryElementWithData:primitiveType:primitiveCount:bytesPerIndex:` | `SCNGeometryElement.m` | **added** (commit `1f8a5812e`) |
| `geometrySources`, `geometryElements`, `+geometryWithSources:elements:` | `SCNGeometry.m` | **added** (commit `bc8ff2c89`) |

Five rows this series has found the port implements and the registry did not carry.

## The earlier gap, superseded

Three SceneKit members it needs: `geometrySources` and `geometryElements` and
`+geometryWithSources:elements:` are implemented by the port and are now rows (`ios8.json`, 70 → 73).
The other two are **not implemented and not in the 16.4 headers either**:

- `+[SCNGeometrySource geometryWithVector:vectorFormat:vertexCount:vectorStride:dataOffset:dataStride:]`
  and the `SCNGeometrySourceFormat` enum — `grep -rhoE "SCNGeometrySourceFormat[A-Za-z0-9]+"` over the
  SDK's SceneKit headers returns **nothing**, so the enum's name cannot be read from them.
- `+[SCNGeometryElement geometryWithData:primitiveType:primitiveCount:bytesPerIndex:dataOffset:]` — not
  in `SCNGeometryElement.m`.

Both are SceneKit rows to add rather than anything ARKit can do, and the first needs the SceneKit band
to tell the format enum's real spelling.

## `ARSCNFaceGeometry`, documented

This device has no TrueDepth, so no face is ever tracked, and Apple's own answer for a device that
cannot is what `+faceGeometryWithDevice:` returns: `nil`. The class and its two constructors are
carried and answer that; `-updateFromFaceGeometry:` is **absent by sensor** — it takes an
`ARFaceGeometry`, which this device's registry does not carry at all, because face tracking needs a
sensor it has not. Labelled documented rather than measured, because there is no device here that has
the sensor to measure it on.

## `ARSKView`: the dependency, with its rows

SpriteKit is **not carried**: no entry among the 43 libraries, no `SpriteKit/` folder, no `SKView` row,
no `SKView.m`. The ladder puts `_OBJC_CLASS_$_SKView` first at **7.0**:

```
7.0  1        7.1  1        8.0  2        9.0  3
```

So `ARSKView`, being declared as `@interface ARSKView : SKView`, is a SpriteKit dependency at every
band. Its nine rows: the class, `anchorForNode:`, `hitTest:types:`, `nodeForAnchor:`, and
`ARSKViewDelegate`'s five `view:` methods. The cause is above and it is for the SpriteKit owner.
