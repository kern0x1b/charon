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
    recipes/ld64-armv7/        the linker, built from cctools-port
    recipes/ios6-base/         the base class a port's conanfile extends

## A new machine

    brew install conan cmake ninja ccache llvm
    xcode-select --install

    git clone https://github.com/kern0x1b/ios6-toolchain.git
    conan config install ios6-toolchain/config
    conan ios6-remote ios6 ios6-toolchain

Xcode is not required and does not need to be installed. The Command Line Tools
carry the compiler and the compiler runtime, theos carries the SDK, and the
linker is built from source by the `ld64-armv7` recipe.

## A port

Its own `conanfile.py`, its own `recipes/`, its own `conan.lock`:

    from conan import ConanFile

    class RevenantWebKit(ConanFile):
        name = "revenant-webkit"
        python_requires = "ios6-base/1.0"
        python_requires_extend = "ios6-base.Ios6Port"

        def requirements(self):
            self.requires("openssl-ios6/3.0.15")
            self.requires("brotli/1.1.0")

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
