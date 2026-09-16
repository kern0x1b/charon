#!/usr/bin/env python3
"""Check the compatibility shims keep the contract of the call they stand in for.

    tests/compat_test.py

Each shim is compiled for this machine and exercised, because the device it is
for cannot run a test here; and each is checked to be a hidden definition, so
the image that links it binds its own calls to it and exports nothing another
image could bind to.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SHIMS = HERE.parent / "recipes" / "apple-compat" / "all" / "src"

ALIGNED = r"""
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

void *charon_aligned_alloc(size_t alignment, size_t size);

static int fails;

static void expect(int holds, const char *what)
{
    if (!holds) {
        printf("FAIL  %s\n", what);
        fails++;
    }
}

int main(void)
{
    for (size_t alignment = 1; alignment <= 4096; alignment <<= 1) {
        void *memory = charon_aligned_alloc(alignment, alignment * 3);
        expect(memory != NULL, "a power-of-two alignment with a multiple size is allocated");
        expect(((uintptr_t)memory % alignment) == 0, "the memory is aligned as asked");
        free(memory);
    }
    errno = 0;
    expect(charon_aligned_alloc(24, 48) == NULL && errno == EINVAL, "an alignment that is not a power of two is refused");
    errno = 0;
    expect(charon_aligned_alloc(16, 17) == NULL && errno == EINVAL, "a size that is not a multiple is refused");
    errno = 0;
    expect(charon_aligned_alloc(0, 16) == NULL && errno == EINVAL, "a zero alignment is refused");
    size_t rounded = (1 + 128 - 1) & ~(size_t)(128 - 1);
    void *memory = charon_aligned_alloc(128, rounded);
    expect(memory != NULL && ((uintptr_t)memory % 128) == 0, "operator new(1, align_val_t(128)) as libc++ rounds it");
    free(memory);
    return fails != 0;
}
"""


def run(*command, cwd):
    return subprocess.run([str(part) for part in command], cwd=cwd, capture_output=True, text=True)


def failures():
    found = []
    with tempfile.TemporaryDirectory() as scratch:
        folder = Path(scratch)
        (folder / "shim.c").write_text((SHIMS / "aligned_alloc.c").read_text())
        (folder / "main.c").write_text(ALIGNED)
        built = run("xcrun", "clang", "-O2", "shim.c", "main.c", "-o", "aligned", cwd=folder)
        if built.returncode:
            return ["the aligned_alloc shim must compile: {}".format(built.stderr)]
        ran = run("./aligned", cwd=folder)
        found += [line[6:] for line in ran.stdout.splitlines() if line.startswith("FAIL")]
        if ran.returncode and not found:
            found.append("the aligned_alloc test failed without saying why: {}".format(ran.stderr))

        compiled = run("xcrun", "clang", "-target", "armv7-apple-ios6.0", "-Wno-incompatible-sysroot", "-c",
                       SHIMS / "aligned_alloc.c", "-o", "shim.o", cwd=folder)
        if compiled.returncode:
            return found + ["the aligned_alloc shim must compile for armv7 on iOS 6: {}".format(compiled.stderr)]
        symbols = run("xcrun", "nm", "-m", "shim.o", cwd=folder).stdout
        line = next((row for row in symbols.splitlines() if row.endswith(" _charon_aligned_alloc")), "")
        if "private external" not in line:
            found.append("aligned_alloc must be a hidden definition so the image exports nothing libc-named: {}"
                         .format(line or symbols))
        header = SHIMS.parent / "include" / "charon" / "aligned_alloc.h"
        (folder / "caller.cpp").write_text("#include <cstdlib>\n"
                                           "void *call(unsigned long n) { return ::aligned_alloc(16, n); }\n")
        called = run("xcrun", "clang++", "-target", "armv7-apple-ios6.0", "-Wno-incompatible-sysroot",
                     "-Werror=unguarded-availability-new", "-include", header, "-c", "caller.cpp", "-o", "caller.o",
                     cwd=folder)
        if called.returncode:
            found.append("a call to aligned_alloc must compile for iOS 6 with unguarded availability an error once "
                         "the header is included: {}".format(called.stderr[-400:]))
        else:
            undefined = run("xcrun", "nm", "-u", "caller.o", cwd=folder).stdout.split()
            if "_aligned_alloc" in undefined or "_charon_aligned_alloc" not in undefined:
                found.append("the call must reach charon_aligned_alloc, not the system's aligned_alloc: {}".format(
                    undefined))
    return found


def main():
    found = failures()
    for line in found:
        print("FAIL  {}".format(line))
    if found:
        print("{} checks failed".format(len(found)))
        return 1
    print("ok    each compatibility shim keeps its call's contract and stays hidden in the image that links it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
