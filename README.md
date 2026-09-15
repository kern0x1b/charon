# ios6-toolchain

The part of building for armv7 / iOS 6 that is the same for every project: how
to build it at all, without Xcode installed.

Libraries are not here. Each port carries its own recipes and builds them
itself, because ports disagree - this engine wants OpenSSL 3.0.15, the Telegram
port 1.1.1w - and a shared library set would make one of them override the
other. What is shared is only what is true for all of them.

## What is here

    config/settings_user.yml   iOS 6.0 and 6.1, which Conan does not ship
    config/profiles/ios6-armv7 the target: armv7, iOS 6.0, the theos SDK,
                               Cortex-A9 with NEON, and the linker
    config/extensions/hooks/   refuses a missing SDK or a swapped linker
    config/extensions/commands/ serves a checkout's recipes, in the right order
    config/packaging/ios6.mk   the theos settings every package is built with
    tools/sdk-usage.py         which files of an SDK a build actually read
    recipes/ld64/               the linker, built from cctools-port
    recipes/ios6-base/         the base class a port's conanfile extends

## A new machine

    brew install conan cmake ninja ccache llvm
    xcode-select --install

    git clone https://github.com/kern0x1b/ios6-toolchain.git
    conan config install ios6-toolchain/config
    conan ios6-remote ios6 ios6-toolchain

Xcode is not required and does not need to be installed. The Command Line Tools
carry the compiler and the compiler runtime, theos carries the SDK, and the
linker is built from source by the `ld64` recipe.

## A port

Its own `conanfile.py`, its own `recipes/`, its own `conan.lock`:

    from conan import ConanFile

    class RevenantWebKit(ConanFile):
        name = "revenant-webkit"
        python_requires = "ios6-base/1.0@ios6/stable"
        python_requires_extend = "ios6-base.Ios6Port"

        def requirements(self):
            self.requires("openssl/3.0.15@ios6/stable")
            self.requires("brotli/1.1.0@ios6/stable")

and its own repository serving them:

    conan ios6-remote <port> <port checkout>
    conan install . -pr:h ios6-armv7 -pr:b default --build=missing

`conan ios6-remote` is `conan remote add` with the order enforced. A port and
this repository both carry recipes under names ConanCenter also publishes -
icu, brotli, libxslt - and Conan asks the remotes in the order they are
registered. `conan remote add` appends, so ConanCenter answers first and a
build that has never seen these packages silently gets recipes that cannot
cross-compile for this target. The command puts the checkouts in front and
keeps them there.

## Where the packages are

`CMakeDeps` serves CMake. Everything else a port builds with - shell scripts,
Theos makefiles - needs the same answer, so `ios6-base` writes it once:
`build/conan/ios6-deps.env`, one line per package, taken from the dependency
graph rather than typed out.

    IOS6_HOST_OPENSSL=/.../openssl/3.0.15/Release/armv7
    IOS6_BUILD_LD64=/.../ld64/956.6/Release/armv8

`IOS6_HOST_*` are the libraries built for the phone, `IOS6_BUILD_*` the tools
that run on this machine. The same file reads from a shell and from make:

    . build/conan/ios6-deps.env
    include build/conan/ios6-deps.env

A port that extends `ios6-base.Ios6Port` gets it without doing anything. A
conanfile that does not - a test harness built for the Mac - calls it directly:

    def generate(self):
        self.python_requires["ios6-base"].module.DependencyEnv(self).generate()

Nothing downstream names a version, an architecture or a deploy layout, so a
version bump in `conanfile.py` reaches every consumer. A path that cannot be
written as a plain assignment - one with a space in it - stops the install
rather than producing a file that half the tools misread.

## What it takes from Apple

Nothing of Apple's is in this repository. What a build uses comes from three
places, and each is kept to what is needed:

- **The Command Line Tools** - the compilers and their runtime, `mig`, and the
  archive and binary tools. They are installed once by `xcode-select --install`
  and nothing here replaces them.
- **The iOS SDK, from theos.** Read, never copied. A port records exactly which
  of its files it reads - `tools/sdk-usage.py` turns the compiler's and the
  linker's own logs into that list - so the dependency is a known set of paths
  rather than a whole SDK. This repository's CI builds nothing that reads it and
  does not download it.
- **ld64**, built from cctools-port. Only its linker is built - `ld64/src/3rd`,
  `mach_o` and `ld` - and only libtapi's own targets, with LLVM configured for
  the host alone. The package holds the linker, `libtapi.dylib` and their
  license files. cctools-port can build a whole toolchain beside it, its
  assembler under the GPL among it; none of that is built or shipped.

The linker is built with the optimisation cctools chooses by default. It used to
be built unoptimised by accident: the recipe passed `CFLAGS` to `configure` for
one warning in `otool`, and an explicit `CFLAGS` replaces the default `-O3`
rather than adding to it. Building only the linker made that warning flag
unnecessary. Built both ways with the same flags, the partial build and the full
one produce the same 31362 functions at the same sizes, differing only in the
order they are laid out; `libtapi.dylib` comes out byte for byte the same. The
engine links with the optimised linker and passes the same 55 on-device checks.

libtapi is built in two steps on purpose. `vt_gen` generates `GenVT.inc`, which
libtapi's sources include, and asking Ninja for both at once lets it compile
those sources first - a build that passes or fails depending on scheduling.

## Reproducible packages

Two things made the same recipe produce different bytes on a different machine,
and the hook removes both for every iOS 6 package: the absolute path of Conan's
build folder, which `__FILE__` writes into objects, is mapped to `/source` and
`/build` with `-ffile-prefix-map`. Recipes that stamp a time use the time of the
commit they build rather than the time they ran.

## Packaging

Every port ships a .deb, and the settings that produce one are the same for all
of them: one architecture, a deployment target far below the SDK, the plain
(non-rootless) package layout, and the module flags this SDK needs. They live
in `config/packaging/ios6.mk`, which `conan config install` puts where a port's
own makefile can include it:

    include $(if $(CONAN_HOME),$(CONAN_HOME),$(HOME)/.conan2)/packaging/ios6.mk

What stays with the port is its identity - the package id, the version, the
icon, and what it stages into the package.

Recipes name a git URL and a commit. Nothing is vendored, nothing is committed
as a binary, and a clean clone builds what the lock says.

## Why the linker is here

Apple's linker from Xcode 27 cannot link a 25MB armv7 dylib: a Thumb branch
reaches 16MB, the call stubs sit after all the text, and it does not insert the
branch islands that bridge the gap. ld64 does. It also has to be built from
source, with libtapi for the SDK's `.tbd` stubs, which makes it a package like
any other - pinned to the commits it is known to build from.
