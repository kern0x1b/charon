// The apple-compat shims for OSAtomic's 32-bit add and subtract, and for ffsll and flsll, against the HOST's own
// definitions, in one process. The shims are compiled with their names renamed to charon_port_* (run.sh), so the
// host's call, under the real name, and the port's are both callable here. Each case prints one line, "ok <name>" or
// "FAIL <name> ...", and the process exits with the number of failures.
#include <limits.h>
#include <stdint.h>
#include <stdio.h>

typedef int32_t (*atomic_op)(volatile int32_t *);

// the host's own definitions, under the names the system exports
int32_t OSAtomicIncrement32(volatile int32_t *);
int32_t OSAtomicIncrement32Barrier(volatile int32_t *);
int32_t OSAtomicDecrement32(volatile int32_t *);
int32_t OSAtomicDecrement32Barrier(volatile int32_t *);
int ffsll(long long);
int flsll(long long);

// the port's shims, renamed at build time
int32_t charon_port_OSAtomicIncrement32(volatile int32_t *);
int32_t charon_port_OSAtomicIncrement32Barrier(volatile int32_t *);
int32_t charon_port_OSAtomicDecrement32(volatile int32_t *);
int32_t charon_port_OSAtomicDecrement32Barrier(volatile int32_t *);
int charon_port_ffsll(long long);
int charon_port_flsll(long long);

static int failures;

static void report(int passed, const char *name, long long got, long long want)
{
    if (passed) {
        printf("ok %s\n", name);
    } else {
        printf("FAIL %s got=%lld want=%lld\n", name, got, want);
        failures++;
    }
}

// Each call answers the value after the operation, and leaves the word as the operation says. Both words start at the
// same value and take the same steps, and the answers and the stored words are compared after every step.
static void atomic_case(const char *name, atomic_op host, atomic_op port)
{
    const int32_t starts[] = {0, 1, -1, 41, INT32_MAX, INT32_MIN, INT32_MAX - 1, INT32_MIN + 1, 1 << 30};
    int passed = 1;
    for (size_t i = 0; i < sizeof(starts) / sizeof(starts[0]) && passed; i++) {
        volatile int32_t a = starts[i], b = starts[i];
        for (int step = 0; step < 4 && passed; step++) {
            int32_t ra = host(&a), rb = port(&b);
            if (ra != rb || a != b) {
                report(0, name, rb, ra);
                passed = 0;
            }
        }
    }
    if (passed)
        report(1, name, 0, 0);
}

// The masks that separate the answers: the edges, every single bit, and the bit runs from each position.
static void ffs_case(const char *name, int (*host)(long long), int (*port)(long long))
{
    long long masks[] = {0, 1, -1, 2, INT64_MIN, INT64_MAX, 0x80000000LL, 0x100000000LL, 0x0000FFFF00000000LL};
    int passed = 1;
    for (size_t i = 0; i < sizeof(masks) / sizeof(masks[0]); i++) {
        int a = host(masks[i]), b = port(masks[i]);
        if (a != b) {
            report(0, name, b, a);
            passed = 0;
        }
    }
    for (int bit = 0; bit < 64; bit++) {
        unsigned long long one = 1ULL << bit;
        unsigned long long low = one - 1;
        long long candidates[] = {(long long)one, (long long)low, (long long)(one | 1), (long long)(one | low)};
        for (size_t j = 0; j < 4; j++) {
            int a = host(candidates[j]), b = port(candidates[j]);
            if (a != b) {
                report(0, name, b, a);
                passed = 0;
            }
        }
    }
    if (passed)
        report(1, name, 0, 0);
}

int main(void)
{
    atomic_case("OSAtomicIncrement32", OSAtomicIncrement32, charon_port_OSAtomicIncrement32);
    atomic_case("OSAtomicIncrement32Barrier", OSAtomicIncrement32Barrier, charon_port_OSAtomicIncrement32Barrier);
    atomic_case("OSAtomicDecrement32", OSAtomicDecrement32, charon_port_OSAtomicDecrement32);
    atomic_case("OSAtomicDecrement32Barrier", OSAtomicDecrement32Barrier, charon_port_OSAtomicDecrement32Barrier);
    ffs_case("ffsll", ffsll, charon_port_ffsll);
    ffs_case("flsll", flsll, charon_port_flsll);
    if (failures == 0)
        printf("checks=all failures=0\n");
    else
        printf("checks=failed failures=%d\n", failures);
    return failures;
}
