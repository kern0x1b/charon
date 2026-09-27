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
- **What that run found, and what was done about it.** Two defects, both fixed: a submesh whose index
  buffer came from a caller with no allocator answered nil from `indexBufferAsIndexType:` instead of
  re-reading its indices, and `vertexAttributeDataForAttributeNamed:asFormat:` reported the width of
  the attribute as the stride between vertices - so every mesh the port's own generators made had a
  bounding box read out of the wrong stride. Six differences are **open** and named here rather than
  papered over:
  1. The OBJ reader makes one mesh per group; the system makes one mesh with a submesh per group and
     material (`solid_red`, `lid`). The port's answer also holds fewer vertices for the same face.
  2. The PLY reader produces **no objects at all**, in its ASCII and its binary form alike, where the
     system produces one mesh of four vertices and two triangles.
  3. `MDLTransform` decomposes a matrix into its translation, rotation, shear and scale; the system
     keeps the four it was given and answers the accessors from those, so `scaleAtTime:` after
     `setMatrix:` of a diagonal matrix is 1, 1, 1 on the system and the matrix's own scale in the port.
  4. The generators triangulate differently: the ellipsoid's vertex and index counts differ, and the
     plane's and the ellipsoid's own bounding boxes come out inverted in the port where the system's
     are the box of the surface.
  5. A material's default properties differ: the system carries sixteen, the port two.
  6. The MDLVertexDescriptor of a mesh built from buffers carries the system's own internal
     attributes, which the port's does not.
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
