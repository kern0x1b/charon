# ld64 (cctools-port, ld64-956.6)

Apple's ld64 from `tpoechtrager/cctools-port`, pinned at `904de2a7` (the `1030.6.3-ld64-956.6` branch tip),
built from source with three patches in `patches/`. It exists because the system `/usr/bin/ld` does not
insert armv7 branch islands, and because `on_fetch` refuses the system linker outright: a toolchain
package is otherwise looked for on the system first, a clean store finds Apple's `ld` under this name and
never builds ours.

`toolchains/apple-ios/xmake.lua` puts this package's `bin/ld` in `-fuse-ld=` for every armv7 device link
a port does, so this is the linker the whole fleet links with.

## The patches

| patch | why |
| --- | --- |
| `libtapi-without-darwin-linker-version-helper.patch` | libtapi builds against a host without `ld`'s linker-version helper |
| `inlined-text-stub-before-search-paths.patch` | use the TAPI file inlined in a `.tbd` before searching the paths |
| `ordinal-for-dylib-that-only-a-reexport-reaches.patch` | the defect below |

## The dylibToOrdinal defect, and what it is

`ld/OutputFile.cpp:5219` `buildDylibOrdinalMapping` gives an ordinal to every dylib in `state.dylibs` and
to every synthetic dylib it makes for a `$ld$previous$` install, and to nothing else. `dylibToOrdinal`
(5211) then asserts when an import proxy asks for a dylib that has no ordinal, and `compressedOrdinalForAtom`
(5344) asserts on the same missing entry. Both are reached from the symbol-table and bind encoders.

The dylib that misses is measured, not guessed: an instrumented build of this same tree, which prints the
dylib and the symbol instead of asserting, names

```
no ordinal for dylib leaf=libobjc.tbd
  path=…/iPhoneOS16.4.sdk/usr/lib/libobjc.tbd
  install=/usr/lib/libobjc.A.dylib  implicit=1 explicit=0 provided=1
```

and the symbols `_objc_getClass`, `_class_getSuperclass`, `_object_getClass`, `_objc_getAssociatedObject`,
`_objc_setAssociatedObject`. The ordinal table already holds `/usr/lib/libobjc.A.dylib` at ordinal 6, held
by the *other* `File` for the same install name, `libobjc.A.tbd`: `InputFiles::addDylib` keys
`_installPathToDylibs` by install path and keeps one file per path, while `InputFiles::searchLibraries`
asks each implicitly linked file it finds there. A second `File` for an install path that is already
loaded owns import proxies and never reaches `state.dylibs`, so it has no ordinal.

The patch repairs the invariant where the encoder needs it: after the ordinal loop, sweep the
import-proxies sections and give such a dylib the ordinal of the dylib already loaded under its install
path (`hasOrdinalForInstallPath`), or a fresh one plus an `_dylibsToLoad` entry so the library the symbol
came from is the one the output loads and binds to. Nothing that linked before changes — measured, not
argued: the 123-object Matter link with `-Wl,-no_implicit_dylibs`, which already worked, comes out
**byte-identical** (`shasum -a 256` `307de01e2d2a454cceb1e4e25a15a1d2a73e114a86dd1b5ea0b3530c38f10d5f`)
from the unpatched and the patched linker, when both write the same output path. Without that flag the
same link aborts unpatched and links patched.

## Reproducing it

The smallest link that aborts, reduced by ddmin from the 123-object `libMatterBackports.dylib` link:

```
clang -target armv7-apple-ios -miphoneos-version-min=6.1.3 -isysroot <iPhoneOS16.4.sdk> -mlinker-version=956.6 \
  -fuse-ld=<ld> -dynamiclib -install_name /usr/lib/charon/org.charon.apple-backports/libMatterBackports.dylib \
  -o out.dylib libCHIP.a src/app/clusters/descriptor/DescriptorCluster.cpp.o \
  -L<libcxx>/lib -lc++ libapple-compat.a -framework Foundation -framework CoreBluetooth
```

one object, no `-lc++abi`, no backports, no `-no_implicit_dylibs`. It aborts in
`compressedOrdinalForAtom`; the full 123-object link aborts in `dylibToOrdinal`, the same missing ordinal.

## The store, and why a rebuild of this package is a fleet event

This recipe has **no digest**: `add_versions("956.6", "6809ba18…")` is a fixed string and nothing hashes
`patches/`, unlike `packages/a/apple-backports/xmake.lua`, which puts a `sources` config hashed from its
own files into the package identity. So a patch added here does not change the install path
`~/.xmake/packages/l/ld64/956.6/aac8ea2d04874dfdbdc0b81f5db2dd03/`, and the fix is invisible until that
directory is rebuilt — and because `toolchains/apple-ios` hands this `ld` to every armv7 link, whoever
rebuilds it changes the linker for every package in the fleet at once. Rebuild it once, deliberately,
under the coordinator. Adding a digest over `patches/` (what `apple-backports` does for its own sources)
would make a changed linker a *different* package instead, which is the better shape and is the
coordinator's call.

`ld64` also has exactly one in-tree dependent, `packages/i/iphoneos-sdk`, which uses it for four `-r`
relocations of `crt1.o`, `crt1.3.1.o`, `dylib1.o` and `bundle1.o`. Everything else reaches it through the
toolchain.
