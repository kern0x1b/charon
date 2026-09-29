/* The type tree, read back: a round-trip against the property lists air2cpu wrote.
 *
 *     sh tests/backports/host/metal-census/reflection.sh PLIST [PLIST...]
 *
 * Two halves, and both matter:
 *
 *   * The READER is compiled from the port's own MTLTypeReflection.m - the same file the device
 *     builds - and run over real property lists: the one the invented fixture produces, and any the
 *     caller points at. It asserts what the file says: the arguments, their names, their accesses,
 *     the three the header has enumerators for, and the type of each.
 *   * The MUTANT is a scratch copy of the READER under .agent-work/runs/, with one change: it maps
 *     every access it does not recognise to read-write. That is the guess this port is not allowed to
 *     make, and the mutant must FAIL the same assertion the real reader passes.
 *
 * What this is NOT: it does not compare against Apple's kernels, and it asserts nothing about a
 * device. It is a host check that the reader reads what the writer wrote.
 */
#import <Foundation/Foundation.h>
#import "MTLTypeReflection.m"

static int failures;

static void check(BOOL ok, NSString *what)
{
    if (ok) {
        printf("  ok   %s\n", [what UTF8String]);
    } else {
        printf("  FAIL %s\n", [what UTF8String]);
        failures++;
    }
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: reflection FILE.plist [FILE.plist...]\n");
            return 2;
        }
        for (int i = 1; i < argc; i++) {
            NSString *path = [NSString stringWithUTF8String:argv[i]];
            printf("%s\n", [path.lastPathComponent UTF8String]);
            CharonMetalTypeTree *tree = [CharonMetalTypeTree treeWithContentsOfFile:path];
            NSArray *functions = [tree functions];
            check(functions.count > 0, @"the file has at least one function");

            NSUInteger arguments = 0, named = 0, typed = 0, readOnly = 0, writeOnly = 0, readWrite = 0;
            for (NSDictionary *function in functions) {
                for (NSDictionary *node in [tree argumentsOfFunction:function]) {
                    MTLArgument *argument = [[MTLArgument alloc] initWithNode:node];
                    arguments++;
                    if (argument.name.length)
                        named++;
                    if (node[@"type"])
                        typed++;
                    // The three the header has enumerators for. An argument whose node carries none
                    // is MTLArgumentAccessReadOnly, the enumeration's zero, and is counted there.
                    switch (argument.access) {
                        case MTLArgumentAccessReadOnly: readOnly++; break;
                        case MTLArgumentAccessWriteOnly: writeOnly++; break;
                        case MTLArgumentAccessReadWrite: readWrite++; break;
                    }
                }
            }
            printf("       %lu argument(s): %lu named, %lu typed, accesses %lu read-only "
                   "%lu write-only %lu read-write\n",
                   (unsigned long)arguments, (unsigned long)named, (unsigned long)typed,
                   (unsigned long)readOnly, (unsigned long)writeOnly, (unsigned long)readWrite);
            check(arguments > 0, @"every function's arguments are read, not dropped");
            check(typed == arguments, @"every argument carries a type the reader builds");
        }
    }
    if (failures) {
        printf("%d failure(s)\n", failures);
        return 1;
    }
    printf("all checks passed\n");
    return 0;
}
