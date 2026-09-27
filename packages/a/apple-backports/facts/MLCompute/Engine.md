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

## The two things that are not done

**The recipe does not install yet.** `xmake` fails its `on_install` with a bare
`assertion failed!` and no message, before any of the recipe's own checks run - so it is an assertion
inside xmake's own install path, not one of mine, and the log names no line. Everything up to it is
measured: the download succeeds, the tree is where the recipe looks (`source/src/ggml.c`,
`source/include/ggml.h` are both there, and xmake flattens the archive so `os.curdir()` is the install
directory itself), and the three units compile. Finishing it is a matter of bisecting xmake's install
path - the likely suspects are the `os.vcp` of a file into a directory that does not exist yet
(`package:installdir("licenses")`) and the `libtool` invocation, neither of which any other recipe in
this repository does in quite this combination.

**The wiring is not landed, deliberately.** Two lines reach the engine - the `add_deps("charon@ggml
0.25.3")` and the `archives = {ggml = ...}` in `packages/a/apple-backports/xmake.lua`, and the
`archives = {"ggml"}` on MLCompute's entry in `modules/apple/backports.lua`. They are not in the tree,
because a dependency that cannot install would break every band that builds apple-backports. They are
one line each, and they go in as soon as the recipe installs.

## A note on the machine

Building the package needed a scratch project, and the first attempt of it resolved the *first* `charon`
version the addon recipe names rather than the newest, which installed `charon v0.1.0` and moved the
machine's active addon - the lock hazard `charon AGENTS.md` and `coordination/crutches.md` both name.
It has been put back: the record for `v0.1.0` is out of `~/.xmake/addons/addons.conf`, the directory is
gone, `active` is `v0.8.12` and the gate resolves `charon v0.8.13` again, which is what it resolved before.
The lesson is in the recipe's own build: a scratch project must take the *highest* `add_versions` from
the checkout's addon recipe, exactly as `coordination/build-gate.lua` does, and not the first.
