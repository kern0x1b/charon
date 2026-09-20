# air2es

Turns the render functions of a Metal library into OpenGL ES 2.0 shaders, for the iPhone 4S and the iPad 2, whose
PowerVR SGX 543 has no Metal. A `.metallib` holds AIR, LLVM bitcode with Apple's intrinsics and metadata; an
application ships that, not the Metal source, so AIR is what is translated.

    air2es MODULE.bc PREFIX                    one function: PREFIX.vert or PREFIX.frag, and PREFIX.json
    metallib2es.py air2es LIB.metallib OUT     every function of a library into OUT, with OUT/library.json

`air2es` links LLVM (`llvm-config --libs core bitreader`); `tests/backports/host/air2es/run.sh` builds it and holds it to
the fixtures. The Metal backport reads `OUT` when an application asks for `LIB.metallib` and finds `LIB.metallib.es2`
beside it.

## What it writes

The GLSL is ES 1.00, and glslang accepts it as that. `PREFIX.json` says what the runtime has to bind, read from the
function's own metadata: the vertex attributes with the buffer, offset and stride a buffer read by vertex identifier
comes from, the uniforms with the buffer and offset each is loaded from (and the stride between instances when the
index is an instance identifier), the textures, the sizes of textures the function asks for, the varyings (with a
`flat` mark) and the vertex inputs of a vertex descriptor.

`half` becomes `mediump`. The vertex shader ends with `gl_Position.y *= charon_flip`, which the runtime sets to -1 for
a render target that is a texture, since Metal's window has its origin at the top and ES's framebuffer object at the
bottom.

## What it refuses

A function it cannot translate is refused with the reason, and no file is written: control flow across basic blocks,
a texture read in a vertex function (the SGX 543 has no vertex texture units),
integer bit operations, `half` reads from a buffer, dynamic indices into a buffer element, an output to a second
render target (there are no multiple render targets in ES 2.0), texture arrays, cubes, depth textures, sampling with
gradients or an explicit level, sampling with an offset or in pixel coordinates, function constants, tessellation,
compute kernels, and any AIR intrinsic without an ES 1.00 form.

A `flat` varying is interpolated, since ES 2.0 has no flat qualifier; the result is exact where the value is the
same at the three vertices of every triangle, and the JSON marks the varying so a port can tell.
