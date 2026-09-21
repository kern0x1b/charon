#!/usr/bin/env python3
"""Check the compatibility shims keep the contract of the call they stand in for.

    tests/compat_test.py

Each shim is compiled for this machine and exercised, because the device it is
for cannot run a test here; and each is checked to be a hidden definition, so
the image that links it binds its own calls to it and exports nothing another
image could bind to - except the locks, whose waiters and wakes every image of a
process must share, which are exported from one copy that all images bind to.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SHIMS = HERE.parent / "packages" / "a" / "apple-compat" / "src"

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
    static const struct { clockid_t clock; const char *what; long long tolerance; } clocks[] = {
        { CLOCK_MONOTONIC, "CLOCK_MONOTONIC counts from boot, sleep included, as Darwin's does", 5000000LL },
        { CLOCK_UPTIME_RAW, "CLOCK_UPTIME_RAW counts the time awake, as Darwin's does", 5000000LL },
        { CLOCK_PROCESS_CPUTIME_ID, "CLOCK_PROCESS_CPUTIME_ID counts this process's processor time", 20000000LL },
        { CLOCK_THREAD_CPUTIME_ID, "CLOCK_THREAD_CPUTIME_ID counts this thread's processor time", 20000000LL },
    };
    for (volatile long spin = 0; spin < 30000000; spin++) {
    }
    for (size_t index = 0; index < sizeof clocks / sizeof clocks[0]; index++) {
        struct timespec ours, darwins;
        int answered = charon_clock_gettime(clocks[index].clock, &ours);
        clock_gettime(clocks[index].clock, &darwins);
        long long apart = ((long long)darwins.tv_sec - ours.tv_sec) * 1000000000LL + darwins.tv_nsec - ours.tv_nsec;
        expect(answered == 0 && apart > -clocks[index].tolerance && apart < clocks[index].tolerance &&
               ours.tv_nsec >= 0 && ours.tv_nsec < 1000000000, clocks[index].what);
    }
    struct timespec monotonic, raw;
    charon_clock_gettime(CLOCK_MONOTONIC, &monotonic);
    charon_clock_gettime(CLOCK_MONOTONIC_RAW, &raw);
    long long drift = ((long long)raw.tv_sec - monotonic.tv_sec) * 1000000000LL + raw.tv_nsec - monotonic.tv_nsec;
    expect(drift >= 0 && drift < 5000000LL,
           "CLOCK_MONOTONIC_RAW counts from boot with sleep, the only such clock iOS 6 has");
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


UNFAIR_LOCK = r"""
#include <dlfcn.h>
#include <mach/mach.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct { uint32_t value; } lock_t;
typedef struct { lock_t lock; uint32_t count; } recursive_t;
void os_unfair_lock_lock(lock_t *);
bool os_unfair_lock_trylock(lock_t *);
void os_unfair_lock_unlock(lock_t *);
void os_unfair_recursive_lock_lock_with_options(recursive_t *, uint32_t);
void os_unfair_recursive_lock_unlock(recursive_t *);

static int fails;

static void expect(int holds, const char *what)
{
    if (!holds) {
        printf("FAIL  %s\n", what);
        fails++;
    }
}

struct api {
    void (*lock)(lock_t *);
    bool (*trylock)(lock_t *);
    void (*unlock)(lock_t *);
};

static struct api ours = { os_unfair_lock_lock, os_unfair_lock_trylock, os_unfair_lock_unlock };
static struct api darwins;
static const struct api *using;
static lock_t shared;
static long counter;
static _Atomic int holding;
static _Atomic(uint32_t) seen;

static void *hold(void *unused)
{
    (void)unused;
    using->lock(&shared);
    atomic_store(&holding, 1);
    usleep(200000);
    atomic_store(&seen, shared.value);
    using->unlock(&shared);
    return NULL;
}

static void *contend(void *unused)
{
    (void)unused;
    using->lock(&shared);
    using->unlock(&shared);
    return NULL;
}

static void *count(void *unused)
{
    (void)unused;
    for (int round = 0; round < 20000; round++) {
        using->lock(&shared);
        counter++;
        using->unlock(&shared);
    }
    return NULL;
}

static void *try_other(void *unused)
{
    (void)unused;
    return (void *)(intptr_t)using->trylock(&shared);
}

static int dies(void (*body)(void))
{
    fflush(stdout);
    pid_t child = fork();
    if (child == 0) {
        freopen("/dev/null", "w", stderr);
        alarm(10);
        body();
        _exit(0);
    }
    int status = 0;
    waitpid(child, &status, 0);
    return WIFSIGNALED(status) && WTERMSIG(status) != SIGALRM;
}

static void relock(void) { lock_t lock = {0}; using->lock(&lock); using->lock(&lock); }
static void unlock_unlocked(void) { lock_t lock = {0}; using->unlock(&lock); }
static void *take(void *lock) { using->lock(lock); return NULL; }
static void unlock_foreign(void) { lock_t lock = {0}; pthread_t thread; pthread_create(&thread, NULL, take, &lock); pthread_join(thread, NULL); using->unlock(&lock); }

static void behaves(const struct api *api, const char *name)
{
    char what[256];
    using = api;
    uint32_t self = pthread_mach_thread_np(pthread_self()) | 1;
    snprintf(what, sizeof what, "%s: this kernel hands out odd thread port names, so the shim's word is Darwin's own", name);
    expect(self == pthread_mach_thread_np(pthread_self()), what);
    shared.value = 0;
    api->lock(&shared);
    snprintf(what, sizeof what, "%s: a held lock records the owner's Mach thread port name with the no-waiters bit", name);
    expect(shared.value == self, what);
    snprintf(what, sizeof what, "%s: trylock of a lock this thread holds fails", name);
    expect(!api->trylock(&shared), what);
    pthread_t thread;
    pthread_create(&thread, NULL, try_other, NULL);
    void *got;
    pthread_join(thread, &got);
    snprintf(what, sizeof what, "%s: trylock of a lock another thread holds fails", name);
    expect(got == NULL, what);
    api->unlock(&shared);
    snprintf(what, sizeof what, "%s: unlock leaves the lock free", name);
    expect(shared.value == 0, what);
    pthread_create(&thread, NULL, try_other, NULL);
    pthread_join(thread, &got);
    snprintf(what, sizeof what, "%s: trylock of a free lock takes it", name);
    expect(got != NULL && shared.value != 0, what);
    shared.value = 0;

    atomic_store(&holding, 0);
    pthread_t holder, waiter;
    pthread_create(&holder, NULL, hold, NULL);
    while (!atomic_load(&holding))
        usleep(1000);
    pthread_create(&waiter, NULL, contend, NULL);
    pthread_join(holder, NULL);
    pthread_join(waiter, NULL);
    snprintf(what, sizeof what, "%s: a waiter clears the low bit of the owner's word, so the unlock wakes it", name);
    expect((atomic_load(&seen) & 1) == 0 && atomic_load(&seen) != 0, what);
    snprintf(what, sizeof what, "%s: the waiter gets the lock and releases it", name);
    expect(shared.value == 0, what);

    counter = 0;
    pthread_t threads[8];
    for (int index = 0; index < 8; index++)
        pthread_create(&threads[index], NULL, count, NULL);
    for (int index = 0; index < 8; index++)
        pthread_join(threads[index], NULL);
    snprintf(what, sizeof what, "%s: eight threads contending lose no update", name);
    expect(counter == 8 * 20000, what);

    snprintf(what, sizeof what, "%s: locking a lock this thread holds crashes", name);
    expect(dies(relock), what);
    snprintf(what, sizeof what, "%s: unlocking a free lock crashes", name);
    expect(dies(unlock_unlocked), what);
    snprintf(what, sizeof what, "%s: unlocking another thread's lock crashes", name);
    expect(dies(unlock_foreign), what);
}

typedef void (*recursive_lock_f)(recursive_t *, uint32_t);
typedef void (*recursive_unlock_f)(recursive_t *);

static void recursive(recursive_lock_f lock, recursive_unlock_f unlock, const char *name)
{
    char what[256];
    recursive_t held = {{0}, 0};
    uint32_t self = pthread_mach_thread_np(pthread_self()) | 1;
    lock(&held, 0);
    lock(&held, 0);
    lock(&held, 0);
    snprintf(what, sizeof what, "%s: a recursive lock taken three times holds the owner and a count of two", name);
    expect(held.lock.value == self && held.count == 2, what);
    unlock(&held);
    unlock(&held);
    snprintf(what, sizeof what, "%s: two unlocks leave it held once", name);
    expect(held.lock.value == self && held.count == 0, what);
    unlock(&held);
    snprintf(what, sizeof what, "%s: the last unlock frees it", name);
    expect(held.lock.value == 0, what);
}

int main(void)
{
    void *platform = dlopen("/usr/lib/system/libsystem_platform.dylib", RTLD_LAZY | RTLD_NOLOAD);
    darwins.lock = platform ? dlsym(platform, "os_unfair_lock_lock") : NULL;
    darwins.trylock = platform ? dlsym(platform, "os_unfair_lock_trylock") : NULL;
    darwins.unlock = platform ? dlsym(platform, "os_unfair_lock_unlock") : NULL;
    expect(darwins.lock && darwins.lock != ours.lock, "the test reaches Darwin's os_unfair_lock_lock beside the shim");
    behaves(&darwins, "Darwin");
    behaves(&ours, "the shim");
    recursive_lock_f darwin_lock = platform ? dlsym(platform, "os_unfair_recursive_lock_lock_with_options") : NULL;
    recursive_unlock_f darwin_unlock = platform ? dlsym(platform, "os_unfair_recursive_lock_unlock") : NULL;
    if (darwin_lock && darwin_unlock)
        recursive(darwin_lock, darwin_unlock, "Darwin");
    recursive(os_unfair_recursive_lock_lock_with_options, os_unfair_recursive_lock_unlock, "the shim");
    return fails != 0;
}
"""


PORT_NAMES = r"""
#include <mach/mach.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <unistd.h>

#include "unfair_lock.h"

/* XNU hands out odd thread port names, and libplatform's word format relies on it; Shade hands out even ones (0x10c00,
   spaced by 0x100). The shim sets the low bit itself, so both work; here each case runs with owner values the two kernels
   would give, through the same words the lock keeps. */

static int fails;

static void expect(int holds, const char *what)
{
    if (!holds) {
        printf("FAIL  %s\n", what);
        fails++;
    }
}

static charon_unfair_lock shared;
static uint32_t owners[2];
static _Atomic int held;
static _Atomic(uint32_t) seen;
static _Atomic long counter;

static void *hold(void *which)
{
    uint32_t self = charon_unfair_owner(owners[(intptr_t)which]);
    charon_unfair_lock_lock(&shared, self);
    atomic_store(&held, 1);
    usleep(150000);
    atomic_store(&seen, atomic_load(&shared.value));
    charon_unfair_unlock(&shared, self);
    return NULL;
}

static void *wait_for_it(void *which)
{
    uint32_t self = charon_unfair_owner(owners[(intptr_t)which]);
    for (int round = 0; round < 200; round++) {
        charon_unfair_lock_lock(&shared, self);
        atomic_fetch_add(&counter, 1);
        charon_unfair_unlock(&shared, self);
    }
    return NULL;
}

static void names(uint32_t first, uint32_t second, const char *what)
{
    char said[160];
    owners[0] = first;
    owners[1] = second;
    atomic_store(&shared.value, 0);
    atomic_store(&held, 0);
    atomic_store(&counter, 0);
    pthread_t holder, waiter;
    pthread_create(&holder, NULL, hold, (void *)0);
    while (!atomic_load(&held))
        usleep(1000);
    pthread_create(&waiter, NULL, wait_for_it, (void *)1);
    pthread_join(holder, NULL);
    pthread_join(waiter, NULL);
    snprintf(said, sizeof said, "a lock whose owners have %s port names hands over to a waiter", what);
    expect(atomic_load(&counter) == 200 && atomic_load(&shared.value) == 0, said);
    snprintf(said, sizeof said, "a waiter on %s port names clears the low bit of the owner's word", what);
    expect((atomic_load(&seen) & CHARON_UNFAIR_NO_WAITERS) == 0 && atomic_load(&seen) != 0, said);
}

static void stalled(int signal)
{
    (void)signal;
    printf("FAIL  a lock whose owners have the port names one of these kernels gives hands over to a waiter; one slept for 30 s\n");
    fflush(stdout);
    _exit(1);
}

int main(void)
{
    signal(SIGALRM, stalled);
    alarm(30);
    names(0x1e03, 0x1e17, "the odd");
    names(0x10c00, 0x11e00, "the even");
    uint32_t self = charon_unfair_self();
    expect((self & CHARON_UNFAIR_NO_WAITERS) != 0 && (self | CHARON_UNFAIR_NO_WAITERS) == self,
           "the owner a thread records always carries the no-waiters bit, whichever name the kernel gave it");
    expect(self == (pthread_mach_thread_np(pthread_self()) | CHARON_UNFAIR_NO_WAITERS),
           "the owner is this thread's Mach port name with that bit set");
    return fails != 0;
}
"""


LOCK_SIDE = r"""
#include <stdint.h>
typedef struct { uint32_t value; } lock_t;
void os_unfair_lock_lock(lock_t *);
void os_unfair_lock_unlock(lock_t *);
__attribute__((visibility("default"))) void SIDE_lock(lock_t *lock) { os_unfair_lock_lock(lock); }
__attribute__((visibility("default"))) void SIDE_unlock(lock_t *lock) { os_unfair_lock_unlock(lock); }
"""


TWO_IMAGES = r"""
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/time.h>
#include <signal.h>
#include <unistd.h>

typedef struct { uint32_t value; } lock_t;
void one_lock(lock_t *);
void one_unlock(lock_t *);
void two_lock(lock_t *);
void two_unlock(lock_t *);

static lock_t shared;

static void stalled(int signal)
{
    (void)signal;
    printf("FAIL  two images that bind the lock to one copy wake each other; a waiter slept past every unlock for 30 s\n");
    fflush(stdout);
    _exit(1);
}
static long counter;

static void *through_one(void *unused)
{
    (void)unused;
    for (int round = 0; round < 3000; round++) {
        one_lock(&shared);
        counter++;
        if (round % 500 == 0)
            usleep(2000);
        one_unlock(&shared);
    }
    return NULL;
}

static void *through_two(void *unused)
{
    (void)unused;
    for (int round = 0; round < 3000; round++) {
        two_lock(&shared);
        counter++;
        if (round % 500 == 0)
            usleep(2000);
        two_unlock(&shared);
    }
    return NULL;
}

int main(void)
{
    signal(SIGALRM, stalled);
    alarm(30);
    struct timeval start, end;
    gettimeofday(&start, NULL);
    pthread_t threads[8];
    for (int index = 0; index < 8; index++)
        pthread_create(&threads[index], NULL, index % 2 ? through_two : through_one, NULL);
    for (int index = 0; index < 8; index++)
        pthread_join(threads[index], NULL);
    gettimeofday(&end, NULL);
    double seconds = (end.tv_sec - start.tv_sec) + (end.tv_usec - start.tv_usec) / 1e6;
    int fails = 0;
    if (counter != 8 * 3000) {
        printf("FAIL  a lock two images take, each with its own copy of the shim, loses no update\n");
        fails++;
    }
    (void)seconds;
    return fails;
}
"""


FORWARDED_LOCK = r"""
#include <dlfcn.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef struct { uint32_t value; } lock_t;
void os_unfair_lock_lock(lock_t *);
void os_unfair_lock_unlock(lock_t *);

static void (*darwin_lock)(lock_t *);
static void (*darwin_unlock)(lock_t *);
static lock_t shared;
static _Atomic int done;

static void stalled(int signal)
{
    (void)signal;
    printf("FAIL  the exported copy reaches the system's os_unfair_lock by opening libsystem_platform, not by a search that finds the copy itself\n");
    fflush(stdout);
    _exit(1);
}

static void *wait_in_darwin(void *unused)
{
    (void)unused;
    darwin_lock(&shared);
    darwin_unlock(&shared);
    atomic_store(&done, 1);
    return NULL;
}

int main(void)
{
    int fails = 0;
    signal(SIGALRM, stalled);
    alarm(20);
    void *platform = dlopen("/usr/lib/system/libsystem_platform.dylib", RTLD_LAZY | RTLD_NOLOAD);
    darwin_lock = platform ? dlsym(platform, "os_unfair_lock_lock") : NULL;
    darwin_unlock = platform ? dlsym(platform, "os_unfair_lock_unlock") : NULL;
    Dl_info first;
    void *found = dlsym(RTLD_DEFAULT, "os_unfair_lock_lock");
    if (!darwin_lock || !found || found == darwin_lock || !dladdr(found, &first) || !strstr(first.dli_fname, "libshared")) {
        printf("FAIL  the test must reproduce the trap: a search of every image finds the exported copy before the system's\n");
        fails++;
    }
    os_unfair_lock_lock(&shared);
    pthread_t waiter;
    pthread_create(&waiter, NULL, wait_in_darwin, NULL);
    usleep(200000);
    os_unfair_lock_unlock(&shared);
    for (int tick = 0; tick < 500 && !atomic_load(&done); tick++)
        usleep(10000);
    if (!atomic_load(&done)) {
        printf("FAIL  where the system has os_unfair_lock, the exported copy is the system's, so a waiter in the system's lock hears its unlock\n");
        fails++;
    }
    return fails != 0;
}
"""


SYSTEM_RANDOM = r"""
#include <stdio.h>
#include <stdint.h>
#include <string.h>

void charon_arc4random_buf(void *, size_t);
void arc4random_buf(void *, size_t);

/* The stream the shim reads only where the release has no arc4random_buf of its own. This one is compiled with the
   system's, so what the shim answers must not be these words: it must ask the library that defines the call. */
uint32_t arc4random(void)
{
    return 0x5c5c5c5c;
}

int main(void)
{
    unsigned char bytes[32];
    memset(bytes, 0xaa, sizeof bytes);
    charon_arc4random_buf(bytes, sizeof bytes);
    int ours = 1;
    for (size_t at = 0; at < sizeof bytes; at++) {
        if (bytes[at] != 0x5c)
            ours = 0;
    }
    if (ours) {
        printf("FAIL  arc4random_buf must use the system's where the release has it, not its own stream\n");
        return 1;
    }
    return 0;
}
"""

DISPATCH_BLOCKS = r"""
#include <Block.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

/* The shim's own calls are the ones this program defines; Darwin's are the same calls in libdispatch, opened by path. Each
   scenario runs against both and the two must answer alike. */
typedef dispatch_block_t (*create_f)(unsigned long, dispatch_block_t);
typedef dispatch_block_t (*create_qos_f)(unsigned long, unsigned int, int, dispatch_block_t);
typedef void (*perform_f)(unsigned long, dispatch_block_t);
typedef intptr_t (*wait_f)(dispatch_block_t, dispatch_time_t);
typedef void (*notify_f)(dispatch_block_t, dispatch_queue_t, dispatch_block_t);
typedef void (*cancel_f)(dispatch_block_t);
typedef intptr_t (*testcancel_f)(dispatch_block_t);

dispatch_block_t dispatch_block_create(unsigned long, dispatch_block_t);
dispatch_block_t dispatch_block_create_with_qos_class(unsigned long, unsigned int, int, dispatch_block_t);
void dispatch_block_perform(unsigned long, dispatch_block_t);
intptr_t dispatch_block_wait(dispatch_block_t, dispatch_time_t);
void dispatch_block_notify(dispatch_block_t, dispatch_queue_t, dispatch_block_t);
void dispatch_block_cancel(dispatch_block_t);
intptr_t dispatch_block_testcancel(dispatch_block_t);

struct api {
    create_f create; create_qos_f create_qos; perform_f perform; wait_f wait; notify_f notify; cancel_f cancel;
    testcancel_f testcancel;
};

static int fails;
static int ran;

static void expect(int holds, const char *what)
{
    if (!holds) {
        printf("FAIL  %s\n", what);
        fails++;
    }
}

static char *scenario(const struct api *api, char *log, size_t size)
{
    dispatch_queue_t queue = dispatch_queue_create("scenario", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t parallel = dispatch_queue_create("parallel", DISPATCH_QUEUE_CONCURRENT);
    size_t at = 0;
#define LOG(...) at += snprintf(log + at, size - at, __VA_ARGS__)

    ran = 0;
    dispatch_block_t work = api->create(0, ^{ __atomic_add_fetch(&ran, 1, __ATOMIC_SEQ_CST); });
    dispatch_async(queue, work);
    LOG("run:wait=%ld ran=%d cancelled=%ld;", (long)api->wait(work, DISPATCH_TIME_FOREVER), ran, (long)api->testcancel(work));
    Block_release(work);

    ran = 0;
    work = api->create(0, ^{ __atomic_add_fetch(&ran, 1, __ATOMIC_SEQ_CST); });
    api->cancel(work);
    LOG("cancel:test=%ld;", (long)api->testcancel(work));
    dispatch_async(queue, work);
    LOG("wait=%ld ran=%d;", (long)api->wait(work, DISPATCH_TIME_FOREVER), ran);
    Block_release(work);

    ran = 0;
    work = api->create(0, ^{ __atomic_add_fetch(&ran, 1, __ATOMIC_SEQ_CST); });
    LOG("timeout:wait=%d;", api->wait(work, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_MSEC)) != 0);
    dispatch_async(queue, work);
    LOG("again=%ld ran=%d;", (long)api->wait(work, DISPATCH_TIME_FOREVER), ran);
    Block_release(work);

    ran = 0;
    __block int notified = 0;
    dispatch_semaphore_t told = dispatch_semaphore_create(0);
    work = api->create(0, ^{ __atomic_add_fetch(&ran, 1, __ATOMIC_SEQ_CST); });
    api->notify(work, parallel, ^{ notified = ran; dispatch_semaphore_signal(told); });
    dispatch_async(queue, work);
    LOG("notify:got=%d ran-at-notice=%d;", dispatch_semaphore_wait(told, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0, notified);
    Block_release(work);

    ran = 0;
    api->perform(0, ^{ __atomic_add_fetch(&ran, 1, __ATOMIC_SEQ_CST); });
    LOG("perform:ran=%d;", ran);

    ran = 0;
    work = api->create(0, ^{ __atomic_add_fetch(&ran, 1, __ATOMIC_SEQ_CST); });
    work();
    work();
    LOG("direct:twice=%d;", ran);
    Block_release(work);

    dispatch_block_t some = ^{ };
    LOG("valid:flags=%d qos=%d rel=%d ok=", api->create(0x100, some) == NULL, api->create_qos(0, 0x99, 0, some) == NULL,
        api->create_qos(0, 0x21, -16, some) == NULL);
    dispatch_block_t fine = api->create_qos(0x20, 0x21, -3, some);
    LOG("%d;", fine != NULL);
    if (fine)
        Block_release(fine);
    fine = api->create_qos(0, 0x00, 0, some);
    LOG("unspecified=%d;", fine != NULL);
    if (fine)
        Block_release(fine);

    dispatch_semaphore_t left = dispatch_semaphore_create(0);
    work = api->create(0, ^{ });
    api->notify(work, parallel, ^{ dispatch_semaphore_signal(left); });
    Block_release(work);
    LOG("dispose:notified=%d;", dispatch_semaphore_wait(left, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0);

    ran = 0;
    work = api->create(DISPATCH_BLOCK_BARRIER | DISPATCH_BLOCK_ENFORCE_QOS_CLASS, ^{ __atomic_add_fetch(&ran, 1, __ATOMIC_SEQ_CST); });
    dispatch_async(parallel, work);
    LOG("flags:wait=%ld ran=%d;", (long)api->wait(work, DISPATCH_TIME_FOREVER), ran);
    Block_release(work);

    /* The work item a Swift program makes: created with a class, waited for after its queue runs it, or cancelled while it waits. */
    ran = 0;
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    dispatch_async(queue, ^{ dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER); });
    work = api->create_qos(DISPATCH_BLOCK_ENFORCE_QOS_CLASS, 0x15, 0, ^{ __atomic_add_fetch(&ran, 1, __ATOMIC_SEQ_CST); });
    dispatch_async(queue, work);
    api->cancel(work);
    dispatch_semaphore_signal(gate);
    LOG("cancelled-queued:wait=%ld ran=%d test=%ld;", (long)api->wait(work, DISPATCH_TIME_FOREVER), ran, (long)api->testcancel(work));
    Block_release(work);
    dispatch_release(queue);
    dispatch_release(parallel);
    return log;
}

int main(void)
{
    struct api ours = {dispatch_block_create, dispatch_block_create_with_qos_class, dispatch_block_perform, dispatch_block_wait,
                       dispatch_block_notify, dispatch_block_cancel, dispatch_block_testcancel};
    void *libdispatch = dlopen("/usr/lib/system/libdispatch.dylib", RTLD_LAZY | RTLD_LOCAL);
    expect(libdispatch != NULL, "the test reaches Darwin's libdispatch beside the shim");
    struct api darwins = {dlsym(libdispatch, "dispatch_block_create"), dlsym(libdispatch, "dispatch_block_create_with_qos_class"),
                          dlsym(libdispatch, "dispatch_block_perform"), dlsym(libdispatch, "dispatch_block_wait"),
                          dlsym(libdispatch, "dispatch_block_notify"), dlsym(libdispatch, "dispatch_block_cancel"),
                          dlsym(libdispatch, "dispatch_block_testcancel")};
    expect(darwins.create && (void *)darwins.create != (void *)ours.create, "Darwin's dispatch_block_create is not the shim");
    char mine[2048], theirs[2048];
    scenario(&ours, mine, sizeof mine);
    scenario(&darwins, theirs, sizeof theirs);
    if (strcmp(mine, theirs)) {
        printf("FAIL  the shim and Darwin answer alike\n  shim:   %s\n  darwin: %s\n", mine, theirs);
        fails++;
    }
    return fails != 0;
}
"""

UNFAIR_ASSERT = r"""
#include <dlfcn.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct { uint32_t word; } lock_t;
void os_unfair_lock_lock(lock_t *);
void os_unfair_lock_unlock(lock_t *);
void os_unfair_lock_assert_owner(const lock_t *);
void os_unfair_lock_assert_not_owner(const lock_t *);

static int fails;
static lock_t held_elsewhere;
static lock_t gate;

static void expect(int holds, const char *what)
{
    if (!holds) {
        printf("FAIL  %s\n", what);
        fails++;
    }
}

/* Does the call end the process? Run it in a child and see. A lock is a thread's, and the child's thread is another one than
   the parent's, so the child takes the lock itself when the call is to find it held. */
static int dies(void (*call)(const lock_t *), lock_t *lock, int take)
{
    fflush(stdout);
    pid_t child = fork();
    if (child == 0) {
        freopen("/dev/null", "w", stderr);
        if (take)
            os_unfair_lock_lock(lock);
        call(lock);
        _exit(0);
    }
    int status = 0;
    waitpid(child, &status, 0);
    return WIFSIGNALED(status);
}

static void *other(void *unused)
{
    os_unfair_lock_lock(&held_elsewhere);
    os_unfair_lock_lock(&gate);
    os_unfair_lock_unlock(&gate);
    os_unfair_lock_unlock(&held_elsewhere);
    return NULL;
}

int main(void)
{
    void *platform = dlopen("/usr/lib/system/libsystem_platform.dylib", RTLD_LAZY | RTLD_LOCAL);
    void (*darwin_owner)(const lock_t *) = platform ? dlsym(platform, "os_unfair_lock_assert_owner") : NULL;
    void (*darwin_not_owner)(const lock_t *) = platform ? dlsym(platform, "os_unfair_lock_assert_not_owner") : NULL;
    expect(darwin_owner && (void *)darwin_owner != (void *)os_unfair_lock_assert_owner, "the test reaches Darwin's assert beside the shim");
    lock_t mine = {0};
    struct { const char *name; void (*owner)(const lock_t *); void (*not_owner)(const lock_t *); } sides[] = {
        {"the shim", os_unfair_lock_assert_owner, os_unfair_lock_assert_not_owner},
        {"Darwin", darwin_owner, darwin_not_owner}};
    for (int side = 0; side < 2; side++) {
        char what[160];
        sides[side].not_owner(&mine);
        snprintf(what, sizeof what, "%s: an unlocked lock is not owned by this thread", sides[side].name);
        expect(!dies(sides[side].not_owner, &mine, 0), what);
        snprintf(what, sizeof what, "%s: assert_owner ends the process on an unlocked lock", sides[side].name);
        expect(dies(sides[side].owner, &mine, 0), what);
        snprintf(what, sizeof what, "%s: a lock this thread holds is owned by it", sides[side].name);
        expect(!dies(sides[side].owner, &mine, 1), what);
        snprintf(what, sizeof what, "%s: assert_not_owner ends the process on a lock this thread holds", sides[side].name);
        expect(dies(sides[side].not_owner, &mine, 1), what);
        os_unfair_lock_lock(&mine);
        sides[side].owner(&mine);
        os_unfair_lock_unlock(&mine);
    }
    os_unfair_lock_lock(&gate);
    pthread_t thread;
    pthread_create(&thread, NULL, other, NULL);
    while (__atomic_load_n(&held_elsewhere.word, __ATOMIC_ACQUIRE) == 0)
        usleep(1000);
    for (int side = 0; side < 2; side++) {
        char what[160];
        snprintf(what, sizeof what, "%s: a lock another thread holds is not this thread's", sides[side].name);
        expect(!dies(sides[side].not_owner, &held_elsewhere, 0), what);
        snprintf(what, sizeof what, "%s: assert_owner ends the process on a lock another thread holds", sides[side].name);
        expect(dies(sides[side].owner, &held_elsewhere, 0), what);
    }
    os_unfair_lock_unlock(&gate);
    pthread_join(thread, NULL);
    return fails != 0;
}
"""

DISPATCH_QUEUES = r"""
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

/* The calls of the shims are the ones this program defines; Darwin's are the same calls in libdispatch, opened by path. A
   scenario that must end the process runs in a child that is this program again, since libdispatch is not usable after a fork. */
extern char **environ;

typedef void (*assert_f)(dispatch_queue_t);
typedef unsigned int (*qos_f)(dispatch_queue_t, int *);
typedef dispatch_queue_t (*create_f)(const char *, dispatch_queue_attr_t, dispatch_queue_t);
typedef dispatch_queue_attr_t (*qos_attr_f)(dispatch_queue_attr_t, unsigned int, int);

void dispatch_assert_queue_not(dispatch_queue_t) __asm("_dispatch_assert_queue_not$V2");
void dispatch_assert_queue_barrier(dispatch_queue_t);
unsigned int dispatch_queue_get_qos_class(dispatch_queue_t, int *);
dispatch_queue_t dispatch_queue_create_with_target(const char *, dispatch_queue_attr_t, dispatch_queue_t) __asm("_dispatch_queue_create_with_target$V2");
dispatch_queue_attr_t dispatch_queue_attr_make_with_qos_class(dispatch_queue_attr_t, unsigned int, int);
dispatch_queue_attr_t dispatch_queue_attr_make_initially_inactive(dispatch_queue_attr_t);
dispatch_queue_attr_t dispatch_queue_attr_make_with_autorelease_frequency(dispatch_queue_attr_t, unsigned long);

struct api {
    assert_f not_on, barrier;
    qos_f qos;
    create_f create;
    qos_attr_f qos_attr;
};

static struct api ours, darwins;
static char *self;
static int fails;

static void expect(int holds, const char *what)
{
    if (!holds) {
        printf("FAIL  %s\n", what);
        fails++;
    }
}

static void on_queue(dispatch_queue_t queue, void (^work)(void))
{
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(queue, ^{ work(); dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
}

/* One scenario, in this process; it returns when nothing was wrong. */
static void scenario(const struct api *api, const char *name)
{
    dispatch_queue_t serial = dispatch_queue_create("scenario.serial", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t other = dispatch_queue_create("scenario.other", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t target = dispatch_queue_create("scenario.target", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t targeting = api->create("scenario.targeting", DISPATCH_QUEUE_SERIAL, target);
    if (!strcmp(name, "not-main-on-main"))
        api->not_on(dispatch_get_main_queue());
    else if (!strcmp(name, "not-main-off-main"))
        on_queue(serial, ^{ api->not_on(dispatch_get_main_queue()); });
    else if (!strcmp(name, "not-serial-inside"))
        on_queue(serial, ^{ api->not_on(serial); });
    else if (!strcmp(name, "not-serial-outside"))
        api->not_on(serial);
    else if (!strcmp(name, "not-other-inside"))
        on_queue(serial, ^{ api->not_on(other); });
    else if (!strcmp(name, "not-target-inside-targeting"))
        on_queue(targeting, ^{ api->not_on(target); });
    else if (!strcmp(name, "not-global-inside"))
        on_queue(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ api->not_on(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)); });
    else if (!strcmp(name, "barrier-inside"))
        on_queue(serial, ^{ api->barrier(serial); });
    else if (!strcmp(name, "barrier-outside"))
        api->barrier(serial);
}

static int ends(const char *program, const char *name, const char *side)
{
    fflush(stdout);
    char *argv[] = {(char *)program, (char *)name, (char *)side, NULL};
    pid_t child;
    if (posix_spawn(&child, program, NULL, NULL, argv, environ))
        return -1;
    int status = 0;
    waitpid(child, &status, 0);
    return WIFSIGNALED(status);
}

int main(int argc, char **argv)
{
    ours = (struct api){dispatch_assert_queue_not, dispatch_assert_queue_barrier, dispatch_queue_get_qos_class,
                        dispatch_queue_create_with_target, dispatch_queue_attr_make_with_qos_class};
    void *libdispatch = dlopen("/usr/lib/system/libdispatch.dylib", RTLD_LAZY | RTLD_LOCAL);
    darwins = (struct api){dlsym(libdispatch, "dispatch_assert_queue_not$V2"), dlsym(libdispatch, "dispatch_assert_queue_barrier"),
                           dlsym(libdispatch, "dispatch_queue_get_qos_class"), dlsym(libdispatch, "dispatch_queue_create_with_target$V2"),
                           dlsym(libdispatch, "dispatch_queue_attr_make_with_qos_class")};
    if (argc == 3) {
        scenario(!strcmp(argv[2], "shim") ? &ours : &darwins, argv[1]);
        return 0;
    }
    self = argv[0];
    expect(libdispatch && darwins.not_on && (void *)darwins.not_on != (void *)ours.not_on, "the test reaches Darwin's dispatch_assert_queue_not beside the shim");
    static const char *names[] = {"not-main-on-main", "not-main-off-main", "not-serial-inside", "not-serial-outside", "not-other-inside",
                                  "not-target-inside-targeting", "not-global-inside", "barrier-inside", "barrier-outside"};
    for (unsigned index = 0; index < sizeof names / sizeof names[0]; index++) {
        int mine = ends(self, names[index], "shim"), theirs = ends(self, names[index], "darwin");
        char what[200];
        snprintf(what, sizeof what, "%s: the shim ends the process as Darwin does (shim %d, Darwin %d)", names[index], mine, theirs);
        expect(mine == theirs, what);
    }

    /* The class of service of the queues that have one, and of one that has none. */
    dispatch_queue_t made = dispatch_queue_create("qos.made", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t queues[] = {dispatch_get_main_queue(), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
                                 dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
                                 dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), made};
    for (unsigned index = 0; index < sizeof queues / sizeof queues[0]; index++) {
        int mine_relative = 7, theirs_relative = 7;
        unsigned int mine = ours.qos(queues[index], &mine_relative), theirs = darwins.qos(queues[index], &theirs_relative);
        char what[200];
        snprintf(what, sizeof what, "queue %u: the class is Darwin's (shim 0x%x/%d, Darwin 0x%x/%d)", index, mine, mine_relative, theirs, theirs_relative);
        expect(mine == theirs && mine_relative == theirs_relative, what);
    }
    expect(ours.qos(made, NULL) == 0, "a queue with no class answers none, and a null relative priority is allowed");

    /* Attributes: iOS 8 refuses an invalid class by answering the attribute it was given, which the shim does for every class. */
    expect(dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, 0x99, 0) == DISPATCH_QUEUE_CONCURRENT &&
           darwins.qos_attr(DISPATCH_QUEUE_CONCURRENT, 0x99, 0) == DISPATCH_QUEUE_CONCURRENT, "an invalid class answers the attribute given");
    dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, 0x19, -2);
    attr = dispatch_queue_attr_make_with_autorelease_frequency(attr, 1);
    attr = dispatch_queue_attr_make_initially_inactive(attr);
    dispatch_queue_t made_with = dispatch_queue_create("qos.attr", attr);
    __block int ran = 0;
    on_queue(made_with, ^{ ran = 1; });
    expect(ran == 1 && !strcmp(dispatch_queue_get_label(made_with), "qos.attr"),
           "a queue made from the attributes runs its blocks, active, under the label it was given");

    /* A queue made with a target runs on it. */
    dispatch_queue_t target = dispatch_queue_create("target.q", DISPATCH_QUEUE_SERIAL);
    static char key;
    dispatch_queue_set_specific(target, &key, &key, NULL);
    for (int side = 0; side < 2; side++) {
        dispatch_queue_t targeting = (side ? darwins.create : ours.create)("targeting.q", DISPATCH_QUEUE_SERIAL, target);
        __block void *seen = NULL;
        on_queue(targeting, ^{ seen = dispatch_get_specific(&key); });
        char what[120];
        snprintf(what, sizeof what, "%s: a queue made with a target sees the target's specifics", side ? "Darwin" : "the shim");
        expect(seen == &key && !strcmp(dispatch_queue_get_label(targeting), "targeting.q"), what);
    }
    dispatch_queue_t untargeted = ours.create("untargeted.q", NULL, NULL);
    ran = 0;
    on_queue(untargeted, ^{ ran = 1; });
    expect(ran == 1, "a queue made with no target is an ordinary queue");
    return fails != 0;
}
"""

LATER_CALLS = r"""
#define __STDC_WANT_LIB_EXT1__ 1
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <spawn.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

int memset_s(void *, size_t, int, size_t);
void charon_arc4random_buf(void *, size_t);
void *voucher_copy(void);
void *voucher_adopt(void *);
unsigned int qos_class_self(void);
int charon_clock_getres(clockid_t, struct timespec *);
dispatch_queue_t charon_dispatch_get_global_queue(long, unsigned long);
void shim_activate(dispatch_object_t) __asm("_dispatch_activate");
void shim_assert_queue(dispatch_queue_t) __asm("_dispatch_assert_queue$V2");

static int fails;

static void expect(int holds, const char *what)
{
    if (!holds) {
        printf("FAIL  %s\n", what);
        fails++;
    }
}

static const char *program;

/* libdispatch does not survive fork, so a scenario that may crash runs in a fresh process of this program. */
static int dies(const char *scenario)
{
    fflush(stdout);
    pid_t child;
    char *arguments[] = {(char *)program, (char *)scenario, NULL};
    if (posix_spawn(&child, program, NULL, NULL, arguments, NULL) != 0)
        return -1;
    int status = 0;
    waitpid(child, &status, 0);
    return WIFSIGNALED(status) && WTERMSIG(status) != SIGALRM;
}

static void memsets(void)
{
    int (*darwin)(void *, size_t, int, size_t) = dlsym(RTLD_DEFAULT, "memset_s");
    expect(darwin && darwin != memset_s, "the test reaches Darwin's memset_s beside the shim");
    static const struct { size_t capacity, count; int null; } cases[] = {
        {16, 8, 0}, {16, 16, 0}, {16, 17, 0}, {16, SIZE_MAX, 0}, {SIZE_MAX, 4, 0}, {16, 8, 1}, {0, 0, 0},
    };
    for (size_t index = 0; index < sizeof cases / sizeof cases[0]; index++) {
        unsigned char mine[24], theirs[24];
        memset(mine, 0xaa, sizeof mine);
        memset(theirs, 0xaa, sizeof theirs);
        int got = memset_s(cases[index].null ? NULL : mine, cases[index].capacity, 0x5c, cases[index].count);
        int wanted = darwin(cases[index].null ? NULL : theirs, cases[index].capacity, 0x5c, cases[index].count);
        char what[160];
        snprintf(what, sizeof what, "memset_s(capacity %zu, count %zu%s) answers %d and writes the bytes Darwin's does",
                 cases[index].capacity, cases[index].count, cases[index].null ? ", NULL" : "", wanted);
        expect(got == wanted && memcmp(mine, theirs, sizeof mine) == 0, what);
    }
}

/* The stream the fallback reads from, so what it writes is exactly what this says. The shim is compiled here with
   CHARON_COMPAT_SYSTEM=0, which is the release that has no arc4random_buf of its own. */
static uint32_t charon_test_words;

uint32_t arc4random(void)
{
    return ++charon_test_words;
}

static void randoms(void)
{
    void (*darwin)(void *, size_t) = dlsym(RTLD_DEFAULT, "arc4random_buf");
    expect(darwin && darwin != charon_arc4random_buf, "the test reaches Darwin's arc4random_buf beside the shim");
    static const size_t lengths[] = {0, 1, 3, 4, 5, 8, 31, 64};
    for (size_t index = 0; index < sizeof lengths / sizeof lengths[0]; index++) {
        size_t length = lengths[index];
        unsigned char mine[96], wanted[96];
        memset(mine, 0xaa, sizeof mine);
        memset(wanted, 0xaa, sizeof wanted);
        /* Word after word of the stream, the tail the low bytes of the one that follows them: the answer of the system's
           own implementation, and of every release that has arc4random and not arc4random_buf. */
        charon_test_words = 0;
        for (size_t at = 0; at < length; at += sizeof(uint32_t)) {
            uint32_t word = at + sizeof(uint32_t) <= length ? (uint32_t)(at / sizeof(uint32_t) + 1) : (uint32_t)(length / sizeof(uint32_t) + 1);
            size_t bytes = length - at < sizeof(uint32_t) ? length - at : sizeof(uint32_t);
            memcpy(wanted + 16 + at, &word, bytes);
        }
        charon_test_words = 0;
        charon_arc4random_buf(mine + 16, length);
        char what[160];
        snprintf(what, sizeof what, "arc4random_buf fills %zu bytes from the stream, the tail included, and nothing around them", length);
        expect(memcmp(mine, wanted, sizeof mine) == 0, what);
    }
    /* A caller that names the symbol rather than writing the call - the standard library of Embedded Swift does - reaches
       the same shim, which is why the image defines that name too. */
    unsigned char named[16], renamed[16];
    charon_test_words = 0;
    arc4random_buf(named, sizeof named);
    charon_test_words = 0;
    charon_arc4random_buf(renamed, sizeof renamed);
    expect(memcmp(named, renamed, sizeof named) == 0, "the shim answers to the name of the call itself");

    charon_test_words = 0;
    unsigned char first[32], second[32];
    charon_arc4random_buf(first, sizeof first);
    charon_arc4random_buf(second, sizeof second);
    expect(memcmp(first, second, sizeof first) != 0, "two fills of the same length read on through the stream");
}

static void vouchers(void)
{
    expect(voucher_copy() == NULL, "without vouchers the current voucher is none");
    expect(voucher_adopt(NULL) == NULL, "adopting none leaves none adopted before");
    expect(dies("foreign-voucher") == 1, "a voucher no system call made is refused");
}

static _Atomic(unsigned) observed;

static void *plain_thread(void *unused)
{
    (void)unused;
    unsigned int (*darwin)(void) = dlsym(RTLD_DEFAULT, "qos_class_self");
    atomic_store(&observed, qos_class_self() == darwin() ? qos_class_self() : 0xdead);
    long priorities[] = {DISPATCH_QUEUE_PRIORITY_HIGH, DISPATCH_QUEUE_PRIORITY_DEFAULT, DISPATCH_QUEUE_PRIORITY_LOW,
                         DISPATCH_QUEUE_PRIORITY_BACKGROUND};
    unsigned classes[] = {0x19, 0x15, 0x11, 0x09};
    for (int index = 0; index < 4; index++) {
        __block unsigned mine = 0, theirs = 0;
        dispatch_semaphore_t finished = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(priorities[index], 0), ^{
            mine = qos_class_self();
            theirs = darwin();
            dispatch_semaphore_signal(finished);
        });
        dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
        char what[160];
        snprintf(what, sizeof what, "a worker of the global queue of priority %ld has class 0x%x as Darwin's (0x%x) says",
                 priorities[index], classes[index], theirs);
        expect(mine == classes[index] && theirs == classes[index], what);
    }
    return NULL;
}

static void classes(void)
{
    unsigned int (*darwin)(void) = dlsym(RTLD_DEFAULT, "qos_class_self");
    expect(darwin && darwin != qos_class_self, "the test reaches Darwin's qos_class_self beside the shim");
    expect(qos_class_self() == 0x21 && darwin() == 0x21, "the main thread is user-interactive, as Darwin says");
    pthread_t thread;
    pthread_create(&thread, NULL, plain_thread, NULL);
    pthread_join(thread, NULL);
    expect(atomic_load(&observed) == 0x15, "a thread from pthread_create has the default class, as Darwin says");
}

static void resolutions(void)
{
    static const struct { clockid_t clock; int as_darwin; } clocks[] = {
        {CLOCK_REALTIME, 1}, {CLOCK_MONOTONIC, 1}, {CLOCK_PROCESS_CPUTIME_ID, 1}, {CLOCK_UPTIME_RAW, 1},
        {CLOCK_UPTIME_RAW_APPROX, 1}, {CLOCK_MONOTONIC_RAW, 0}, {CLOCK_MONOTONIC_RAW_APPROX, 0}, {CLOCK_THREAD_CPUTIME_ID, 0},
    };
    for (size_t index = 0; index < sizeof clocks / sizeof clocks[0]; index++) {
        struct timespec mine = {-1, -1}, theirs = {-1, -1};
        int got = charon_clock_getres(clocks[index].clock, &mine);
        clock_getres(clocks[index].clock, &theirs);
        char what[160];
        if (clocks[index].as_darwin) {
            snprintf(what, sizeof what, "clock %d resolves to Darwin's %ld ns", clocks[index].clock, theirs.tv_nsec);
            expect(got == 0 && mine.tv_sec == theirs.tv_sec && mine.tv_nsec == theirs.tv_nsec, what);
        } else {
            snprintf(what, sizeof what, "clock %d, which charon_clock_gettime counts in microseconds, resolves to one", clocks[index].clock);
            expect(got == 0 && mine.tv_sec == 0 && mine.tv_nsec == 1000, what);
        }
    }
    errno = 0;
    struct timespec unused;
    expect(charon_clock_getres((clockid_t)12345, &unused) == -1 && errno == EINVAL, "an unknown clock is refused");
    expect(charon_clock_getres(CLOCK_REALTIME, NULL) == 0, "a known clock without a result to fill answers 0");
}

static void global_queues(void)
{
    static const struct { long identifier; long priority; } classes[] = {
        {0x21, DISPATCH_QUEUE_PRIORITY_HIGH}, {0x19, DISPATCH_QUEUE_PRIORITY_HIGH}, {0x15, DISPATCH_QUEUE_PRIORITY_DEFAULT},
        {0x11, DISPATCH_QUEUE_PRIORITY_LOW}, {0x09, DISPATCH_QUEUE_PRIORITY_BACKGROUND}, {0, DISPATCH_QUEUE_PRIORITY_DEFAULT},
        {DISPATCH_QUEUE_PRIORITY_HIGH, DISPATCH_QUEUE_PRIORITY_HIGH}, {DISPATCH_QUEUE_PRIORITY_LOW, DISPATCH_QUEUE_PRIORITY_LOW},
        {DISPATCH_QUEUE_PRIORITY_BACKGROUND, DISPATCH_QUEUE_PRIORITY_BACKGROUND},
    };
    for (size_t index = 0; index < sizeof classes / sizeof classes[0]; index++) {
        char what[160];
        snprintf(what, sizeof what, "class or priority %ld reaches the global queue of priority %ld", classes[index].identifier,
                 classes[index].priority);
        expect(charon_dispatch_get_global_queue(classes[index].identifier, 0) == dispatch_get_global_queue(classes[index].priority, 0),
               what);
    }
    expect(charon_dispatch_get_global_queue(7, 0) == NULL, "an identifier that is neither a class nor a priority answers NULL");
    expect(charon_dispatch_get_global_queue(0x19, 2) == dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 2),
           "the flags reach the system unchanged");
}

static void activations(void)
{
    __block _Atomic int fired = 0;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(0, 0));
    dispatch_source_set_timer(source, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC), DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(source, ^{
        atomic_fetch_add(&fired, 1);
    });
    usleep(50000);
    expect(atomic_load(&fired) == 0, "a source nobody activated does not fire");
    shim_activate(source);
    shim_activate(source);
    for (int tick = 0; tick < 200 && atomic_load(&fired) == 0; tick++)
        usleep(5000);
    expect(atomic_load(&fired) == 1, "an activated source fires, and a second activation resumes nothing more");
    dispatch_source_cancel(source);
    dispatch_queue_t queue = dispatch_queue_create("charon.activate", NULL);
    shim_activate(queue);
    __block int ran = 0;
    dispatch_sync(queue, ^{
        ran = 1;
    });
    expect(ran, "activating a queue, which starts active, leaves it running blocks");
}

static dispatch_queue_t serial, inner;

static void on_worker(void (^body)(void))
{
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        body();
        dispatch_semaphore_signal(finished);
    });
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
}

static int scenario(const char *name)
{
    freopen("/dev/null", "w", stderr);
    alarm(10);
    void (*darwin)(dispatch_queue_t) = dlsym(RTLD_DEFAULT, "dispatch_assert_queue$V2");
    serial = dispatch_queue_create("charon.serial", NULL);
    inner = dispatch_queue_create("charon.inner", NULL);
    dispatch_set_target_queue(inner, serial);
    if (!strcmp(name, "foreign-voucher"))
        voucher_adopt((void *)0x1000);
    else if (!strcmp(name, "shim-main-thread-on-serial"))
        shim_assert_queue(serial);
    else if (!strcmp(name, "darwin-main-thread-on-serial"))
        darwin(serial);
    else if (!strcmp(name, "shim-target-on-targeting"))
        dispatch_sync(serial, ^{ shim_assert_queue(inner); });
    else if (!strcmp(name, "darwin-target-on-targeting"))
        dispatch_sync(serial, ^{ darwin(inner); });
    else if (!strcmp(name, "shim-worker-on-main"))
        on_worker(^{ shim_assert_queue(dispatch_get_main_queue()); });
    else if (!strcmp(name, "darwin-worker-on-main"))
        on_worker(^{ darwin(dispatch_get_main_queue()); });
    return 0;
}

static void assertions(void)
{
    void (*darwin)(dispatch_queue_t) = dlsym(RTLD_DEFAULT, "dispatch_assert_queue$V2");
    expect(darwin != NULL, "the test reaches Darwin's dispatch_assert_queue$V2");
    serial = dispatch_queue_create("charon.serial", NULL);
    inner = dispatch_queue_create("charon.inner", NULL);
    dispatch_set_target_queue(inner, serial);
    shim_assert_queue(dispatch_get_main_queue());
    darwin(dispatch_get_main_queue());
    dispatch_sync(serial, ^{ shim_assert_queue(serial); darwin(serial); });
    dispatch_sync(inner, ^{ shim_assert_queue(serial); darwin(serial); shim_assert_queue(inner); });
    dispatch_sync(serial, ^{ shim_assert_queue(dispatch_get_main_queue()); darwin(dispatch_get_main_queue()); });
    dispatch_queue_t global = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
    on_worker(^{ shim_assert_queue(global); darwin(global); });
    static const char *crashes[][2] = {
        {"main-thread-on-serial", "the main thread outside a block is not on another queue"},
        {"target-on-targeting", "a block on a target queue is not on the queue that targets it"},
        {"worker-on-main", "a worker thread is not on the main queue"},
    };
    for (size_t index = 0; index < sizeof crashes / sizeof crashes[0]; index++) {
        char shim[64], system[64];
        snprintf(shim, sizeof shim, "shim-%s", crashes[index][0]);
        snprintf(system, sizeof system, "darwin-%s", crashes[index][0]);
        expect(dies(shim) == 1 && dies(system) == 1, crashes[index][1]);
    }
}

int main(int argc, char **argv)
{
    program = argv[0];
    if (argc > 1)
        return scenario(argv[1]);
    memsets();
    randoms();
    vouchers();
    classes();
    resolutions();
    global_queues();
    activations();
    assertions();
    return fails != 0;
}
"""


ALLOC_WITH_ZONE = r"""
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>

id objc_allocWithZone(Class);
id objc_opt_self(id);

static int zoned;

@interface Answering : NSObject
@end

@implementation Answering
- (instancetype)self
{
    return nil;
}
@end

@interface Counted : NSObject
@property int value;
@end

@implementation Counted
+ (instancetype)allocWithZone:(NSZone *)zone
{
    zoned++;
    return [super allocWithZone:zone];
}
@end

int main(void)
{
    int fails = 0;
    id (*darwin)(Class) = dlsym(RTLD_DEFAULT, "objc_allocWithZone");
    id mine = [objc_allocWithZone([Counted class]) init];
    id theirs = [darwin([Counted class]) init];
    if (![mine isKindOfClass:[Counted class]] || [theirs class] != [mine class] || zoned != 2) {
        printf("FAIL  objc_allocWithZone allocates through the class's +allocWithZone:, as Darwin's does\n");
        fails++;
    }
    if (objc_allocWithZone(Nil) != nil || darwin(Nil) != nil) {
        printf("FAIL  objc_allocWithZone of Nil answers nil\n");
        fails++;
    }

    id (*darwin_self)(id) = dlsym(RTLD_DEFAULT, "objc_opt_self");
    Counted *counted = [Counted new];
    if (objc_opt_self((id)[Counted class]) != (id)[Counted class] || objc_opt_self(counted) != counted ||
        objc_opt_self(nil) != nil || objc_opt_self(@42) != @42) {
        printf("FAIL  objc_opt_self answers the class, the object, nil and a tagged pointer themselves\n");
        fails++;
    }
    Answering *answering = [Answering new];
    if (objc_opt_self(answering) != darwin_self(answering)) {
        printf("FAIL  objc_opt_self answers what -self answers where the class overrides it, as Darwin's does\n");
        fails++;
    }
    return fails;
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
                                      ("unlinkat", "return unlinkat(3, \"x\", 0);", "unistd.h"),
                                      ("clock_getres", "struct timespec t; return clock_getres(CLOCK_MONOTONIC, &t);", "time.h"),
                                      ("dispatch_get_global_queue", "return dispatch_get_global_queue(0x19, 0) != 0;",
                                       "dispatch/dispatch.h")):
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

        def outcome(name, ran):
            reported = [line[6:] for line in ran.stdout.splitlines() if line.startswith("FAIL")]
            if ran.returncode and not reported:
                reported.append("the {} test failed without saying why: {} {}".format(name, ran.returncode, ran.stderr[-300:]))
            return reported

        locks = [SHIMS / "{}.c".format(symbol) for symbol in ("os_unfair_lock_lock", "os_unfair_lock_trylock", "os_unfair_lock_unlock",
                                                             "os_unfair_recursive_lock_lock_with_options",
                                                             "os_unfair_recursive_lock_unlock")]
        waits = [SHIMS / "__ulock_wait.c", SHIMS / "__ulock_wake.c"]
        (folder / "unfair.c").write_text(UNFAIR_LOCK)
        built = run("xcrun", "clang", "-O2", "-w", "-DCHARON_COMPAT_SYSTEM=0", *locks, *waits, "unfair.c", "-o", "unfair", cwd=folder)
        if built.returncode:
            found.append("the os_unfair_lock shims must compile: {}".format(built.stderr[-400:]))
        else:
            found += outcome("os_unfair_lock", run("./unfair", cwd=folder))

        (folder / "names.c").write_text(PORT_NAMES)
        built = run("xcrun", "clang", "-O2", "-w", "-DCHARON_COMPAT_SYSTEM=0", "-I", SHIMS, "names.c", *waits, "-o", "names",
                    cwd=folder)
        if built.returncode:
            found.append("the port-name test must compile: {}".format(built.stderr[-400:]))
        else:
            found += outcome("port names", run("./names", cwd=folder))

        # The locks are exported once for the process, as libc++abi does: two images bind to that copy and wake each other.
        shared = folder / "shared"
        shared.mkdir()
        (shared / "side.c").write_text(LOCK_SIDE)
        (shared / "images.c").write_text(TWO_IMAGES)
        steps = [run("xcrun", "clang", "-O2", "-w", "-fvisibility=hidden", "-DCHARON_COMPAT_SYSTEM=0", "-dynamiclib", *locks, *waits,
                     "-install_name", "@rpath/libshared.dylib", "-o", "libshared.dylib", cwd=shared)]
        for side in ("one", "two"):
            steps.append(run("xcrun", "clang", "-O2", "-w", "-fvisibility=hidden", "-DSIDE_lock={}_lock".format(side),
                             "-DSIDE_unlock={}_unlock".format(side), "-dynamiclib", "side.c", "-L.", "-lshared", "-install_name",
                             "@rpath/lib{}.dylib".format(side), "-o", "lib{}.dylib".format(side), cwd=shared))
        steps.append(run("xcrun", "clang", "-O2", "images.c", "-L.", "-lone", "-ltwo", "-Wl,-rpath,@executable_path", "-o", "images",
                         cwd=shared))
        if any(step.returncode for step in steps):
            found.append("two images bound to one exported lock must link: {}".format(" ".join(step.stderr[-300:] for step in steps)))
        else:
            exports = run("xcrun", "nm", "-gm", "libshared.dylib", cwd=shared).stdout
            for symbol in [path.stem for path in locks]:
                if not re.search(r"\) external _{}$".format(re.escape(symbol)), exports, re.M):
                    found.append("{} must be an exported definition, since every image of a process binds to one copy".format(symbol))
            if re.search(r" external ___ulock_wa(it|ke)$", exports, re.M):
                found.append("the copy of the locks must keep __ulock_wait and __ulock_wake to itself")
            imported = run("xcrun", "nm", "-m", "libone.dylib", cwd=shared).stdout
            if "_os_unfair_lock_lock (from libshared)" not in imported:
                found.append("an image calling os_unfair_lock_lock must bind it to the one copy: {}".format(imported))
            found += outcome("two-image lock", run("./images", cwd=shared))
            forwarding = folder / "forwarding"
            forwarding.mkdir()
            (forwarding / "forward.c").write_text(FORWARDED_LOCK)
            steps = [run("xcrun", "clang", "-O2", "-w", "-fvisibility=hidden", "-dynamiclib", *locks, *waits, "-install_name",
                         "@rpath/libshared.dylib", "-o", "libshared.dylib", cwd=forwarding),
                     run("xcrun", "clang", "-O2", "-w", "forward.c", "-L.", "-lshared", "-Wl,-rpath,@executable_path", "-o", "forward",
                         cwd=forwarding)]
            if any(step.returncode for step in steps):
                found.append("the forwarding lock test must link: {}".format(" ".join(step.stderr[-300:] for step in steps)))
            else:
                found += outcome("forwarded lock", run("./forward", cwd=forwarding))

        later = ["memset_s", "arc4random_buf", "voucher_copy", "voucher_adopt", "qos_class_self", "clock_getres", "dispatch_get_global_queue",
                 "dispatch_activate", "dispatch_assert_queue$V2"]
        (folder / "calls.c").write_text(LATER_CALLS)
        built = run("xcrun", "clang", "-O2", "-w", "-DCHARON_COMPAT_SYSTEM=0", *[SHIMS / "{}.c".format(symbol) for symbol in later],
                    "calls.c", "-o", "calls", cwd=folder)
        if built.returncode:
            found.append("the shims of later dispatch, clock and memory calls must compile: {}".format(built.stderr[-400:]))
        else:
            found += outcome("later calls", run(folder / "calls", cwd=folder))
        blocks = [SHIMS / "{}.c".format(symbol) for symbol in ("dispatch_block_create", "dispatch_block_create_with_qos_class",
                                                            "dispatch_block_perform", "dispatch_block_wait", "dispatch_block_notify",
                                                            "dispatch_block_cancel", "dispatch_block_testcancel")]
        (folder / "blocks.c").write_text(DISPATCH_BLOCKS)
        built = run("xcrun", "clang", "-O2", "-w", "-fblocks", "-DCHARON_COMPAT_SYSTEM=0", *blocks, "blocks.c", "-o", "blocks", cwd=folder)
        if built.returncode:
            found.append("the dispatch_block shims must compile: {}".format(built.stderr[-400:]))
        else:
            found += outcome("dispatch_block", run("./blocks", cwd=folder))
        asserts = [SHIMS / "{}.c".format(symbol) for symbol in ("os_unfair_lock_assert_owner", "os_unfair_lock_assert_not_owner")]
        (folder / "asserts.c").write_text(UNFAIR_ASSERT)
        built = run("xcrun", "clang", "-O2", "-w", "-DCHARON_COMPAT_SYSTEM=0", *asserts, *locks, *waits, "asserts.c", "-o", "asserts", cwd=folder)
        if built.returncode:
            found.append("the os_unfair_lock assert shims must compile: {}".format(built.stderr[-400:]))
        else:
            found += outcome("os_unfair_lock assert", run("./asserts", cwd=folder))

        queue_shims = [SHIMS / "{}.c".format(symbol) for symbol in ("dispatch_assert_queue_not$V2", "dispatch_assert_queue_barrier",
                                                                   "dispatch_queue_get_qos_class", "dispatch_queue_create_with_target$V2",
                                                                   "dispatch_queue_attr_make_with_qos_class",
                                                                   "dispatch_queue_attr_make_initially_inactive",
                                                                   "dispatch_queue_attr_make_with_autorelease_frequency")]
        (folder / "queues.c").write_text(DISPATCH_QUEUES)
        built = run("xcrun", "clang", "-O2", "-w", "-fblocks", "-DCHARON_COMPAT_SYSTEM=0", *queue_shims, "queues.c", "-o", "queues", cwd=folder)
        if built.returncode:
            found.append("the dispatch queue shims must compile: {}".format(built.stderr[-400:]))
        else:
            found += outcome("dispatch queue", run("./queues", cwd=folder))

        (folder / "system-random.c").write_text(SYSTEM_RANDOM)
        built = run("xcrun", "clang", "-O2", "-w", SHIMS / "arc4random_buf.c", "system-random.c", "-o", "system-random", cwd=folder)
        if built.returncode:
            found.append("the arc4random_buf shim must compile against the system's own: {}".format(built.stderr[-400:]))
        else:
            found += outcome("system arc4random_buf", run("./system-random", cwd=folder))
        (folder / "alloc.m").write_text(ALLOC_WITH_ZONE)
        built = run("xcrun", "clang", "-O2", "-w", "-fobjc-arc", "-DCHARON_COMPAT_SYSTEM=0", SHIMS / "objc_allocWithZone.c",
                    SHIMS / "objc_opt_self.c", "alloc.m", "-framework", "Foundation", "-o", "alloc", cwd=folder)
        if built.returncode:
            found.append("the objc_allocWithZone shim must compile: {}".format(built.stderr[-400:]))
        else:
            found += outcome("objc_allocWithZone", run("./alloc", cwd=folder))

        for symbol in [path.stem for path in locks] + later + [path.stem for path in blocks + asserts + queue_shims] + ["objc_allocWithZone", "objc_opt_self"]:
            process_wide = symbol in ("os_unfair_lock_lock", "os_unfair_lock_trylock", "os_unfair_lock_unlock",
                                      "os_unfair_recursive_lock_lock_with_options", "os_unfair_recursive_lock_unlock")
            if (SHIMS.parent / "include" / "charon" / "{}.h".format(symbol)).exists():
                defined = "_charon_" + symbol
            else:
                defined = "_" + symbol
            for architecture, release in (("armv7", "6.0"), ("arm64", "7.0")):
                object_file = "ios-{}-{}.o".format(symbol, architecture)
                shim = run("xcrun", "clang", "-target", "{}-apple-ios{}".format(architecture, release), "-Wno-incompatible-sysroot",
                           "-Os", "-fvisibility=hidden", "-c", SHIMS / "{}.c".format(symbol), "-o", object_file, cwd=folder)
                listing = run("xcrun", "nm", "-m", object_file, cwd=folder).stdout
                line = next((row for row in listing.splitlines() if row.endswith(" " + defined)), "")
                if shim.returncode or not line or ("private external" in line) == process_wide:
                    found.append("{} must compile for {} on iOS {} as {} definition: {} {}".format(
                        symbol, architecture, release, "an exported" if process_wide else "a hidden", shim.stderr[-300:], listing))
                    continue
                undefined = run("xcrun", "nm", "-u", object_file, cwd=folder).stdout.split()
                if any(name.startswith("___atomic_") for name in undefined):
                    found.append("{} for {} must not call the atomic library functions iOS {} lacks: {}".format(
                        symbol, architecture, release, undefined))
                uses_objc = any(name.startswith(("_objc_", "_object_", "_class_", "_sel_")) for name in undefined)
                options = run("xcrun", "otool", "-l", object_file, cwd=folder).stdout
                if uses_objc and "string #1 -lobjc" not in options:
                    found.append("{} calls the Objective-C runtime, so its object must ask the linker for libobjc".format(symbol))

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
    print("ok    each compatibility shim keeps its call's contract, hidden in the image that links it or exported once for the process")
    return 0


if __name__ == "__main__":
    sys.exit(main())
