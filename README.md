# ios6-toolchain

Everything the armv7 / iOS 6 ports need in order to build, in one place, so that
each port carries a list of dependencies instead of a directory of shell
scripts.

## What a new machine needs

    brew install conan cmake ninja ccache llvm
    xcode-select --install

Xcode itself is not required. The Command Line Tools carry the compiler and the
compiler runtime; the SDK comes from theos; the linker and the binary utilities
are built by the `ld64-armv7` package here.

## Setting it up

    git clone <this repo> ios6-toolchain
    conan config install ios6-toolchain/config
    conan remote add ios6 ios6-toolchain --type=local-recipes-index

`conan config install` brings the profile and the extra iOS versions; the remote
serves the recipes straight from the working tree, so editing a recipe here is
immediately visible to every project.

## Using it

    conan install . -pr:h ios6-armv7 -pr:b default --build=missing

The profile pins the target - armv7, iOS 6.0, the theos SDK, Cortex-A9 with
NEON - and pulls in `ld64-armv7` as a build tool, which puts itself first in the
compiler driver's search for `ld`.

## Why the linker is a package

Apple's linker from Xcode 27 cannot link a 25MB armv7 dylib: a Thumb branch
reaches 16MB, the call stubs sit after all the text, and it does not insert
branch islands to bridge the gap. ld64 does. Since it also has to be built from
source with libtapi for the SDK's `.tbd` stubs, it is a package like any other,
pinned to the commits it is known to build from.

## Layout

    config/settings_user.yml   iOS 6.0 and 6.1, which Conan does not ship
    config/profiles/ios6-armv7 the profile every port includes
    recipes/                   served as the local-recipes-index remote
