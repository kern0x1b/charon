# Charon

A build driver for ports: a project declares what it builds in one `charon.toml`,
and Charon writes the recipes, the profiles, the CMake projects and the packages
from it, builds them with Conan, and holds every binary to the invariants of the
platform it runs on. The platform is a file of facts; `apple-ios` is the first,
from armv7 on iOS 6 to arm64 on current releases, with what an old release lacks
provided by `apple-compat` rather than by pinning old libraries.

Libraries are not here. Each port carries its own recipes and builds them
itself, because ports make their own choices for the same library, and a shared
set would make one override the other. What is here is only what is true for
every port of a platform.

## What is here

    config/settings_user.yml   iOS 6.0 and 6.1, which Conan does not ship
    config/extensions/hooks/   refuses a build missing what its platform requires, and maps machine paths away
    config/extensions/charon/  Charon: the entry point, what it generates, and the phone transport
    config/extensions/charon/platforms/  apple-ios: what a port that builds for iOS is built with
    tools/sdk-usage.py         which files of an SDK a build actually read
    recipes/ld64/              the linker, built from cctools-port
    recipes/ldid/              the signing tool the device accepts
    recipes/libplist/          the property-list library ldid reads entitlements with
    recipes/iphoneos-sdk/      the SDK, fetched and verified on the machine that uses it
    recipes/libcxx/            the C++ runtime an old iOS does not ship
    recipes/dyld-imports-check/  the check that every import exists in a device's dyld cache
    recipes/charon-base/       what every port's recipe extends, whatever its platform
    recipes/charon-apple/      the Apple half: Mach-O invariants, bundles, signing, the .deb writer

## A new machine

    brew install conan cmake ninja ccache llvm
    xcode-select --install

    git clone https://github.com/kern0x1b/charon.git
    conan config install charon/config

    export LLVM_PREFIX="$(brew --prefix llvm)"

Charon is the entry point, the way Gradle is. Inside a port, run it once by its
full path:

    "$(conan config home)/extensions/charon/charon" setup <path to this repo>

That installs this configuration, registers this repository's recipes and the
port's own ahead of the general remotes, and links `charon` into the first
writable folder on PATH, so every later call is just `charon`. A new port starts from a template, which builds, packages and passes
`check:imports` as written:

    charon new tweak|daemon|app NAME [--identifier com.example.name]

`CHARON_MAINTAINER` fills the control file's maintainer. The verbs are the same
in every port:

    charon build [--variant NAME]   everything the declaration names
    charon lock                     pin every variant's graph to what the indexes serve now
    charon task NAME [NAME...]      declared tasks, run the way the pipeline runs them
    charon test [--tier NAME]       the declared test tiers
    charon package                  the .deb, copied to build/<variant>/
    charon install                  package and dpkg -i the .deb on the phone, refusing to
                                    install an app over one with another bundle identifier
    charon deploy, charon run       install on the phone, launch the application
    charon device log [SECONDS] [TEXT]  the phone's log over USB, filtered
    charon generate                 write the recipe, profile and CMake without building
    charon integrate, clean, provenance, device run|copy|fetch

The phone is named in the port's `device.env` (`DEVICE_HOST`, `DEVICE_PORT`,
`DEVICE_UDID`, `DEVICE_PASSWORD`). A port with more than one keeps
`device.NAME.env` beside it and picks one with `--device NAME`, or with
`CHARON_DEVICE=NAME` for a whole shell.

`conan config install` copies rather than links, so after changing Charon here
run `charon setup` again; `charon provenance` says which copy is answering.

A port with one pipeline needs no `[variants]`: each name under `[pipeline]` is
a variant with no options of its own. A port carries no conanfile.py, no profile,
no CMake and no Makefile. It carries
`charon.toml`, and Charon writes the rest into `build/<variant>/charon/`:

    [port]
    name = "revenant-webkit"
    version = "0.1.0"
    index = "revenant"

    [platform]
    use = "apple-ios"
    arch = "armv7"
    os-version = "6.0"
    distribution = "jailbreak"

    [target]
    cppstd = 23
    cpu = "cortex-a9"

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

`[[executable]]` is a program for the device - a daemon, a tool - generated as
`add_executable` and installed at `install`. A staged device library or
executable with `entitlements` is signed with that file and its signature read
back, as the application's is.

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
while it is still there, and a binary none of whose code pointers names a function it can check is refused as having arrived stripped; ld64 gets this right, a linker that drops the bit or
a post-link edit that sets it on ARM code does not, and either one runs until
the first call through the pointer. An executable's `__PAGEZERO` must be at
least 4 GB on arm64 and end where `__TEXT` starts on armv7. After
`sign:application` the signature is read back and must carry every declared
entitlement with its declared value. After a project builds, every object and
archive member its links read - asked of Ninja with `ninja -t inputs`, so an
object left over from a deleted source is not read - must record the target's
minimum OS version exactly when it was built here or by a package in the
dependency graph; an input from outside the graph is refused only when newer
and otherwise reported by name: newer means the binary needs a later
iOS, and older or none means it was compiled without the target's flags - the
assembler is where that usually happens. Every host profile, shared or
generated, exports `IPHONEOS_DEPLOYMENT_TARGET` from its `os.version` into the
build environment, so a compiler or assembler a build system invokes without a
version flag stamps the target's minimum rather than its own default; an
explicit flag still wins. The variable reaches everything a host package's
build runs, so a recipe that compiles and runs a helper on the build machine
inside its own `build()` runs that step with an environment that unsets it;
a tool that belongs to the build machine is better a build-context package. A binary that weakly imports from libSystem a call apple-compat records as
arriving after the target release is refused, naming the component to link:
on the device that call jumps to NULL. A port can only take one out with a
reason, `[waive] pagezero = "why"`, and `input-minimum` may name packages,
`[waive] input-minimum = { tdlib = "why" }`; an unknown name, a package nothing
depends on, or an empty reason is refused.

Recipes reach a build only through a local recipe index, which trims each
`conandata.yml` to the version it exports. A top-level table with no key for
that version is dropped there, so a recipe reading it works from its folder and
fails for every consumer; `charon build` and `charon setup` refuse such an index
before anything runs. `charon setup` also names each `conandata.yml` whose text
the trim rewrites: `conan create` in that folder gives a different revision from
the one consumers resolve, so a package built that way is not the one they use.

`[platform]` names what the port builds for, and nothing else says it. A
platform is a file of facts - `config/extensions/charon/platforms/apple-ios.toml`
is the first - giving the operating system, its SDK name, the architectures it
builds with the oldest and newest release each supports, the tools every build
for an architecture requires (the SDK package; ld64 for armv7), the compiler's
runtime, the configuration and the deployment-target variable its tools read,
and the distributions it knows. Charon writes the whole host profile from it,
refuses an architecture, a release or a distribution the platform does not
have, and refuses `[target]` repeating `os`, `arch`, `os-version`, `sdk` or
`system-name`. `[variants.NAME.platform]` changes the architecture or the
release for one slice. A port's own `platforms/NAME.toml` is used before
Charon's, so a platform can be written or corrected without changing Charon.
`[target]` keeps what tunes the build: `cppstd`, `cpu`, `fpu`, `defines`.

A platform also says where a framework lived before it became public:
`[frameworks.IOSurface] public-since = "11.0"` makes a build for an older release
link IOSurface through the SDK's own stub laid out at
`/System/Library/PrivateFrameworks`, so the image records the location that
release loads it from. `dyld-imports-check` refuses a binary that loads a library
neither the device's cache nor the build itself provides, besides every symbol
the device does not export.

`ldid` signs with the package the platform names under `port-tool-requires`,
never with one that happens to be on PATH.

`tool-requires` reach every package the profile builds; `port-tool-requires`
reach only the port's own recipe, beside its `[tools]`, and a port naming the
same tool picks its version. apple-ios names `dyld-imports-check` there, which
the `check:imports` step runs over the stage and the application bundle against
the device's shared cache: `user.apple-ios:dyld_shared_cache`, or else
`<user.charon:home, ~/.charon>/dyld/dyld_shared_cache_<arch>`. Without a cache
the step refuses rather than passing having looked at nothing. It is the check
that proves a build loads: a table of calls that arrived late only knows what
someone wrote into it.

`charon where pkg:NAME` prints the folder of a package a variant's build links,
and `charon where tool:NAME` one it runs, answered from the same lock and profile
the build uses and never building anything; a script asks it instead of reading
generated environment files.

The rest Charon derives rather than being told: the host profile comes from
`[target]`, the engine build is the one direct child of `build/` that CMake
configured and that has frameworks laid out, the frameworks to install are
whatever the build staged, and a test tier gets the phone, the build tree or its
packages only when it declares `needs` or `packages`.

`LLVM_PREFIX` is read once, by `config/global.conf`, into
`user.ld64:llvm_prefix`. Only the `ld64` recipe asks for it: cctools' configure
runs `llvm-config` to find `libLTO`, and a linker built without it silently
drops LTO support, which this target builds with. Recipes never read the
environment themselves, so a missing path stops `conan create` with that
sentence rather than producing a linker that cannot link.

To set it for one invocation instead, the flag is `-c:a`, not `-c`: `ld64` is a
`tool_requires`, so it is configured in the **build** context, which a plain
`-c` never reaches. A guard firing while the value is plainly set on the command
line is almost always this.

`libcxx` offers the newest LLVM release, 23.1.1. Its runtime calls what old
releases lack - `aligned_alloc`, `clock_gettime`, the `*at` calls, `__ulock_wait`
- and links `apple-compat` hidden, which provides each for the releases before it
arrived; the recipe refuses a runtime that still imports one of them.

Xcode is not required and does not need to be installed. The Command Line Tools
carry the compiler and the compiler runtime, the SDK comes from the
`iphoneos-sdk` package, and the linker and the signing tool are built from
source by the `ld64` and `ldid` recipes. Theos itself is not needed.

## A port

A port is `charon.toml`, its own `recipes/` for the libraries it builds, and its
own `conan.lock`. `charon setup` registers the port's recipes as the remote
`[port] index` names and this repository's as `charon`, and keeps both ahead of
ConanCenter. A port and this repository both carry recipes under names
ConanCenter also publishes - icu, brotli, libxslt - and Conan asks the remotes
in the order they are registered; `conan remote add` appends, so without that
ConanCenter answers first and a build that has never seen these packages
silently gets recipes that cannot cross-compile for this target.

`charon profiles`, which `charon setup` also runs, writes a shared profile for
every architecture of every platform - `apple-ios-armv7` at iOS 6.0 and
`apple-ios-armv8` at 7.0 - from the same platform files a port's profile is
written from, for building a recipe with plain `conan create`. A port's own
choices - the C++ standard, CPU tuning - are `[target]` keys.

`@charon/stable` is for what this repository serves - the linker, the C++ runtime,
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
`charon-deps.env` like any other. The cache holds the recipe and the artifacts, not
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

Every recipe carries a `test_package`, and `conan create` runs it. `charon-base`
provides the whole of it; a recipe adds three files:

    test_package/conanfile.py      python_requires_extend = "charon-base.CharonTestPackage"
    test_package/CMakeLists.txt    find_package(<name> CONFIG) and one executable
    test_package/test_package.c    a program that calls the library for real

The program is compiled against the package and linked for the target through
ld64, so a package that builds but cannot be linked against - a missing
component, a define its headers need, a runtime it forgot to declare - fails in
its own `conan create`, not in a port an hour into a build. It runs only where
the target can run; for iOS the link is the test. A tool such as ld64 checks
what it says about itself instead.

## Handing packages on

`charon publish INDEX OUT` archives the packages built from an index's recipes
with `conan cache save`, without sources, and writes beside the archive a table
of each package's license, source and binaries. A recipe with `upload_policy =
"skip"` is left out - the iOS SDK is Apple's to hand on, not ours - and a package
with no `licenses/` folder refuses the archive. `conan cache restore` puts the
archive into another machine's cache, where builds for the same settings take
the binaries instead of building them. The archives of this index are attached
to the repository's releases named `packages-<date>`.

## Where the packages are

`CMakeDeps` serves CMake. Everything else a port runs - a test harness, a shell
script - needs the same answer, so `charon-base` writes it once:
`build/conan/<arch>/charon-deps.env`, one line per package, taken from the dependency
graph rather than typed out.

    CHARON_HOST_OPENSSL=/.../openssl/3.0.15/Release/armv7
    CHARON_BUILD_LD64=/.../ld64/956.6/Release/armv8

`CHARON_HOST_*` are the libraries built for the device, `CHARON_BUILD_*` the tools
that run on this machine. The same file reads from a shell and from make:

    . build/conan/armv7/charon-deps.env
    include build/conan/armv8/charon-deps.env

The folder is per architecture, so a port that ships both slices installs twice
and each slice keeps its own paths - a `lipo -create` step reads one file for
each. A port built from `charon.toml` writes it into its build tree instead,
`build/<variant>/conan/charon-deps.env`, and a test tier that declares `packages`
gets its own under `build/tier-packages/<tier>/`.

A port that extends `charon-base.CharonPort` gets it without doing anything. A
conanfile that does not - a test harness built for the Mac - calls it directly:

    def generate(self):
        self.python_requires["charon-base"].module.DependencyEnv(self).generate()

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
- **The iOS SDK, from the `iphoneos-sdk` package.** The profiles require it; it
  downloads the SDK archive [theos/sdks](https://github.com/theos/sdks) publishes
  as a release asset, checks its sha256 and its `SDKSettings.plist`, lays it out
  as Xcode does - `Platforms/iPhoneOS.platform/Developer/SDKs/` - and answers
  `tools.apple:sdk_path` for every build that requires it. It is never uploaded
  anywhere (`upload_policy = "skip"`): the SDK is Apple's, and this project only
  says where it comes from. A `tools.apple:sdk_path` set in a profile or on the
  command line still wins. A port records exactly which
  of its files it reads - `tools/sdk-usage.py` turns the compiler's and the
  linker's own logs into that list - so the dependency is a known set of paths
  rather than a whole SDK. This repository's CI fetches it only to check the
  package names the SDK it says it does.
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
to `charon-apple.DebianPackage`. For the variant that builds `[application]`,
the final bundle joins that tree where the port's distribution installs
applications (`applications` under the platform's `[distributions.<name>]`,
`/Applications` for a jailbroken iOS device). A port with several variants
names the one its package is written from with `[package] variant`; the others
package their bundle or tree without a .deb. A recipe written by hand calls the same class:

    def package(self):
        self.python_requires["charon-apple"].module.DebianPackage(
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
