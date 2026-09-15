import os

from conan.errors import ConanException


def _is_ios6_target(conanfile):
    settings = getattr(conanfile, "settings", None)
    if settings is None:
        return False
    return (settings.get_safe("os") == "iOS"
            and settings.get_safe("arch") == "armv7")


def pre_generate(conanfile):
    if not _is_ios6_target(conanfile):
        return
    maps = []
    for folder, name in ((conanfile.source_folder, "/source"), (conanfile.build_folder, "/build")):
        if folder:
            maps.append(f"-ffile-prefix-map={folder}={name}")
    if maps:
        conanfile.conf.append("tools.build:cflags", maps)
        conanfile.conf.append("tools.build:cxxflags", maps)


def pre_build(conanfile):
    """Two things that must never be resolved silently.

    A missing SDK and a swapped linker both fail late and far from their cause:
    the SDK as errors inside Apple's headers, the linker as an assertion or an
    out-of-range branch in a binary that linked fine on the machine next to it.
    """
    if not _is_ios6_target(conanfile):
        return

    sdk = conanfile.conf.get("tools.apple:sdk_path")
    if not sdk:
        raise ConanException(
            f"{conanfile.ref}: no SDK. The ios6-armv7 profile sets "
            "tools.apple:sdk_path; build with -pr:h ios6-armv7.")
    if not os.path.isdir(sdk):
        raise ConanException(
            f"{conanfile.ref}: the SDK is not at {sdk}. Install theos with an "
            "iPhoneOS SDK, or point IOS_SDK at one. Do not continue without it: "
            "the build fails much later, inside Apple's headers.")

    if conanfile.name == "ld64":
        return
    build_deps = {str(d.ref.name) for d in conanfile.dependencies.build.values()}
    if "ld64" not in build_deps:
        raise ConanException(
            f"{conanfile.ref}: ld64 is not in the build context. Apple's "
            "linker cannot link this target once the text passes 16MB, and it "
            "fails differently on different machines. The ios6-armv7 profile "
            "requires it; a profile that does not is the wrong profile.")
