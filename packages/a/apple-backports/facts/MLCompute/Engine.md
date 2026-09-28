# The engine, and what it cost to choose one

The brief's rule is "reuse before writing": a neural-net engine is not to be hand-written. Three were
named as candidates; this is what was measured about them, what was taken, and what is left.

## ggml 0.25.3, and why

MIT, three C translation units, and its shape is MLCompute's:

| what MLCompute needs | what ggml has | measured |
| --- | --- | --- |
| a graph of nodes over named tensors | `ggml_build_forward_expand` over a `ggml_cgraph` | its header, `include/ggml.h` |
| tensors with a shape and a count | `ggml_new_tensor_4d`, `ggml_set_name`, `ggml_get_data` | ditto |
| convolution, depthwise, strided, padded, transposed | `ggml_conv_2d`, `ggml_conv_2d_dw`, `ggml_conv_2d_sk_p0`, `ggml_conv_2d_ph`, `ggml_conv_transpose_1d` | ditto |
| pooling, normalization, the matrix product, the row gather, the padded write, the sort | `ggml_pool_2d`, `ggml_group_norm`, `ggml_rms_norm`, `ggml_mul_mat`, `ggml_get_rows`, `ggml_set_rows`, `ggml_argsort` | ditto |
| SGD and AdamW over a parameter's moments | `ggml_opt_step_sgd`, `ggml_opt_step_adamw` | ditto |
| an elementwise operator for the activations that take parameters | `ggml_map_custom1/2/3`, with the callback of ours | ditto |

The three it is *not* asked to do: an average pooling, an L2-norm pooling and an upsample. Those three
are composed in MLCompute's own translation unit from the operators above - a mean over a reshaped
window, a root of a sum of squares, a repeat and a reshape - which is using the library and not writing
a second engine. And the activations that take a, b or c go through `ggml_map_custom1` with the formula
out of `Engine.md`, so the framework's own measured arithmetic is in the callback rather than in a
parallel implementation of it.

**It is C.** That is the reason it is preferred over ncnn and XNNPACK here: a C engine reaches an old
release's C runtime, while a C++ one reaches its C++ runtime, which the 4.3 band does not ship and which
this port would then have to stub. ncnn and XNNPACK are the better *kernels* and would give a faster
result; ncnn is also a far larger build and its tensor model is not MLCompute's, and XNNPACK's operators
want their weights pre-packed, which is a poor fit for a program that hands MLCompute descriptors.

## What was measured about it

**It builds for this port's oldest release.** All three translation units compile for
`armv7-apple-ios6.1.3` with the toolchain the gate uses, with `-Os -fvisibility=hidden -fno-exceptions
-fno-rtti` and no warning: `ggml.c`, `ggml-alloc.c` and `ggml-quants.c` each produce an object. The one
thing that has to be got right is that **no `GGML_USE_*` may be named at all**: every backend is behind an
`#ifdef`, so `-DGGML_USE_OPENMP=0` turns OpenMP *on* and the build then fails on a missing `omp.h`, which
is what the first attempt of the recipe did. With none named the library builds its plain C CPU path.

The recipe is `packages/g/ggml/xmake.lua`. It pins the tarball
`ggml/archive/refs/tags/v0.25.3.tar.gz` by its sha256, writes the two macros the library's sources ask
for and its CMake would otherwise generate (`GGML_VERSION`, `GGML_COMMIT`, from
`src/ggml-version.h.in`), compiles the three units and installs `libggml.a` with the five headers
MLCompute includes.

## Two things that cost a day each, and what they were

**The bare `assertion failed!` was a trailing slash.** `xmake -vD` named it -
`packages/g/ggml/xmake.lua:88`, in `on_test` - and everything before it had succeeded: the three units
compiled, `libtool` made the archive, and the log showed every copy. `os.vcp` copies a file *as* its
destination unless the destination names a directory, and xmake spells "this is a directory" as a
trailing slash - which is why `Box2D` and `charon` in the neighbouring recipes end theirs in `.. "/"`.
Without it the five headers became one file called `ggml`, and the test could not find
`include/ggml/ggml.h`. With the slash, and an `os.mkdir` for the include and licences directories, the
install says `ok` and the recipe's own test passes.

**The archive needs five translation units, not three.** The CPU backend's own two carry the convenience
wrappers that `ggml.c` only declares - `ggml_sigmoid`, `ggml_new_f32`, `ggml_set_f32`, the graph
compute - and with only the library's three the archive links with undefined symbols the first time
anything calls one.

**The recipe is landed and wired**: `add_deps("charon@ggml 0.25.3")` and its `archives` entry in
`packages/a/apple-backports/xmake.lua`, and `archives = {"ggml"}` on MLCompute's entry in
`modules/apple/backports.lua`. Both gates build it and link it, in both bands.

## What is not done

**The first mapping is written and compiles, and is not in the tree.** `CharonMLCGraph.mm` maps the
twenty-one activations onto ggml's operators - the ten ggml has an operator for directly, the other
eleven through `ggml_map_custom1` with the measured formula of `Engine.md` in the callback - and it
compiles clean for `armv7-apple-ios6.1.3`. It is held in `.agent-work/` rather than committed because
two things about it are not finished:

1. **it does not compile inside the gate**, and the place to look is named: `modules/apple/backports.lua`'s
   `compile()` adds an archive's `-I` only in its `.mm` branch, and the gate's resolve does report the
   archive, so the trace of that one compile says where the include path goes;
2. **its host differential cannot link the archive directly**, because the archive is compiled
   `-fvisibility=hidden` - deliberately, so the engine is never API of the image that links it. The host
   side of the comparison therefore has to be a dylib built the way the library is and loaded, not a
   program linked against `libggml.a`, which is the same reason a second copy of ggml in a process could
   never bind to this one.

Both are mechanical, and neither is a doubt about the design: the formulas are the measured ones and the
operators are ggml's.

## A note on the machine

Building the package needed a scratch project, and the first attempt of it resolved the *first* `charon`
version the addon recipe names rather than the newest, which installed `charon v0.1.0` and moved the
machine's active addon - the lock hazard `charon AGENTS.md` and `coordination/crutches.md` both name.
It has been put back: the record for `v0.1.0` is out of `~/.xmake/addons/addons.conf`, the directory is
gone, `active` is `v0.8.12` and the gate resolves `charon v0.8.13` again, which is what it resolved before.
The lesson is in the recipe's own build: a scratch project must take the *highest* `add_versions` from
the checkout's addon recipe, exactly as `coordination/build-gate.lua` does, and not the first.
