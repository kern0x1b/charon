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

## The gap in `ARSCNPlaneGeometry`

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
