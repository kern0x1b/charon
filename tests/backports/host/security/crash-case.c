/* The two verdicts a driver must keep apart, and a case that produces each on demand.
 *
 * A case that dies on a signal prints nothing, and a driver that reports a missing output file as a
 * difference says "the port's class was not found" about a process that never got that far. This case
 * exists so the driver is exercised by BOTH shapes without waiting for a real mutation to segfault:
 *
 *   crash    raises SIGSEGV, so the driver must say "crashed: 11" and NOT "class not found"
 *   missing  prints a WRONG line, so the driver must say the difference and name it
 *   clean    prints the value the comparison wants
 *
 * Three times in the Security series a mutation was caught by a signal - EXIT=134 for the C strings and
 * EXIT=139 for the dispatch_data values - and each time the comparison reported the rows after the crash
 * as "the case did not measure it". That is a harness failure reported as a missing class.
 */
#include <signal.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
    const char *mode = argc > 1 ? argv[1] : "clean";
    if (strcmp(mode, "crash") == 0) {
        printf("about to die\n");
        fflush(stdout);
        raise(SIGSEGV);            /* no return: nothing after this is printed */
    }
    if (strcmp(mode, "missing") == 0) {
        printf("value\t1\n");      /* one value, so the comparison sees a MISSING one, not a wrong one */
        return 0;
    }
    printf("value\t1\t1\n");
    return 0;
}
