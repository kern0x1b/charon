# MTKTextureLoader and MTKMesh, iOS 9

Part of the Tier 2 Metal/MetalKit verdict.

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

The mipmap options (`OptionGenerateMipmaps`/`OptionAllocateMipmaps`), cube layout
(`OptionCubeLayout`/its three origin constants), `OptionOrigin`, `OptionTextureUsage`,
`OptionTextureStorageMode` and `OptionTextureCPUCacheMode` are read by nothing: this port always
loads a single non-mipmapped 2D texture the way the pixels were decoded. A real, stated gap.

`-newTextureWithMDLTexture:...` (both the `error:` and `completionHandler:` forms) is not
implemented at all. It needs a real `MDLTexture` carrying decoded pixel data from ModelIO's own
material pipeline - a different, larger piece of ModelIO than the `MDLVertexDescriptor` this pass
carries (`facts/ModelIO/VertexDescriptor.md`), and out of scope for it.

## MTKMesh

`MTKMesh` itself is real and LOAD-FAIL-safe, but its own construction is genuinely walled - at
`MDLMesh`, not at `MTKMesh`. Both its initializers (`-initWithMesh:device:error:` and
`+newMeshesFromAsset:device:sourceMeshes:error:`) require a real `MDLMesh` (a geometry/submesh
object model: vertex buffers, submeshes, bounding box, procedural generators) or a real `MDLAsset`
(a file-format importer) respectively. This pass carries `MDLVertexDescriptor` - a plain layout
description with no dependency on either - but not `MDLMesh` or `MDLAsset`, which are a
substantially larger, separate ModelIO object model. Both initializers therefore answer nil with
an `NSError` in `MTKModelErrorDomain` naming exactly this: "this port does not carry MDLMesh".
`vertexBuffers`/`submeshes` answer empty arrays and `vertexDescriptor` a fresh default rather than
crash, though in practice no instance is ever produced by a successful initializer to call them on.
