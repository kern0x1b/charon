# ModelIO: what is owed, with the measurement that shows it

Every number here was measured by `tests/backports/host/modelio/run.sh` on both sides over byte-identical
inputs. The run states how many differences it expects to still be open, so a green-looking run cannot be
mistaken for a closed one.

## The cylinder generator — indices, not vertices

Five parameter points, the last one held out from the derivation:

| radial | vertical | host vertices | port vertices | host indices | port indices |
| --- | --- | --- | --- | --- | --- |
| 8 | 1 | 38 | 38 | 108 | 144 |
| 8 | 2 | 47 | 47 | 162 | 192 |
| 8 | 3 | 56 | 56 | 216 | 240 |
| 12 | 2 | 67 | 67 | 234 | 288 |
| 5 | 4 | 44 | 44 | 180 | 180 |

**Vertices agree at every point, including the held-out one.** Only the index count differs, and the excess is
exactly

    gap = 2 * (radial - vertical - 1)   triangles

which fits the four derived points and **predicts the held-out point as 0, which is what was measured**.

**The rule is not written**, and the reason is recorded so the next attempt does not repeat it. Subtracting
`2 * max(3, radial)` triangles for the two caps and fitting what is left gives `18v + 2`, which fits the three
`radial = 8` points and fails at `(12, 2)` and `(5, 4)`. So the system's cylinder is **not** this wall plus
two caps of the same kind, and the subtraction premise is false. The host's triangle counts — 36, 54, 72, 78,
60 — are not linear in either variable.

**How to finish it, exactly:** dump the index buffer and each vertex's *y*, then classify each triangle by
whether its three vertices share a `y`: one distinct value is a cap triangle, two is a wall one. That is a
counting of the host's own bytes and needs no arithmetic assumption. It is not done here.

## The generator share rows — the same family

```
  share cylinder r3 v3  vertices agree  host indices  96  port indices  90
  share cylinder r4 v2  vertices agree  host indices  90  port indices  96
  share cylinder r6 v2  vertices agree  host indices 126  port indices 144
  share cylinder r8 v2  host indices 192  port indices 162
  share cylinder r12 v2 host indices 288  port indices 234
```

Vertices agree throughout; the indices differ in **both directions** — 96 against 90 and 90 against 96 — so this
is not one missing fan but a different partition between the wall and the caps.

## A binary USD reader — owed, not a divergence

The system answers `+[MDLAsset canImportFileExtension:]` **1 for every extension except `mdl`**:

```
  obj 1   ply 1   usda 1   usd 1   usdc 1   usdz 1   abc 1   mdl 0
```

so the method describes **Apple's ModelIO**, not what any one reader supports. The port answers from the
readers it has — `obj`, `ply`, `usda` — which is what its own comment says it is for, and the differential
counts that as one difference on `canImport`.

**Scope:** `usd`, `usdc`, `usdz`, read through the extension switch beside `obj`, `ply` and `usda` in
`MDLAsset9.m`. `abc` (Alembic) is answered by the system and is **not** in scope here. Closed when a reader
exists and `canImportFileExtension:` answers those three **from it**, under a differential of its own, not
by adding names to a list.

## The voxel families and the mesh bounds — owed, numbers recorded

```
  mesh min 0.00000 0.00000 0.00000  max -1.00000 -1.00000 -1.00000
  mesh attributes 31
  voxel extent 0 0 0 to 1 1 0
  voxel indices 32 a3bb2e35
  voxels after union 3        voxels after difference 2
  voxrule 1 voxels            voxrule 2 voxels
  voxrule 3 voxels            voxrule 4 voxels
```

Not diagnosed. `voxel indices 32 a3bb2e35` carries what looks like a **checksum**, which points at
determinism rather than at shape; the eight `voxrule N voxels` rows are the same shape of difference four
times over. The mesh bounds report a maximum of **-1** where the minimum is 0, which is a single inverted
comparison worth looking at first.

## The PLY comment rule — owed, and deliberately not encoded

`tri-comment.ply` carries a `#` line inside the face element's data. The system reads it as a point cloud
(12 indices, geometry 0) where the file plainly holds two triangles. Four variants of the same bytes:

| fixture | comment position | system answers |
| --- | --- | --- |
| `tri.ply` | none | 6 indices, geometry 2 — triangle |
| variant A | before the first face | 3 indices — **a face dropped, silently** |
| variant B | between two faces | 6 indices — ignored |
| variant C | in the **header** | 12 indices, geometry 0 — point cloud |

It is **position-dependent, not comment-dependent**, and variant A loses a face without saying so, so no rule
is encoded: copying that would make the port drop faces silently. `tri.ply` is written comment-free so both
sides measure the same file, and the divergence keeps its own fixture.

## Malformed input: the system throws, and the port returns

Measured on a polygon file whose `faceVertexIndices` name a vertex that does not exist:

```
  system:  Bad: face vertex index out of bound.
           *** Terminating app due to uncaught exception 'NSInvalidArgumentException',
               reason: '-[MDLObject submeshWithIndexBuffer:vertexBuffer:vertexOffset:indexCount:indexType:geometryType:material:]'
  port:    charon-usda-bad-index file face=0 id=99 vertexCount=5      then an early return
```

The host's behaviour is deterministic across every run and is a **throw that terminates the process**, not a
warning and not a nil return. The port's is a diagnostic on stderr and a quiet return, which is why the
out-of-range case is still unexercised end to end: the differential's port probe reads the fixtures it
writes itself, so a planted file never reaches the reader.

**Decision, by parity policy: mirror the throw.** A caller that gets a nil mesh back from a malformed asset
will read past it; a caller that gets an exception can handle it. The port should raise
`NSInvalidArgumentException` with a reason naming the file, the face and the index, and the refusal stays
where it is — the arithmetic that produced an index past the end is now fixed, so the guard only ever sees a
genuinely malformed file. **Not done in this series; it is the next one.**
