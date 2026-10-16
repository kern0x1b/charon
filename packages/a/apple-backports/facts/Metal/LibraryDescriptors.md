# The library's type, install name and function descriptors, iOS 14.0 and later

A library on this port is the translated form of a metallib file: `CharonMetalDevice` loads
`<name>.metallib.es2`, a folder of C and ES that the build made from the AIR, and it refuses a library built
from source or from bytes in memory. A `CharonMetalLibrary` holds one `CharonMetalFunction` per kernel or
shader, each a name, a stage, its translated source and its reflection.

## Measured on the host

`tests/backports/device/library-probe/library.m` builds a library from source on the host, so these answers are
for a library of that kind. The host has no Metal compiler on this machine, so it cannot build a `.metallib`
file to ask the same questions of a file-loaded library. Recorded in
`tests/backports/device/library-probe/host-expectations.txt`:

* **The type is executable** (`library.type=0`, which is `MTLLibraryTypeExecutable`). A library built from source
  holds functions a pipeline dispatches; a dynamic library is the other type, and this port carries none.
* **The install name is `default.metallib`** for a library built from source. This is not nil, which is why the
  install name is owed below and not answered.
* **A descriptor's specialized name is the function's name.** A descriptor that names `fill`, specializes it with
  an int constant at index 0, and gives the specialized name `fill_scale3` returns a function whose `name` is
  `fill_scale3`, of kernel type, with options `0` (none).
* **A descriptor with only a name** returns the library's function of that name, under that name.
* **A descriptor that names no function** returns nil with an error.
* **The completion-handler form** answers the same function and the same error, once, on the handler.
* **The descriptor's options default to `0`**, which is `MTLFunctionOptionNone`.

## What the port does

* **`type`** is `MTLLibraryTypeExecutable`, because the library is the translated form of an executable metallib.
* **`newFunctionWithDescriptor:error:` and its completion-handler form** make the function the library holds
  under the descriptor's name, specialized with the descriptor's constant values. The function is named by the
  specialized name when the descriptor has one, and it answers the descriptor's options from `-options`. A name
  the library does not hold is refused with an error (code 13), as the name form already is.
* **The intersection-function forms** return nil with an error (code 22). An intersection function is for ray
  tracing, and the SGX 543 has no ray tracing, so a library of this device holds none. The device's answer is
  the one that matters; the reasoning is in `coordination/crutches.md`.

## Owed: `installName`

The host answers `default.metallib` for a library built from source. The port's libraries come from a file, and
the install name of a library loaded from a file has not been measured: the host cannot build a metallib file.
Answering `default.metallib` for every port library would be a guess that happens to match one case, so the
member is owed until a file-loaded library is asked on the host.

## Not measured, and where the port side stands

* The port side has not been run. The probe builds its library from source, which the port refuses, so a port run
  of this probe needs a library from a file, which the device run has to supply.
* Non-zero options: the probe asks only `MTLFunctionOptionNone`. The port keeps the options it was given and
  compiles nothing differently for them, so a non-zero value is recorded but its Metal answer is not checked.
* The intersection forms are not asked on the host, because they need a ray-tracing device and a source with
  intersection functions, and the port's device has neither.
