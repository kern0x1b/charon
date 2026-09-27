# ModelIO on iOS 6: the asset, the mesh, the material, the voxel

Measured 2026-09-27 for `registry/ModelIO/ios9asset.json` (359 rows: 50 classes, 157 methods, 152
properties) and the three classes of `registry/ModelIO/ios9.json`.

## The wall this runs into

iOS 6 carries no ModelIO at all. The 6.1.3 armv7 dyld cache holds no `MDLAsset`, no `MDLMesh`, no
`MDLTexture` and no `MDLVertexDescriptor`: `~/.charon/dyld/6.1.3/selectors_armv7.txt`, the release's
whole selector table, has no `vertexAttributeDataForAttributeNamed:`, no `faceVertexIndices`, and no
selector of any of the classes below. The framework arrived in iOS 9. So there is nothing on the
release to answer with, and the work is building it.

`MDLVertexDescriptor`, `MDLVertexAttribute` and `MDLVertexBufferLayout` were already carried, in
`MetalKit/MDLVertexDescriptor9.m`, for MetalKit's vertex-descriptor bridge; `VertexDescriptor.md`
records that pass and its narrower scope. This pass carries the rest.

## What the port builds

**The object graph.** `MDLObject` is a named node with a transform, a set of components keyed by the
protocol each of them answers to, and children. `addChild:` and a container reached through
`children` both make the child's `parent` this object, `path` is the slash-separated chain of names
from the root, and `boundingBoxAtTime:` is the union of the boxes of the children, each of them
brought into this node's own space by the transform of the whole chain above it. A node with no
children has the zero box.

**The transform.** `MDLTransform` holds a real `matrix_float4x4` and its samples, and reads the
translation, rotation, shear and scale back off that matrix in the order the header describes: the
rotation is a product of the three axis rotations in X, Y, Z order, and the shear is read off the
normalised basis. A sample set at a time already held replaces that sample rather than standing
beside it, and a time before the first or after the last sample falls on the first or the last, as
every animated value here and on the host reads there. `MDLTransformStack` is the product of the
operations it holds, in the order they were added; each operation reads one animated value and turns
it into a matrix, and the value is findable by the name the operation was added under.

**The animated values.** One shape behind all of them: a time and up to sixteen components, held in
order, with linear or constant interpolation between two samples. Every concrete class converts to and
from its own type at that boundary and nothing else. `precision` is double only once a double has
been set, which is what the header's own default of float means.

**The mesh.** A vertex buffer of real interleaved bytes - position, normal, texture coordinate at
twelve, twelve and eight - with a descriptor saying where each sits and a submesh over the indices.
`boundingBox` is read off the positions, not stored. `vertexAttributeDataForAttributeNamed:asFormat:`
gives the same bytes back when the format is the one stored and reads them component by component
into a new buffer when it is not, using each format's own component width read off its bit range.
`indexBufferAsIndexType:` re-reads the indices at the depth asked for rather than reinterpreting the
bytes, which is what a 16-bit and a 32-bit index mean by the same number. The generators - plane,
box, ellipsoid, cylinder, cone - lay down real vertices, real normals and real texture coordinates,
with the caps and the quads asked for. The icosahedron, the hemisphere, the capsule, the
subdivision, the tangent basis and the unwrapped texture coordinates are **not** carried yet.

**The material.** A real set of named properties. The value a property is given decides its type, and
every value spelling reads that same value: a `float3` read back as `float4` is the three components
and a one, which is what a renderer wants from a scalar. `luminance` is the Rec. 709 weighting of a
colour, of a float, or of the first components of a vector. A physically plausible scattering
function carries the eight properties of the older one plus the eleven of its own, and its version
is 1.

**The texture.** A real block of texels. `texelDataWithTopLeftOrigin:` and
`texelDataWithBottomLeftOrigin:` are the same bytes with the rows flipped, `imageFromTexture:` is a
CGImage for the 8-bit channel counts CoreGraphics reads - and **nil** for any other encoding, which
is a real answer rather than a picture of something else. `writeToURL:` goes through ImageIO.

**The asset.** `-initWithURL:` reads the file the URL names:

- **Wavefront OBJ** - `v`, `vn`, `vt`, `f` with `o` and `g` opening an object and `usemtl` a
  material. Corners that name the same position, normal and texture coordinate are one vertex, so the
  file's own sharing of its vertices is the sharing the mesh has. A face of n corners is n - 2
  triangles. A vertex the file gives no normal for is given the sum of the normals of the faces that
  meet there, and a direction of no length is the Y axis, so a face of a mesh that names no normals
  still points where the file's own winding says it points.
- **Stanford PLY** - the ASCII and the binary little-endian form, and a header whose elements and
  properties are read as the header states them, so a property the port does not know is skipped by
  its own size. A face list is fanned into triangles as the object format is.
- **ASCII Universal Scene Description** - a `def Mesh` prim's `point3f[] points`, `int[]
  faceVertexCounts` and `int[] faceVertexIndices`.

`canImportFileExtension:` answers yes for exactly those three, and `canExportFileExtension:` answers
no: nothing the port reads is written back out yet, and `exportAssetToURL:` says so with an error
rather than writing a file that is not the asset. `exportAssetToURL:` and
`canExportFileExtension:` are the two rows registered here that answer "not yet" - they are present
and honest, which is what the rule asks for, but a caller that exports gets no file.

**The voxel array.** A box of space divided into cubic voxels and a set of which are filled. The
index of a voxel is where it sits in that division, the data behind it is read voxel by voxel, the
index of a point in space and the point at the centre of a voxel are the two directions of the same
division, and `union`/`intersect`/`difference` with another array put the other array's voxels into
this one's space through the two boxes they sit in. `setVoxelsForMesh:` fills every voxel the mesh's
own triangles pass through, widened by the patch radius.

## What is measured, and what is reasoned

- **Measured**: that iOS 6 carries no ModelIO (the release's own selector table and dyld cache, read
  directly). That the port's own code is what answers every row below 7.0 - the gate builds it and
  reads the built libraries' exports and Objective-C metadata.
- **Measured**: the two-process host differential, `tests/backports/host/modelio/`. One probe, built
  twice - once against the framework the host carries, once against the port's own sources with
  `port-support.m` supplying the symbols ModelIO would have exported - so the two never meet in one
  runtime. Each is run over the same input files, which the probe itself writes: one Wavefront object
  with two groups, a quad and a triangle, one polygon file in ASCII and the same one in binary
  little-endian, and one ASCII scene description. Each writes what it computed as canonical text -
  every vertex position, normal and texture coordinate, every index count and geometry type, every
  bounding box, every transform decomposition and stack product, every texel under both origins, every
  material property with its semantic and type, every voxel set operation - and `compare.py` matches
  them by key with the numbers compared to a stated tolerance. The verdict of the run in this tree:
  **242 measurements, 45 the same, 26 different, 196 one side only, at a tolerance of 5e-4.**
- **What that run found, and what came of it.** The first run read **242 measurements, 45 the same, 26
  different, 196 one side only**. The tree now reads **248 measurements, 232 the same, 6 different, 24
  one side only** - 248 because the probe itself was wrong about the box it handed the voxel array and
  that measurement was added once the box was written the way the struct declares it. Every step of
  that was a defect the run found, and every defect is below.
- **Fixed, each found by the run.**
  1. `simd_min` and `simd_max` take a three-element vector and hand the vector straight back on this
     target, so every box grown with them stayed the box it started from. The two ends of a box are
     now taken a component at a time, in one place.
  2. `MDLAxisAlignedBoundingBox` declares **maxBounds first**, so the empty box written as
     `{{+inf}, {-inf}}` put +inf in maxBounds and -inf in minBounds: a box that starts unbounded. It is
     written from outside in now, and the emptiness test that follows it is a test.
  3. The generators wrote their descriptor's attribute offsets as 12 and 24 - the width of the three
     used lanes of a `vector_float3` - while `sizeof(vector_float3)` is 16, so every normal and every
     texture coordinate was read out of the middle of a position. All four generators' boxes now equal
     the system's.
  4. `MDLMesh` and `MDLVoxelArray` answered the union of their children's boxes, which for an object
     with no children is the zero box; they answer their own box now.
  5. The binary PLY branch decoded the whole file as text, and the body of a binary file is not text,
     so it came back nil and read nothing. The header is found in the bytes and decoded on its own.
  6. The Wavefront reader made a mesh per group; it makes one mesh for the file with a submesh per
     group and material, named as the file names them, with the vertices shared across the whole file.
     A corner that names no normal or no coordinate says so, rather than saying "the first one" - the
     fifth vertex of a lid is not the first corner of the face below it. Five vertices where there were
     two, and the same five the system has.
  7. `MDLTransform` decomposed a matrix into its four components; the system keeps the four it was
     given, and answers its accessors from those. A matrix set outright now leaves them where they
     were.
  8. `objectAtPath:` read the first name of the path as the receiver's own; the path is relative to
     the receiver, and the system answers `/root/child` as nil and `/child` as the child.
  9. A node with no box of its own answered the zero box; the system's own empty box is a maximum of
     zero and a minimum of minus one, and that is what the port answers.
  10. The names an operation of a transform stack answers were left in a record that retained nothing,
      so they dangled. The stack owns the names now.
- **The sharing rule of a generator, read off the counts.** The probe now asks the system for the
  vertex and index counts of the same surfaces over twenty sizes - an ellipsoid at five radial and four
  vertical segment counts, a cylinder and a box at two of each - and the rule is in the numbers. For
  the **ellipsoid the port now matches the system exactly at every one of the twenty sizes, vertices
  and indices alike**: the system has four rings of vertices for two rings of quads, five for three and
  eight for six, with the index count of the quads alone, so each pole is a ring of its own and the
  ring past the last ring of quads repeats it. That is what the port emits now.
- **A method the build did not have at all.** The same run found
  `+[MDLMesh newBoxWithDimensions:segments:geometryType:inwardNormals:allocator:]` answering
  *unrecognized selector* on the port while the system answers it: it is in the ledger and it was
  missing from what the port carries. It is there now, over the box the extent form already builds.
- **Still different, four measurements, with both answers beside them.**
  1. **The cylinder's sharing, and a crash.** The system builds the cylinder of eight radial and two
     vertical segments as 47 vertices and 162 indices; the port's first attempt gives 14 and 54, and on
     the **second** cylinder the probe takes an exception and the rest of the sharing table is lost. So
     the cylinder's vertex sharing is still wrong, and something in it throws when a second one is
     built. That is a new defect this measurement found and this pass did not fix.
  2. **The descriptor of a mesh built from buffers.** 31 attributes on the system, one in the port:
     Apple's own internal attributes, which are not a thing a port can read.
  3. **The voxel array's index extent**, and the rule behind it. The probe now builds arrays of 1, 8, 27
     and 64 bytes over boxes of one, two, three and four voxels a side at a voxel size of one and two.
     The system answers `INT_MAX, INT_MAX, INT_MAX` to `-INT_MAX` for the arrays of one and eight bytes
     and `0 0 0` to `0 0 0` for the arrays of 27 and 64, and it answers the same for the same inputs on
     every run, so it is not uninitialised memory - it is a fixed answer that carries no information
     about the division. The port derives the extent from the box and the voxel size, which is the
     documented way to get one, and the two are a named difference rather than a rule to copy.
  4. **The union of two such arrays**, and the difference and the index bytes, all following from (3).
- **The 24 measurements one side has and the other does not, named.** Six are the OBJ submesh lines the
  group model now accounts for - the host names a submesh `solid_red` where the port names the two
  `red` and `lid`, and the host's first submesh holds six indices where the port's holds its own
  range. Nine are the `tri` and `tribin` name and material lines: the system takes a mesh's name from
  its file's stem (`tri`, `tribin`) and names a material a polygon file names nothing `PLY Material`,
  and the port takes neither from the file. Six are the `specular value` line of a material: the
  system carries `specular` as a float and the port as a colour in the older scattering function and as
  a float in the physically plausible one, so the two disagree on the property of the material a
  loaded mesh is given. The last three are the tessellation counts above. **None is a port feature
  the system lacks.**
- **Not measured on the device**: no run on an iPad 2 running 6.1.3 and no run under `xmake emulate`
  went with this pass. What the device adds is the one thing the host cannot answer: that these
  classes' selectors resolve against the release's own runtime and a dylib of the port's loads beside
  them.
- **Reasoned, not measured**: the black-body curve of a colour-temperature swatch, the value noise
  and cellular noise fields, and the cone's slope normal.

- **Named divergences between the two SDK headers**, which is why the probe takes the two spellings as
  a compile-time flag and not as a runtime question: the macOS header's plane generator takes no
  `inwardNormals:` where the iOS one does, and the macOS `MDLTexture` initialiser takes an `isCube:`
  where the iOS one does not.
- **Not measured on the device**: no run on an iPad 2 running 6.1.3 and no run under `xmake emulate`
  went with this pass. What the device adds is the one thing the host cannot answer: that these
  classes' selectors resolve against the release's own runtime and a dylib of the port's loads beside
  them.
- **Reasoned, not measured**: the black-body curve of a colour-temperature swatch, the value noise
  and cellular noise fields, and the cone's slope normal. These are the port's own implementations of
  what the header names; they are not Apple's algorithms and no check here compares them, because the
  host's values for them are Apple's.

## Where the boundary of this pass is

Not carried: `MDLCamera`, `MDLLight` and its three kinds, `MDLTexture`'s sky cube, the scattering
functions' property graph beyond what is here, `MDLMesh`'s subdivision, tangent basis, unwrapped
texture coordinates, ambient-occlusion and light-map baking, `MDLMesh`'s icosahedron, hemisphere and
capsule generators, `MDLVoxelArray`'s coarse mesh and signed-shell conversion beyond the shell
itself, and the six `kUTType*` constants of `MDLTypes.h`, whose string values are not in any cache
held here and were therefore left alone rather than guessed.
