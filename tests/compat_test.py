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


CLOCK_AND_DIRECTORY = r"""
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

int charon_clock_gettime(clockid_t which, struct timespec *now);
DIR *charon_fdopendir(int descriptor);

static int fails;

static void expect(int holds, const char *what)
{
    if (!holds) {
        printf("FAIL  %s\n", what);
        fails++;
    }
}

int main(int argc, char **argv)
{
    struct timespec real, first, second;
    time_t before = time(NULL);
    expect(charon_clock_gettime(CLOCK_REALTIME, &real) == 0, "CLOCK_REALTIME is answered");
    expect(real.tv_sec >= before - 1 && real.tv_sec <= time(NULL) + 1, "CLOCK_REALTIME is the calendar time");
    expect(real.tv_nsec >= 0 && real.tv_nsec < 1000000000, "nanoseconds stay below a second");
    expect(charon_clock_gettime(CLOCK_MONOTONIC, &first) == 0, "CLOCK_MONOTONIC is answered");
    usleep(2000);
    expect(charon_clock_gettime(CLOCK_MONOTONIC, &second) == 0, "CLOCK_MONOTONIC is answered again");
    expect(second.tv_sec > first.tv_sec || (second.tv_sec == first.tv_sec && second.tv_nsec > first.tv_nsec),
           "CLOCK_MONOTONIC moves forward");
    struct timespec system;
    clock_gettime(CLOCK_UPTIME_RAW, &system);
    long long apart = (long long)system.tv_sec - (long long)second.tv_sec;
    expect(apart > -2 && apart < 2, "CLOCK_MONOTONIC counts the uptime iOS 6 can give, not the calendar");
    errno = 0;
    expect(charon_clock_gettime((clockid_t)12345, &first) == -1 && errno == EINVAL, "an unknown clock is refused");

    int descriptor = open(argv[1], O_RDONLY);
    DIR *directory = charon_fdopendir(descriptor);
    expect(directory != NULL, "an open directory's descriptor becomes a directory stream");
    int seen = 0;
    struct dirent *entry;
    while (directory && (entry = readdir(directory)) != NULL) {
        seen += strcmp(entry->d_name, "marker") == 0;
    }
    expect(seen == 1, "the stream lists the directory the descriptor names");
    expect(fcntl(descriptor, F_GETFD) == -1 && errno == EBADF, "the stream owns the descriptor, as fdopendir's does");
    if (directory) {
        closedir(directory);
    }
    errno = 0;
    expect(charon_fdopendir(-1) == NULL && errno == EBADF, "a descriptor that is not open is refused");
    return fails != 0;
}
"""


AT_CALLS = r"""
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

int charon_openat(int directory, const char *path, int flags, ...);
int charon_fchmodat(int directory, const char *path, mode_t mode, int flags);
int charon_unlinkat(int directory, const char *path, int flags);
int charon_clock_gettime(clockid_t which, struct timespec *now);

static int fails;

static void expect(int holds, const char *what)
{
    if (!holds) {
        printf("FAIL  %s\n", what);
        fails++;
    }
}

int main(int argc, char **argv)
{
    const char *root = argv[1];
    int directory = open(root, O_RDONLY);
    int created = charon_openat(directory, "made", O_CREAT | O_WRONLY, 0640);
    expect(created >= 0, "openat creates a file relative to a directory descriptor");
    close(created);
    char absolute[1024];
    snprintf(absolute, sizeof(absolute), "%s/made", root);
    struct stat seen;
    expect(stat(absolute, &seen) == 0 && (seen.st_mode & 0777) == 0640, "openat passes the creation mode");
    int again = charon_openat(-1, absolute, O_RDONLY);
    expect(again >= 0, "an absolute path ignores the directory descriptor");
    close(again);
    expect(chdir(root) == 0, "the test can change into its folder");
    int here = charon_openat(AT_FDCWD, "made", O_RDONLY);
    expect(here >= 0, "AT_FDCWD resolves against the working directory");
    close(here);
    expect(charon_fchmodat(directory, "made", 0600, 0) == 0 && stat(absolute, &seen) == 0 &&
           (seen.st_mode & 0777) == 0600, "fchmodat changes the mode of a file relative to a descriptor");
    errno = 0;
    expect(charon_fchmodat(directory, "made", 0600, 0x4000) == -1 && errno == EINVAL, "fchmodat refuses unknown flags");
    expect(mkdirat(directory, "folder", 0700) == 0 || mkdir("folder", 0700) == 0, "the test can make a folder");
    errno = 0;
    expect(charon_unlinkat(directory, "folder", 0) == -1, "unlinkat without AT_REMOVEDIR does not remove a folder");
    expect(charon_unlinkat(directory, "folder", AT_REMOVEDIR) == 0, "unlinkat with AT_REMOVEDIR removes a folder");
    expect(charon_unlinkat(directory, "made", 0) == 0 && stat(absolute, &seen) == -1, "unlinkat removes a file");
    errno = 0;
    expect(charon_openat(-1, "relative", O_RDONLY) == -1 && errno == EBADF,
           "a relative path against a descriptor that is not open is refused");
    struct timespec raw, uptime;
    expect(charon_clock_gettime(CLOCK_MONOTONIC_RAW, &raw) == 0, "CLOCK_MONOTONIC_RAW is answered");
    expect(charon_clock_gettime(CLOCK_UPTIME_RAW, &uptime) == 0, "CLOCK_UPTIME_RAW is answered");
    expect(charon_clock_gettime(CLOCK_MONOTONIC_RAW_APPROX, &raw) == 0 &&
           charon_clock_gettime(CLOCK_UPTIME_RAW_APPROX, &uptime) == 0, "the approximate uptime clocks are answered");
    return fails != 0;
}
"""


LIBRARY_CALLS = r"""
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

double sin(double);
double cos(double);
float sinf(float);
float cosf(float);
struct pair { double sine; double cosine; };
struct pairf { float sine; float cosine; };
struct pair __sincos_stret(double);
struct pairf __sincosf_stret(float);
size_t __strlcpy_chk(char *, const char *, size_t, size_t);
size_t __strlcat_chk(char *, const char *, size_t, size_t);

static int fails;

static void expect(int holds, const char *what)
{
    if (!holds) {
        printf("FAIL  %s\n", what);
        fails++;
    }
}

static int aborts(size_t (*call)(char *, const char *, size_t, size_t))
{
    pid_t child = fork();
    if (child == 0) {
        char small[4] = "";
        call(small, "overflowing", 8, sizeof small);
        _exit(0);
    }
    int status = 0;
    waitpid(child, &status, 0);
    return WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT;
}

int main(void)
{
    for (double x = -7.0; x < 7.0; x += 0.37) {
        struct pair both = __sincos_stret(x);
        expect(both.sine == sin(x) && both.cosine == cos(x), "__sincos_stret answers sin and cos of its argument");
        struct pairf bothf = __sincosf_stret((float)x);
        expect(bothf.sine == sinf((float)x) && bothf.cosine == cosf((float)x),
               "__sincosf_stret answers sinf and cosf of its argument");
    }
    char buffer[8] = "";
    expect(__strlcpy_chk(buffer, "abcdefghij", sizeof buffer, sizeof buffer) == 10 && strcmp(buffer, "abcdefg") == 0,
           "__strlcpy_chk truncates as strlcpy does and returns the source length");
    expect(__strlcat_chk(buffer, "xyz", sizeof buffer, sizeof buffer) == 10 && strcmp(buffer, "abcdefg") == 0,
           "__strlcat_chk truncates as strlcat does and returns the length it tried to create");
    expect(aborts(__strlcpy_chk), "__strlcpy_chk aborts when told the destination is larger than it is");
    expect(aborts(__strlcat_chk), "__strlcat_chk aborts when told the destination is larger than it is");
    return fails != 0;
}
"""


ULOCK = r"""
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/time.h>
#include <unistd.h>

int __ulock_wait(uint32_t operation, void *address, uint64_t value, uint32_t timeout);
int __ulock_wake(uint32_t operation, void *address, uint64_t value);

static int fails;

static void expect(int holds, const char *what)
{
    if (!holds) {
        printf("FAIL  %s\n", what);
        fails++;
    }
}

static _Atomic uint32_t narrow;
static _Atomic uint64_t wide;
static _Atomic int woke;

static void *wait_narrow(void *unused)
{
    (void)unused;
    while (atomic_load(&narrow) == 0)
        __ulock_wait(1, &narrow, 0, 0);
    atomic_fetch_add(&woke, 1);
    return NULL;
}

static void *wait_wide(void *unused)
{
    (void)unused;
    while (atomic_load(&wide) == 0)
        __ulock_wait(5, &wide, 0, 0);
    atomic_fetch_add(&woke, 1);
    return NULL;
}

static double now(void)
{
    struct timeval time;
    gettimeofday(&time, NULL);
    return time.tv_sec + time.tv_usec / 1e6;
}

int main(void)
{
    uint32_t differs = 7;
    expect(__ulock_wait(1, &differs, 3, 0) == 0, "a value that already differs returns at once");
    uint64_t same = 9;
    double started = now();
    expect(__ulock_wait(5, &same, 9, 50000) == -1 && errno == ETIMEDOUT, "a timed wait nobody wakes times out");
    expect(now() - started >= 0.04 && now() - started < 2.0, "the timeout is in microseconds");
    errno = 0;
    expect(__ulock_wake(1, &differs, 0) == -1 && errno == ENOENT, "waking an address nobody waits on says so");

    pthread_t threads[8];
    for (int index = 0; index < 4; index++)
        pthread_create(&threads[index], NULL, wait_narrow, NULL);
    for (int index = 4; index < 8; index++)
        pthread_create(&threads[index], NULL, wait_wide, NULL);
    usleep(100000);
    expect(atomic_load(&woke) == 0, "waiters sleep while the value is unchanged");
    atomic_store(&narrow, 1);
    __ulock_wake(1 | 0x100, &narrow, 0);
    atomic_store(&wide, 1);
    __ulock_wake(5 | 0x100, &wide, 0);
    for (int index = 0; index < 8; index++)
        pthread_join(threads[index], NULL);
    expect(atomic_load(&woke) == 8, "every waiter on 32-bit and 64-bit values wakes once it changes");
    return fails != 0;
}
"""


def run(*command, cwd):
    try:
        return subprocess.run([str(part) for part in command], cwd=cwd, capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(command, 1, "FAIL  {} did not finish in 120 seconds, which a shim that "
                                                       "calls itself or never wakes a waiter does\n".format(command[0]), "")


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
        (folder / "clock.c").write_text(CLOCK_AND_DIRECTORY)
        (folder / "listed").mkdir()
        (folder / "listed" / "marker").write_text("")
        built = run("xcrun", "clang", "-O2", SHIMS / "clock_gettime.c", SHIMS / "fdopendir.c", "clock.c", "-o", "clock",
                    cwd=folder)
        if built.returncode:
            found.append("the clock_gettime and fdopendir shims must compile: {}".format(built.stderr[-400:]))
        else:
            ran = run("./clock", folder / "listed", cwd=folder)
            found += [line[6:] for line in ran.stdout.splitlines() if line.startswith("FAIL")]
            if ran.returncode and not ran.stdout:
                found.append("the clock and directory test failed without saying why: {}".format(ran.stderr))
        (folder / "at.c").write_text(AT_CALLS)
        (folder / "at-root").mkdir()
        built = run("xcrun", "clang", "-O2", SHIMS / "openat.c", SHIMS / "fchmodat.c", SHIMS / "unlinkat.c",
                    SHIMS / "clock_gettime.c", "at.c", "-o", "at", cwd=folder)
        if built.returncode:
            found.append("the *at shims must compile: {}".format(built.stderr[-400:]))
        else:
            ran = run("./at", folder / "at-root", cwd=folder)
            found += [line[6:] for line in ran.stdout.splitlines() if line.startswith("FAIL")]
            if ran.returncode and not ran.stdout:
                found.append("the *at test failed without saying why: {}".format(ran.stderr))
        for symbol, call, include in (("clock_gettime", "struct timespec t; return clock_gettime(CLOCK_MONOTONIC, &t);", "time.h"),
                                      ("fdopendir", "return fdopendir(3) != 0;", "dirent.h"),
                                      ("openat", "return openat(3, \"x\", 0);", "fcntl.h"),
                                      ("fchmodat", "return fchmodat(3, \"x\", 0600, 0);", "sys/stat.h"),
                                      ("unlinkat", "return unlinkat(3, \"x\", 0);", "unistd.h")):
            header = SHIMS.parent / "include" / "charon" / "{}.h".format(symbol)
            (folder / "{}.c".format(symbol)).write_text("#include <{}>\nint call(void) {{ {} }}\n".format(include, call))
            called = run("xcrun", "clang", "-target", "armv7-apple-ios6.0", "-Wno-incompatible-sysroot",
                         "-include", header, "-c", "{}.c".format(symbol), "-o", "{}.o".format(symbol), cwd=folder)
            if called.returncode:
                found.append("a call to {} must compile for iOS 6 with the header: {}".format(symbol, called.stderr[-300:]))
                continue
            undefined = run("xcrun", "nm", "-u", "{}.o".format(symbol), cwd=folder).stdout.split()
            if "_" + symbol in undefined or "_charon_" + symbol not in undefined:
                found.append("a call to {} must reach charon_{}, never the system's weak import: {}".format(
                    symbol, symbol, undefined))
            shim = run("xcrun", "clang", "-target", "armv7-apple-ios6.0", "-Wno-incompatible-sysroot",
                       "-Wno-unguarded-availability", "-c", SHIMS / "{}.c".format(symbol), "-o", "shim-{}.o".format(symbol),
                       cwd=folder)
            if shim.returncode:
                found.append("the {} shim must compile for armv7 on iOS 6: {}".format(symbol, shim.stderr[-300:]))
                continue
            line = next((row for row in run("xcrun", "nm", "-m", "shim-{}.o".format(symbol), cwd=folder).stdout.splitlines()
                         if row.endswith(" _charon_" + symbol)), "")
            if "private external" not in line:
                found.append("charon_{} must be hidden: {}".format(symbol, line))

        (folder / "library.c").write_text(LIBRARY_CALLS)
        linked = ["__sincos_stret", "__sincosf_stret", "__strlcpy_chk", "__strlcat_chk"]
        built = run("xcrun", "clang", "-O2", "-D_FORTIFY_SOURCE=2", "-fno-builtin-sin", "-fno-builtin-cos",
                    "-fno-builtin-sinf", "-fno-builtin-cosf", *[SHIMS / "{}.c".format(symbol) for symbol in linked],
                    "library.c",
                    "-o", "library", cwd=folder)
        if built.returncode:
            found.append("the compiler-called shims must compile: {}".format(built.stderr[-400:]))
        else:
            ran = run("./library", cwd=folder)
            found += [line[6:] for line in ran.stdout.splitlines() if line.startswith("FAIL")]
            if ran.returncode and not ran.stdout:
                found.append("the compiler-called shims test failed without saying why: {}".format(ran.stderr))
        for symbol in linked:
            if (SHIMS.parent / "include" / "charon" / "{}.h".format(symbol)).exists():
                found.append("{} is called by the compiler, not by name, so no header may rename it".format(symbol))
            shim = run("xcrun", "clang", "-target", "armv7-apple-ios6.0", "-Wno-incompatible-sysroot", "-Os",
                       "-c", SHIMS / "{}.c".format(symbol), "-o", "shim-{}.o".format(symbol), cwd=folder)
            listing = run("xcrun", "nm", "-m", "shim-{}.o".format(symbol), cwd=folder).stdout
            line = next((row for row in listing.splitlines() if row.endswith(" _" + symbol)), "")
            if shim.returncode or "private external" not in line:
                found.append("{} must compile for iOS 6 as a hidden definition: {} {}".format(
                    symbol, shim.stderr[-300:], listing))
            if "_" + symbol in run("xcrun", "nm", "-u", "shim-{}.o".format(symbol), cwd=folder).stdout.split():
                found.append("{} compiled for iOS 6 must not call itself".format(symbol))
        (folder / "ulock.c").write_text(ULOCK)
        built = run("xcrun", "clang", "-O2", SHIMS / "__ulock_wait.c", SHIMS / "__ulock_wake.c", "ulock.c", "-o", "ulock",
                    cwd=folder)
        if built.returncode:
            found.append("the __ulock shims must compile: {}".format(built.stderr[-400:]))
        else:
            ran = run("./ulock", cwd=folder)
            found += [line[6:] for line in ran.stdout.splitlines() if line.startswith("FAIL")]
            if ran.returncode and not ran.stdout:
                found.append("the __ulock test failed without saying why: {}".format(ran.stderr))
        for symbol in ("__ulock_wait", "__ulock_wake"):
            shim = run("xcrun", "clang", "-target", "armv7-apple-ios6.0", "-Wno-incompatible-sysroot", "-Os", "-c",
                       SHIMS / "{}.c".format(symbol), "-o", "shim-{}.o".format(symbol), cwd=folder)
            listing = run("xcrun", "nm", "-m", "shim-{}.o".format(symbol), cwd=folder).stdout
            line = next((row for row in listing.splitlines() if row.endswith(" _" + symbol)), "")
            if shim.returncode or "private external" not in line:
                found.append("{} must compile for iOS 6 as a hidden definition: {} {}".format(
                    symbol, shim.stderr[-300:], listing))

        (folder / "late.c").write_text("#include <math.h>\n#include <string.h>\n"
                                       "double both(double x) { return sin(x) + cos(x); }\n"
                                       "unsigned long copy(char *d, const char *s) { char b[8]; "
                                       "return strlcpy(b, s, sizeof b) + strlcat(d, b, 8); }\n")
        late = run("xcrun", "clang", "-target", "armv7-apple-ios9.0", "-Wno-incompatible-sysroot", "-O2",
                   "-D_FORTIFY_SOURCE=2", "-c", "late.c", "-o", "late.o", cwd=folder)
        wanted = set(run("xcrun", "nm", "-u", "late.o", cwd=folder).stdout.split())
        if late.returncode or not {"___sincos_stret", "___strlcpy_chk"} <= wanted:
            found.append("code compiled for iOS 7 or later must call these by name, or the shims cover nothing: "
                         "{} {}".format(late.stderr[-300:], sorted(wanted)))

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
