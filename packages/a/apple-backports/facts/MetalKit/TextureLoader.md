# MTKTextureLoader and MTKMesh, iOS 9

Part of the Tier 2 Metal/MetalKit verdict. What the 18 rows this file once carried as `absent` are
now implemented, and what they do, is written down here rather than left to the row text.

## MTKTextureLoader

Loading a texture from image bytes needs no GPU driver beyond what this port's own
Metal-over-OpenGL-ES-2.0 device already does for real: `-newTextureWithDescriptor:` and
`-replaceRegion:mipmapLevel:withBytes:bytesPerRow:` both already exist in `CharonMetalDevice.m`/
`CharonMetalTexture.m`.

`-initWithDevice:` keeps the device. Every loading method (`newTextureWithCGImage:`,
`newTextureWithData:`, `newTextureWithContentsOfURL:`, `newTextureWithName:scaleFactor:bundle:`,
their array and completion-handler forms) funnels through one real pipeline: decode the source
into a `CGImageRef` (via `UIImage` for data/URL/name forms, direct for the `CGImage` form), draw it
into a `CGBitmapContext` to get real RGBA8 pixels, build an `MTLTextureDescriptor` at
`MTLPixelFormatRGBA8Unorm` or, when `MTKTextureLoaderOptionSRGB` is set, `MTLPixelFormatRGBA8Unorm_sRGB`,
create the texture through the device, and upload the pixels with `-replaceRegion:...`. A failure
at any step (no image, zero-sized image, no bitmap context, device refuses the texture) answers a
real `NSError` in `MTKTextureLoaderErrorDomain`, never a silent nil with no explanation.

The options are read, and each does what `MTKTextureLoader.h` says it does. The eleven constants are
the port's own strings, each spelled as its own name, which is what a caller passing the name it read
out of the header needs (`MTKTextureLoader.h:44` and its siblings).

- **Origin** (`:102`) and its three values. `FlippedVertically` (`:123`) "always" flips;
  `TopLeft` (`:109`) and `BottomLeft` (`:116`) flip only if the file's metadata says the origin is
  top-left. A `CGImage` carries no origin - there is no flag on it for where row 0 is - so for the
  two conditional origins the caller's choice *is* that metadata, and the loader takes it at its word:
  `TopLeft` flips, `BottomLeft` does not, which is the whole difference between them. A flip is the
  rows swapped end for end (`CharonMTKFlipRows`), not a mirror, because the destination is a GLES
  texture whose row 0 is the bottom one.
- **TextureUsage** (`:62`), **TextureCPUCacheMode** (`:69`) and **TextureStorageMode** (`:76`) are
  set on the port's real `MTLTextureDescriptor`, each as the header defines it: the texture "will be
  created with" the value the NSNumber carries.
- **AllocateMipmaps** (`:40`) and **GenerateMipmaps** (`:47`) are the mipmapped flag of the
  descriptor. What the port builds is stated rather than overclaimed: `MTLTextureDescriptor`'s
  factory sets `mipmapLevelCount` to 1 whatever it is handed (`MTLTextureDescriptor8.m:14`), so the
  levels built are the device's one, and this file does not claim a mip chain the port does not have.
- **CubeLayout** (`:86`) with **CubeLayoutVertical** (`:93`), the only layout the header declares. The
  layout is read and checked, and a cube layout offered with a single image is refused with an
  `NSError` in `MTKTextureLoaderErrorDomain` saying so - a cube layout names six faces arranged
  vertically in one texture, and one image is not six faces. It is not silently turned into a 2D
  texture and called a cube.

## MTKMesh

`MTKMesh` itself is real and LOAD-FAIL-safe, and its three supporting types are now carried too, in
`MTKMeshBuffer9.m`. `MTKMeshBufferAllocator` takes the device its header says it is for -
"Initialize the allocator with a device to be used to create buffers", the designated initializer -
and answers `MDLMeshBufferAllocator`'s `newZone:`, `newZoneForBuffersWithSize:andType:`,
`newBuffer:type:`, `newBufferWithData:type:` and the two `newBufferFromZone:` forms. A zone is one
`MTLBuffer`, which is what `MTKModel.h` describes: "A single MetalBuffer is allocated for each zone.
Each zone could have many MTKMes", and a buffer carved out of one is a window at its own offset, so
"Many MTKMeshBuffers may reference the same buffer, but each with it's own offset". A buffer that
does not fit its zone answers nil, as that protocol's own words require ("Returns nil the buffer
could not be allocated in the zone given"). `MTKMeshBuffer` has no `-init`, because the header makes
it `NS_UNAVAILABLE` with the reason "Only an MTKMeshBufferAllocator object can initilize a
MTKMeshBuffer object", and it answers `fillData:offset:` - which "Will not write beyond length of
this buffer" - and `map` over the port's CPU-resident bytes. `MTKSubmesh` carries the mesh, the
submesh index, the vertex and index ranges and the index and primitive types.

What is still walled is `MTKMesh`'s own construction, and it is walled at `MDLMesh`, not at
`MTKMesh`. Both its initializers (`-initWithMesh:device:error:` and
`+newMeshesFromAsset:device:sourceMeshes:error:`) require a real `MDLMesh` (a geometry/submesh
object model: vertex buffers, submeshes, bounding box, procedural generators) or a real `MDLAsset`
(a file-format importer) respectively. This pass carries `MDLVertexDescriptor` - a plain layout
description with no dependency on either - but not `MDLMesh` or `MDLAsset`, which are a
substantially larger, separate ModelIO object model. Both initializers therefore answer nil with
an `NSError` in `MTKModelErrorDomain` naming exactly this: "this port does not carry MDLMesh".
`vertexBuffers`/`submeshes` answer empty arrays and `vertexDescriptor` a fresh default rather than
crash, though in practice no instance is ever produced by a successful initializer to call them on.
