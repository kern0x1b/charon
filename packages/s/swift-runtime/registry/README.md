# What this registry is for, and why it is not in `apple-backports/registry/`

`apple-backports/registry/` describes what the **backports libraries export**. `check_registry`
(`modules/apple/backports.lua`) reads it after every build and fails on an entry that says
`implemented` and names nothing the built dylibs export, with one exception: a protocol or a member
of one, which is never counted as unbuilt.

Every name in *this* directory is a Swift type or a member of one, of a module this package builds
(`libswiftRealityFoundation.dylib`, `libswiftRealityKit.dylib` - these two for a minimum release of 8.0 or later,
see `facts/RealityFoundation/SceneKit.md` - and `libswiftSpatial.dylib`). A Swift
module exports no symbol a dylib inventory sees, so an entry for one of them in
`apple-backports/registry/` is not a record, it is a false claim: it says the backports library
carries a type it does not. CreateML's registry moved out for exactly this reason (its commit
message quotes the gate naming all 51 at once).

So the record of what this package implements lives here, beside the code it describes, and
nothing in it is read by the gate yet: gating Swift-module registries is an infra task, opened
2026-09-27. Until it is, this directory is the record a reader and the corpus's ledger go by, and
it must not be moved into `apple-backports/registry/`, where the gate would name every name in it.

The files:

| file | what it records |
| --- | --- |
| `RealityFoundation.json` | the scene graph, physics, meshes, materials, audio and animation |
| `RealityKit.json` | `ARView`, its environment, its render loop and its gestures |
| `Spatial.json` | the value types, as the ARKit band has built them |

Each entry names the SDK interface the declaration was read from and the measurement behind it. A
row that is **not** in these files is not implemented, whatever the corpus's ledger says about it.

## These rows and the swift-runtime lift sets

They do not touch each other, and the reason is in the recipe rather than in this directory:
`xmake.lua:433` hands `lift()` the **apple-backports** registry (`backported:installdir("share")`), and
`lift/iPhoneOS{16.4,26.2}.sdk.txt` is what that lift leaves alone. Nothing here is read by it — a Swift
module exports no symbol a dylib inventory sees, which is the same reason the rows are kept out of
`apple-backports/registry/`. So adding a row here does not make the committed sets stale, and a series
that only adds rows here owes no re-measure. Rule R4 of `.agents/skills/patch-merge/SKILL.md` §4 fires
on an implemented entry **in the registry the lift reads** that no SDK header declares — a private
class, a stub-only function — and on a change to `modules/apple/lift.lua` itself.

Measured on this series (2026-09-28, on `b74b9a00`): `git diff --name-only cc435f9d..HEAD --
packages/a/apple-backports modules/apple` is empty, `git diff --stat -- packages/s/swift-runtime/lift`
is empty, and `coordination/lift-verify.lua` on this worktree reports `lift_test: 0 failures` with both
sets counted and their headers true.
