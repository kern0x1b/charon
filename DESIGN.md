# How this is put together

Every armv7 / iOS 6 port - this engine, Telegram, VK ID, whatever comes next -
shares a target, a linker and a set of libraries, and differs in what it
actually builds. The split below keeps the shared half in one place without
forcing the ports to look alike.

For anyone arriving from the JVM world, the mapping is close to exact:

| Maven / Gradle | here |
|---|---|
| `gradle build`, `gradle clean`, `gradle test` | `make build`, `make clean`, `make test` - Charon, `config/extensions/charon/` |
| `gradlew` committed in the project | the port's four-line `Makefile`, which includes Charon from the installed configuration |
| `build.gradle` per module | `conanfile.py` in each port |
| convention plugin / parent POM | `ios6-base`, consumed with `python_requires` |
| `~/.gradle/init.gradle`, toolchain config | `config/profiles/ios6-armv7` and `ios-arm64`, installed with `conan config install` |
| Maven Central / company Artifactory | this repository, registered as a `local-recipes-index` remote |
| `gradle.lockfile`, `dependencyManagement` | `conan.lock` in each port |
| `~/.m2/repository` | `~/.conan2` |

## The three layers

**Shared configuration** - `config/`. Two profiles pin the target:
`ios6-armv7` - armv7, iOS 6.0, the theos SDK, and `ld64` as a build tool - and
`ios-arm64` - arm64 from iOS 7.0, the theos SDK. They carry nothing a port
chooses for itself: a C++ standard, CPU tuning or a later deployment target goes
in the port's own profile, which includes one of these.
`settings_user.yml` adds the iOS versions Conan does not ship. A machine picks
all of it up with one command, and there is exactly one copy of these facts.

**The toolchain** - `recipes/ld64`. The one artifact that is the same for
every port, because it is what makes building possible at all. Libraries are
deliberately not here: the ports disagree on versions, and a shared set would
make one port override another's. Each port carries its own recipes, names a
git URL and a commit, and builds them itself.

**Shared conventions** - `recipes/ios6-base`. The base class a port's conanfile
extends: the generators, the layout, and the check that refuses an operating
system or architecture this toolchain does not build for. This is the piece that stops ten ports from
drifting into ten different spellings of the same build.

## What stays with the port

Its own `conanfile.py`, listing its own dependencies, and its own `conan.lock`.
Duplication here is deliberate and cheap: two ports that both need OpenSSL both
say so, and both get the same package out of the cache. What is not duplicated
is the library itself, the patches, the toolchain, or the knowledge of how this
target is built.

A port's file should be readable in one screen:

    from conan import ConanFile

    class RevenantWebKit(ConanFile):
        name = "revenant-webkit"
        python_requires = "ios6-base/1.0"
        python_requires_extend = "ios6-base.Ios6Port"

        def requirements(self):
            self.requires("openssl/3.0.15@ios6/stable")
            self.requires("brotli/1.1.0")

## Adding a port

1. Write the port's `conanfile.py` as above, its `charon.toml`, and a two-line
   `Makefile` that includes `charon.mk` from the installed configuration.
2. `make setup ARGS=<this repo>` - installs this configuration and registers both
   recipe indexes ahead of the general remotes, because `conan remote add` appends
   after ConanCenter, which would otherwise answer first.
3. `make build`
4. Commit the resulting `conan.lock`.

## Adding a library

Put it under `recipes/<name>/` in the conan-center layout, pin the source by
tag or commit, and keep any patch inside the recipe rather than in a script.
A patch must fail loudly when the text it looks for is gone: `replace_in_file`
raises by default, and that is the behaviour to keep. A silently skipped patch
produces a build that fails somewhere unrelated, months later.

## Versions, and why patches are version-shaped

Recipe versions track upstream, and a port pins the version it needs. The first
two consumers already disagree: this engine builds against OpenSSL 3.0.15, the
Telegram port against 1.1.1w. That is not a case for one recipe carrying both -
the arm-xlate patch is shaped by the version it patches. 3.5.0 moved the block
out from under the patch we use, and 1.1.1's is different again from 3.0's. A
recipe version carries the patch that matches it; ports choose.

## What the checks cover, and what they do not

Every push builds the linker and the libraries on a runner neither of us has
touched, and then looks at what came out rather than at the exit code: the
slice is armv7, the deployment target is iOS 6.0, libcrypto still contains its
ARM assembly, and `OPENSSL_armcap_P` resolves through a plain `__data` word
rather than the non-lazy pointer the linker rejects. It also feeds the build a
missing SDK to confirm that failure is still refused, so the guard rails cannot
rot unnoticed.

None of that proves the result runs. This target is one where a build can
succeed and still be wrong - the failure that started all of this was a linker
that exited 0 and produced a binary that could not have run. A device is the
only thing that settles it, and the device suite stays manual, on real hardware.
Treat green CI as "the toolchain reproduces", not as "the code is good".

## Binaries

Recipes only, for now: each machine builds a package once and caches it in
`~/.conan2`. If sharing built binaries between machines becomes worth it, that
is a real Conan remote - Artifactory or any server - added alongside, with no
change to the recipes or the ports.
