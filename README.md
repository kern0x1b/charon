# ios6-toolchain

The part of building for armv7 / iOS 6 that is the same for every project: how
to build it at all, without Xcode installed.

Libraries are not here. Each port carries its own recipes and builds them
itself, because ports disagree - this engine wants OpenSSL 3.0.15, the Telegram
port 1.1.1w - and a shared library set would make one of them override the
other. What is shared is only what is true for all of them.

## What is here

    config/settings_user.yml   iOS 6.0 and 6.1, which Conan does not ship
    config/profiles/ios6-armv7 the target: armv7, iOS 6.0, the theos SDK, the linker
    config/profiles/ios-arm64  the target: arm64, iOS 7.0 or later, the theos SDK
    config/extensions/hooks/   refuses a missing SDK or a swapped linker
    config/extensions/charon/  Charon: the entry point, what it generates, and the phone transport
    tools/sdk-usage.py         which files of an SDK a build actually read
    recipes/ld64/              the linker, built from cctools-port
    recipes/ldid/              the signing tool the device accepts
    recipes/ios6-base/         the base class a port's conanfile extends, and its .deb writer

## A new machine

    brew install conan cmake ninja ccache llvm
    xcode-select --install

    git clone https://github.com/kern0x1b/ios6-toolchain.git
    conan config install ios6-toolchain/config

    export LLVM_PREFIX="$(brew --prefix llvm)"

Charon is the entry point, the way Gradle is. Put it on the path once per
machine:

    ln -s "$(conan config home)/extensions/charon/charon" /usr/local/bin/charon

and inside a port `charon setup <path to this repo>` installs this configuration
and registers this repository's recipes and the port's own ahead of the general
remotes. The verbs are the same in every port:

    charon build [--variant NAME]   everything the declaration names
    charon task NAME [NAME...]      declared tasks, run the way the pipeline runs them
    charon test [--tier NAME]       the declared test tiers
    charon package                  the .deb
    charon deploy, charon run       install on the phone, launch the application
    charon generate                 write the recipe, profile and CMake without building
    charon integrate, clean, provenance, device run|copy|fetch

`conan config install` copies rather than links, so after changing Charon here
run `charon setup` again; `charon provenance` says which copy is answering.

A port carries no conanfile.py, no profile, no CMake and no Makefile. It carries
`charon.toml`, and Charon writes the rest into `build/<variant>/charon/`:

    [port]
    name = "revenant-webkit"
    version = "0.1.0"
    index = "revenant"

    [target]
    include-profiles = ["ios6-armv7"]
    arch = "armv7"
    os = "iOS"
    os-version = "6.0"
    sdk = "iphoneos"

    [requires]
    openssl = "3.0.15@revenant/stable"

    [[device-library]]
    name = "RevSafari"
    sources = ["platform/safari/rev-safari-tweak.c"]
    install = "/Library/MobileSubstrate/DynamicLibraries"
    installs-into = "stage"
    frameworks = ["CoreFoundation"]

    [tasks.carry-check]
    script = "scripts/carry-check.py"

    [tasks.where]
    shell = "echo built into"
    args = "{build}"

    [tasks.census]
    python = """
    import sys
    print(sys.argv[1:])
    """
    args = "{pkg:openssl}"

    [pipeline]
    system = ["task:carry-check", "build:device-library", "stage:frameworks", "task:where"]

A task is a table with exactly one of `script`, `shell` or `python`, and its
`args` may name anything the build knows: `{port}`, `{build}`, `{stage}`,
`{pkg:NAME}`, `{include:NAME}`, `{lib:NAME:LIBRARY}`, `{bin:TOOL}`,
`{target:NAME}`. Every task runs from `{port}`, the folder holding
`charon.toml`; the generated recipe finds it from the `build/<variant>/charon`
folder it lives in, so it carries no checkout path, and `user.charon:port`
names another. A task runs in `[pipeline]` as `task:NAME`, before the build under `charon integrate`
when `[integrate] before-build` names it, or on its own with `charon task NAME`.

A target's `sources` may be patterns - `src/**/*.m` - with `exclude`, expanded
when Charon writes the project; a pattern that matches nothing is refused. An
application is linked by `build:application` and signed by `sign:application`,
and the steps between them get `{application}` and `{executable}`, so a Mach-O
fix-up runs on the linked, unsigned binary. `strip = "-S -x"` strips the
executable right after it is linked; `plist-file` starts Info.plist from a file,
with `[application.plist]` over it and the derived keys filling only what both
leave out; `bundle = [{ from = "{pkg:NAME}/lib/libfoo.dylib", into = "Frameworks" }]`
copies a package's file into the bundle and gives a binary its
`@executable_path` identity. Neither the executable nor anything bundled may load a library the bundle carries from anywhere else, whatever version suffix the path spells. `include-exclude` removes a folder whether a pattern or a literal entry
brought it in, so excluding a tree excludes every folder inside it. A port that
copies C++ runtime libraries into the device layout names them under
`[stage.runtime]` and the package they come from as `[stage] runtime-from`; a
port that ships no runtime declares neither and needs no such package. A library the application opens by a path string
is not rewritten by any of this - that path is the application's own. A
pipeline that builds an application and never signs it is refused, unless
another variant merges it.

Anything Charon writes can be replaced. `cmake = "<dir>"` on a target uses that
project instead of a generated one; `[engine] user-toolchain` and
`project-include` name hand-written cmake files; `[use] profile` and
`[use] recipe` name a profile or a recipe of the port's own; `script =` keeps a
large task in a file. The declaration alone is the default and none of these is
required.

`[conf]` holds what dependency builds read from the profile. A sentence names a
value the port needs but does not set, and `charon setup` warns while it is
empty; a table sets it, with the reason beside it:
`"user.x:headers" = { value = "{port}/include", why = "..." }`. A set value is
written into the generated profile, so a dependency Conan builds from source
under `charon build` sees it too, and `{port}` is resolved by the profile from
where it lies rather than written as a checkout path. `[variants.NAME.conf]`
replaces the keys it names for that slice. A value may not name a package
placeholder, because a profile is read before the graph that could answer it;
a dependency that needs another package's files requires that package, for
example headers only with `requires(..., headers=True, libs=False)`.

Every binary a step produces is verified before anything strips or signs it,
whatever the pipeline says: targets installed into the stage, staged
frameworks, the application's executable and everything bundled with it, and
each merged binary. On armv7 every rebased pointer to a function must carry
bit 0 exactly when that function is Thumb code, read from the symbol table
while it is still there; ld64 gets this right, a linker that drops the bit or
a post-link edit that sets it on ARM code does not, and either one runs until
the first call through the pointer. An executable's `__PAGEZERO` must be at
least 4 GB on arm64 and end where `__TEXT` starts on armv7. After
`sign:application` the signature is read back and must carry every declared
entitlement with its declared value. A port can only take one out with a
reason, `[waive] pagezero = "why"`; an unknown name or an empty reason is
refused.

The rest Charon derives rather than being told: the host profile comes from
`[target]`, the engine build is the one direct child of `build/` that CMake
configured and that has frameworks laid out, the frameworks to install are
whatever the build staged, and a test tier gets the phone, the build tree or its
packages only when it declares `needs` or `packages`.

`LLVM_PREFIX` is read once, by `config/global.conf`, into
`user.ios6:llvm_prefix`. Only the `ld64` recipe asks for it: cctools' configure
runs `llvm-config` to find `libLTO`, and a linker built without it silently
drops LTO support, which this target builds with. Recipes never read the
environment themselves, so a missing path stops `conan create` with that
sentence rather than producing a linker that cannot link.

To set it for one invocation instead, the flag is `-c:a`, not `-c`: `ld64` is a
`tool_requires`, so it is configured in the **build** context, which a plain
`-c` never reaches. A guard firing while the value is plainly set on the command
line is almost always this.

Xcode is not required and does not need to be installed. The Command Line Tools
carry the compiler and the compiler runtime, the SDK is the one theos publishes
in [theos/sdks](https://github.com/theos/sdks), and the linker and the signing
tool are built from source by the `ld64` and `ldid` recipes. Theos itself is not
needed.

## A port

A port is `charon.toml`, its own `recipes/` for the libraries it builds, and its
own `conan.lock`. `charon setup` registers the port's recipes as the remote
`[port] index` names and this repository's as `ios6`, and keeps both ahead of
ConanCenter. A port and this repository both carry recipes under names
ConanCenter also publishes - icu, brotli, libxslt - and Conan asks the remotes
in the order they are registered; `conan remote add` appends, so without that
ConanCenter answers first and a build that has never seen these packages
silently gets recipes that cannot cross-compile for this target.

The shared profiles say only what is true of the target: the operating system,
the architecture, the SDK and, for armv7, the linker. A port's own choices - the
C++ standard, CPU tuning, a later deployment target - are `[target]` keys, and
the profile Charon writes includes the shared one `include-profiles` names.
arm64 starts at iOS 7.0, and the base class refuses anything lower.

`@ios6/stable` is for what this repository serves - the linker, the C++ runtime,
the base class - and nothing else. A port's own libraries carry the port's name,
`openssl/3.0.15@revenant/stable`, `openssl/3.0.15@itglegacy/stable`: two ports
build the same library with different choices, and two recipes behind one
reference overwrite each other's packages in the Conan cache every port on the
machine shares.

## Packaging a library

Three things every recipe meets sooner or later.

A library built with a SOVERSION leaves `libfoo.dylib -> libfoo.1.2.3.dylib` in
its build tree. A `copy(self, "*.dylib", ...)` in `package()` that matches the
unversioned name stores the link, not the file it points at, and the package
ends up holding a dangling symlink. Copy the real file, and recreate the short
name with `os.symlink` inside `package_folder` if consumers link against it.

Some sources already live in the consuming repository - a submodule pinned in a
monorepo, too large to copy around. There is no need for an environment
variable naming the checkout. Point `layout()` at the sources, build them where
they are with `conan build`, then turn that build into a normal package with
`conan export-pkg`: it runs `package()` against the local build folder and
stores the result in the cache, resolvable by `requires()` and written into
`ios6-deps.env` like any other. The cache holds the recipe and the artifacts, not
the sources, so it cannot rebuild the package with `--build`; the repository is
where that happens. If the package must be rebuildable from the cache,
`exports_sources` copies the sources in on export instead.

Each Conan command is its own process, and `conan build` and `conan export-pkg`
are two of them. Anything `build()` stores on `self` is gone when `package()`
runs, so `package()` has to find what it copies the same way `build()` made it -
from the layout and the settings - rather than from state the build left behind.

Editing a recipe changes its revision, and every package exported under the old
revision stops matching - for each architecture, including the ones the edit was
not about. A lockfile still names the old revision, and on the machine that made
the edit nothing fails: the old revision is still in the local cache, so the
build quietly uses it. Only a fresh clone fails. Update the lock in the same
change as the recipe:
`conan lock create . --lockfile="" --update --lockfile-out=conan.lock` with the
same profiles as the build. `--lockfile=""` starts over from what the recipes
say now - Conan otherwise reads a `conan.lock` it finds beside the conanfile as
its input and keeps the revisions in it - and `--update` exports the recipes
from the indexes again instead of taking the revision already in the cache.

Every recipe carries a `test_package`, and `conan create` runs it. `ios6-base`
provides the whole of it; a recipe adds three files:

    test_package/conanfile.py      python_requires_extend = "ios6-base.Ios6TestPackage"
    test_package/CMakeLists.txt    find_package(<name> CONFIG) and one executable
    test_package/test_package.c    a program that calls the library for real

The program is compiled against the package and linked for the target through
ld64, so a package that builds but cannot be linked against - a missing
component, a define its headers need, a runtime it forgot to declare - fails in
its own `conan create`, not in a port an hour into a build. It runs only where
the target can run; for iOS the link is the test. A tool such as ld64 checks
what it says about itself instead.

## Where the packages are

`CMakeDeps` serves CMake. Everything else a port runs - a test harness, a shell
script - needs the same answer, so `ios6-base` writes it once:
`build/conan/<arch>/ios6-deps.env`, one line per package, taken from the dependency
graph rather than typed out.

    IOS6_HOST_OPENSSL=/.../openssl/3.0.15/Release/armv7
    IOS6_BUILD_LD64=/.../ld64/956.6/Release/armv8

`IOS6_HOST_*` are the libraries built for the phone, `IOS6_BUILD_*` the tools
that run on this machine. The same file reads from a shell and from make:

    . build/conan/armv7/ios6-deps.env
    include build/conan/armv8/ios6-deps.env

The folder is per architecture, so a port that ships both slices installs twice
and each slice keeps its own paths - a `lipo -create` step reads one file for
each. A port built from `charon.toml` writes it into its build tree instead,
`build/<variant>/conan/ios6-deps.env`, and a test tier that declares `packages`
gets its own under `build/tier-packages/<tier>/`.

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
- **The iOS SDK, from theos/sdks.** Read, never copied. A port records exactly which
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

Every port ships a .deb. A port declares `[package] control` and, if it has
them, `maintainer-scripts`; `charon package` hands the staged tree - laid out
as the device's filesystem, every binary signed with the `ldid` tool_requires -
to `ios6-base.DebianPackage`. A recipe written by hand calls the same class:

    def package(self):
        self.python_requires["ios6-base"].module.DebianPackage(
            self, "packaging/control", self._stage, "packaging/DEBIAN"
        ).write(os.path.join(self.package_folder, "deb"))

It writes the archive dpkg-deb and theos's dm.pl write - `debian-binary`,
`control.tar.gz`, `data.tar.lzma`, owned by root - with the version from the
recipe, so the port's control file carries neither `Version` nor
`Installed-Size`. Neither theos nor dpkg is needed to produce it.

Everything armv7 links through the `ld64` package, which the profile hands to
every CMake build as `-B`. Apple's own linker from Xcode 27 writes an
`LC_ENCRYPTION_INFO` load command into every armv7 dylib, and iOS 6 will not
start an app whose MobileSubstrate tweak carries one - no crash log, the tweak's
constructor never runs. The same source linked by ld64 has no such command and
loads.

What stays with the port is its identity - the package id, the icon, and what
it stages into the package.

Recipes name a git URL and a commit. Nothing is vendored, nothing is committed
as a binary, and a clean clone builds what the lock says.

## Why the linker is here

Apple's linker from Xcode 27 cannot link a 25MB armv7 dylib: a Thumb branch
reaches 16MB, the call stubs sit after all the text, and it does not insert the
branch islands that bridge the gap. ld64 does. It also has to be built from
source, with libtapi for the SDK's `.tbd` stubs, which makes it a package like
any other - pinned to the commits it is known to build from.
