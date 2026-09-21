# Metal's render API on OpenGL ES 2.0, iOS 8.0

Metal came in iOS 8.0 for the A7 and later. The iPhone 4S and the iPad 2 have a PowerVR SGX 543, which runs OpenGL ES 2.0, and this package gives
Metal's render API over it: the device, the queue, the buffers, the textures, the samplers, the library, the render pipeline, the render
command encoder and the drawable of a `CAMetalLayer`. An application that draws with Metal draws here with the shaders it shipped.

Source: the header of Metal in the SDK of iOS 16.4 for the API and its defaults; the AIR of real applications (a Metal library of iOS 12 and of iOS 16, and
the libraries of iOS 26) for the shaders, read with LLVM; the extensions of the SGX 543 on iOS 6.1.3 from `glGetString(GL_EXTENSIONS)` on a device.

## Shaders

An application ships its Metal library as AIR. `tools/air2es` turns each render function into an ES 1.00 shader and a description of what to bind, when the
application is built, and puts them in a folder beside the library, `NAME.metallib.es2`; `newDefaultLibraryWithBundle:error:`,
`newLibraryWithFile:error:` and `newLibraryWithURL:error:` read that folder. A library given as bytes in memory, and Metal source, have no such
folder and answer an error. The functions the tool refuses (`tools/air2es/README.md`) are not in the library.

## What is done

A vertex function whose inputs come from a vertex descriptor (`[[stage_in]]`) is drawn with the attributes of the descriptor: the formats of bytes and shorts, normalised or not, and of floats, per vertex as vertex arrays and per instance or constant as the value at the element of the draw, each instance drawn on its own. A vertex function that reads its buffers by vertex identifier is drawn with the buffers as vertex arrays, with the stride and offsets the layout
of its structure says; the buffers a function loads constants from are uniforms; a texture is a `sampler2D` and the sampler state sets its filters and
wrapping (clamp to edge, repeat, mirrored repeat); blending, the write mask, culling, the winding, the viewport, the scissor and the blend colour are the encoder's;
`drawPrimitives` and `drawIndexedPrimitives` with 16 or 32 bit indices; a drawable of a layer and a texture as render targets, with the origin of Metal,
the top left, which the port keeps by turning the vertical axis of a target that is a texture; textures of RGBA8, BGRA8, R8 and RG8. Reading a texture back with
`getBytes:` reads the target.

## What is not

* Vertex formats of half floats, 32 bit integers, the packed 10 bit formats and the BGRA one: a pipeline that uses one is refused, since ES 2.0 has no attribute of them. A layout whose step function is per vertex with a step rate other than one, or per patch, is refused too.
* Compute: a compute pipeline answers an error, and the compute encoder answers nil. The graphics of the A5 run no compute functions.
* Depth and stencil: a depth and stencil state answers nil with a line in the log, and there is no depth attachment.
* Multiple render targets, tessellation, texture arrays, cubes, depth and 3D textures, sampling with an offset or gradients, and the function constants
  are not translated, and a function that needs one is not in the library.
* A vertex texture: the SGX 543 has none.
* Instances are drawn one by one; a draw with a base instance is not done.
* A sampler with the address mode clamp to zero or clamp to border, mirror clamp to edge, or with pixel coordinates, answers nil with a line in the log, and a texture
  of another type, pixel format or with more than one sample does the same.
* A `flat` varying is interpolated; it is exact where the value is the same at the vertices of a triangle.
* Nothing waits for the GPU except `waitUntilCompleted`; the handlers of a command buffer run when it is committed, on the thread that commits it.
